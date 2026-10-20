const std = @import("std");
const Context = @import("Context.zig");
const types = @import("types.zig");
const events = @import("events.zig");
const services = @import("services.zig");
const Networking = @import("Networking.zig");
const NetworkingConfig = @import("NetworkingConfig.zig");
const NetworkingDebug = @import("NetworkingDebug.zig");
const Lobbies = @import("Lobbies.zig");
const Utils = @import("Utils.zig");
const Input = @import("Input.zig");
const Voice = @import("Voice.zig");
const RemotePlay = @import("RemotePlay.zig");
const Timeline = @import("Timeline.zig");
const Workshop = @import("Workshop.zig");
const Screenshots = @import("Screenshots.zig");
const c = @import("native.zig").c;
const Client = @This();

context: Context,
pipe: i32,

pub const InitError = error{ AlreadyInitialized, InitializationFailed, SteamClientUnavailable, SteamVersionMismatch, MissingInterface };
pub const Diagnostic = struct {
    message: [c.SW_INIT_MESSAGE_SIZE]u8 = @splat(0),
    pub fn text(self: *const Diagnostic) []const u8 {
        return types.text(&self.message);
    }
};
pub const Ticket = struct { handle: types.AuthTicket, bytes: []const u8 };
pub const BeginAuthResult = enum(i32) { ok = 0, invalid_ticket = 1, duplicate_request = 2, invalid_version = 3, wrong_game = 4, expired_ticket = 5, _ };
pub const License = enum(i32) { has_license = 0, no_license = 1, not_authenticated = 2, _ };

/// Owns the process-wide Steam session. Keep this value at its original address.
/// Call every method on the initializing thread. Do not mix another Steam wrapper
/// or SteamAPI_RunCallbacks with this manual-dispatch client.
pub fn init(self: *Client, diagnostic: *Diagnostic) InitError!void {
    try self.initialize(diagnostic, c.sw_init);
}

fn initialize(self: *Client, diagnostic: *Diagnostic, comptime native_init: @TypeOf(c.sw_init)) InitError!void {
    diagnostic.* = .{};
    try self.context.claim();
    errdefer self.context.release();
    try initializationResult(native_init(&diagnostic.message));
    self.pipe = c.sw_pipe();
}

/// Release messages, close sockets/listeners/groups, leave lobbies, and end auth
/// sessions first, and end any acquired cloud write batch. Pending results are
/// discarded, not delivered during shutdown. Optional teardown is best effort.
/// Pending Workshop queries are not cancelled or drained here. Screenshot input
/// borrowing does not end at session teardown. See Screenshots for retention rules.
/// Borrowed interfaces and session resource handles expire with this session.
/// Diagnostic admission stops before native shutdown. This does not establish
/// callback quiescence; diagnostic code/storage remain valid for the process.
pub fn deinit(self: *Client) void {
    self.deinitialize(c.sw_shutdown);
}

fn deinitialize(self: *Client, comptime native_shutdown: @TypeOf(c.sw_shutdown)) void {
    self.context.checkCanClose();
    NetworkingDebug.shutdown(self.context.lease());
    Utils.shutdown(self.context.lease());
    Input.shutdown(self.context.lease());
    Voice.shutdown(self.context.lease());
    Timeline.shutdown(self.context.lease());
    Workshop.shutdown(self.context.lease());
    Screenshots.shutdown(self.context.lease());
    native_shutdown();
    self.context.release();
}

/// Explicit shipping policy. Call before init and exit promptly when true.
/// Development examples intentionally do not relaunch Steam or the game.
pub fn restartIfNecessary(app: types.AppId) bool {
    if (app == .invalid) @panic("Steamworks restart requires a valid App ID");
    return c.sw_restart_if_necessary(@intFromEnum(app)) != 0;
}

/// Call once per render frame, including title screens and paused simulation.
pub fn runFrame(self: *const Client) void {
    self.context.check();
    c.sw_run_frame(self.pipe);
}

/// Drain after runFrame. Every event owns its payload, and the SDK callback is
/// already freed when this returns. Unknown callbacks are explicit events.
/// An empty drain also releases Steam's calling-thread parameter memory.
/// Draining updates keyboard/request ownership even when the caller ignores events.
pub fn nextEvent(self: *Client) ?events.Event {
    return self.nextEventWith(c.sw_next_event);
}

fn nextEventWith(self: *Client, comptime native_poll: @TypeOf(c.sw_next_event)) ?events.Event {
    self.context.check();
    const state: c.SwPollState = .{
        .leaderboard_download_call = self.context.leaderboard_download_call,
        .keyboard_app_id = self.context.keyboard_app_id,
        .gamepad_pending = @intFromBool(self.context.keyboard_state == .gamepad),
    };
    var native: c.SwEvent = undefined;
    if (native_poll(self.pipe, &state, &native) == 0) return null;
    const event = events.decode(&native);
    self.observeEvent(&event);
    return event;
}

fn observeEvent(self: *Client, event: *const events.Event) void {
    Workshop.observeCompletion(self.context.lease(), event);
    const call = @intFromEnum(event.call);
    if (call != 0 and call == self.context.leaderboard_download_call) {
        self.context.leaderboard_download_call = 0;
        self.context.leaderboard_download_blocked = switch (event.payload) {
            .leaderboard_entries => |*capture| !downloadAccessComplete(capture),
            else => true,
        };
    }
    if (call != 0 and call == self.context.leaderboard_upload_call) self.context.leaderboard_upload_call = 0;
    // Keyboard dismissal is a broadcast, never an API-call completion.
    if (call != 0) return;
    switch (event.payload) {
        .gamepad_dismissed => |value| {
            if (!value.matched or self.context.keyboard_state != .gamepad or @intFromEnum(value.app) != self.context.keyboard_app_id) return;
            self.context.keyboard_state = .none;
            self.context.keyboard_app_id = 0;
        },
        .floating_dismissed => {
            if (self.context.keyboard_state == .floating) {
                self.context.keyboard_state = .none;
                self.context.keyboard_app_id = 0;
            }
        },
        else => {},
    }
}

fn downloadAccessComplete(value: *const types.LeaderboardEntries) bool {
    if (!value.all_rows_accessed or value.reported_count < 0 or value.reported_count > types.LeaderboardEntries.max_entries) return false;
    return switch (value.status) {
        .complete => value.copied_count == value.reported_count and value.failure_index == -1,
        .invalid_details => value.failure_index >= 0 and value.failure_index < value.reported_count and value.copied_count == value.failure_index and (value.reported_details < 0 or value.reported_details > types.LeaderboardEntry.max_details),
        else => false,
    };
}

pub fn userId(self: *const Client) types.SteamId {
    self.context.check();
    return @enumFromInt(c.sw_user_id());
}
pub fn appId(self: *const Client) types.AppId {
    self.context.check();
    return @enumFromInt(c.sw_app_id());
}
pub fn loggedOn(self: *const Client) bool {
    self.context.check();
    return c.sw_logged_on() != 0;
}
pub fn overlayEnabled(self: *const Client) bool {
    self.context.check();
    return c.sw_overlay_enabled() != 0;
}
pub fn serverTime(self: *const Client) u32 {
    self.context.check();
    return c.sw_server_time();
}

