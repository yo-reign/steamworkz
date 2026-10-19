//! Explicit live check. Requires a running, logged-in Steam client.
//! Creates one private lobby, issues/cancels one auth ticket, and exchanges local
//! socket-pair messages. Does not purchase, invite, write saves, or change stats.
const std = @import("std");
const steam = @import("steamworkz");

pub fn main(init: std.process.Init) !void {
    var client: steam.Client = undefined;
    const app = try runSession(init.io, init.gpa, &client);
    // Reuse the same stable storage, but not any handles from the closed session.
    try start(&client);
    defer client.deinit();
    try drain(&client);
    try require(client.loggedOn() and client.appId() == app);
    std.debug.print("Client shutdown/reinitialization checks passed\nSteamworkz live checks passed\n", .{});
}

fn start(client: *steam.Client) !void {
    var diagnostic: steam.Client.Diagnostic = .{};
    client.init(&diagnostic) catch |err| {
        std.debug.print("Steam initialization failed: {t}: {s}\n", .{ err, diagnostic.text() });
        return err;
    };
}

fn runSession(io: std.Io, allocator: std.mem.Allocator, client: *steam.Client) !steam.AppId {
    try start(client);
    defer client.deinit();
    try require(client.loggedOn());
    std.debug.print("Steam initialized: app={d}, persona_available={}\n", .{ @intFromEnum(client.appId()), client.friends().personaName().len != 0 });
    var name_buffer: [256]u8 = undefined;
    const copied_name = try client.friends().personaNameCopy(&name_buffer);
    const owned_name = try client.friends().personaNameAlloc(allocator);
    defer allocator.free(owned_name);
    _ = try client.friends().friendCount();
    try require(std.mem.eql(u8, copied_name, owned_name));
    _ = try client.apps().dlcCount();
    _ = client.apps().language();
    _ = client.apps().subscribed();
    _ = client.stats().achievementCount();
    _ = client.cloud().enabledForAccount();
    _ = client.cloud().enabledForApp();
    std.debug.print("Read-only game services passed\n", .{});
    try socketChecks(io, client);
    try lobbyCheck(io, allocator, client);
    try ticketCheck(io, client);
    return client.appId();
}

fn require(condition: bool) error{LiveCheckFailed}!void {
    if (!condition) return error.LiveCheckFailed;
}

fn drain(client: *const steam.Client) !void {
    client.runFrame();
    while (client.nextEvent()) |event| {
        switch (event.payload) {
            .malformed => return error.MalformedCallback,
            else => {},
        }
    }
}

fn socketChecks(io: std.Io, client: *steam.Client) !void {
    const net = client.networking();
    const literals = [_][:0]const u8{
        "127.0.0.1:27015",  "0.0.0.0",             "[::1]:27016",         "::",                                                    "[2001:db8::1]",
        "::ffff:192.0.2.1", "[::ffff:c000:201]:7", "2001:db8::192.0.2.1", "[ffff:ffff:ffff:ffff:ffff:ffff:255.255.255.255]:65535", "::ffff:1:2:3:4:5:6",
    };
    for (literals) |literal| {
        const pure = try steam.Networking.Address.parse(literal);
        const native = try net.parseAddress(literal);
        try require(pure.port == native.port and std.mem.eql(u8, &pure.ipv6, &native.ipv6));
        var text: [steam.Networking.address_text_size]u8 = undefined;
        const formatted = try std.fmt.bufPrintZ(&text, "{f}", .{pure});
        const roundtrip = try net.parseAddress(formatted);
        try require(pure.port == roundtrip.port and std.mem.eql(u8, &pure.ipv6, &roundtrip.ipv6));
    }

    const pair = try net.socketPair(.{});
    defer {
        net.close(pair[0], .{ .debug = "smoke complete" }) catch {};
        net.close(pair[1], .{ .debug = "smoke complete" }) catch {};
    }
    const info = try net.connectionInfo(pair[0]);
    try require(info.state == .connected);
    const group = try net.createPollGroup();
    defer net.destroyPollGroup(group) catch {};
    try net.setPollGroup(pair[1], group);

    _ = try requireSend(try net.send(pair[0], "Zig Steamworkz", .{ .reliability = .reliable, .no_nagle = true }));
    try require(net.flush(pair[0]) == .ok);
    try receive(io, client, pair[1], group, "Zig Steamworkz");
    try net.setPollGroup(pair[1], .invalid);
    _ = try requireSend(try net.send(pair[0], &.{}, .{ .reliability = .unreliable }));
    try receive(io, client, pair[1], .invalid, &.{});
    _ = try requireSend(try net.sendRaw(pair[0], "raw", steam.Networking.SendFlags.unreliable));
    try receive(io, client, pair[1], .invalid, "raw");
    std.debug.print("Address, socket-pair, poll-group, and message ownership checks passed\n", .{});
}

