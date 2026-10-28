# Client lifecycle, requests and authentication

Return to the [quick start](../README.md#client-and-event-loop) or browse the [API index](api.md).

## Client and event loop

```zig
const steam = @import("steamworkz");

var client: steam.Client = undefined;
var diagnostic: steam.Client.Diagnostic = .{};
try client.init(&diagnostic); // On failure, diagnostic.text() may contain SDK details.
defer client.deinit();

// Once per rendered frame, including menus and paused simulation:
client.runFrame();
while (client.nextEvent()) |event| {
    switch (event.payload) {
        .overlay => |overlay| { _ = overlay.active; },
        .connection_changed => |change| {
            // change.info.connection is Networking.Connection, not an untyped int.
            _ = change;
        },
        else => {},
    }
}
```

Initialize before creating the graphics window if you want overlay support.
There is one client per process. **Keep its storage alive at the same address**;
do not return a live client by value. Client and borrowed service methods,
including teardown, run on its initializing thread. Pure value helpers need no
client call. Do not mix this client with another Steam wrapper,
`SteamAPI_RunCallbacks`, `CCallback`, or `CCallResult`.

`runFrame` fetches work; drain `nextEvent` afterward. `nextEvent` needs a mutable
Client because it updates keyboard, leaderboard and Workshop query ownership even
if the caller discards an event. Every event owns its payload.
The native callback is freed before the event returns. Draining to `null` also
releases the calling thread's temporary Steam API memory. Unknown or malformed
callbacks and call-result retrieval/I/O failures have explicit event variants.

Asynchronous acceptance is **not** operation success. API-call-producing methods
return a typed `Request(kind)`. Its `take(&event)` method matches the call and
payload type. It returns `null` for unrelated events or an inactive tracker.
It consumes a matching completion once, including retrieval or decoding failures.
The event itself remains available to other code.

```zig
const lobbies = client.lobbies();
var request = try lobbies.create(.{ .visibility = .private, .member_limit = 4 });
var joined: steam.SteamId = .invalid;
defer if (joined != .invalid) lobbies.leave(joined) catch {};

// Inside the application's explicit event loop:
if (try request.take(&event)) |created| {
    if (created.result != .ok) {
        std.log.err("Steam rejected lobby creation: {d}", .{@backingInt(created.result)});
        return error.LobbyRejected;
    }
    if (created.lobby == .invalid) return error.InvalidLobbyResult;
    joined = created.lobby;
}
```

The snippet illustrates correlation, not a complete membership lifecycle.
It requires `std`, a live `client`, and an event from its explicit loop.
A successful `.lobby_entered` can establish membership even when result retrieval
fails. Retain cleanup responsibility for memberships your application owns.
An entry broadcast does not identify the originating creation request.
Do not attribute arbitrary application memberships to one pending request.
[`examples/smoke.zig`](../examples/smoke.zig) supplies a bounded lifecycle with separate entry tracking.

Keep one tracker per operation. Discard trackers when their client session ends.
A tracker neither owns a native resource nor cancels the request.

`RequestError` distinguishes unavailable results, I/O failure, malformed data,
and an unexpected completion type. Successful retrieval does **not** imply a
successful operation. Check the returned payload's `result` or `response` field.
Search completions instead return a count. Cloud-write completions return a
`Result` directly.

Ordinary broadcasts have `.invalid` call IDs and never complete a tracker.
A lobby operation can emit both a correlated result and a broadcast.
Output enums retain unknown values. Use `@backingInt` when logging them.

Borrowed service leases detect closed/moved clients, wrong-thread use, and stale
sessions in release modes too. These checks do not make freed client storage safe
to access. Numeric socket/group/lobby/ticket/call handles must not cross sessions.

## Errors and results

The API distinguishes these stages:

1. Local validation returns a Zig error, such as `TooLarge` or `InvalidSendOptions`.
2. Immediate native failure uses the information Steam supplies.
   Invalid request handles produce `RequestRejected`.
   Selected networking mutation booleans produce `OperationFailed` on failure.
   Other APIs preserve their documented booleans. Detailed Steam results remain
   `Result` values or tagged outcomes.
3. Asynchronous retrieval failures come from `request.take`.
   Operation-level results remain in the retrieved payload.

Predicates remain booleans. `Friends.requestUser` also remains a boolean because
false can mean that Steam already cached the requested information.
Errors such as `ListenFailed` identify an operation, not an inferred Steam cause.
The API does not invent precise reasons for native boolean failures.
Lifecycle misuse remains a panic in every optimization mode.

## Authentication

`authSessionTicket` writes into caller storage. Bind the ticket to the receiving
Steam user when known; wait for a matching successful `.auth_ticket` event before
sending bytes. Keep the ticket handle and cancel it when the connection ends.
`webApiTicket` delivers owned ticket bytes in `.web_ticket`; likewise cancel it.
Do not log ticket bytes.

`beginAuthSession` returning `.ok` is only provisional. Observe `.auth_validated`,
including later revocation, before granting/retaining game permissions. End each
auth session on disconnect. Publisher Web API secrets belong on a backend, never
in the client. Authentication does not validate a player's gameplay requests.
`AuthResponse.network_identity_failure` names SDK response 10. Unknown response
values remain representable.