pub fn networking(self: *Client) Networking {
    self.context.check();
    return .{ .lease = self.context.lease() };
}
/// Borrowed facade only. Construction does not query or change native settings.
pub fn networkingConfig(self: *Client) NetworkingConfig {
    self.context.check();
    return .{ .lease = self.context.lease() };
}
/// Borrowed facade only. Call start explicitly to register diagnostic capture.
pub fn networkingDebug(self: *Client) NetworkingDebug.Capture {
    self.context.check();
    return .{ .lease = self.context.lease() };
}
/// Borrowed facade only. Keyboard/filter actions require explicit calls.
pub fn utils(self: *Client) Utils {
    self.context.check();
    return .{ .lease = self.context.lease() };
}
/// Borrowed facade only. Explicitly start and update before action reads.
/// Client.runFrame does not update Input implicitly.
pub fn input(self: *Client) Input {
    self.context.check();
    return .{ .lease = self.context.lease() };
}
/// Borrowed facade only. Recording and decoding require explicit calls.
pub fn voice(self: *Client) Voice {
    self.context.check();
    return .{ .lease = self.context.lease() };
}
/// Borrowed facade only. No session query, UI action or invitation occurs here.
pub fn remotePlay(self: *Client) RemotePlay {
    self.context.check();
    return .{ .lease = self.context.lease() };
}
/// Borrowed facade only. No recording metadata is changed here.
pub fn timeline(self: *Client) Timeline {
    self.context.check();
    return .{ .lease = self.context.lease() };
}
/// Borrowed facade only. Queries and downloads require explicit calls.
pub fn workshop(self: *Client) Workshop {
    self.context.check();
    return .{ .lease = self.context.lease() };
}
/// Borrowed facade only. No screenshot or hook action occurs here.
pub fn screenshots(self: *Client) Screenshots {
    self.context.check();
    return .{ .lease = self.context.lease() };
}
pub fn lobbies(self: *Client) Lobbies {
    self.context.check();
    return .{ .lease = self.context.lease() };
}
pub fn friends(self: *Client) services.Friends {
    self.context.check();
    return .{ .lease = self.context.lease() };
}
pub fn apps(self: *Client) services.Apps {
    self.context.check();
    return .{ .lease = self.context.lease() };
}
pub fn stats(self: *Client) services.Stats {
    self.context.check();
    return .{ .lease = self.context.lease() };
}
pub fn cloud(self: *Client) services.Cloud {
    self.context.check();
    return .{ .lease = self.context.lease() };
}

/// Bytes borrow caller storage. Wait for a matching successful auth_ticket event
/// before transmitting them. Cancel the ticket when the connection ends.
/// Bind the ticket to the receiving Steam user when its identity is known.
pub fn authSessionTicket(self: *const Client, buffer: []u8, recipient: ?types.SteamId) !Ticket {
    if (buffer.len == 0) return error.BufferTooSmall;
    if (recipient == .invalid) return error.InvalidRecipient;
    const capacity = try types.count(buffer.len);
    self.context.check();
    var size: u32 = 0;
    const handle = c.sw_auth_ticket(buffer.ptr, capacity, &size, if (recipient) |id| @intFromEnum(id) else 0);
    if (handle == 0) return error.TicketRejected;
    if (size > buffer.len) {
        c.sw_cancel_ticket(handle);
        return error.InvalidNativeResult;
    }
    return .{ .handle = @enumFromInt(handle), .bytes = buffer[0..size] };
}

/// Ticket bytes arrive in web_ticket. Keep publisher secrets on a trusted server.
pub fn webApiTicket(self: *const Client, identity: [:0]const u8) !types.AuthTicket {
    if (identity.len == 0 or std.mem.indexOfScalar(u8, identity, 0) != null) return error.InvalidIdentity;
    self.context.check();
    const handle = c.sw_web_ticket(identity.ptr);
    if (handle == 0) return error.TicketRejected;
    return @enumFromInt(handle);
}
pub fn cancelTicket(self: *const Client, ticket: types.AuthTicket) void {
    self.context.check();
    if (ticket != .invalid) c.sw_cancel_ticket(@intFromEnum(ticket));
}
/// An immediate .ok is not final authentication. Observe auth_validated and
/// later revocation events before granting or retaining application permissions.
pub fn beginAuthSession(self: *const Client, user: types.SteamId, ticket: []const u8) !BeginAuthResult {
    if (user == .invalid or ticket.len == 0) return error.InvalidTicket;
    const size = try types.count(ticket.len);
    self.context.check();
    return @enumFromInt(c.sw_begin_auth(ticket.ptr, size, @intFromEnum(user)));
}
pub fn endAuthSession(self: *const Client, user: types.SteamId) void {
    self.context.check();
    c.sw_end_auth(@intFromEnum(user));
}
/// For an authenticated peer. Missing authentication is not an offline status.
/// Use apps().owns(app) to query the local user's ownership instead.
pub fn userLicense(self: *const Client, user: types.SteamId, app: types.AppId) License {
    self.context.check();
    return @enumFromInt(c.sw_user_license(@intFromEnum(user), @intFromEnum(app)));
}

test "platform completion draining correlates slots and preserves keyboard ownership" {
    const Native = struct {
        var context: *Context = undefined;
        var event: c.SwEvent = undefined;
        var ready = true;
        fn poll(pipe: i32, state: [*c]const c.SwPollState, out: [*c]c.SwEvent) callconv(.c) u8 {
            context.check();
            std.testing.expect(pipe == 33 and state[0].leaderboard_download_call == context.leaderboard_download_call and state[0].keyboard_app_id == context.keyboard_app_id and state[0].gamepad_pending == @intFromBool(context.keyboard_state == .gamepad)) catch @panic("poll state mismatch");
            if (!ready) return 0;
            out[0] = event;
            return 1;
        }
    };
    var client: Client = undefined;
    try client.context.claim();
    defer {
        Utils.shutdown(client.context.lease());
        Input.shutdown(client.context.lease());
        client.context.release();
    }
    client.pipe = 33;
    Native.context = &client.context;
    _ = client.utils();
    _ = client.input();
    try std.testing.expect(client.context.keyboard_state == .none and client.context.input_state == .inactive);
    client.context.leaderboard_download_call = 101;
    client.context.leaderboard_upload_call = 202;
    client.context.keyboard_state = .gamepad;
    client.context.keyboard_app_id = 73;
    Native.ready = false;
    try std.testing.expect(client.nextEventWith(Native.poll) == null);
    try std.testing.expectEqual(@as(u64, 101), client.context.leaderboard_download_call);
    Native.ready = true;
    Native.event = std.mem.zeroes(c.SwEvent);
    Native.event.kind = c.SW_LEADERBOARD_ENTRIES;
    const capture = &Native.event.data.leaderboard_download.capture;
    capture.reported_count = 1;
    capture.copied_count = 1;
    capture.failure_index = -1;
    capture.all_rows_accessed = 1;
    for ([_]u64{ 0, 99 }) |call| {
        Native.event.call = call;
        _ = client.nextEventWith(Native.poll);
        try std.testing.expectEqual(@as(u64, 101), client.context.leaderboard_download_call);
    }
    Native.event.call = 101;
    _ = client.nextEventWith(Native.poll); // Discarding the result still releases the slot.
    try std.testing.expectEqual(@as(u64, 0), client.context.leaderboard_download_call);
    try std.testing.expect(!client.context.leaderboard_download_blocked);
    try std.testing.expectEqual(@as(u64, 202), client.context.leaderboard_upload_call);
    Native.event.kind = c.SW_CALL_FAILED;
    Native.event.call = 202;
    Native.event.data.call_failure.reason = c.SW_IO_FAILURE;
    _ = client.nextEventWith(Native.poll);
    try std.testing.expectEqual(@as(u64, 0), client.context.leaderboard_upload_call);
    try std.testing.expect(client.context.keyboard_state == .gamepad);
    Native.event = std.mem.zeroes(c.SwEvent);
    Native.event.kind = c.SW_GAMEPAD_DISMISSED;
    Native.event.data.gamepad.capture.status = c.SW_UTILS_TEXT_CANCELED;
    Native.event.data.gamepad.matched = 1;
    Native.event.data.gamepad.app = 74;
    _ = client.nextEventWith(Native.poll);
    try std.testing.expect(client.context.keyboard_state == .gamepad);
    Native.event.data.gamepad.app = 73;
    Native.event.data.gamepad.matched = 0;
    _ = client.nextEventWith(Native.poll);
    try std.testing.expect(client.context.keyboard_state == .gamepad);
    Native.event.kind = c.SW_FLOATING_DISMISSED;
    _ = client.nextEventWith(Native.poll);
    try std.testing.expect(client.context.keyboard_state == .gamepad);
    Native.event.kind = c.SW_GAMEPAD_DISMISSED;
    Native.event.data.gamepad.matched = 1;
    _ = client.nextEventWith(Native.poll);
    try std.testing.expect(client.context.keyboard_state == .none and client.context.keyboard_app_id == 0);
    client.context.keyboard_state = .floating;
    _ = client.nextEventWith(Native.poll);
    try std.testing.expect(client.context.keyboard_state == .floating);
    Native.event.kind = c.SW_FLOATING_DISMISSED;
    _ = client.nextEventWith(Native.poll);
    try std.testing.expect(client.context.keyboard_state == .none);
}