fn requireSend(outcome: steam.Networking.SendOutcome) error{SendRejected}!i64 {
    return switch (outcome) {
        .accepted => |number| number,
        .rejected => |result| {
            std.debug.print("Steam rejected the send: result {d}\n", .{@intFromEnum(result)});
            return error.SendRejected;
        },
    };
}

fn receive(io: std.Io, client: *steam.Client, connection: steam.Networking.Connection, group: steam.Networking.PollGroup, expected: []const u8) !void {
    const net = client.networking();
    for (0..200) |_| {
        try drain(client);
        var messages: [8]steam.Networking.Message = undefined;
        var batch = if (group == .invalid) try net.receive(connection, &messages) else try net.receivePollGroup(group, &messages);
        defer batch.deinit();
        if (batch.messages.len != 0) {
            // A processing error still releases every message in the batch.
            try require(batch.messages.len == 1 and std.mem.eql(u8, expected, batch.messages[0].bytes()));
            return;
        }
        try std.Io.sleep(io, .fromMilliseconds(10), .awake);
    }
    return error.MessageTimeout;
}

fn lobbyCheck(io: std.Io, allocator: std.mem.Allocator, client: *steam.Client) !void {
    const lobbies = client.lobbies();
    var request = try lobbies.create(.{ .visibility = .private, .member_limit = 2 });
    var joined: steam.SteamId = .invalid;
    defer if (joined != .invalid) {
        lobbies.leave(joined) catch {};
    };
    var completed = false;
    for (0..500) |_| {
        client.runFrame();
        while (client.nextEvent()) |event| {
            // Retain membership for cleanup even if result retrieval fails.
            if (event.payload == .lobby_entered and event.payload.lobby_entered.response == .success)
                joined = event.payload.lobby_entered.lobby;
            if (try request.take(&event)) |created| {
                if (created.result != .ok) {
                    std.debug.print("Steam rejected lobby creation: result {d}\n", .{@intFromEnum(created.result)});
                    return error.LobbyRequestFailed;
                }
                joined = created.lobby;
                completed = true;
            }
        }
        if (completed) break;
        try std.Io.sleep(io, .fromMilliseconds(10), .awake);
    }
    if (!completed) return error.LobbyTimeout;
    try require(joined != .invalid);
    try require(try lobbies.owner(joined) == client.userId());
    try lobbies.setData(joined, "wrapper-smoke", "zig");
    var buffer: [32]u8 = undefined;
    const copied = try lobbies.dataCopy(joined, "wrapper-smoke", &buffer);
    const owned = try lobbies.dataAlloc(allocator, joined, "wrapper-smoke");
    defer allocator.free(owned);
    try require(std.mem.eql(u8, copied, "zig") and std.mem.eql(u8, owned, "zig"));
    try lobbies.setMemberData(joined, "wrapper-member", "member");
    const member = try lobbies.memberDataCopy(joined, client.userId(), "wrapper-member", &buffer);
    const owned_member = try lobbies.memberDataAlloc(allocator, joined, client.userId(), "wrapper-member");
    defer allocator.free(owned_member);
    try require(std.mem.eql(u8, member, "member") and std.mem.eql(u8, owned_member, "member"));
    std.debug.print("Private lobby, copied metadata, and typed completion checks passed\n", .{});
}

fn ticketCheck(io: std.Io, client: *steam.Client) !void {
    var bytes: [2048]u8 = undefined;
    const ticket = try client.authSessionTicket(&bytes, client.userId());
    defer client.cancelTicket(ticket.handle);
    try require(ticket.bytes.len != 0);
    for (0..500) |_| {
        client.runFrame();
        var completed = false;
        while (client.nextEvent()) |event| {
            switch (event.payload) {
                .auth_ticket => |value| if (value.ticket == ticket.handle) {
                    try require(value.result == .ok);
                    completed = true;
                },
                .malformed => return error.MalformedCallback,
                else => {},
            }
        }
        if (completed) {
            std.debug.print("Auth ticket completion and cancellation checks passed\n", .{});
            return;
        }
        try std.Io.sleep(io, .fromMilliseconds(10), .awake);
    }
    return error.TicketTimeout;
}
