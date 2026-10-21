//! Borrowed owner-thread Steam Input facade. Construction does nothing.
//! Explicitly start, then runFrame before action reads, then pump/drain Client.
//! Stop before client close; the Client teardown hook makes only a best-effort
//! final attempt. Handles identify SDK objects, not owned resources.
//! Valve: https://partner.steamgames.com/doc/api/ISteamInput
const std = @import("std");
const Context = @import("Context.zig");
const c = @cImport({
    @cInclude("input.h");
});
const native = if (@import("builtin").is_test) TestApi else c;
const Input = @This();

lease: Context.Lease,

pub const Controller = enum(u64) { invalid = 0, all = std.math.maxInt(u64), _ };
pub const ActionSet = enum(u64) { invalid = 0, _ };
pub const DigitalAction = enum(u64) { invalid = 0, _ };
pub const AnalogAction = enum(u64) { invalid = 0, _ };
pub const Origin = enum(i32) { none = 0, _ };
pub const InputType = enum(i32) {
    unknown = 0,
    steam_controller,
    xbox_360,
    xbox_one,
    generic_gamepad,
    ps4,
    apple_mfi,
    android,
    switch_joycon_pair,
    switch_joycon_single,
    switch_pro,
    mobile_touch,
    ps3,
    ps5,
    steam_deck,
    steamos_handheld,
    switch_2_pro,
    steam_controller_2026,
    steam_frame_pair,
    _,
};
pub const SourceMode = enum(i32) {
    none = 0,
    dpad,
    buttons,
    four_buttons,
    absolute_mouse,
    relative_mouse,
    joystick_move,
    joystick_mouse,
    joystick_camera,
    scroll_wheel,
    trigger,
    touch_menu,
    mouse_joystick,
    mouse_region,
    radial_menu,
    single_button,
    switches,
    _,
};
pub const max_controllers = c.SW_INPUT_MAX_CONTROLLERS;
pub const max_active_layers = c.SW_INPUT_MAX_LAYERS;
pub const max_origins = c.SW_INPUT_MAX_ORIGINS;
pub const max_analog_actions = c.SW_INPUT_MAX_ANALOG_ACTIONS;
pub const max_digital_actions = c.SW_INPUT_MAX_DIGITAL_ACTIONS;
pub const maximum_origin = c.SW_INPUT_MAX_ORIGIN;
pub const maximum_input_type = c.SW_INPUT_MAX_TYPE;
pub const Error = error{ InterfaceUnavailable, AlreadyStarted, NotStarted, SessionFailed, InvalidArgument, InsufficientStorage, MalformedCount, NullText };
pub const StartOptions = struct { device_callbacks: bool = false };
pub const StartOutcome = enum { started, rejected };
pub const StopOutcome = enum { stopped, inactive, rejected };
pub const DigitalData = struct { state: bool, active: bool };
/// Raw native floats: mouse modes may report deltas outside [-1, 1].
pub const AnalogData = struct { mode: SourceMode, x: f32, y: f32, active: bool };
pub const GlyphSize = enum(i32) { small = 0, medium, large, _ };
pub const GlyphStyle = struct {
    pub const Base = enum(u32) { knockout = 0, light = 1, dark = 2, _ };
    base: Base = .knockout,
    neutral_color_abxy: bool = false,
    solid_abxy: bool = false,

    fn bits(self: GlyphStyle) Error!u32 {
        const base = @intFromEnum(self.base);
        if (base > 2) return error.InvalidArgument;
        return base | @as(u32, if (self.neutral_color_abxy) 0x10 else 0) | @as(u32, if (self.solid_abxy) 0x20 else 0);
    }
};

