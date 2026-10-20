const std = @import("std");
const Context = @import("Context.zig");
const types = @import("types.zig");
const events = @import("events.zig");
const services = @import("services.zig");
const Networking = @import("Networking.zig");
const NetworkingConfig = @import("NetworkingConfig.zig");
const NetworkingDebug = @import("NetworkingDebug.zig");
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
/// Diagnostic admission stops before native shutdown. This does not establish
/// callback quiescence; diagnostic code/storage remain valid for the process.
pub fn deinit(self: *Client) void {
    self.deinitialize(c.sw_shutdown);
}

fn deinitialize(self: *Client, comptime native_shutdown: @TypeOf(c.sw_shutdown)) void {
    self.context.checkCanClose();
    NetworkingDebug.shutdown(self.context.lease());
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
