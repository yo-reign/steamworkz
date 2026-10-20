const std = @import("std");
const builtin = @import("builtin");
const Context = @import("Context.zig");
const SteamId = @import("types.zig").SteamId;
const c = @cImport({
    @cInclude("utils.h");
});
const native = if (builtin.is_test) Fake else c;
const Utils = @This();

/// Borrowed owner-thread facade; Client storage must stay alive and unmoved.
lease: Context.Lease,

pub const GamepadMode = enum(i32) { normal = 0, password = 1 };
pub const LineMode = enum(i32) { single = 0, multiple = 1 };
pub const FloatingMode = enum(i32) { single = 0, multiple = 1, email = 2, numeric = 3 };
pub const FilterContext = enum(i32) { unknown = 0, game_content = 1, chat = 2, name = 3 };
pub const DefaultConfig = enum(i32) { none = 0, low = 1, medium = 2, high = 3, max = 4, steam_deck = 5, steam_machine = 6, steam_frame = 7, _ };
pub const GamepadOptions = struct {
    mode: GamepadMode = .normal,
    lines: LineMode = .single,
    description: [:0]const u8 = "",
    max_characters: u32,
    existing_text: [:0]const u8 = "",
};
pub const FloatingOptions = struct {
    mode: FloatingMode = .single,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};
pub const FilterOptions = struct { context: FilterContext, source: SteamId };
pub const FilterResult = struct {
    filtered_characters: i32,
    /// Borrows the caller's output buffer; excludes the trailing NUL.
    text: []u8,
};

/// Owned completion data, captured before the native dismissal callback is freed.
/// The 1024-byte capacity includes NUL and is a wrapper bound, not an SDK limit.
pub const GamepadText = struct {
    pub const capacity = 1024;
    pub const Status = enum(i32) { canceled = 0, complete = 1, too_large = 2, unavailable = 3, retrieval_failed = 4, malformed = 5, untracked = 6, _ };
    status: Status,
    reported_length: u32,
    queried_length: u32,
    copied_length: u32,
    bytes: [capacity]u8,

    /// Borrows this owned value, never SDK storage. Empty success is non-null.
    pub fn text(self: *const GamepadText) ?[]const u8 {
        if (self.status != .complete or self.copied_length >= capacity) return null;
        return self.bytes[0..self.copied_length];
    }
};

/// Returns native acceptance, not completion. Both keyboards share one pending
/// slot, released only by a matching dismissal event or Client teardown.
pub fn showGamepad(self: Utils, options: GamepadOptions) !bool {
    self.lease.check();
    if (self.lease.context.keyboard_state != .none) return error.KeyboardPending;
    try string(options.description);
    try string(options.existing_text);
    var app_id: u32 = 0;
    const accepted = try boolean(native.sw_utils_show_gamepad(@intFromEnum(options.mode), @intFromEnum(options.lines), options.description.ptr, options.max_characters, options.existing_text.ptr, &app_id));
    if (accepted) {
        self.lease.context.keyboard_state = .gamepad;
        self.lease.context.keyboard_app_id = app_id;
    }
    return accepted;
}

/// Coordinates are signed pixels relative to the game window; dimensions must
/// be positive. Native OS key events supply the text, not a delayed text getter.
pub fn showFloating(self: Utils, options: FloatingOptions) !bool {
    self.lease.check();
    if (self.lease.context.keyboard_state != .none) return error.KeyboardPending;
    if (options.width <= 0 or options.height <= 0) return error.InvalidRectangle;
    const accepted = try boolean(native.sw_utils_show_floating(@intFromEnum(options.mode), options.x, options.y, options.width, options.height));
    if (accepted) self.lease.context.keyboard_state = .floating;
    return accepted;
}

/// Native acceptance does not release the pending slot or establish cancellation.
/// A different or absent pending mode is a local error, without a native call.
pub fn dismissGamepad(self: Utils) !bool {
    self.lease.check();
    if (self.lease.context.keyboard_state != .gamepad) return error.KeyboardNotPending;
    return boolean(native.sw_utils_dismiss_gamepad());
}

