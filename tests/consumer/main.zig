const std = @import("std");
const steam = @import("steamworkz");

// Retained for real native linkage in every mode; never called by pure main.
export fn consumerClientLoggedOn(client: *const steam.Client) bool {
    return client.loggedOn();
}

pub fn main() !void {
    // Taking its address retains native linkage without invoking the export.
    std.mem.doNotOptimizeAway(&consumerClientLoggedOn);
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
