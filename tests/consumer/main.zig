const steam = @import("steamworkz");

// Keep a native-backed method in the linked binary in every optimization mode.
// This entry point is never called; the fixture never initializes Steam.
export fn consumerClientLoggedOn(client: *const steam.Client) bool {
    return client.loggedOn();
}

pub fn main() !void {
    // Value-only API use is safe even if this compile/link fixture is run manually.
    _ = try steam.Networking.Address.parse("127.0.0.1:27015");
}