/// ISteamInput::Init(true) enables explicit manual runFrame updates. If requested,
/// EnableDeviceCallbacks adds device events to Client dispatch. Rejection poisons
/// this session; no retry. An action manifest/game configuration is still required.
pub fn start(self: Input, options: StartOptions) Error!StartOutcome {
    self.lease.check();
    switch (self.lease.context.input_state) {
        .active => return error.AlreadyStarted,
        .init_failed, .shutdown_failed => return error.SessionFailed,
        .inactive => {},
    }
    var accepted = false;
    try status(native.sw_input_start(options.device_callbacks, &accepted));
    self.lease.context.input_state = if (accepted) .active else .init_failed;
    return if (accepted) .started else .rejected;
}
/// Inactive is an explicit no-op. Rejected Shutdown is never silently retried.
pub fn stop(self: Input) Error!StopOutcome {
    self.lease.check();
    switch (self.lease.context.input_state) {
        .inactive => return .inactive,
        .init_failed, .shutdown_failed => return error.SessionFailed,
        .active => {},
    }
    var accepted = false;
    try status(native.sw_input_stop(&accepted));
    self.lease.context.input_state = if (accepted) .inactive else .shutdown_failed;
    return if (accepted) .stopped else .rejected;
}
/// Client-only final teardown while the lease is still live, before native
/// Steam shutdown. Attempts Shutdown once for active/init_failed; skips unused
/// or previously rejected shutdown. Clears wrapper state, not a cleanup claim.
pub fn shutdown(lease: Context.Lease) void {
    lease.check();
    switch (lease.context.input_state) {
        .active, .init_failed => {
            var accepted = false;
            _ = native.sw_input_stop(&accepted);
        },
        .inactive, .shutdown_failed => {},
    }
    lease.context.input_state = .inactive;
}
/// ISteamInput::RunFrame with SDK 1.65's reserved true argument. Call once per
/// game frame before reading actions; Client.runFrame does not update Input.
pub fn runFrame(self: Input) Error!void {
    try self.checkActive();
    try status(native.sw_input_frame());
}
/// NUL-free, lexically absolute path in host syntax. Windows requires a drive
/// or complete UNC server/share; this wrapper excludes device-namespace paths.
/// Does not check encoding acceptance, existence, contents or manifest loading.
/// The bool is native acceptance, not proof the action configuration is usable.
pub fn setManifestPath(self: Input, path: [:0]const u8) Error!bool {
    try self.checkActive();
    try validString(path);
    if (!absoluteManifestPath(@import("builtin").os.tag, path)) return error.InvalidArgument;
    var accepted = false;
    try status(native.sw_input_manifest(path.ptr, &accepted));
    return accepted;
}
/// All returned slices borrow caller storage. Short or malformed enumeration
/// publishes nothing. Native calls always use a full SDK-sized private array.
pub fn connectedControllers(self: Input, destination: []Controller) Error![]Controller {
    try self.checkActive();
    var values: [max_controllers]u64 = undefined;
    var count: usize = 0;
    try status(native.sw_input_controllers(&values, values.len, &count));
    return publish(Controller, destination, &values, count);
}
/// ISteamInput::GetActionSetHandle by manifest name. Preserves .invalid on a miss;
/// this identity owns no resource and needs no teardown.
pub fn actionSet(self: Input, name: [:0]const u8) Error!ActionSet {
    return @enumFromInt(try self.lookup(0, name));
}
/// ISteamInput::GetDigitalActionHandle by manifest name; .invalid is preserved.
pub fn digitalAction(self: Input, name: [:0]const u8) Error!DigitalAction {
    return @enumFromInt(try self.lookup(1, name));
}
/// ISteamInput::GetAnalogActionHandle by manifest name; .invalid is preserved.
pub fn analogAction(self: Input, name: [:0]const u8) Error!AnalogAction {
    return @enumFromInt(try self.lookup(2, name));
}
/// ISteamInput::ActivateActionSet selects actions for subsequent reads. Void
/// forwarding does not prove the controller or action set is usable.
pub fn activateActionSet(self: Input, controller: Controller, action_set: ActionSet) Error!void {
    try self.activate(0, controller, action_set);
}
pub fn activateLayer(self: Input, controller: Controller, layer: ActionSet) Error!void {
    try self.activate(1, controller, layer);
}
pub fn deactivateLayer(self: Input, controller: Controller, layer: ActionSet) Error!void {
    try self.activate(2, controller, layer);
}
pub fn deactivateAllLayers(self: Input, controller: Controller) Error!void {
    try self.activate(3, controller, .invalid);
}
pub fn currentActionSet(self: Input, controller: Controller) Error!ActionSet {
    try self.checkActive();
    var value: u64 = 0;
    try status(native.sw_input_current_set(@intFromEnum(controller), &value));
    return @enumFromInt(value);
}
pub fn activeLayers(self: Input, controller: Controller, destination: []ActionSet) Error![]ActionSet {
    try self.checkActive();
    var values: [max_active_layers]u64 = undefined;
    var count: usize = 0;
    try status(native.sw_input_layers(@intFromEnum(controller), &values, values.len, &count));
    return publish(ActionSet, destination, &values, count);
}
/// ISteamInput::GetDigitalActionData after runFrame. Check active before state;
/// an inactive action is not equivalent to an active, released button.
pub fn digitalData(self: Input, controller: Controller, action: DigitalAction) Error!DigitalData {
    try self.checkActive();
    var data: c.struct_sw_input_digital = undefined;
    try status(native.sw_input_digital_data(@intFromEnum(controller), @intFromEnum(action), &data));
    return .{ .state = data.state, .active = data.active };
}
/// ISteamInput::GetAnalogActionData after runFrame. Check active and mode before
/// interpreting x/y; mouse deltas need not lie within joystick [-1, 1] bounds.
pub fn analogData(self: Input, controller: Controller, action: AnalogAction) Error!AnalogData {
    try self.checkActive();
    var data: c.struct_sw_input_analog = undefined;
    try status(native.sw_input_analog_data(@intFromEnum(controller), @intFromEnum(action), &data));
    return .{ .mode = @enumFromInt(data.mode), .x = data.x, .y = data.y, .active = data.active };
}
pub fn digitalOrigins(self: Input, controller: Controller, action_set: ActionSet, action: DigitalAction, destination: []Origin) Error![]Origin {
    return self.origins(false, controller, action_set, @intFromEnum(action), destination);
}
pub fn analogOrigins(self: Input, controller: Controller, action_set: ActionSet, action: AnalogAction, destination: []Origin) Error![]Origin {
    return self.origins(true, controller, action_set, @intFromEnum(action), destination);
}
pub fn inputType(self: Input, controller: Controller) Error!InputType {
    try self.checkActive();
    var value: i32 = 0;
    try status(native.sw_input_type(@intFromEnum(controller), &value));
    return @enumFromInt(value);
}
pub fn translateOrigin(self: Input, destination_type: InputType, origin: Origin) Error!Origin {
    try self.checkActive();
    try validOrigin(origin);
    const kind = @intFromEnum(destination_type);
    if (kind < 0 or kind > maximum_input_type) return error.InvalidArgument;
    var value: i32 = 0;
    try status(native.sw_input_translate(kind, @intFromEnum(origin), &value));
    return @enumFromInt(value);
}
/// Text/glyph path slices borrow destination, exclude NUL, and survive later
/// SDK calls. Null, empty and insufficient storage are distinct; no truncation.
/// Paths are not opened and images are not loaded by this wrapper.
pub fn glyphPNG(self: Input, origin: Origin, size: GlyphSize, style: GlyphStyle, destination: []u8) Error![]const u8 {
    try self.checkActive();
    try validOrigin(origin);
    const n = @intFromEnum(size);
    if (n < 0 or n > 2) return error.InvalidArgument;
    return text(0, 0, @intFromEnum(origin), n, try style.bits(), destination);
}
/// ISteamInput::GetGlyphSVGForActionOrigin; copied path borrows destination.
/// Like glyphPNG, excludes NUL, never truncates, and does not load the image.
pub fn glyphSVG(self: Input, origin: Origin, style: GlyphStyle, destination: []u8) Error![]const u8 {
    try self.checkActive();
    try validOrigin(origin);
    return text(1, 0, @intFromEnum(origin), 0, try style.bits(), destination);
}
/// ISteamInput::GetStringForActionOrigin; localized text copied into destination,
/// excluding NUL. NullText and InsufficientStorage are errors, not empty names.
pub fn originName(self: Input, origin: Origin, destination: []u8) Error![]const u8 {
    try self.checkActive();
    try validOrigin(origin);
    return text(2, 0, @intFromEnum(origin), 0, 0, destination);
}
pub fn digitalActionName(self: Input, action: DigitalAction, destination: []u8) Error![]const u8 {
    try self.checkActive();
    return text(3, @intFromEnum(action), 0, 0, 0, destination);
}
pub fn analogActionName(self: Input, action: AnalogAction, destination: []u8) Error![]const u8 {
    try self.checkActive();
    return text(4, @intFromEnum(action), 0, 0, 0, destination);
}
/// Raw motor values. Success means forwarding only, not hardware delivery,
/// capability, duration, or a guaranteed zero-to-stop contract.
pub fn vibrate(self: Input, controller: Controller, left: u16, right: u16) Error!void {
    try self.checkActive();
    try status(native.sw_input_vibration(@intFromEnum(controller), left, right));
}
pub fn vibrateExtended(self: Input, controller: Controller, left: u16, right: u16, left_trigger: u16, right_trigger: u16) Error!void {
    try self.checkActive();
    try status(native.sw_input_vibration_extended(@intFromEnum(controller), left, right, left_trigger, right_trigger));
}