test "platform download cleanup uncertainty blocks while matching uploads always clear" {
    const Native = struct {
        var event: c.SwEvent = undefined;
        fn poll(_: i32, _: [*c]const c.SwPollState, out: [*c]c.SwEvent) callconv(.c) u8 {
            out[0] = event;
            return 1;
        }
    };
    // Each case owns a fresh session. No public operation clears an uncertainty latch.
    for (0..11) |case| {
        var client: Client = undefined;
        try client.context.claim();
        defer client.context.release();
        client.pipe = 1;
        client.context.leaderboard_download_call = 101;
        client.context.leaderboard_upload_call = 202;
        Native.event = std.mem.zeroes(c.SwEvent);
        Native.event.call = 101;
        Native.event.kind = c.SW_LEADERBOARD_ENTRIES;
        const capture = &Native.event.data.leaderboard_download.capture;
        capture.reported_count = 1;
        capture.failure_index = 0;
        capture.status = c.SW_LEADERBOARD_CAPTURE_INVALID_DETAILS;
        capture.reported_details = -1;
        capture.all_rows_accessed = 1;
        switch (case) {
            0 => {}, // All rows accessed, invalid metadata: resource is consumed.
            1 => capture.all_rows_accessed = 0,
            2 => capture.status = c.SW_LEADERBOARD_CAPTURE_ENTRY_FAILED,
            3 => capture.status = c.SW_LEADERBOARD_CAPTURE_UNTRACKED,
            4 => capture.status = 123456,
            5 => capture.reported_details = 1, // Inconsistent claimed invalid-detail status.
            6 => {
                capture.status = c.SW_LEADERBOARD_CAPTURE_COMPLETE;
                capture.failure_index = -1;
            }, // Missing published row.
            7 => Native.event.kind = c.SW_MALFORMED,
            8 => Native.event.kind = c.SW_UNHANDLED,
            9 => {
                Native.event.kind = c.SW_CALL_FAILED;
                Native.event.data.call_failure.reason = c.SW_RESULT_UNAVAILABLE;
            },
            10 => {
                Native.event.kind = c.SW_CALL_FAILED;
                Native.event.data.call_failure.reason = c.SW_IO_FAILURE;
            },
            else => unreachable,
        }
        _ = client.nextEventWith(Native.poll);
        try std.testing.expectEqual(@as(u64, 0), client.context.leaderboard_download_call);
        try std.testing.expectEqual(case != 0, client.context.leaderboard_download_blocked);
        try std.testing.expectEqual(@as(u64, 202), client.context.leaderboard_upload_call);
        Native.event.call = 202;
        _ = client.nextEventWith(Native.poll);
        try std.testing.expectEqual(@as(u64, 0), client.context.leaderboard_upload_call);
        try std.testing.expectEqual(case != 0, client.context.leaderboard_download_blocked);
        _ = client.nextEventWith(Native.poll); // Duplicate cannot change the download latch.
        try std.testing.expectEqual(case != 0, client.context.leaderboard_download_blocked);
    }
}

test "platform optional teardown precedes native shutdown with a live lease" {
    const Native = struct {
        var context: *Context = undefined;
        var calls: usize = 0;
        fn shutdown() callconv(.c) void {
            context.check();
            std.testing.expect(context.keyboard_state == .none and context.keyboard_app_id == 0 and context.input_state == .inactive) catch @panic("optional teardown order mismatch");
            calls += 1;
        }
    };
    var client: Client = undefined;
    try client.context.claim();
    var closed = false;
    defer if (!closed) client.deinitialize(Native.shutdown);
    Native.context = &client.context;
    client.context.keyboard_state = .gamepad;
    client.context.keyboard_app_id = 73;
    client.context.input_state = .init_failed;
    client.deinitialize(Native.shutdown);
    closed = true;
    try std.testing.expectEqual(@as(usize, 1), Native.calls);
    var renewed: Context = undefined;
    try renewed.claim();
    defer renewed.release();
}

test "capability completion observation precedes return even for discarded events" {
    const Native = struct {
        var event: c.SwEvent = undefined;
        var ready = true;
        fn poll(_: i32, _: [*c]const c.SwPollState, out: [*c]c.SwEvent) callconv(.c) u8 {
            if (!ready) return 0;
            out[0] = event;
            return 1;
        }
        fn pending(context: *Context) void {
            context.workshop_serial = 1;
            context.workshop_active = 1;
            context.workshop_handle = 0; // A valid native handle, not a sentinel.
            context.workshop_call = 91;
            context.workshop_state = .pending;
            context.workshop_requested = 1;
            context.workshop_returned = 0;
        }
        fn success() void {
            event = std.mem.zeroes(c.SwEvent);
            event.kind = c.SW_WORKSHOP_QUERY_COMPLETED;
            event.call = 91;
            event.data.workshop_query.result = 1;
            event.data.workshop_query.returned = 1;
        }
    };
    var client: Client = undefined;
    try claimTestClient(&client);
    defer {
        Workshop.shutdown(client.context.lease());
        client.context.release();
    }
    const query: Workshop.Query = .{ .lease = client.context.lease(), .token = 1 };
    Native.pending(&client.context);
    Native.ready = false;
    try std.testing.expect(client.nextEventWith(Native.poll) == null);
    try std.testing.expectEqual(Workshop.QueryState.pending, try query.state());
    Native.ready = true;
    Native.success();
    for ([_]u64{ 0, 92 }) |call| {
        Native.event.call = call;
        _ = client.nextEventWith(Native.poll);
        try std.testing.expectEqual(Workshop.QueryState.pending, try query.state());
        try std.testing.expectEqual(@as(u64, 91), client.context.workshop_call);
    }
    for (0..10) |case| {
        Native.pending(&client.context);
        Native.success();
        switch (case) {
            0 => {},
            1 => Native.event.data.workshop_query.result = 2,
            2 => Native.event.data.workshop_query.result = 123456, // Owned integer boundary.
            3 => Native.event.data.workshop_query.query = 17,
            4 => Native.event.data.workshop_query.returned = 2,
            5 => Native.event.kind = c.SW_MALFORMED,
            6 => Native.event.kind = c.SW_UNHANDLED,
            7 => Native.event.kind = c.SW_SCREENSHOT_REQUESTED,
            8, 9 => {
                Native.event.kind = c.SW_CALL_FAILED;
                Native.event.data.call_failure.reason = if (case == 8) c.SW_RESULT_UNAVAILABLE else c.SW_IO_FAILURE;
            },
            else => unreachable,
        }
        _ = client.nextEventWith(Native.poll); // No Request.take or caller event handling.
        try std.testing.expectEqual(@as(u64, 0), client.context.workshop_call);
        try std.testing.expectEqual(@as(u64, 0), @intFromEnum(try query.handle()));
        try std.testing.expectEqual(if (case == 0) Workshop.QueryState.ready else .failed, try query.state());
        try std.testing.expectEqual(if (case == 0) @as(?u32, 1) else null, try query.resultCount());
        Native.success();
        _ = client.nextEventWith(Native.poll); // Duplicate success cannot reopen a failed owner.
        try std.testing.expectEqual(if (case == 0) Workshop.QueryState.ready else .failed, try query.state());
    }
}

test "capability facades are inert and teardown precedes native shutdown" {
    const Native = struct {
        var context: *Context = undefined;
        var calls: usize = 0;
        fn shutdown() callconv(.c) void {
            context.check();
            std.testing.expect(context.voice_state == .inactive and context.workshop_state == .none and context.workshop_active == 0 and context.workshop_call == 0 and !context.screenshot_hook_owned) catch @panic("capability teardown order mismatch");
            for (context.timeline_ranges) |slot| {
                std.testing.expect(slot.token == 0) catch @panic("timeline owner survived native shutdown boundary");
            }
            calls += 1;
        }
    };
    Native.calls = 0;
    for ([_]Workshop.QueryState{ .created, .ready, .failed, .pending, .release_failed }) |query_state| {
        var client: Client = undefined;
        try claimTestClient(&client);
        Native.context = &client.context;
        var open = true;
        defer if (open) client.deinitialize(Native.shutdown);
        for ([_]Context.Lease{ client.voice().lease, client.remotePlay().lease, client.timeline().lease, client.workshop().lease, client.screenshots().lease }) |lease| {
            try std.testing.expect(lease.context == &client.context);
            try std.testing.expectEqual(client.context.generation, lease.generation);
        }
        try std.testing.expect(client.context.voice_state == .inactive and client.context.workshop_state == .none and !client.context.screenshot_hook_owned);
        for (client.context.timeline_ranges) |slot| try std.testing.expectEqual(@as(u64, 0), slot.token);
        // Synthetic wrapper ownership only. Owning-module TestApi substitutes all calls.
        client.context.voice_state = .recording;
        client.context.timeline_ranges[0] = .{ .token = 1, .handle = 0 };
        client.context.workshop_active = 1;
        client.context.workshop_handle = 0;
        client.context.workshop_state = query_state;
        client.context.workshop_call = if (query_state == .pending) 91 else 0;
        client.context.screenshot_hook_owned = true;
        client.deinitialize(Native.shutdown);
        open = false;
    }
    try std.testing.expectEqual(@as(usize, 5), Native.calls);
    var renewed: Context = undefined;
    try renewed.claim();
    defer renewed.release();
}

