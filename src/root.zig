//! Steamworkz: game-facing Steamworks 1.65 bindings for Zig 0.16.0.
//! Public game callers use Zig only; the package privately compiles its C++ bridge.
//! The SDK is external and consumer-supplied. See the README for setup and ownership.

pub const Client = @import("Client.zig");
pub const Networking = @import("Networking.zig");
pub const NetworkingConfig = @import("NetworkingConfig.zig");
const networking_debug = @import("NetworkingDebug.zig");
pub const NetworkingDebug = networking_debug.Capture;
// Analyze the required C-ABI sink even when no caller starts capture.
// This does not register a native callback or initialize an interface.
comptime {
    _ = networking_debug;
}
pub const Lobbies = @import("Lobbies.zig");
pub const Utils = @import("Utils.zig");
pub const Input = @import("Input.zig");
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
pub const Leaderboard = @import("types.zig").Leaderboard;
pub const LeaderboardEntry = @import("types.zig").LeaderboardEntry;
pub const LeaderboardEntries = @import("types.zig").LeaderboardEntries;
pub const Result = @import("types.zig").Result;

test {
    _ = @import("Context.zig");
    _ = @import("types.zig");
    _ = @import("events.zig");
    _ = @import("requests.zig");
    _ = @import("services.zig");
    _ = Client;
    _ = Networking;
    _ = NetworkingConfig;
    _ = networking_debug;
    _ = Lobbies;
    _ = Utils;
    _ = Input;
}