/// Native acceptance does not release the pending slot or establish cancellation.
pub fn dismissFloating(self: Utils) !bool {
    self.lease.check();
    if (self.lease.context.keyboard_state != .floating) return error.KeyboardNotPending;
    return boolean(native.sw_utils_dismiss_floating());
}

/// Explicit dictionary initialization. False preserves native language
/// unavailability: FilterText may still pass input through unchanged.
pub fn initFilter(self: Utils) !bool {
    self.lease.check();
    return boolean(native.sw_utils_init_filter());
}

/// Caller owns output; it must not overlap input (including its NUL) and must
/// hold input.len + 1 bytes. Output may be modified after local validation,
/// including when the interface is unavailable or the native result malformed.
/// The signed filtered-character count is independent of the output byte count.
pub fn filterText(self: Utils, options: FilterOptions, input: [:0]const u8, output: []u8) !FilterResult {
    self.lease.check();
    const capacity = try filterCapacity(input.len, output.len);
    try string(input);
    if (overlaps(input.ptr, input.len + 1, output.ptr, output.len)) return error.OverlappingBuffers;
    // An unwritten native output must not appear terminated due to old zeroes.
    @memset(output, 0x7f);
    var filtered_characters: i32 = 0;
    try status(native.sw_utils_filter(@intFromEnum(options.context), @intFromEnum(options.source), input.ptr, output.ptr, capacity, &filtered_characters));
    const length = std.mem.indexOfScalar(u8, output, 0) orelse return error.MalformedNativeOutput;
    return .{ .filtered_characters = filtered_characters, .text = output[0..length] };
}

/// Guidance only: does not apply settings or gate functionality by hardware name.
/// Unknown numeric values survive so callers can choose their own fallback.
pub fn defaultConfig(self: Utils) !DefaultConfig {
    self.lease.check();
    var value: i32 = 0;
    try status(native.sw_utils_default_config(&value));
    return @enumFromInt(value);
}

/// Internal Client hook, called while the lease is live and before native shutdown.
/// One best-effort dismissal of the pending mode; no invented completion or retry.
pub fn shutdown(lease: Context.Lease) void {
    lease.check();
    switch (lease.context.keyboard_state) {
        .none => {},
        .gamepad => {
            _ = native.sw_utils_dismiss_gamepad();
        },
        .floating => {
            _ = native.sw_utils_dismiss_floating();
        },
    }
    lease.context.keyboard_state = .none;
    lease.context.keyboard_app_id = 0;
}

fn string(value: [:0]const u8) error{ InteriorNul, InvalidUtf8 }!void {
    if (std.mem.indexOfScalar(u8, value, 0) != null) return error.InteriorNul;
    if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
}
fn boolean(value: i32) !bool {
    return switch (value) {
        -1 => error.Unavailable,
        -2 => error.InvalidArgument,
        0 => false,
        1 => true,
        else => error.MalformedNativeOutput,
    };
}
fn status(value: i32) !void {
    switch (value) {
        0 => {},
        -1 => return error.Unavailable,
        -2 => return error.InvalidArgument,
        else => return error.MalformedNativeOutput,
    }
}
fn filterCapacity(input_len: usize, output_len: usize) !u32 {
    if (input_len >= std.math.maxInt(u32) or output_len > std.math.maxInt(u32)) return error.TooLarge;
    if (output_len <= input_len) return error.BufferTooSmall;
    return @intCast(output_len);
}
fn overlaps(input: [*]const u8, input_len: usize, output: [*]const u8, output_len: usize) bool {
    const a = @intFromPtr(input);
    const b = @intFromPtr(output);
    return if (a <= b) b - a < input_len else a - b < output_len;
}