fn initializationResult(result: i32) InitError!void {
    return switch (result) {
        0 => {},
        2 => error.SteamClientUnavailable,
        3 => error.SteamVersionMismatch,
        4 => error.MissingInterface,
        else => error.InitializationFailed,
    };
}

test "license results distinguish missing authentication from lack of ownership" {
    // EUserHasLicenseForAppResult::k_EUserHasLicenseResultNoAuth in SDK 1.65.
    const result: License = @enumFromInt(2);
    try std.testing.expectEqual(License.not_authenticated, result);
    try std.testing.expect(result != .no_license);
}

test "initialization errors preserve actionable SDK failure categories" {
    try initializationResult(0);
    try std.testing.expectError(error.SteamClientUnavailable, initializationResult(2));
    try std.testing.expectError(error.SteamVersionMismatch, initializationResult(3));
    try std.testing.expectError(error.MissingInterface, initializationResult(4));
    try std.testing.expectError(error.InitializationFailed, initializationResult(99));
}

test "native initialization failure releases process ownership and keeps diagnostics" {
    const Failure = struct {
        fn init(message: [*c]u8) callconv(.c) i32 {
            const text = "fixture failure";
            @memcpy(message[0..text.len], text);
            message[text.len] = 0;
            return 2;
        }
    };
    var client: Client = undefined;
    var diagnostic: Diagnostic = .{};
    try std.testing.expectError(error.SteamClientUnavailable, client.initialize(&diagnostic, Failure.init));
    try std.testing.expectEqualStrings("fixture failure", diagnostic.text());
    var next: Context = undefined;
    try next.claim();
    defer next.release();
}

test "client shutdown disables diagnostics before native release" {
    const Probe = struct {
        // Exercise the required production C-ABI sink, not a public test hook.
        const bridge = @cImport({
            @cInclude("networking_debug.h");
        });
        var capture: NetworkingDebug.Capture = undefined;
        var called = false;
        var during: NetworkingDebug.Capture.Drain = undefined;
        fn shutdown() callconv(.c) void {
            called = true;
            bridge.sw_networking_debug_sink(4, "during native shutdown");
            var output: [1]NetworkingDebug.Capture.Record = undefined;
            // The lease must still be live while native shutdown runs.
            during = capture.drain(&output);
        }
    };
    var client: Client = undefined;
    try claimTestClient(&client);
    var open = true;
    defer if (open) {
        NetworkingDebug.shutdown(client.context.lease());
        client.context.release();
    };
    const control: NetworkingDebug.Capture = .{ .lease = client.context.lease() };
    try control.stop();
    var output: [1]NetworkingDebug.Capture.Record = undefined;
    // Tests own all producers. Drain prior process-wide records without assuming
    // the queue's incidental capacity or resetting its persistent state.
    while (true) {
        const drained = control.drain(&output);
        try std.testing.expect(!drained.busy);
        if (drained.count == 0) break;
    }
    const config = client.networkingConfig();
    const capture = client.networkingDebug();
    try std.testing.expect(config.lease.context == &client.context);
    try std.testing.expect(capture.lease.context == &client.context);
    try std.testing.expectEqual(client.context.generation, config.lease.generation);
    try std.testing.expectEqual(client.context.generation, capture.lease.generation);
    Probe.bridge.sw_networking_debug_sink(4, "facade access must not enable capture");
    try std.testing.expectEqual(@as(usize, 0), capture.drain(&output).count);
    try capture.start(.warning);
    Probe.bridge.sw_networking_debug_sink(4, "before close");
    try std.testing.expectEqual(@as(usize, 1), capture.drain(&output).count);
    try std.testing.expectEqualStrings("before close", output[0].bytes());
    Probe.capture = capture;
    client.deinitialize(Probe.shutdown);
    open = false;
    try std.testing.expect(Probe.called);
    try std.testing.expect(!Probe.during.busy);
    try std.testing.expectEqual(@as(usize, 0), Probe.during.count);
    var next: Context = undefined;
    try next.claim(); // Native shutdown finished, then process ownership released.
    defer next.release();
}

test "analyze every public client method" {
    std.testing.refAllDecls(Client);
}

// Synthetic ownership only: successful native initialization is deliberately absent.
fn claimTestClient(client: *Client) !void {
    try client.context.claim();
    client.pipe = 0;
}

fn fatalMarker(comptime name: []const u8) !void {
    try std.Io.File.stderr().writeStreamingAll(std.testing.io, "STEAMWORKZ_FATAL_READY:" ++ name ++ "\n");
}

test "lifecycle control stable client and renewed empty receive" {
    var client: Client = undefined;
    try claimTestClient(&client);
    var empty: [0]Networking.Message = .{};
    var batch = try client.networking().receive(.invalid, &empty);
    batch.deinit();
    client.context.checkCanClose();
    client.context.release();
    try claimTestClient(&client);
    defer client.context.release();
    batch = try client.networking().receive(.invalid, &empty);
    batch.deinit();
    const lease = client.context.lease();
    lease.acquireMessage();
    lease.releaseMessage();
    client.context.checkCanClose();
}

