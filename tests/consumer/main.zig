const std = @import("std");
const steam = @import("steamworkz");

// Retained for real native linkage in every mode; never called by pure main.
export fn consumerClientLoggedOn(client: *const steam.Client) bool {
    return client.loggedOn();
}

// Keep a reachable ownership transition so optimization cannot treat every
// lease as permanently closed and discard the native paths below.
export fn consumerInitialize(client: *steam.Client, diagnostic: *steam.Client.Diagnostic) bool {
    client.init(diagnostic) catch return false;
    return true;
}
export fn consumerShutdown(client: *steam.Client) void {
    client.deinit();
}

// Linkage coverage only, not an application recipe. Pure main never calls this
// function or changes global networking settings/registers a callback.
export fn consumerNetworking(client: *steam.Client, connection: u32, payload: [*]const u8, size: usize) bool {
    const net = client.networking();
    const handle: steam.Networking.Connection = @enumFromInt(connection);
    var lanes: [2]steam.Networking.LaneRealTimeStatus = undefined;
    const status = net.realTimeStatus(handle, &lanes) catch return false;
    std.mem.doNotOptimizeAway(status);
    var text: [256]u8 = undefined;
    const detail = net.detailedStatus(handle, &text) catch return false;
    std.mem.doNotOptimizeAway(detail);
    const configured = net.configureLanes(handle, &.{ .{ .priority = 0, .weight = 1 }, .{ .priority = 10, .weight = 1 } }) catch return false;
    std.mem.doNotOptimizeAway(configured);
    var outcomes: [1]steam.Networking.BatchSendOutcome = undefined;
    const sent = net.sendBatch(&.{.{ .connection = handle, .payload = payload[0..size], .lane = 1, .options = .{ .reliability = .reliable } }}, &outcomes) catch return false;
    std.mem.doNotOptimizeAway(sent);

    const config = client.networkingConfig();
    config.set(.global, .nagle_delay_us, 123) catch return false;
    const value = config.get(.global, .nagle_delay_us) catch return false;
    std.mem.doNotOptimizeAway(value);
    config.clear(.global, .nagle_delay_us) catch return false;
    const applied = config.applySimulation(.{ .send_lag_ms = 1 }) catch return false;
    std.mem.doNotOptimizeAway(applied);
    const reset = config.resetSimulation() catch return false;
    std.mem.doNotOptimizeAway(reset);

    const capture = client.networkingDebug();
    capture.start(.warning) catch return false;
    var records: [1]steam.NetworkingDebug.Record = undefined;
    std.mem.doNotOptimizeAway(capture.drain(&records));
    capture.stop() catch return false;
    return true;
}

pub fn main() !void {
    // Taking addresses retains production paths without executing them.
    std.mem.doNotOptimizeAway(&consumerClientLoggedOn);
    std.mem.doNotOptimizeAway(&consumerInitialize);
    std.mem.doNotOptimizeAway(&consumerShutdown);
    std.mem.doNotOptimizeAway(&consumerNetworking);
    const address = try steam.Networking.Address.parse("127.0.0.1:27015");
    var text: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
    defer text.deinit();
    try address.format(&text.writer);
    if (!std.mem.eql(u8, text.written(), "127.0.0.1:27015")) return error.AddressMismatch;

    const image: steam.ImageHandle = @enumFromInt(37);
    const unknown: steam.Result = @enumFromInt(-12345);
    if (@intFromEnum(image) != 37 or @intFromEnum(unknown) != -12345) return error.ValueMismatch;
    var request = try steam.Request(.lobby_created).init(@enumFromInt(42));
    const event: steam.Event = .{
        .call = @enumFromInt(42),
        .callback_id = 513,
        .payload = .{ .lobby_created = .{ .lobby = @enumFromInt(123), .result = .access_denied } },
    };
    const value = (try request.take(&event)) orelse return error.MissingCompletion;
    if (value.result != .access_denied or @intFromEnum(value.lobby) != 123 or request.isPending()) return error.CompletionMismatch;
    if (try request.take(&event) != null) return error.DuplicateCompletion;
    inline for (.{ .lobby_entered, .lobby_list, .stats_received, .cloud_written }) |kind| {
        const pending = try steam.Request(kind).init(@enumFromInt(99));
        if (!pending.isPending()) return error.MissingRequest;
    }
}