// Private inert boundary for facade tests. The C++ fixture independently checks
// SDK forwarding; no executed Zig test path can resolve an actual SDK interface.
const Fake = struct {
    var result: i32 = 1;
    var calls: usize = 0;
    var gamepad_dismissals: usize = 0;
    var floating_dismissals: usize = 0;
    var terminate: bool = true;
    var config: i32 = 7;
    var check_forwarding: bool = false;
    var live_lease: ?Context.Lease = null;
    fn reset() void {
        result = 1;
        calls = 0;
        gamepad_dismissals = 0;
        floating_dismissals = 0;
        terminate = true;
        config = 7;
        check_forwarding = false;
        live_lease = null;
    }
    fn check(condition: bool) void {
        if (!condition) @panic("unexpected Utils fixture arguments");
    }
    fn call() i32 {
        if (live_lease) |lease| lease.check();
        calls += 1;
        return result;
    }
    fn sw_utils_show_gamepad(mode: i32, lines: i32, description: [*:0]const u8, chars: u32, existing: [*:0]const u8, app: *u32) i32 {
        if (check_forwarding) {
            check(mode == 1 and lines == 1 and chars == std.math.maxInt(u32));
            check(std.mem.eql(u8, std.mem.span(description), "é") and std.mem.eql(u8, std.mem.span(existing), "text"));
        }
        app.* = 73;
        return call();
    }
    fn sw_utils_show_floating(mode: i32, x: i32, y: i32, width: i32, height: i32) i32 {
        if (check_forwarding) check(mode == 3 and x == -7 and y == -9 and width == 23 and height == 31);
        return call();
    }
    fn sw_utils_dismiss_gamepad() i32 {
        gamepad_dismissals += 1;
        return call();
    }
    fn sw_utils_dismiss_floating() i32 {
        floating_dismissals += 1;
        return call();
    }
    fn sw_utils_init_filter() i32 {
        return call();
    }
    fn sw_utils_filter(context: i32, source: u64, input: [*:0]const u8, output: [*]u8, capacity: u32, count: *i32) i32 {
        check(context == 2 and source == 123456 and std.mem.eql(u8, std.mem.span(input), "é!!") and capacity == 8);
        const value = call();
        if (value < 0) return value;
        if (terminate) @memcpy(output[0..4], "é*\x00");
        count.* = -3;
        return 0;
    }
    fn sw_utils_default_config(value: *i32) i32 {
        value.* = config;
        const result_value = call();
        return if (result_value < 0) result_value else 0;
    }
};