fn checkActive(self: Input) Error!void {
    self.lease.check();
    switch (self.lease.context.input_state) {
        .active => {},
        .inactive => return error.NotStarted,
        .init_failed, .shutdown_failed => return error.SessionFailed,
    }
}
fn status(value: i32) Error!void {
    switch (value) {
        0 => {},
        -1 => return error.InterfaceUnavailable,
        -2 => return error.InvalidArgument,
        -3 => return error.MalformedCount,
        -4 => return error.InsufficientStorage,
        -5 => return error.NullText,
        else => @panic("Invalid private Input status"),
    }
}
fn validString(value: [:0]const u8) Error!void {
    if (std.mem.indexOfScalar(u8, value, 0) != null) return error.InvalidArgument;
}
fn absoluteManifestPath(os: std.Target.Os.Tag, path: []const u8) bool {
    if (os != .windows) return std.fs.path.isAbsolutePosix(path);
    switch (std.fs.path.parsePathWindows(u8, path).kind) {
        .drive_absolute => return true,
        .unc_absolute => {
            // parsePathWindows also classifies incomplete UNC roots as absolute.
            if (path.len <= 2 or path[2] == '/' or path[2] == '\\') return false;
            var parts = std.mem.tokenizeAny(u8, path[2..], "/\\");
            _ = parts.next() orelse return false;
            return parts.next() != null;
        },
        else => return false,
    }
}
fn validOrigin(origin: Origin) Error!void {
    const n = @intFromEnum(origin);
    if (n < 0 or n > maximum_origin) return error.InvalidArgument;
}
fn publish(comptime T: type, destination: []T, values: anytype, count: usize) Error![]T {
    if (count > values.len) return error.MalformedCount;
    if (count > destination.len) return error.InsufficientStorage;
    for (destination[0..count], values[0..count]) |*out, value| out.* = @enumFromInt(value);
    return destination[0..count];
}
fn lookup(self: Input, kind: u32, name: [:0]const u8) Error!u64 {
    try self.checkActive();
    try validString(name);
    var value: u64 = 0;
    try status(native.sw_input_lookup(kind, name.ptr, &value));
    return value;
}
fn activate(self: Input, operation: u32, controller: Controller, action_set: ActionSet) Error!void {
    try self.checkActive();
    try status(native.sw_input_activate(operation, @intFromEnum(controller), @intFromEnum(action_set)));
}
fn origins(self: Input, analog: bool, controller: Controller, action_set: ActionSet, action: u64, destination: []Origin) Error![]Origin {
    try self.checkActive();
    var values: [max_origins]i32 = undefined;
    var count: usize = 0;
    try status(native.sw_input_origins(analog, @intFromEnum(controller), @intFromEnum(action_set), action, &values, values.len, &count));
    return publish(Origin, destination, &values, count);
}
fn text(kind: u32, action: u64, origin: i32, size: i32, style: u32, destination: []u8) Error![]const u8 {
    var length: usize = 0;
    try status(native.sw_input_text(kind, action, origin, size, style, destination.ptr, destination.len, &length));
    return destination[0..length];
}

