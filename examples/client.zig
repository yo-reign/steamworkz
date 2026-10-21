//! First-use recipe: initialization, copied text and an explicit event loop.
//! Builds/tests compile this program but never run it. Launching it initializes
//! Steam; supply your development App ID and a running Steam client explicitly.
const std = @import("std");
const steam = @import("steamworkz");

pub fn main(init: std.process.Init) !void {
    // Initialize in final storage, before creating a game's graphics window.
    // Do not return or move this Client by value after initialization.
    var client: steam.Client = undefined;
    var diagnostic: steam.Client.Diagnostic = .{};
    client.init(&diagnostic) catch |err| {
        std.debug.print("Steam initialization failed: {t}: {s}\n", .{ err, diagnostic.text() });
        return err;
    };
    defer client.deinit();

    var name_buffer: [256]u8 = undefined;
    const name = try client.friends().personaNameCopy(&name_buffer);
    const app = client.appId(); // Another Steam call cannot invalidate the copy.
    // A game can display `name`; this example does not log personal information.
    std.debug.print("App {d}: copied {d} persona-name bytes\n", .{ @intFromEnum(app), name.len });

    // A short headless demonstration. In a game, use its existing render loop,
    // including menus/paused simulation; Steamworkz creates no update thread.
    for (0..120) |_| {
        client.runFrame();
        var quit = false;
        while (client.nextEvent()) |event| {
            switch (event.payload) {
                .shutdown => quit = true,
                .overlay => |overlay| {
                    // Feed this into the game's pause/input policy.
                    std.debug.print("Overlay active: {}\n", .{overlay.active});
                },
                .malformed => std.debug.print("Malformed callback: {d}\n", .{event.callback_id}),
                .call_failed => |failure| std.debug.print("Call-result retrieval failed: {t}\n", .{failure}),
                else => {},
            }
        }
        // Drain even when quitting: Client observes ownership changes as it goes.
        if (quit) return;
        try std.Io.sleep(init.io, .fromMilliseconds(16), .awake);
    }
}