test "platform fatal guard" {
    if (!@import("steamworkz_test_options").fatal_lifecycle) return error.SkipZigTest;
    const libc = @cImport({
        @cInclude("stdlib.h");
    });
    const LeaseCase = enum { closed, stale, foreign, owner };
    const Method = enum {
        gamepad,
        gamepad_invalid,
        gamepad_pending,
        floating,
        floating_invalid,
        dismiss_gamepad,
        dismiss_floating,
        filter_init,
        filter_invalid,
        filter_native,
        hardware,
        utils_shutdown,
        input_start,
        input_stop,
        input_frame,
        manifest_invalid,
        manifest_native,
        controllers,
        action_set,
        digital_action,
        analog_action,
        activate_set,
        activate_layer,
        deactivate_layer,
        deactivate_all,
        current_set,
        layers,
        digital_data,
        analog_data,
        digital_origins,
        analog_origins,
        input_type,
        translate_invalid,
        translate_native,
        png_invalid,
        png_native,
        svg,
        origin_name,
        digital_name,
        analog_name,
        vibrate,
        vibrate_extended,
        input_shutdown,
        change_count,
        change_invalid,
        change_native,
        batch_begin,
        batch_pending,
        batch_exhausted,
        batch_end_consumed,
        batch_end_stale,
        batch_end_native,
        icon_invalid,
        icon_native,
        find_invalid,
        find_native,
        metadata_invalid,
        metadata_native,
        download_invalid,
        download_native,
        download_pending,
        download_blocked,
        users_empty,
        users_native,
        upload_invalid,
        upload_native,
        upload_pending,
        percentage_request,
        percentage_first,
        percentage_next_invalid,
        percentage_next_native,
        percentage_name_invalid,
        percentage_name_native,
        client_utils,
        client_input,
        client_poll,
        client_deinit,
        client_close_batch,
    };
    const lease_text = libc.getenv("STEAMWORKZ_GUARD_LEASE");
    const method_text = libc.getenv("STEAMWORKZ_GUARD_METHOD");
    if (lease_text == null or method_text == null) return error.MissingGuardSelection;
    const lease_case = std.meta.stringToEnum(LeaseCase, std.mem.span(lease_text)) orelse return error.InvalidGuardSelection;
    const method = std.meta.stringToEnum(Method, std.mem.span(method_text)) orelse return error.InvalidGuardSelection;
    const Probe = struct {
        client: *Client,
        lease: Context.Lease,
        method: Method,
        fn prepare(self: @This()) void {
            // Synthetic state only. No native owner is acquired by this fixture.
            const context = &self.client.context;
            context.input_state = if (self.method == .input_start or self.method == .input_stop) .inactive else .active;
            context.keyboard_state = switch (self.method) {
                .gamepad_pending, .dismiss_gamepad => .gamepad,
                .dismiss_floating => .floating,
                else => .none,
            };
            context.cloud_batch_active = switch (self.method) {
                .batch_end_native, .batch_pending, .client_close_batch => 1,
                .batch_end_stale => 2,
                else => 0,
            };
            context.cloud_batch_serial = if (self.method == .batch_exhausted) std.math.maxInt(u64) else 0;
            context.leaderboard_download_call = if (self.method == .download_pending) 1 else 0;
            context.leaderboard_download_blocked = self.method == .download_blocked;
            context.leaderboard_upload_call = if (self.method == .upload_pending) 1 else 0;
        }
        fn invoke(self: @This()) void {
            const utility: Utils = .{ .lease = self.lease };
            const controls: Input = .{ .lease = self.lease };
            const cloud_api: services.Cloud = .{ .lease = self.lease };
            const stats_api: services.Stats = .{ .lease = self.lease };
            var buffer: [16]u8 = undefined;
            const board: types.Leaderboard = @enumFromInt(1);
            switch (self.method) {
                .gamepad, .gamepad_pending => {
                    _ = utility.showGamepad(.{ .max_characters = 1 }) catch return;
                },
                .gamepad_invalid => {
                    _ = utility.showGamepad(.{ .max_characters = 1, .description = "bad\x00name" }) catch return;
                },
                .floating, .floating_invalid => {
                    _ = utility.showFloating(.{ .x = 0, .y = 0, .width = if (self.method == .floating) 1 else 0, .height = 1 }) catch return;
                },
                .dismiss_gamepad => {
                    _ = utility.dismissGamepad() catch return;
                },
                .dismiss_floating => {
                    _ = utility.dismissFloating() catch return;
                },
                .filter_init => {
                    _ = utility.initFilter() catch return;
                },
                .filter_invalid => {
                    _ = utility.filterText(.{ .context = .chat, .source = .invalid }, "", &.{}) catch return;
                },
                .filter_native => {
                    _ = utility.filterText(.{ .context = .chat, .source = @enumFromInt(123456) }, "é!!", buffer[0..8]) catch return;
                },
                .hardware => {
                    _ = utility.defaultConfig() catch return;
                },
                .utils_shutdown => Utils.shutdown(self.lease),
                .input_start => {
                    _ = controls.start(.{}) catch return;
                },
                .input_stop => {
                    _ = controls.stop() catch return;
                },
                .input_frame => controls.runFrame() catch return,
                .manifest_invalid => {
                    _ = controls.setManifestPath("relative") catch return;
                },
                .manifest_native => {
                    _ = controls.setManifestPath(if (@import("builtin").os.tag == .windows) "C:" ++ "\\manifest.vdf" else "/manifest.vdf") catch return;
                },
                .controllers => {
                    _ = controls.connectedControllers(&.{}) catch return;
                },
                .action_set => {
                    _ = controls.actionSet("action") catch return;
                },
                .digital_action => {
                    _ = controls.digitalAction("action") catch return;
                },
                .analog_action => {
                    _ = controls.analogAction("action") catch return;
                },
                .activate_set => controls.activateActionSet(.all, .invalid) catch return,
                .activate_layer => controls.activateLayer(.all, .invalid) catch return,
                .deactivate_layer => controls.deactivateLayer(.all, .invalid) catch return,
                .deactivate_all => controls.deactivateAllLayers(.all) catch return,
                .current_set => {
                    _ = controls.currentActionSet(.all) catch return;
                },
                .layers => {
                    _ = controls.activeLayers(.all, &.{}) catch return;
                },
                .digital_data => {
                    _ = controls.digitalData(.all, .invalid) catch return;
                },
                .analog_data => {
                    _ = controls.analogData(.all, .invalid) catch return;
                },
                .digital_origins => {
                    _ = controls.digitalOrigins(.all, .invalid, .invalid, &.{}) catch return;
                },
                .analog_origins => {
                    _ = controls.analogOrigins(.all, .invalid, .invalid, &.{}) catch return;
                },
                .input_type => {
                    _ = controls.inputType(.all) catch return;
                },
                .translate_invalid => {
                    _ = controls.translateOrigin(@enumFromInt(-1), .none) catch return;
                },
                .translate_native => {
                    _ = controls.translateOrigin(.unknown, .none) catch return;
                },
                .png_invalid => {
                    _ = controls.glyphPNG(.none, @enumFromInt(-1), .{}, &buffer) catch return;
                },
                .png_native => {
                    _ = controls.glyphPNG(.none, .small, .{}, &buffer) catch return;
                },
                .svg => {
                    _ = controls.glyphSVG(.none, .{}, &buffer) catch return;
                },
                .origin_name => {
                    _ = controls.originName(.none, &buffer) catch return;
                },
                .digital_name => {
                    _ = controls.digitalActionName(.invalid, &buffer) catch return;
                },
                .analog_name => {
                    _ = controls.analogActionName(.invalid, &buffer) catch return;
                },
                .vibrate => controls.vibrate(.all, 0, 0) catch return,
                .vibrate_extended => controls.vibrateExtended(.all, 0, 0, 0, 0) catch return,
                .input_shutdown => Input.shutdown(self.lease),
                .change_count => {
                    _ = cloud_api.localChangeCount() catch return;
                },
                .change_invalid => {
                    _ = cloud_api.localChangeAt(std.math.maxInt(usize), &.{}) catch return;
                },
                .change_native => {
                    _ = cloud_api.localChangeAt(0, &buffer) catch return;
                },
                .batch_begin, .batch_pending, .batch_exhausted => {
                    _ = cloud_api.beginWriteBatch() catch return;
                },
                .batch_end_consumed, .batch_end_stale, .batch_end_native => {
                    var batch: services.Cloud.WriteBatch = .{ .lease = self.lease, .token = if (self.method == .batch_end_consumed) 0 else 1 };
                    _ = batch.end() catch return;
                },
                .icon_invalid => {
                    _ = stats_api.achievementIcon("") catch return;
                },
                .icon_native => {
                    _ = stats_api.achievementIcon("name") catch return;
                },
                .find_invalid => {
                    _ = stats_api.findLeaderboard("bad\x00name") catch return;
                },
                .find_native => {
                    _ = stats_api.findLeaderboard("name") catch return;
                },
                .metadata_invalid => {
                    _ = stats_api.leaderboardMetadata(.invalid, &.{}) catch return;
                },
                .metadata_native => {
                    _ = stats_api.leaderboardMetadata(board, &buffer) catch return;
                },
                .download_invalid => {
                    _ = stats_api.downloadLeaderboard(.invalid, .{ .global = .{ .first_rank = 0, .last_rank = 0 } }) catch return;
                },
                .download_native, .download_pending, .download_blocked => {
                    _ = stats_api.downloadLeaderboard(board, .{ .global = .{ .first_rank = 1, .last_rank = 1 } }) catch return;
                },
                .users_empty => {
                    _ = stats_api.downloadLeaderboardUsers(board, &.{}) catch return;
                },
                .users_native => {
                    _ = stats_api.downloadLeaderboardUsers(board, &.{.invalid}) catch return;
                },
                .upload_invalid => {
                    _ = stats_api.uploadLeaderboard(.invalid, .{ .score = 0 }) catch return;
                },
                .upload_native, .upload_pending => {
                    _ = stats_api.uploadLeaderboard(board, .{ .score = 0 }) catch return;
                },
                .percentage_request => {
                    _ = stats_api.requestGlobalPercentages() catch return;
                },
                .percentage_first => {
                    _ = stats_api.firstGlobalPercentage() catch return;
                },
                .percentage_next_invalid => {
                    _ = stats_api.nextGlobalPercentage(.invalid) catch return;
                },
                .percentage_next_native => {
                    _ = stats_api.nextGlobalPercentage(@enumFromInt(0)) catch return;
                },
                .percentage_name_invalid => {
                    _ = stats_api.globalPercentage("") catch return;
                },
                .percentage_name_native => {
                    _ = stats_api.globalPercentage("name") catch return;
                },
                .client_utils => {
                    _ = self.client.utils();
                },
                .client_input => {
                    _ = self.client.input();
                },
                .client_poll => {
                    _ = self.client.nextEvent();
                },
                .client_deinit, .client_close_batch => self.client.deinit(),
            }
        }
        fn foreign(self: @This()) void {
            fatalMarker("wrong-thread") catch return;
            self.invoke();
        }
    };
    var client: Client = undefined;
    try claimTestClient(&client);
    var active = true;
    defer if (active) {
        client.context.cloud_batch_active = 0; // Synthetic fixture state, not native cleanup.
        Utils.shutdown(client.context.lease());
        Input.shutdown(client.context.lease());
        client.context.release();
    };
    const probe: Probe = .{ .client = &client, .lease = client.context.lease(), .method = method };
    switch (lease_case) {
        .closed => {
            client.context.release();
            active = false;
            probe.prepare();
            try fatalMarker("moved-client");
            probe.invoke();
        },
        .stale => {
            client.context.release();
            active = false;
            try claimTestClient(&client);
            active = true;
            probe.prepare();
            try fatalMarker("stale-lease");
            probe.invoke();
        },
        .foreign => {
            probe.prepare();
            const thread = try std.Thread.spawn(.{}, Probe.foreign, .{probe});
            thread.join();
        },
        .owner => {
            if (method != .client_close_batch) return error.InvalidGuardSelection;
            probe.prepare();
            try fatalMarker("outstanding-cloud-batch");
            probe.invoke();
        },
    }
    return error.ExpectedLeasePanic;
}