// Private boundary substitution: no owning-file test can reach Steam.
const TestApi = struct {
    var result: i32 = 0;
    var accepted = true;
    var calls: usize = 0;
    var stops: usize = 0;
    var enumeration_count: usize = 0;
    var last: [6]u64 = @splat(0);
    var returned_text: ?[]const u8 = "glyph/path";
    var digital: c.struct_sw_input_digital = .{ .state = true, .active = false };
    var analog: c.struct_sw_input_analog = .{ .mode = 5, .x = -1234.5, .y = -0.0, .active = false };
    fn reset() void {
        result = 0;
        accepted = true;
        calls = 0;
        stops = 0;
        enumeration_count = 0;
        last = @splat(0);
        returned_text = "glyph/path";
    }
    fn record(args: []const u64) i32 {
        calls += 1;
        @memcpy(last[0..args.len], args);
        return result;
    }
    fn sw_input_start(notifications: bool, out: *bool) i32 {
        out.* = accepted;
        return record(&.{@intFromBool(notifications)});
    }
    fn sw_input_stop(out: *bool) i32 {
        stops += 1;
        out.* = accepted;
        return record(&.{});
    }
    fn sw_input_frame() i32 {
        return record(&.{});
    }
    fn sw_input_manifest(path: [*:0]const u8, out: *bool) i32 {
        std.debug.assert(std.fs.path.isAbsolute(std.mem.span(path)));
        out.* = accepted;
        return record(&.{});
    }
    fn enumerate(comptime T: type, out: [*]T, capacity: usize, count: *usize) i32 {
        for (out[0..capacity], 0..) |*value, i| value.* = @intCast(1000 + i);
        count.* = enumeration_count;
        return result;
    }
    fn sw_input_controllers(out: [*]u64, capacity: usize, count: *usize) i32 {
        std.debug.assert(capacity == max_controllers);
        _ = record(&.{});
        return enumerate(u64, out, capacity, count);
    }
    fn sw_input_layers(controller: u64, out: [*]u64, capacity: usize, count: *usize) i32 {
        std.debug.assert(capacity == max_active_layers);
        _ = record(&.{controller});
        return enumerate(u64, out, capacity, count);
    }
    fn sw_input_lookup(kind: u32, name: [*:0]const u8, out: *u64) i32 {
        std.debug.assert(std.mem.eql(u8, std.mem.span(name), "action"));
        out.* = std.math.maxInt(u64) - 1;
        return record(&.{kind});
    }
    fn sw_input_activate(operation: u32, controller: u64, action_set: u64) i32 {
        return record(&.{ operation, controller, action_set });
    }
    fn sw_input_current_set(controller: u64, out: *u64) i32 {
        out.* = 23;
        return record(&.{controller});
    }
    fn sw_input_digital_data(controller: u64, action: u64, out: *c.struct_sw_input_digital) i32 {
        out.* = digital;
        return record(&.{ controller, action });
    }
    fn sw_input_analog_data(controller: u64, action: u64, out: *c.struct_sw_input_analog) i32 {
        out.* = analog;
        return record(&.{ controller, action });
    }
    fn sw_input_origins(is_analog: bool, controller: u64, action_set: u64, action: u64, out: [*]i32, capacity: usize, count: *usize) i32 {
        std.debug.assert(capacity == max_origins);
        _ = record(&.{ @intFromBool(is_analog), controller, action_set, action });
        return enumerate(i32, out, capacity, count);
    }
    fn sw_input_type(controller: u64, out: *i32) i32 {
        out.* = 254;
        return record(&.{controller});
    }
    fn sw_input_translate(kind: i32, origin: i32, out: *i32) i32 {
        out.* = 32000;
        return record(&.{ @intCast(kind), @intCast(origin) });
    }
    fn sw_input_text(kind: u32, action: u64, origin: i32, size: i32, style: u32, out: [*]u8, capacity: usize, length: *usize) i32 {
        const r = record(&.{ kind, action, @intCast(origin), @intCast(size), style });
        length.* = 0;
        if (r != 0) return r;
        const value = returned_text orelse return -5;
        if (value.len > capacity) return -4;
        @memcpy(out[0..value.len], value);
        length.* = value.len;
        return 0;
    }
    fn sw_input_vibration(controller: u64, left: u16, right: u16) i32 {
        return record(&.{ controller, left, right });
    }
    fn sw_input_vibration_extended(controller: u64, left: u16, right: u16, left_trigger: u16, right_trigger: u16) i32 {
        return record(&.{ controller, left, right, left_trigger, right_trigger });
    }
};

