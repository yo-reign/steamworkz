//! One private-lobby request: local acceptance, completion and membership differ.
//! Builds/tests compile this program but never run it. Explicit execution needs
//! Steam and a development App ID, and creates/leaves a temporary private lobby.
//! This standalone program is the sole lobby creator/joiner for its session.
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

    const lobbies = client.lobbies();
    // Returning a Request means Steam accepted the call, not that a lobby exists.
    var request = try lobbies.create(.{ .visibility = .private, .member_limit = 4 });
    var membership: steam.SteamId = .invalid;
    defer if (membership != .invalid) {
        lobbies.leave(membership) catch |err| {
            std.debug.print("Lobby departure failed: {t}\n", .{err});
        };
    };

    const CompletionError = steam.RequestError || error{ LobbyRejected, InvalidLobbyResult };
    var failure: ?CompletionError = null;
    var completed = false;
    for (0..500) |_| {
        client.runFrame();
        var quit = false;
        while (client.nextEvent()) |event| {
            if (event.payload == .shutdown) quit = true;
            // Sole-creator policy: remember the first entry for cleanup even if
            // call-result retrieval fails. A broadcast has no request identity;
            // a game with other joins must track its own memberships separately.
            if (!completed and membership == .invalid and event.call == .invalid and
                event.payload == .lobby_entered and event.payload.lobby_entered.response == .success)
            {
                membership = event.payload.lobby_entered.lobby;
            }

            const completion = request.take(&event) catch |err| failed: {
                failure = err;
                break :failed null;
            };
            if (completion) |created| {
                // Retrieval succeeded. The native operation may still have failed.
                if (created.result != .ok) {
                    std.debug.print("Lobby creation rejected: Steam result {d}\n", .{@backingInt(created.result)});
                    failure = error.LobbyRejected;
                } else if (created.lobby == .invalid) {
                    failure = error.InvalidLobbyResult;
                } else {
                    // Correlated identity supersedes any provisional entry.
                    membership = created.lobby;
                    completed = true;
                }
            }
        }
        // Finish draining this frame before taking the failure/exit path, so an
        // already-queued entry can still establish cleanup responsibility.
        if (failure) |err| {
            std.debug.print("Completion failed: {t}; ending this session without retry\n", .{err});
            return err;
        }
        if (quit) return;
        if (completed) {
            std.debug.print("Private lobby created; leaving it before shutdown\n", .{});
            return;
        }
        try std.Io.sleep(init.io, .fromMilliseconds(10), .awake);
    }
    // A timeout is not cancellation. Only observed owned membership can be left;
    // ending the client session does not prove the remote operation never ran.
    // In a game, preserve this uncertainty instead of starting a conflicting retry.
    return error.LobbyTimeout;
}
