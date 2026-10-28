# API reference index

Follow the feature's Zig declarations alongside Valve's documentation. The
[public root](../src/root.zig) is the source index; methods document ownership,
completion and cleanup at the point of use.

| Zig entry point | Valve reference |
| --- | --- |
| [`Client`](../src/Client.zig) | [Initialization and dispatch](https://partner.steamgames.com/doc/sdk/api), [ISteamUser](https://partner.steamgames.com/doc/api/ISteamUser) |
| [`Event`](../src/events.zig), [`Request`](../src/requests.zig) | [Callbacks and call results](https://partner.steamgames.com/doc/sdk/api#callbacks) |
| [`Lobbies`](../src/Lobbies.zig) | [ISteamMatchmaking](https://partner.steamgames.com/doc/api/ISteamMatchmaking) |
| [`Networking`](../src/Networking.zig) | [ISteamNetworkingSockets](https://partner.steamgames.com/doc/api/ISteamNetworkingSockets) |
| [`NetworkingConfig`](../src/NetworkingConfig.zig), [`NetworkingDebug`](../src/NetworkingDebug.zig) | [ISteamNetworkingUtils](https://partner.steamgames.com/doc/api/ISteamNetworkingUtils) |
| [`Friends`, `Apps`, `Stats`, `Cloud`](../src/services.zig) | [ISteamFriends](https://partner.steamgames.com/doc/api/ISteamFriends), [ISteamApps](https://partner.steamgames.com/doc/api/ISteamApps), [ISteamUserStats](https://partner.steamgames.com/doc/api/ISteamUserStats), [ISteamRemoteStorage](https://partner.steamgames.com/doc/api/ISteamRemoteStorage) |
| [`Utils`](../src/Utils.zig), [`Input`](../src/Input.zig) | [ISteamUtils](https://partner.steamgames.com/doc/api/ISteamUtils), [ISteamInput](https://partner.steamgames.com/doc/api/ISteamInput) |
| [`Voice`](../src/Voice.zig), [`RemotePlay`](../src/RemotePlay.zig) | [ISteamUser](https://partner.steamgames.com/doc/api/ISteamUser), [ISteamRemotePlay](https://partner.steamgames.com/doc/api/ISteamRemotePlay) |
| [`Workshop`](../src/Workshop.zig), [`Screenshots`](../src/Screenshots.zig), [`Timeline`](../src/Timeline.zig) | [ISteamUGC](https://partner.steamgames.com/doc/api/ISteamUGC), [ISteamScreenshots](https://partner.steamgames.com/doc/api/ISteamScreenshots), [ISteamTimeline](https://partner.steamgames.com/doc/api/ISteamTimeline) |

Valve's reference describes native behavior; the Zig declarations describe the
wrapper's storage and error contracts. The supplied SDK **1.65 headers** are the
version authority when living web documentation differs. Not every native method
is exposed, and Steamworkz does not replace game networking or save-management code.

For wrapper-specific contracts, see [client lifecycle and requests](lifecycle.md),
[networking and lobbies](networking.md), and
[services and optional capabilities](services.md).