test "Input lifecycle preserves rejection and unavailable state without silent retries" {
    TestApi.reset();
    var context: Context = undefined;
    try context.claim();
    var owns_context = true;
    defer if (owns_context) {
        shutdown(context.lease());
        context.release();
    };
    const input: Input = .{ .lease = context.lease() };
    try std.testing.expectEqual(.inactive, try input.stop());
    shutdown(input.lease);
    try std.testing.expectEqual(@as(usize, 0), TestApi.calls);
    try std.testing.expectError(error.NotStarted, input.runFrame());
    TestApi.result = -1;
    try std.testing.expectError(error.InterfaceUnavailable, input.start(.{}));
    try std.testing.expect(context.input_state == .inactive);
    TestApi.result = 0;
    try std.testing.expectEqual(.started, try input.start(.{ .device_callbacks = true }));
    try std.testing.expectEqual(@as(u64, 1), TestApi.last[0]);
    const calls = TestApi.calls;
    try std.testing.expectError(error.AlreadyStarted, input.start(.{}));
    try std.testing.expectEqual(calls, TestApi.calls);
    try input.runFrame();
    TestApi.result = -1;
    try std.testing.expectError(error.InterfaceUnavailable, input.stop());
    try std.testing.expect(context.input_state == .active);
    TestApi.result = 0;
    try std.testing.expectEqual(.stopped, try input.stop());
    try std.testing.expectEqual(.inactive, try input.stop());
    TestApi.accepted = false;
    try std.testing.expectEqual(.rejected, try input.start(.{}));
    const before = TestApi.calls;
    try std.testing.expectError(error.SessionFailed, input.start(.{}));
    try std.testing.expectError(error.SessionFailed, input.stop());
    try std.testing.expectError(error.SessionFailed, input.runFrame());
    try std.testing.expectEqual(before, TestApi.calls);
    shutdown(input.lease);
    try std.testing.expectEqual(before + 1, TestApi.calls);
    try std.testing.expect(context.input_state == .inactive);
    // Final teardown ends a session: reset through Context, not another start.
    context.release();
    owns_context = false;
    try context.claim();
    owns_context = true;
    const renewed: Input = .{ .lease = context.lease() };
    TestApi.accepted = true;
    _ = try renewed.start(.{});
    TestApi.accepted = false;
    try std.testing.expectEqual(.rejected, try renewed.stop());
    const after = TestApi.calls;
    try std.testing.expectError(error.SessionFailed, renewed.start(.{}));
    try std.testing.expectError(error.SessionFailed, renewed.stop());
    shutdown(renewed.lease);
    try std.testing.expectEqual(after, TestApi.calls);
}

test "Input final shutdown is live-lease best effort and skips an unused feature" {
    TestApi.reset();
    var context: Context = undefined;
    try context.claim();
    defer {
        shutdown(context.lease());
        context.release();
    }
    const input: Input = .{ .lease = context.lease() };
    shutdown(input.lease);
    try std.testing.expectEqual(@as(usize, 0), TestApi.stops);
    _ = try input.start(.{});
    TestApi.result = -1;
    shutdown(input.lease);
    try std.testing.expectEqual(@as(usize, 1), TestApi.stops);
    try std.testing.expect(context.input_state == .inactive);
    shutdown(input.lease);
    try std.testing.expectEqual(@as(usize, 1), TestApi.stops);
}

