const std = @import("std");
const Context = @import("Context.zig");
const types = @import("types.zig");
const events = @import("events.zig");
const services = @import("services.zig");
const Networking = @import("Networking.zig");
const Lobbies = @import("Lobbies.zig");
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
/// sessions first. Pending results are discarded, not delivered during shutdown.
/// Borrowed interfaces and numeric resource handles expire with this session.
pub fn deinit(self: *Client) void {
    self.context.checkCanClose();
    c.sw_shutdown();
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
pub fn nextEvent(self: *const Client) ?events.Event {
    self.context.check();
    var native: c.SwEvent = undefined;
    if (c.sw_next_event(self.pipe, &native) == 0) return null;
    return events.decode(&native);
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

test "analyze every public client method" {
    std.testing.refAllDecls(Client);
}