test "capability fatal guard" {
    if (!@import("steamworkz_test_options").fatal_lifecycle) return error.SkipZigTest;
    const libc = @cImport({
        @cInclude("stdlib.h");
    });
    const LeaseCase = enum { closed, stale, foreign };
    const Method = enum {
        voice_start,
        voice_start_recording,
        voice_start_draining,
        voice_stop_inactive,
        voice_stop_recording,
        voice_stop_draining,
        voice_state,
        voice_available,
        voice_read_empty,
        voice_read,
        voice_decode_rate,
        voice_decode_empty,
        voice_decode_overlap,
        voice_decode,
        voice_rate,
        voice_shutdown_inactive,
        voice_shutdown_recording,
        voice_shutdown_draining,
        remote_count,
        remote_index,
        remote_index_excess,
        remote_together_invalid,
        remote_together,
        remote_steam,
        remote_guest,
        remote_name_empty,
        remote_name,
        remote_form,
        remote_resolution,
        remote_ui,
        remote_invite_invalid,
        remote_invite_friend,
        remote_invite_guest,
        timeline_mode_invalid,
        timeline_mode,
        timeline_tooltip_invalid,
        timeline_tooltip,
        timeline_clear_invalid,
        timeline_clear,
        timeline_instant_invalid,
        timeline_instant,
        timeline_completed_invalid,
        timeline_completed,
        timeline_start_invalid,
        timeline_start,
        timeline_start_full,
        timeline_start_exhausted,
        range_update_invalid,
        range_update,
        range_update_closed,
        range_end_invalid,
        range_end,
        range_end_closed,
        range_cancel,
        range_cancel_closed,
        timeline_remove_zero,
        timeline_shutdown_empty,
        timeline_shutdown_active,
        workshop_create_empty,
        workshop_create,
        workshop_create_busy,
        workshop_create_exhausted,
        query_state,
        query_handle,
        query_count,
        query_send,
        query_send_pending,
        query_read_index,
        query_read_ready,
        query_read_pending,
        query_release,
        query_release_pending,
        query_release_failed,
        query_release_stale,
        workshop_observe_empty,
        workshop_observe_pending,
        workshop_shutdown_empty,
        workshop_shutdown_active,
        workshop_shutdown_pending,
        workshop_shutdown_failed,
        workshop_count,
        workshop_subscriptions_empty,
        workshop_subscriptions_excess,
        workshop_subscriptions,
        workshop_state,
        workshop_install_empty,
        workshop_install,
        workshop_progress,
        workshop_download,
        screenshot_rgb_invalid,
        screenshot_rgb,
        screenshot_file_invalid,
        screenshot_file,
        screenshot_trigger,
        screenshot_hook_enable,
        screenshot_hook_duplicate,
        screenshot_hook_disable_empty,
        screenshot_hook_disable,
        screenshot_hook_query,
        screenshot_shutdown_empty,
        screenshot_shutdown_owned,
        client_voice,
        client_remote,
        client_timeline,
        client_workshop,
        client_screenshots,
    };
    const lease_text = libc.getenv("STEAMWORKZ_GUARD_LEASE");
    const method_text = libc.getenv("STEAMWORKZ_GUARD_METHOD");
    if (lease_text == null or method_text == null) return error.MissingGuardSelection;
    const lease_case = std.meta.stringToEnum(LeaseCase, std.mem.span(lease_text)) orelse return error.InvalidGuardSelection;
    const method = std.meta.stringToEnum(Method, std.mem.span(method_text)) orelse return error.InvalidGuardSelection;
    const Probe = struct {
        client: *Client,
        lease: Context.Lease,
        method: Method,

        fn prepare(self: @This()) void {
            // Synthetic states only. No acquisition, recording, download or hook action.
            const ctx = &self.client.context;
            ctx.voice_state = switch (self.method) {
                .voice_start_recording, .voice_stop_recording, .voice_shutdown_recording => .recording,
                .voice_start_draining, .voice_stop_draining, .voice_shutdown_draining => .draining,
                else => .inactive,
            };
            ctx.timeline_ranges = @splat(.{});
            ctx.timeline_serial = if (self.method == .timeline_start_exhausted) std.math.maxInt(u64) else 1;
            switch (self.method) {
                .timeline_start_full => for (&ctx.timeline_ranges, 1..) |*slot, token| {
                    slot.* = .{ .token = token, .handle = 0 };
                },
                .range_update_invalid, .range_update, .range_end_invalid, .range_end, .range_cancel, .timeline_shutdown_active => ctx.timeline_ranges[0] = .{ .token = 1, .handle = 0 },
                else => {},
            }
            ctx.workshop_serial = if (self.method == .workshop_create_exhausted) std.math.maxInt(u64) else 1;
            ctx.workshop_active = if (self.method == .query_release_stale) 2 else 1;
            ctx.workshop_handle = 0;
            ctx.workshop_requested = 1;
            ctx.workshop_returned = 1;
            ctx.workshop_state = switch (self.method) {
                .workshop_create_empty, .workshop_create, .workshop_create_exhausted, .workshop_observe_empty, .workshop_shutdown_empty => .none,
                .query_send_pending, .query_read_pending, .query_release_pending, .workshop_observe_pending, .workshop_shutdown_pending => .pending,
                .query_count, .query_read_index, .query_read_ready => .ready,
                .query_release_failed, .workshop_shutdown_failed => .release_failed,
                else => .created,
            };
            if (ctx.workshop_state == .none) ctx.workshop_active = 0;
            ctx.workshop_call = if (ctx.workshop_state == .pending) 91 else 0;
            ctx.screenshot_hook_owned = switch (self.method) {
                .screenshot_hook_duplicate, .screenshot_hook_disable, .screenshot_shutdown_owned => true,
                else => false,
            };
        }
        fn invoke(self: @This()) void {
            const voice_api: Voice = .{ .lease = self.lease };
            const remote: RemotePlay = .{ .lease = self.lease };
            const timeline_api: Timeline = .{ .lease = self.lease };
            const range: Timeline.Range = .{ .lease = self.lease, .token = switch (self.method) {
                .range_update_closed, .range_end_closed, .range_cancel_closed => 0,
                else => 1,
            } };
            const workshop_api: Workshop = .{ .lease = self.lease };
            const query: Workshop.Query = .{ .lease = self.lease, .token = 1 };
            const screenshots_api: Screenshots = .{ .lease = self.lease };
            const session: types.RemotePlaySession = @enumFromInt(73);
            const marker: Timeline.Event = .{ .title = "", .description = "", .icon = "", .priority = 0 };
            var buffer: [16]u8 = @splat(0);
            var pcm: [8]i16 = @splat(0);
            switch (self.method) {
                .voice_start, .voice_start_recording, .voice_start_draining => voice_api.start() catch return,
                .voice_stop_inactive, .voice_stop_recording, .voice_stop_draining => {
                    _ = voice_api.stop() catch return;
                },
                .voice_state => {
                    _ = voice_api.state();
                },
                .voice_available => {
                    _ = voice_api.available() catch return;
                },
                .voice_read_empty => {
                    _ = voice_api.read(&.{}) catch return;
                },
                .voice_read => {
                    _ = voice_api.read(&buffer) catch return;
                },
                .voice_decode_rate => {
                    _ = voice_api.decode(&buffer, &pcm, 0) catch return;
                },
                .voice_decode_empty => {
                    _ = voice_api.decode(&.{}, &.{}, 24000) catch return;
                },
                .voice_decode_overlap => {
                    _ = voice_api.decode(std.mem.sliceAsBytes(&pcm), &pcm, 24000) catch return;
                },
                .voice_decode => {
                    _ = voice_api.decode(&buffer, &pcm, 24000) catch return;
                },
                .voice_rate => {
                    _ = voice_api.optimalSampleRate() catch return;
                },
                .voice_shutdown_inactive, .voice_shutdown_recording, .voice_shutdown_draining => Voice.shutdown(self.lease),
                .remote_count => {
                    _ = remote.sessionCount() catch return;
                },
                .remote_index => {
                    _ = remote.sessionAt(0) catch return;
                },
                .remote_index_excess => {
                    _ = remote.sessionAt(@as(usize, std.math.maxInt(i32)) + 1) catch return;
                },
                .remote_together_invalid => {
                    _ = remote.isTogether(.invalid) catch return;
                },
                .remote_together => {
                    _ = remote.isTogether(session) catch return;
                },
                .remote_steam => {
                    _ = remote.steamId(session) catch return;
                },
                .remote_guest => {
                    _ = remote.guestId(session) catch return;
                },
                .remote_name_empty => {
                    _ = remote.clientName(session, &.{}) catch return;
                },
                .remote_name => {
                    _ = remote.clientName(session, &buffer) catch return;
                },
                .remote_form => {
                    _ = remote.formFactor(session) catch return;
                },
                .remote_resolution => {
                    _ = remote.resolution(session) catch return;
                },
                .remote_ui => {
                    _ = remote.showTogetherUi() catch return;
                },
                .remote_invite_invalid => {
                    _ = remote.invite(.{ .friend = .invalid }) catch return;
                },
                .remote_invite_friend => {
                    _ = remote.invite(.{ .friend = @enumFromInt(73) }) catch return;
                },
                .remote_invite_guest => {
                    _ = remote.invite(.guest) catch return;
                },
                .timeline_mode_invalid => timeline_api.setMode(@enumFromInt(0)) catch return,
                .timeline_mode => timeline_api.setMode(.playing) catch return,
                .timeline_tooltip_invalid => timeline_api.setTooltip("bad\x00text", 0) catch return,
                .timeline_tooltip => timeline_api.setTooltip("", 0) catch return,
                .timeline_clear_invalid => timeline_api.clearTooltip(std.math.nan(f32)) catch return,
                .timeline_clear => timeline_api.clearTooltip(0) catch return,
                .timeline_instant_invalid => {
                    _ = timeline_api.instant(marker, .{ .clip = @enumFromInt(0) }) catch return;
                },
                .timeline_instant => {
                    _ = timeline_api.instant(marker, .{}) catch return;
                },
                .timeline_completed_invalid => {
                    _ = timeline_api.completed(marker, .{ .duration = -1 }) catch return;
                },
                .timeline_completed => {
                    _ = timeline_api.completed(marker, .{}) catch return;
                },
                .timeline_start_invalid => {
                    var invalid = marker;
                    invalid.priority = std.math.maxInt(u32);
                    _ = timeline_api.start(invalid, 0, .none) catch return;
                },
                .timeline_start, .timeline_start_full, .timeline_start_exhausted => {
                    _ = timeline_api.start(marker, 0, .none) catch return;
                },
                .range_update_invalid => range.update(.{ .title = "", .description = "", .icon = "", .priority = .{ .set = std.math.maxInt(u32) }, .clip = .none }) catch return,
                .range_update, .range_update_closed => range.update(.{ .title = "", .description = "", .icon = "", .priority = .keep_current, .clip = .none }) catch return,
                .range_end_invalid => {
                    _ = range.end(std.math.nan(f32)) catch return;
                },
                .range_end, .range_end_closed => {
                    _ = range.end(0) catch return;
                },
                .range_cancel, .range_cancel_closed => range.cancel() catch return,
                .timeline_remove_zero => timeline_api.remove(@enumFromInt(0)) catch return,
                .timeline_shutdown_empty, .timeline_shutdown_active => Timeline.shutdown(self.lease),
                .workshop_create_empty => {
                    _ = workshop_api.createDetailsQuery(&.{}) catch return;
                },
                .workshop_create, .workshop_create_busy, .workshop_create_exhausted => {
                    _ = workshop_api.createDetailsQuery(&.{.invalid}) catch return;
                },
                .query_state => {
                    _ = query.state() catch return;
                },
                .query_handle => {
                    _ = query.handle() catch return;
                },
                .query_count => {
                    _ = query.resultCount() catch return;
                },
                .query_send, .query_send_pending => {
                    _ = query.send() catch return;
                },
                .query_read_index, .query_read_ready, .query_read_pending => {
                    var details: Workshop.Details = undefined;
                    _ = query.read(if (self.method == .query_read_index) 1 else 0, &details) catch return;
                },
                .query_release, .query_release_pending, .query_release_failed, .query_release_stale => {
                    _ = query.release() catch return;
                },
                .workshop_observe_empty, .workshop_observe_pending => {
                    const event: events.Event = .{ .call = @enumFromInt(91), .callback_id = 0, .payload = .malformed };
                    Workshop.observeCompletion(self.lease, &event);
                },
                .workshop_shutdown_empty, .workshop_shutdown_active, .workshop_shutdown_pending, .workshop_shutdown_failed => Workshop.shutdown(self.lease),
                .workshop_count => {
                    _ = workshop_api.subscriptionCount(.{}) catch return;
                },
                .workshop_subscriptions_empty => {
                    _ = workshop_api.subscriptions(&.{}, .{}) catch return;
                },
                .workshop_subscriptions_excess => {
                    var items: [1025]types.WorkshopItem = undefined;
                    _ = workshop_api.subscriptions(&items, .{}) catch return;
                },
                .workshop_subscriptions => {
                    var items: [3]types.WorkshopItem = undefined;
                    _ = workshop_api.subscriptions(&items, .{}) catch return;
                },
                .workshop_state => {
                    _ = workshop_api.itemState(.invalid) catch return;
                },
                .workshop_install_empty => {
                    _ = workshop_api.installInfo(.invalid, &.{}) catch return;
                },
                .workshop_install => {
                    _ = workshop_api.installInfo(.invalid, &buffer) catch return;
                },
                .workshop_progress => {
                    _ = workshop_api.downloadProgress(.invalid) catch return;
                },
                .workshop_download => {
                    _ = workshop_api.downloadItem(.invalid, .{}) catch return;
                },
                .screenshot_rgb_invalid => {
                    _ = screenshots_api.submitRgbBorrowed(&.{}, 0, 0) catch return;
                },
                .screenshot_rgb => {
                    _ = screenshots_api.submitRgbBorrowed(buffer[0..3], 1, 1) catch return;
                },
                .screenshot_file_invalid => {
                    _ = screenshots_api.submitFile("relative.tga", null, 1, 1) catch return;
                },
                .screenshot_file => {
                    const path = if (@import("builtin").os.tag == .windows) "C:" ++ "\\inert.tga" else "/inert.tga";
                    _ = screenshots_api.submitFile(path, null, 1, 1) catch return;
                },
                .screenshot_trigger => screenshots_api.trigger() catch return,
                .screenshot_hook_enable, .screenshot_hook_duplicate => screenshots_api.enableHook() catch return,
                .screenshot_hook_disable_empty, .screenshot_hook_disable => screenshots_api.disableHook() catch return,
                .screenshot_hook_query => {
                    _ = screenshots_api.isHooked() catch return;
                },
                .screenshot_shutdown_empty, .screenshot_shutdown_owned => Screenshots.shutdown(self.lease),
                .client_voice => {
                    _ = self.client.voice();
                },
                .client_remote => {
                    _ = self.client.remotePlay();
                },
                .client_timeline => {
                    _ = self.client.timeline();
                },
                .client_workshop => {
                    _ = self.client.workshop();
                },
                .client_screenshots => {
                    _ = self.client.screenshots();
                },
            }
        }
        fn foreign(self: @This()) void {
            fatalMarker("wrong-thread") catch return;
            self.invoke();
        }
    };
    var client: Client = undefined;
    try claimTestClient(&client);
    var active = true;
    defer if (active) client.context.release(); // All ownership above is synthetic.
    const probe: Probe = .{ .client = &client, .lease = client.context.lease(), .method = method };
    switch (lease_case) {
        .closed => {
            client.context.release();
            active = false;
            probe.prepare();
            try fatalMarker("moved-client");
            probe.invoke();
        },
        .stale => {
            client.context.release();
            active = false;
            try claimTestClient(&client);
            active = true;
            probe.prepare();
            try fatalMarker("stale-lease");
            probe.invoke();
        },
        .foreign => {
            probe.prepare();
            const thread = try std.Thread.spawn(.{}, Probe.foreign, .{probe});
            thread.join();
        },
    }
    return error.ExpectedLeasePanic;
}