test "Input enumerations publish zero exact short and malformed counts atomically" {
    TestApi.reset();
    var context: Context = undefined;
    try context.claim();
    defer {
        shutdown(context.lease());
        context.release();
    }
    const input: Input = .{ .lease = context.lease() };
    _ = try input.start(.{});
    var controllers: [max_controllers]Controller = @splat(.invalid);
    var layers: [max_active_layers]ActionSet = @splat(.invalid);
    var origins_out: [max_origins]Origin = @splat(.none);
    try std.testing.expectEqual(@as(usize, 0), (try input.connectedControllers(&controllers)).len);
    try std.testing.expectEqual(@as(usize, 0), (try input.activeLayers(.all, &layers)).len);
    try std.testing.expectEqual(@as(usize, 0), (try input.digitalOrigins(.all, .invalid, .invalid, &origins_out)).len);
    try std.testing.expectEqual(@as(usize, 0), (try input.analogOrigins(.all, .invalid, .invalid, &origins_out)).len);
    TestApi.enumeration_count = max_controllers;
    try std.testing.expectError(error.InsufficientStorage, input.connectedControllers(controllers[0 .. max_controllers - 1]));
    try std.testing.expectEqual(Controller.invalid, controllers[0]);
    try std.testing.expectEqual(@as(usize, max_controllers), (try input.connectedControllers(&controllers)).len);
    TestApi.enumeration_count = max_active_layers;
    try std.testing.expectError(error.InsufficientStorage, input.activeLayers(.all, layers[0 .. max_active_layers - 1]));
    try std.testing.expectEqual(ActionSet.invalid, layers[0]);
    try std.testing.expectEqual(@as(usize, max_active_layers), (try input.activeLayers(.all, &layers)).len);
    TestApi.enumeration_count = max_origins;
    inline for (.{ false, true }) |is_analog| {
        origins_out = @splat(.none);
        if (is_analog) {
            try std.testing.expectError(error.InsufficientStorage, input.analogOrigins(.all, @enumFromInt(7), @enumFromInt(8), origins_out[0 .. max_origins - 1]));
            try std.testing.expectEqual(Origin.none, origins_out[0]);
            _ = try input.analogOrigins(.all, @enumFromInt(7), @enumFromInt(8), &origins_out);
        } else {
            try std.testing.expectError(error.InsufficientStorage, input.digitalOrigins(.all, @enumFromInt(7), @enumFromInt(8), origins_out[0 .. max_origins - 1]));
            try std.testing.expectEqual(Origin.none, origins_out[0]);
            _ = try input.digitalOrigins(.all, @enumFromInt(7), @enumFromInt(8), &origins_out);
        }
        try std.testing.expectEqual(@as(u64, @intFromBool(is_analog)), TestApi.last[0]);
        try std.testing.expectEqual(@as(u64, 7), TestApi.last[2]);
        try std.testing.expectEqual(@as(u64, 8), TestApi.last[3]);
        for (origins_out, 0..) |v, i| try std.testing.expectEqual(@as(i32, @intCast(1000 + i)), @intFromEnum(v));
    }
    for (controllers, layers, 0..) |h, l, i| {
        try std.testing.expectEqual(@as(u64, 1000 + i), @intFromEnum(h));
        try std.testing.expectEqual(@as(u64, 1000 + i), @intFromEnum(l));
    }
    controllers = @splat(.invalid);
    layers = @splat(.invalid);
    origins_out = @splat(.none);
    TestApi.enumeration_count = std.math.maxInt(usize);
    try std.testing.expectError(error.MalformedCount, input.connectedControllers(&controllers));
    try std.testing.expectError(error.MalformedCount, input.activeLayers(.all, &layers));
    try std.testing.expectError(error.MalformedCount, input.digitalOrigins(.all, .invalid, .invalid, &origins_out));
    try std.testing.expectError(error.MalformedCount, input.analogOrigins(.all, .invalid, .invalid, &origins_out));
    try std.testing.expectEqual(Controller.invalid, controllers[0]);
    try std.testing.expectEqual(ActionSet.invalid, layers[0]);
    try std.testing.expectEqual(Origin.none, origins_out[0]);
}