test "Utils keyboard serialization acceptance and live teardown" {
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    Fake.reset();
    const utils: Utils = .{ .lease = context.lease() };
    Fake.live_lease = utils.lease;
    defer Fake.live_lease = null;
    defer shutdown(utils.lease);
    shutdown(utils.lease);
    try std.testing.expectEqual(@as(usize, 0), Fake.calls);
    try std.testing.expectError(error.KeyboardNotPending, utils.dismissGamepad());
    try std.testing.expectError(error.KeyboardNotPending, utils.dismissFloating());
    const gamepad: GamepadOptions = .{ .mode = .password, .lines = .multiple, .description = "é", .max_characters = std.math.maxInt(u32), .existing_text = "text" };
    const floating: FloatingOptions = .{ .mode = .numeric, .x = -7, .y = -9, .width = 23, .height = 31 };
    Fake.check_forwarding = true;
    Fake.result = 0;
    try std.testing.expect(!try utils.showGamepad(gamepad));
    try std.testing.expect(context.keyboard_state == .none and context.keyboard_app_id == 0);
    try std.testing.expect(!try utils.showFloating(floating));
    try std.testing.expect(context.keyboard_state == .none);
    Fake.result = -1;
    try std.testing.expectError(error.Unavailable, utils.showGamepad(gamepad));
    try std.testing.expectError(error.Unavailable, utils.showFloating(floating));
    try std.testing.expect(context.keyboard_state == .none);
    Fake.result = 1;
    try std.testing.expect(try utils.showGamepad(gamepad));
    try std.testing.expectEqual(@as(u32, 73), context.keyboard_app_id);
    const calls = Fake.calls;
    try std.testing.expectError(error.KeyboardPending, utils.showGamepad(.{ .max_characters = 0 }));
    try std.testing.expectError(error.KeyboardPending, utils.showFloating(floating));
    try std.testing.expectError(error.KeyboardNotPending, utils.dismissFloating());
    try std.testing.expectEqual(calls, Fake.calls);
    try std.testing.expect(try utils.dismissGamepad());
    try std.testing.expect(context.keyboard_state == .gamepad);
    Fake.result = 0;
    try std.testing.expect(!try utils.dismissGamepad());
    Fake.result = -1;
    try std.testing.expectError(error.Unavailable, utils.dismissGamepad());
    try std.testing.expect(context.keyboard_state == .gamepad);
    const before_shutdown = Fake.gamepad_dismissals;
    shutdown(utils.lease);
    try std.testing.expectEqual(before_shutdown + 1, Fake.gamepad_dismissals);
    try std.testing.expect(context.keyboard_state == .none and context.keyboard_app_id == 0);
    Fake.result = 1;
    try std.testing.expect(try utils.showFloating(floating));
    try std.testing.expectError(error.KeyboardPending, utils.showGamepad(gamepad));
    try std.testing.expectError(error.KeyboardPending, utils.showFloating(floating));
    try std.testing.expectError(error.KeyboardNotPending, utils.dismissGamepad());
    try std.testing.expect(try utils.dismissFloating());
    Fake.result = 0;
    try std.testing.expect(!try utils.dismissFloating());
    Fake.result = -1;
    try std.testing.expectError(error.Unavailable, utils.dismissFloating());
    try std.testing.expect(context.keyboard_state == .floating);
    Fake.result = 0;
    const before_floating = Fake.floating_dismissals;
    shutdown(utils.lease);
    try std.testing.expectEqual(before_floating + 1, Fake.floating_dismissals);
    try std.testing.expect(context.keyboard_state == .none);
    const after_shutdown = Fake.calls;
    shutdown(utils.lease);
    try std.testing.expectEqual(after_shutdown, Fake.calls);
}

test "Utils validates text rectangles capacity and overlap before native calls" {
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    Fake.reset();
    const utils: Utils = .{ .lease = context.lease() };
    defer shutdown(utils.lease);
    try std.testing.expectError(error.InteriorNul, utils.showGamepad(.{ .max_characters = 1, .description = "a\x00b" }));
    try std.testing.expectError(error.InvalidUtf8, utils.showGamepad(.{ .max_characters = 1, .existing_text = "\xff" }));
    try std.testing.expectError(error.InvalidRectangle, utils.showFloating(.{ .x = -1, .y = 0, .width = 0, .height = 1 }));
    try std.testing.expectError(error.InvalidRectangle, utils.showFloating(.{ .x = -1, .y = 0, .width = 1, .height = -1 }));
    const options: FilterOptions = .{ .context = .chat, .source = @enumFromInt(123456) };
    var output: [8]u8 = undefined;
    try std.testing.expectError(error.BufferTooSmall, utils.filterText(options, "é!!", output[0..4]));
    try std.testing.expectError(error.InteriorNul, utils.filterText(options, "a\x00b", &output));
    try std.testing.expectError(error.InvalidUtf8, utils.filterText(options, "\xff", &output));
    var shared: [16:0]u8 = @splat(0);
    @memcpy(shared[0..5], "é!!\x00");
    try std.testing.expectError(error.OverlappingBuffers, utils.filterText(options, shared[0..4 :0], shared[0..8]));
    try std.testing.expectError(error.OverlappingBuffers, utils.filterText(options, shared[0..4 :0], shared[4..12]));
    @memcpy(shared[4..9], "é!!\x00");
    try std.testing.expectError(error.OverlappingBuffers, utils.filterText(options, shared[4..8 :0], shared[0..8]));
    try std.testing.expectError(error.TooLarge, filterCapacity(std.math.maxInt(u32), std.math.maxInt(u32)));
    if (@sizeOf(usize) > 4) try std.testing.expectError(error.TooLarge, filterCapacity(0, @as(usize, std.math.maxInt(u32)) + 1));
    try std.testing.expectEqual(@as(u32, 1), try filterCapacity(0, 1));
    try std.testing.expect(!overlaps(shared[0..].ptr, 4, shared[4..].ptr, 4));
    try std.testing.expectEqual(@as(usize, 0), Fake.calls);
    // Empty descriptions/existing text and a zero character limit are forwarded.
    try std.testing.expect(try utils.showGamepad(.{ .max_characters = 0 }));
    shutdown(utils.lease);
}