test "networking fatal guard" {
    if (!@import("steamworkz_test_options").fatal_lifecycle) return error.SkipZigTest;
    const libc = @cImport({
        @cInclude("stdlib.h");
    });
    const LeaseCase = enum { closed, stale, foreign };
    const Method = enum {
        telemetry_empty,
        telemetry_excess,
        detailed_empty,
        lanes_empty,
        lanes_weight,
        lanes_native,
        batch_empty,
        batch_lane,
        batch_native,
        config_set_invalid,
        config_set_native,
        config_clear_invalid,
        config_clear_native,
        config_get_invalid,
        config_get_native,
        simulation_invalid,
        simulation_native,
        simulation_reset,
        debug_start_invalid,
        debug_start_native,
        debug_drain_empty,
        debug_drain_storage,
        debug_stop,
        debug_shutdown,
    };
    const lease_text = libc.getenv("STEAMWORKZ_GUARD_LEASE");
    const method_text = libc.getenv("STEAMWORKZ_GUARD_METHOD");
    if (lease_text == null or method_text == null) return error.MissingGuardSelection;
    const lease_case = std.meta.stringToEnum(LeaseCase, std.mem.span(lease_text)) orelse return error.InvalidGuardSelection;
    const method = std.meta.stringToEnum(Method, std.mem.span(method_text)) orelse return error.InvalidGuardSelection;
    const Probe = struct {
        networking: Networking,
        config: NetworkingConfig,
        capture: NetworkingDebug.Capture,
        method: Method,

        fn invoke(self: @This()) void {
            switch (self.method) {
                .telemetry_empty => {
                    _ = self.networking.realTimeStatus(.invalid, &.{}) catch return;
                },
                .telemetry_excess => {
                    var lanes: [Networking.max_lanes + 1]Networking.LaneRealTimeStatus = undefined;
                    _ = self.networking.realTimeStatus(.invalid, &lanes) catch return;
                },
                .detailed_empty => {
                    _ = self.networking.detailedStatus(.invalid, &.{}) catch return;
                },
                .lanes_empty => {
                    _ = self.networking.configureLanes(.invalid, &.{}) catch return;
                },
                .lanes_weight => {
                    _ = self.networking.configureLanes(.invalid, &.{.{ .priority = 0, .weight = 0 }}) catch return;
                },
                .lanes_native => {
                    _ = self.networking.configureLanes(.invalid, &.{.{ .priority = 0, .weight = 1 }}) catch return;
                },
                .batch_empty => {
                    _ = self.networking.sendBatch(&.{}, &.{}) catch return;
                },
                .batch_lane, .batch_native => {
                    var outcomes: [1]Networking.BatchSendOutcome = undefined;
                    _ = self.networking.sendBatch(&.{.{ .connection = .invalid, .payload = "probe", .lane = if (self.method == .batch_lane) 65535 else 0 }}, &outcomes) catch return;
                },
                .config_set_invalid => self.config.set(.global, @enumFromInt(999), 0) catch return,
                .config_set_native => self.config.set(.global, .send_buffer_bytes, 123) catch return,
                .config_clear_invalid => self.config.clear(.global, @enumFromInt(999)) catch return,
                .config_clear_native => self.config.clear(.global, .send_buffer_bytes) catch return,
                .config_get_invalid => {
                    _ = self.config.get(.global, @enumFromInt(999)) catch return;
                },
                .config_get_native => {
                    _ = self.config.get(.global, .send_buffer_bytes) catch return;
                },
                .simulation_invalid => {
                    _ = self.config.applySimulation(.{ .send_loss_percent = -1 }) catch return;
                },
                .simulation_native => {
                    _ = self.config.applySimulation(.{}) catch return;
                },
                .simulation_reset => {
                    _ = self.config.resetSimulation() catch return;
                },
                .debug_start_invalid => self.capture.start(@enumFromInt(0)) catch return,
                .debug_start_native => self.capture.start(.warning) catch return,
                .debug_drain_empty => {
                    _ = self.capture.drain(&.{});
                },
                .debug_drain_storage => {
                    var output: [1]NetworkingDebug.Capture.Record = undefined;
                    _ = self.capture.drain(&output);
                },
                .debug_stop => self.capture.stop() catch return,
                .debug_shutdown => NetworkingDebug.shutdown(self.capture.lease),
            }
        }
        fn foreign(self: @This()) void {
            fatalMarker("wrong-thread") catch return;
            self.invoke();
        }
    };
    var client: Client = undefined;
    try claimTestClient(&client);
    var active = true;
    defer if (active) client.context.release();
    const probe: Probe = .{
        .networking = client.networking(),
        .config = client.networkingConfig(),
        .capture = client.networkingDebug(),
        .method = method,
    };
    switch (lease_case) {
        .closed => {
            client.context.release();
            active = false;
            try fatalMarker("moved-client");
            probe.invoke();
        },
        .stale => {
            client.context.release();
            active = false;
            try claimTestClient(&client);
            active = true;
            try fatalMarker("stale-lease");
            probe.invoke();
        },
        .foreign => {
            const thread = try std.Thread.spawn(.{}, Probe.foreign, .{probe});
            thread.join();
        },
    }
    // Local validation, an empty return, or an inert bridge abort cannot pass as
    // the expected lease panic. The existing runner checks marker and diagnostic.
    return error.ExpectedLeasePanic;
}