test "Input distinct handles action forwarding and raw state conversion" {
    try std.testing.expect(Controller != ActionSet and ActionSet != DigitalAction and DigitalAction != AnalogAction);
    TestApi.reset();
    var context: Context = undefined;
    try context.claim();
    defer {
        shutdown(context.lease());
        context.release();
    }
    const input: Input = .{ .lease = context.lease() };
    _ = try input.start(.{});
    const set = try input.actionSet("action");
    try std.testing.expectEqual(@as(u64, 0), TestApi.last[0]);
    const digital = try input.digitalAction("action");
    try std.testing.expectEqual(@as(u64, 1), TestApi.last[0]);
    const analog = try input.analogAction("action");
    try std.testing.expectEqual(@as(u64, 2), TestApi.last[0]);
    try std.testing.expectEqual(std.math.maxInt(u64) - 1, @intFromEnum(set));
    try std.testing.expectEqual(@intFromEnum(set), @intFromEnum(digital));
    try std.testing.expectEqual(@intFromEnum(set), @intFromEnum(analog));
    try input.activateActionSet(.all, set);
    try std.testing.expectEqualSlices(u64, &.{ 0, std.math.maxInt(u64), @intFromEnum(set) }, TestApi.last[0..3]);
    try input.activateLayer(.all, set);
    try std.testing.expectEqual(@as(u64, 1), TestApi.last[0]);
    try input.deactivateLayer(.all, set);
    try std.testing.expectEqual(@as(u64, 2), TestApi.last[0]);
    try input.deactivateAllLayers(.all);
    try std.testing.expectEqualSlices(u64, &.{ 3, std.math.maxInt(u64), 0 }, TestApi.last[0..3]);
    try std.testing.expectEqual(@as(u64, 23), @intFromEnum(try input.currentActionSet(.all)));
    for ([_]bool{ false, true }) |active| for ([_]bool{ false, true }) |state| {
        TestApi.digital = .{ .state = state, .active = active };
        try std.testing.expectEqual(DigitalData{ .state = state, .active = active }, try input.digitalData(.all, digital));
    };
    for ([_]u32{ 0x80000000, 0x7fc12345, 0x7f800000, 0xc49a5000 }) |bits| {
        TestApi.analog = .{ .mode = 31, .x = @bitCast(bits), .y = @bitCast(bits ^ 0x80000000), .active = false };
        const data = try input.analogData(.all, analog);
        try std.testing.expectEqual(@as(i32, 31), @intFromEnum(data.mode));
        try std.testing.expectEqual(bits, @as(u32, @bitCast(data.x)));
        try std.testing.expectEqual(bits ^ 0x80000000, @as(u32, @bitCast(data.y)));
        try std.testing.expect(!data.active);
    }
    try std.testing.expectEqual(@as(i32, 254), @intFromEnum(try input.inputType(.all)));
    try std.testing.expectEqual(@as(i32, 32000), @intFromEnum(try input.translateOrigin(@enumFromInt(254), @enumFromInt(32767))));
    try std.testing.expectEqualSlices(u64, &.{ 254, 32767 }, TestApi.last[0..2]);
    try input.vibrate(.all, 0, 65535);
    try std.testing.expectEqualSlices(u64, &.{ std.math.maxInt(u64), 0, 65535 }, TestApi.last[0..3]);
    try input.vibrateExtended(.all, 1, 2, 3, 65535);
    try std.testing.expectEqualSlices(u64, &.{ std.math.maxInt(u64), 1, 2, 3, 65535 }, TestApi.last[0..5]);
}

test "Input glyph styles text ownership and local input validation" {
    TestApi.reset();
    var context: Context = undefined;
    try context.claim();
    defer {
        shutdown(context.lease());
        context.release();
    }
    const input: Input = .{ .lease = context.lease() };
    _ = try input.start(.{});
    var buffer: [64]u8 = @splat(0xaa);
    const path = if (@import("builtin").os.tag == .windows) "C:" ++ "\\manifest.vdf" else "/manifest.vdf";
    try std.testing.expect(try input.setManifestPath(path));
    TestApi.accepted = false;
    try std.testing.expect(!try input.setManifestPath(path));
    for ([_]GlyphStyle.Base{ .knockout, .light, .dark }) |base| for ([_]bool{ false, true }) |neutral| for ([_]bool{ false, true }) |solid| {
        const style: GlyphStyle = .{ .base = base, .neutral_color_abxy = neutral, .solid_abxy = solid };
        const copied = try input.glyphPNG(@enumFromInt(32767), .large, style, &buffer);
        try std.testing.expectEqualStrings("glyph/path", copied);
        try std.testing.expectEqual(@as(u64, try style.bits()), TestApi.last[4]);
        try std.testing.expectEqual(@as(u64, 2), TestApi.last[3]);
        _ = try input.glyphSVG(@enumFromInt(32767), style, &buffer);
        try std.testing.expectEqual(@as(u64, 1), TestApi.last[0]);
    };
    const copied = try input.originName(.none, &buffer);
    TestApi.returned_text = "changed";
    try std.testing.expectEqualStrings("glyph/path", copied);
    _ = try input.digitalActionName(@enumFromInt(71), &buffer);
    try std.testing.expectEqualSlices(u64, &.{ 3, 71 }, TestApi.last[0..2]);
    _ = try input.analogActionName(@enumFromInt(72), &buffer);
    try std.testing.expectEqualSlices(u64, &.{ 4, 72 }, TestApi.last[0..2]);
    buffer = @splat(0xaa);
    try std.testing.expectError(error.InsufficientStorage, input.originName(.none, buffer[0..1]));
    try std.testing.expectEqual(@as(u8, 0xaa), buffer[0]);
    TestApi.returned_text = "";
    try std.testing.expectEqual(@as(usize, 0), (try input.originName(.none, buffer[0..0])).len);
    TestApi.returned_text = null;
    try std.testing.expectError(error.NullText, input.originName(.none, &buffer));
    const before = TestApi.calls;
    try std.testing.expectError(error.InvalidArgument, input.setManifestPath("relative"));
    try std.testing.expectError(error.InvalidArgument, input.setManifestPath("/a\x00b"));
    try std.testing.expectError(error.InvalidArgument, input.actionSet("a\x00b"));
    try std.testing.expectError(error.InvalidArgument, input.translateOrigin(@enumFromInt(256), .none));
    try std.testing.expectError(error.InvalidArgument, input.translateOrigin(.unknown, @enumFromInt(-1)));
    try std.testing.expectError(error.InvalidArgument, input.originName(@enumFromInt(32768), &buffer));
    try std.testing.expectError(error.InvalidArgument, input.glyphPNG(.none, @enumFromInt(3), .{}, &buffer));
    try std.testing.expectError(error.InvalidArgument, input.glyphSVG(.none, .{ .base = @enumFromInt(3) }, &buffer));
    try std.testing.expectEqual(before, TestApi.calls);
}

