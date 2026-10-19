//! Steamworkz: game-facing Steamworks 1.65 bindings for Zig 0.16.0.
//! Public game callers use Zig only; the package privately compiles its C++ bridge.
//! The SDK is external and consumer-supplied. See the README for setup and ownership.

pub const Client = @import("Client.zig");
pub const Networking = @import("Networking.zig");
pub const Lobbies = @import("Lobbies.zig");
pub const Friends = @import("services.zig").Friends;
pub const Apps = @import("services.zig").Apps;
pub const Stats = @import("services.zig").Stats;
pub const Cloud = @import("services.zig").Cloud;
pub const Event = @import("events.zig").Event;
pub const Request = @import("requests.zig").Request;
pub const RequestError = @import("requests.zig").Error;
pub const LobbyEnterResponse = @import("events.zig").LobbyEnterResponse;
pub const AuthResponse = @import("events.zig").AuthResponse;
pub const SteamId = @import("types.zig").SteamId;
pub const AppId = @import("types.zig").AppId;
pub const ApiCall = @import("types.zig").ApiCall;
pub const AuthTicket = @import("types.zig").AuthTicket;
pub const ImageHandle = @import("types.zig").ImageHandle;
pub const Result = @import("types.zig").Result;

test {
    _ = @import("Context.zig");
    _ = @import("types.zig");
    _ = @import("events.zig");
    _ = @import("requests.zig");
    _ = @import("services.zig");
    _ = Client;
    _ = Networking;
    _ = Lobbies;
}