test "lifecycle fatal wrong-thread" {
    if (!@import("steamworkz_test_options").fatal_lifecycle) return error.SkipZigTest;
    var client: Client = undefined;
    try claimTestClient(&client);
    defer client.context.release();
    _ = client.networking(); // Adjacent owner-thread control.
    const Foreign = struct {
        fn run(value: *Client) void {
            fatalMarker("wrong-thread") catch return;
            _ = value.networking();
        }
    };
    const thread = try std.Thread.spawn(.{}, Foreign.run, .{&client});
    thread.join();
}

test "lifecycle fatal moved-client" {
    if (!@import("steamworkz_test_options").fatal_lifecycle) return error.SkipZigTest;
    var client: Client = undefined;
    try claimTestClient(&client);
    defer client.context.release();
    _ = client.networking();
    var copy = client;
    try fatalMarker("moved-client");
    _ = copy.networking();
}

test "lifecycle fatal stale-lease" {
    if (!@import("steamworkz_test_options").fatal_lifecycle) return error.SkipZigTest;
    var client: Client = undefined;
    try claimTestClient(&client);
    const old = client.networking();
    client.context.release();
    try claimTestClient(&client); // Same address: only the generation changed.
    defer client.context.release();
    var empty: [0]Networking.Message = .{};
    var fresh = try client.networking().receive(.invalid, &empty);
    fresh.deinit();
    try fatalMarker("stale-lease");
    _ = try old.receive(.invalid, &empty);
}

test "lifecycle fatal outstanding-message" {
    if (!@import("steamworkz_test_options").fatal_lifecycle) return error.SkipZigTest;
    var client: Client = undefined;
    try claimTestClient(&client);
    client.context.checkCanClose();
    client.context.lease().acquireMessage();
    try fatalMarker("outstanding-message");
    client.deinit(); // Must panic before sw_shutdown.
}