test "Input inactive and failed sessions reject every operation before validation" {
    TestApi.reset();
    var context: Context = undefined;
    try context.claim();
    defer {
        shutdown(context.lease());
        context.release();
    }
    const input: Input = .{ .lease = context.lease() };
    var handles: [0]Controller = .{};
    var layers: [0]ActionSet = .{};
    var origins_out: [0]Origin = .{};
    var buffer: [0]u8 = .{};
    inline for (.{ .inactive, .init_failed, .shutdown_failed }) |state| {
        context.input_state = state;
        const expected = if (state == .inactive) error.NotStarted else error.SessionFailed;
        try std.testing.expectError(expected, input.runFrame());
        try std.testing.expectError(expected, input.setManifestPath("relative"));
        try std.testing.expectError(expected, input.connectedControllers(&handles));
        try std.testing.expectError(expected, input.actionSet("bad\x00name"));
        try std.testing.expectError(expected, input.digitalAction("bad\x00name"));
        try std.testing.expectError(expected, input.analogAction("bad\x00name"));
        try std.testing.expectError(expected, input.activateActionSet(.all, .invalid));
        try std.testing.expectError(expected, input.activateLayer(.all, .invalid));
        try std.testing.expectError(expected, input.deactivateLayer(.all, .invalid));
        try std.testing.expectError(expected, input.deactivateAllLayers(.all));
        try std.testing.expectError(expected, input.currentActionSet(.all));
        try std.testing.expectError(expected, input.activeLayers(.all, &layers));
        try std.testing.expectError(expected, input.digitalData(.all, .invalid));
        try std.testing.expectError(expected, input.analogData(.all, .invalid));
        try std.testing.expectError(expected, input.digitalOrigins(.all, .invalid, .invalid, &origins_out));
        try std.testing.expectError(expected, input.analogOrigins(.all, .invalid, .invalid, &origins_out));
        try std.testing.expectError(expected, input.inputType(.all));
        try std.testing.expectError(expected, input.translateOrigin(@enumFromInt(-1), .none));
        try std.testing.expectError(expected, input.glyphPNG(.none, @enumFromInt(-1), .{}, &buffer));
        try std.testing.expectError(expected, input.glyphSVG(@enumFromInt(-1), .{}, &buffer));
        try std.testing.expectError(expected, input.originName(@enumFromInt(-1), &buffer));
        try std.testing.expectError(expected, input.digitalActionName(.invalid, &buffer));
        try std.testing.expectError(expected, input.analogActionName(.invalid, &buffer));
        try std.testing.expectError(expected, input.vibrate(.all, 0, 0));
        try std.testing.expectError(expected, input.vibrateExtended(.all, 0, 0, 0, 0));
    }
    try std.testing.expectEqual(@as(usize, 0), TestApi.calls);
}

test "Input manifest paths are lexically absolute without filesystem access" {
    for ([_][]const u8{ "/manifest.vdf", "/a/../manifest.vdf", "/", "//server/share/manifest.vdf" }) |path| {
        try std.testing.expect(absoluteManifestPath(.linux, path));
        try std.testing.expect(absoluteManifestPath(.macos, path));
    }
    const drive = "C:";
    for ([_][]const u8{ "", "manifest.vdf", drive ++ "\\manifest.vdf", "./manifest.vdf" }) |path| {
        try std.testing.expect(!absoluteManifestPath(.linux, path));
        try std.testing.expect(!absoluteManifestPath(.macos, path));
    }
    for ([_][]const u8{ drive ++ "\\manifest.vdf", "D:" ++ "/a/../manifest.vdf", drive ++ "/", "\\\\server\\share\\manifest.vdf", "//server/share/manifest.vdf", "\\\\server\\share" }) |path| {
        try std.testing.expect(absoluteManifestPath(.windows, path));
    }
    for ([_][]const u8{ "", "manifest.vdf", "C:", "C:manifest.vdf", "\\manifest.vdf", "/manifest.vdf", "\\\\", "\\\\server", "\\\\server\\", "\\\\\\share", "//server/", "//", "\\\\?\\" ++ drive ++ "\\manifest.vdf", "\\\\.\\" ++ drive ++ "\\manifest.vdf", "\\\\?", "\\\\." }) |path| {
        try std.testing.expect(!absoluteManifestPath(.windows, path));
    }
}
