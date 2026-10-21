//! Received-message ownership with a local socket pair, not a peer/P2P tutorial.
//! Builds/tests compile this program but never run it. Explicit execution needs
//! Steam and a development App ID; it sends only between two local connections.
const std = @import("std");
const steam = @import("steamworkz");

pub fn main(init: std.process.Init) !void {
    var client: steam.Client = undefined;
    var diagnostic: steam.Client.Diagnostic = .{};
    client.init(&diagnostic) catch |err| {
        std.debug.print("Steam initialization failed: {t}: {s}\n", .{ err, diagnostic.text() });
        return err;
    };
    defer client.deinit();

    const net = client.networking();
    const pair = try net.socketPair(.{});
    defer {
        net.close(pair[0], .{}) catch |err| std.debug.print("Sender close failed: {t}\n", .{err});
        net.close(pair[1], .{}) catch |err| std.debug.print("Receiver close failed: {t}\n", .{err});
    }
    switch (try net.send(pair[0], "hello", .{ .reliability = .reliable, .no_nagle = true })) {
        .accepted => {}, // Local acceptance is not an acknowledgement of delivery.
        .rejected => |result| {
            std.debug.print("Send rejected: Steam result {d}\n", .{@intFromEnum(result)});
            return error.SendRejected;
        },
    }

    for (0..200) |_| {
        client.runFrame();
        var quit = false;
        while (client.nextEvent()) |event| {
            if (event.payload == .shutdown) quit = true;
        }
        if (quit) return;

        var storage: [8]steam.Networking.Message = undefined;
        var batch = try net.receive(pair[1], &storage);
        // Register cleanup immediately. It releases unread messages too, even
        // when processing returns an error. Never copy a live batch or message.
        defer batch.deinit();
        for (batch.messages) |*message| {
            try processPacket(message.bytes());
            // Do not retain bytes() past release. Copy explicitly if the game
            // needs to queue the payload for a later frame or another thread.
        }
        if (batch.messages.len != 0) return;
        try std.Io.sleep(init.io, .fromMilliseconds(10), .awake);
    }
    return error.ReceiveTimeout;
}

fn processPacket(bytes: []const u8) error{EmptyPacket}!void {
    // Stand-in for a fallible game handler. This example's policy rejects empty
    // packets; Steamworkz itself permits zero-byte messages.
    if (bytes.len == 0) return error.EmptyPacket;
    std.debug.print("Processed {d} message bytes\n", .{bytes.len});
}