test "Utils filtering preserves signed characters bytes availability and unknown defaults" {
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    Fake.reset();
    const utils: Utils = .{ .lease = context.lease() };
    try std.testing.expect(try utils.initFilter());
    Fake.result = 0;
    try std.testing.expect(!try utils.initFilter());
    const options: FilterOptions = .{ .context = .chat, .source = @enumFromInt(123456) };
    var output: [8]u8 = @splat(0);
    const result = try utils.filterText(options, "é!!", &output);
    try std.testing.expectEqual(@as(i32, -3), result.filtered_characters);
    try std.testing.expectEqualStrings("é*", result.text);
    try std.testing.expectEqual(@intFromPtr(&output), @intFromPtr(result.text.ptr));
    Fake.terminate = false;
    try std.testing.expectError(error.MalformedNativeOutput, utils.filterText(options, "é!!", &output));
    try std.testing.expectEqual(DefaultConfig.steam_frame, try utils.defaultConfig());
    Fake.config = 12345;
    try std.testing.expectEqual(@as(i32, 12345), @intFromEnum(try utils.defaultConfig()));
    Fake.result = -1;
    try std.testing.expectError(error.Unavailable, utils.initFilter());
    try std.testing.expectError(error.Unavailable, utils.filterText(options, "é!!", &output));
    try std.testing.expectError(error.Unavailable, utils.defaultConfig());
}

test "Utils owned gamepad text distinguishes empty success and cancellation" {
    var value: GamepadText = .{ .status = .complete, .reported_length = 1, .queried_length = 1, .copied_length = 0, .bytes = @splat(0) };
    try std.testing.expectEqualStrings("", value.text().?);
    value.status = .canceled;
    try std.testing.expect(value.text() == null);
    value.status = .complete;
    @memcpy(value.bytes[0..3], "é!");
    value.copied_length = 3;
    const owned_copy = value;
    @memset(&value.bytes, 0);
    try std.testing.expectEqualStrings("é!", owned_copy.text().?);
    value.copied_length = GamepadText.capacity;
    try std.testing.expect(value.text() == null);
    try std.testing.expectEqual(@as(usize, c.SW_UTILS_TEXT_CAPACITY), GamepadText.capacity);
    inline for (.{ .{ GamepadText.Status.canceled, c.SW_UTILS_TEXT_CANCELED }, .{ GamepadText.Status.complete, c.SW_UTILS_TEXT_COMPLETE }, .{ GamepadText.Status.too_large, c.SW_UTILS_TEXT_TOO_LARGE }, .{ GamepadText.Status.unavailable, c.SW_UTILS_TEXT_UNAVAILABLE }, .{ GamepadText.Status.retrieval_failed, c.SW_UTILS_TEXT_RETRIEVAL_FAILED }, .{ GamepadText.Status.malformed, c.SW_UTILS_TEXT_MALFORMED } }) |pair| {
        try std.testing.expectEqual(@as(i32, pair[1]), @intFromEnum(pair[0]));
    }
}
