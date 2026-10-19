# Steamworkz

A game-facing Steamworks **1.65** package for **Zig 0.16.0**. Public game
callers use Zig only; Steamworkz privately compiles its C++ bridge. No game is
a dependency. This is a focused API, not a binding to every SDK feature.

Targets: macOS arm64/x86_64, Linux x86_64 with glibc, and Windows x86_64.
Windows GNU is the verified cross-compilation target at the extraction baseline.

## Setup and build

Obtain the official SDK under your Steamworks agreement. Keep it outside this
repository; do not copy or symlink it into the checkout. Pass the extracted
**`sdk` directory**, containing `public` and `redistributable_bin`, not the zip or
its parent directory.

```sh
cd steamworkz
zig build test -Dsdk=/absolute/path/to/sdk
zig build -Dsdk=/absolute/path/to/sdk
```

Alternatively, set `STEAMWORKS_SDK` to that external directory. Explicit `-Dsdk`
takes precedence over the environment variable. With neither supplied, the build
fails with setup instructions; there is no `./sdk` fallback or automatic download.
The build installs `steamworkz-smoke` and the appropriate official runtime in
`zig-out/bin`. These generated outputs must not enter the source package.

There is **no JavaScript, Node, Bun, alignment generator, or separate binding
build step**. `build.zig` compiles our small C++ bridge against Valve's headers.
Packed SDK structures never cross into Zig. Our private C boundary contains
ordinary C values; aggregates cross through pointers. The bridge uses the
SDK's flat exports and inline value helpers, not guessed layouts or vtables.
It does not require an additional C++ standard library.

### Build steps

| Command | Effect |
| --- | --- |
| `zig build` | Compile/link the headless example; install it and the runtime |
| `zig build test` | Run offline Zig tests and three C++ fixtures, plus the consumer build regression |
| `zig build test-compile -Dtarget=x86_64-linux-gnu` | Compile/link tests and the consumer without executing target binaries |
| `zig build test-consumer` | Compile/link and install a real dependency consumer into the build cache, without running it |
| `zig build live-test` | Explicitly initialize Steam and run the bounded live checks |
| `zig build tooling` | Write a local, gitignored `compile_commands.json` for native C++ editor analysis |

All accept `-Dsdk=...`; optimization uses `-Doptimize=ReleaseSafe`, `ReleaseFast`,
or `ReleaseSmall`. `test` requires SDK headers/libraries but does **not** initialize
Steam, log in, or contact Steam services. `tooling` generates editor configuration,
not bindings. It uses the host compiler configuration; regenerate it if the SDK
path changes. An exported `STEAMWORKS_SDK` also lets Zig language servers resolve
the package without command-line build options.

`tests/consumer` is an independent project that uses `b.dependency`, the exported
module, and both public runtime helpers. `test` and `test-compile` include this
regression. It checks supplied target/optimization options and SDK propagation.
It installs the consumer and official runtime only into an ignored cache output.
It constructs a cached-run command but never executes it or initializes Steam.
The package manifest includes the fixture sources, not its generated outputs.
The independent fixture uses the same SDK option/environment precedence.
ZLS can also receive the option through a local `zls.build.json`. Do not commit
machine-specific SDK paths.

For explicit live checks, start Steam and log in, then run:

```sh
zig build live-test -Dsdk=/absolute/path/to/sdk
```

This build step sets development App ID **480** for its child process only.
`-Dapp-id=YOUR_ID` selects another app you may use. It does not write an app-id file
or implement shipping/relaunch policy. The example performs read-only queries,
local socket-pair traffic, one private temporary lobby, and ticket request/cancel.
It does not invite friends, open overlays, purchase, or modify cloud saves/stats.

## Consume as a package

The repository is [yo-reign/steamworkz](https://github.com/yo-reign/steamworkz)
(push URL: `https://github.com/yo-reign/steamworkz.git`). Choose an accepted
published source revision, obtain its **full commit ID**, and use an archive URL
pinned to that commit (not a branch or mutable tag). From your game project, run:

```sh
# Set this to the actual immutable source archive URL for your chosen revision.
zig fetch --save=steamworkz "$STEAMWORKZ_IMMUTABLE_URL"
```

Zig writes the dependency URL and computed content hash into `build.zig.zon`.
Review and commit that pin; never guess the hash. Verify the pinned dependency
from a fresh Zig cache before shipping. The archive must contain owned source
and documentation only, not the SDK, caches, or installed runtimes. The local
path dependency in `tests/consumer` is a regression fixture, not the remote
consumption recipe.

In your `build.zig`, resolve the SDK path relative to the consuming project and
forward the resolved path to the dependency and runtime helpers:

```zig
const sdk = b.pathFromRoot(b.option([]const u8, "sdk", "Official Steamworks SDK directory") orelse
    b.graph.environ_map.get("STEAMWORKS_SDK") orelse
    @panic("Pass -Dsdk=/absolute/path/to/sdk or set STEAMWORKS_SDK"));
const steamworkz = b.dependency("steamworkz", .{
    .target = target,
    .optimize = optimize,
    .sdk = sdk,
});
exe.root_module.addImport("steamworkz", steamworkz.module("steamworkz"));

const steamworkz_build = @import("steamworkz");
steamworkz_build.installRuntime(b, target.result, sdk);
// For a cached `b.addRunArtifact(exe)` rather than the installed executable:
steamworkz_build.configureRun(b, run_cmd, target.result, sdk);
```

This excerpt assumes your build already defines `target`, `optimize`, `exe`, and
`run_cmd`. Game source needs only `@import("steamworkz")`; no SDK headers,
`@cImport`, C++ adapter, or separate bridge build recipe belongs in game code.

Put a runtime beside **each executable that loads it**:
`libsteam_api.dylib` on macOS, `libsteam_api.so` on Linux, or `steam_api64.dll` on
Windows. Linux executables get an `$ORIGIN` search path. The macOS library uses
`@loader_path/libsteam_api.dylib`; an unrelated rpath does not fix a missing
adjacent library. Cached build-run/test processes use a process-local library
search path. SDK redistribution and app deployment remain subject to Valve's
terms; SDK headers are not included in this package's source distribution.

## Client and event loop

```zig
const steam = @import("steamworkz");

var client: steam.Client = undefined;
var diagnostic: steam.Client.Diagnostic = .{};
try client.init(&diagnostic); // On failure, diagnostic.text() explains SDK errors.
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

`runFrame` fetches work; drain `nextEvent` afterward. Every event owns its payload.
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
        std.log.err("Steam rejected lobby creation: {d}", .{@intFromEnum(created.result)});
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
`examples/smoke.zig` supplies a bounded lifecycle with separate entry tracking.

Keep one tracker per operation. Discard trackers when their client session ends.
A tracker neither owns a native resource nor cancels the request.

`RequestError` distinguishes unavailable results, I/O failure, malformed data,
and an unexpected completion type. Successful retrieval does **not** imply a
successful operation. Check the returned payload's `result` or `response` field.
Search completions instead return a count. Cloud-write completions return a
`Result` directly.

Ordinary broadcasts have `.invalid` call IDs and never complete a tracker.
A lobby operation can emit both a correlated result and a broadcast.
Output enums retain unknown values. Use `@intFromEnum` when logging them.

Borrowed service leases detect closed/moved clients, wrong-thread use, and stale
sessions in release modes too. These checks do not make freed client storage safe
to access. Numeric socket/group/lobby/ticket/call handles must not cross sessions.

## Errors and results

The API distinguishes these stages:

1. Local validation returns a Zig error, such as `TooLarge` or `InvalidSendOptions`.
2. Immediate native failure uses the information Steam supplies.
   Invalid request handles produce `RequestRejected`.
   Native mutation booleans produce `OperationFailed` on failure.
   Detailed Steam results remain `Result` values or tagged outcomes.
3. Asynchronous retrieval failures come from `request.take`.
   Operation-level results remain in the retrieved payload.

Predicates remain booleans. `Friends.requestUser` also remains a boolean because
false can mean that Steam already cached the requested information.
Errors such as `ListenFailed` identify an operation, not an inferred Steam cause.
The API does not invent precise reasons for native boolean failures.
Lifecycle misuse remains a panic in every optimization mode.

## Networking and lobbies

`client.networking()` exposes modern **ISteamNetworkingSockets**:

- P2P listen/connect by Steam identity and virtual port; IP listen/connect.
- Accept/close, connection information, reliable/unreliable sends, and flushing.
- Receive from a connection or poll group; create/assign/destroy groups.
- Local socket pairs for deterministic transport checks.
- Pure IPv4/IPv6 parsing and Zig formatting, plus native SDK text helpers.
- Relay initialization and typed availability values.

Listen for `.connection_changed`. Accept inbound `.connecting` connections on a
listener you own. Close terminal connections even after a peer closes; the native
handle still needs cleanup. Unreliable delivery is not a replication protocol.

```zig
const net = client.networking();
switch (try net.send(connection, bytes, .{ .reliability = .reliable, .no_nagle = true })) {
    .accepted => |number| { _ = number; }, // Local acceptance, not remote delivery.
    .rejected => |result| {
        std.log.err("Steam rejected the send: {d}", .{@intFromEnum(result)});
        return error.SendRejected;
    },
}

var storage: [16]steam.Networking.Message = undefined;
var batch = try net.receive(connection, &storage);
defer batch.deinit();
for (batch.messages) |*message| {
    try process(message.bytes()); // An error still releases unread messages.
}
```

`process` represents the application's message handler.
`sendRaw` accepts SDK bits when advanced or future flags are necessary.
`SendOptions.no_delay` applies only to unreliable messages.
It remains independent of `no_nagle`.
`close(connection, .{ .debug = "done", .linger = true })` uses named options.
Close, listener cleanup, and poll-group mutation now return error unions.
`closeListen` closes associated incoming connections ungracefully, as the SDK
specifies. Complete any intended graceful connection shutdown before closing the
listener.
A socket pair uses `socketPair(.{ .network_loopback = false })`.

A batch borrows caller-provided storage and owns its initialized messages.
Do not copy a live batch or message, move messages out, or overwrite live slots.
No message ownership-transfer API exists.
One `defer batch.deinit()` releases the entire batch, including unread messages.
Individual messages may be deinitialized early while the client remains open.
Batch cleanup skips their released native handles.
Message bytes expire when their message is released.

A batch contains at most 64 messages. Invalid native batches release their
acquired handles before returning an error. Client teardown refuses outstanding
messages. Release batches before closing the client.
Close connections and listeners before teardown.
Destroy poll groups before teardown.
See `examples/smoke.zig` for complete socket-pair and poll-group cleanup.

Addresses can be prepared before Steam initialization:

```zig
const address = try steam.Networking.Address.parse("[::1]:27015");
var buffer: [steam.Networking.address_text_size]u8 = undefined;
const text = try std.fmt.bufPrint(&buffer, "{f}", .{address});
```

The pure parser accepts numeric IPv4 and IPv6 literals up to 53 bytes.
IPv6 ports require brackets. Names and scope IDs are not supported.
Formatting includes the port and represents mapped IPv4 addresses as IPv4.
Native `net.parseAddress` and `net.formatAddress` remain available for exact SDK
text behavior. Those native helpers still require a live client.

`client.lobbies()` provides create/join/leave, filtered searches, cached list
results, ownership/membership, metadata, invitations, binary chat, and game-server
associations. `.lobby_game_created` carries the associated `GameServer` value.
Serialize searches: native filters and search results use shared cache/state.
Consume or copy one result list before starting the next. No cancellation is
invented for native operations that have none. Empty metadata remains ambiguous;
it is not reported as a fabricated missing-key error. Invitations require explicit
application/user intent.

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

## Game services

- **Friends:** names, accepted friends, persona state, user-info requests,
  avatars/RGBA data, rich presence, explicit invitations, and overlay pages.
  `.avatar_loaded` signals completion of a pending large avatar.
  `ImageHandle` identifies SDK pixels, not an owned allocation or GPU texture.
  For an image handle, query `imageSize` and allocate its checked `ImageSize.rgbaBytes()` count
  before calling `readImage`. Use the dimensions returned by `readImage` for the
  pixel upload; do not assume a fixed avatar size. The caller owns that allocation
  and any GPU resource, and must release each with its respective allocator/API.
- **Apps:** app ownership/subscription, installation and DLC state, DLC listing
  and download progress, languages, owner, build ID, and launch text. Installation
  is not proof of ownership. Treat launch text and join strings as untrusted data.
- **Store:** `friends().openStore(app)` opens a store page only. It does not add
  items to a cart or initiate transactions. Overlay calls can report unavailable.
- **Stats:** integer/float stats, achievements/progress, store completion, and
  requested other-user reads. SDK 1.65 synchronizes current-user stats at startup;
  there is no obsolete `RequestCurrentStats` call. `requestUser` must complete
  successfully before `getUserInt`, `getUserFloat`, or `userAchievement` reads.
  `.stats_unloaded` carries the affected `SteamId` when Steam evicts cached stats.
  Invalidate that user's readiness, then request and await their stats again.
  This is an ordinary broadcast, not a request completion or an automatic cache.
- **Cloud:** enablement queries, existence/size/list/quota, bounded synchronous
  reads, synchronous/asynchronous writes, and explicit file deletion. Check
  `.cloud_written` after an accepted `writeAsync`. Reads can block disk IO, so use
  small files. A successful `read` can return only a prefix if its buffer is small,
  including an empty prefix for empty storage. Success does not prove completeness.
  For a complete file, provide capacity for `fileSize` and check the returned
  length. Coordinate file changes if the size must remain stable across calls.
  **Async cloud reads are deliberately not exposed:** Valve requires
  copying their data within the native call-result context, which this owned-event
  API does not expose. A future implementation needs its own buffer/lifetime
  protocol, not a delayed `FileReadAsyncComplete` wrapper.

Native string views borrow SDK storage until the next Steam call.
Copy retained names, presence, languages, and attributes.
Common identity and lobby metadata methods offer explicit ownership choices:

```zig
const friends = client.friends();
const borrowed = friends.personaName(); // Copy before another Steam call.
_ = borrowed;
var buffer: [256]u8 = undefined;
const copied = try friends.personaNameCopy(&buffer);
_ = copied; // Borrows buffer, not SDK storage.
const owned = try friends.personaNameAlloc(allocator);
defer allocator.free(owned);
```

`friendName`, `presence`, `Lobbies.data`, and `memberData` also have `Copy` and
`Alloc` variants. Copy methods reject short buffers without writing or truncating.
Neither variant appends a zero terminator. Allocation always requires an explicit
allocator. Other borrowed views can use `allocator.dupe` directly.
Empty lobby metadata retains its ambiguous native meaning in every variant.

Fixed-array events expose `connectText()`, `debugText()`, and `nameText()`.
Their slices borrow the containing event payload, not native callback storage.
Sentinel inputs reject interior NUL where truncation would change the request.
Byte counts and image-size arithmetic remain checked before native conversion.

## Migrating the initial API

The extracted baseline already includes the following changes from its initial
API. Extraction renames the dependency/module to `steamworkz` without changing
these signatures. Older callers may need these migrations:

| Initial API | Current API |
| --- | --- |
| `send(connection, bytes, flags)` | `send(connection, bytes, options)` or explicit `sendRaw` |
| Send result struct with `result` and `number` | `SendOutcome` with `accepted` or `rejected` |
| Positional close arguments | `close(connection, CloseOptions)` |
| `socketPair(bool)` | `socketPair(SocketPairOptions)` |
| Native mutation booleans in networking | Error unions handled with `try` or `catch` |
| Receive count and manual per-message cleanup | `MessageBatch`, `batch.messages`, and one `defer` |
| `lobbies.create(type, limit)` | `lobbies.create(.{ .visibility = type, .member_limit = limit })` |
| Raw call handles from create/join/search/stats/cloud requests | Typed `Request(kind)` and `take(&event)` |
| `Lobbies.Error.NativeFailure` | `OperationFailed`, `RequestRejected`, or `InvalidNativeResult`, according to the failure |
| `Friends.requestUser(user, bool)` | `Friends.requestUser(user, .{ .name_only = bool })` |
| Integer avatar image handles | `ImageHandle` |
| Integer relay availability in events | `Networking.Availability` |

Raw `ApiCall` values remain in events and each request's `call` field.
`Request.isPending()` distinguishes active and completed trackers.
The added `.stats_unloaded` event also requires updating exhaustive event switches.

## Scope and validation limits

No game replication, authority, prediction, serialization, tick synchronization,
or scene-readiness protocol is provided. The library also omits legacy P2P,
SteamVR, inventory/purchases, server browsing/administration, custom signaling,
Workshop, leaderboards, and input APIs.

Offline tests cover ownership, init-failure rollback, generations/thread checks,
message validation/release, request validation, C callback copying/correlation,
future enum values, and malformed native results. Public method bodies are
analyzed, and C++ fixtures compile against the SDK rather than copied layouts.

Current execution state and evidence are recorded in [CHECKPOINT.md](CHECKPOINT.md);
planned work and acceptance gates are in [ROADMAP.md](ROADMAP.md). Historical
macOS arm64 live evidence predates extraction and is distinct from new offline
checks and cross-target compile/link success. Remote/multi-account
connections, authentication validation against a peer/backend, graphical overlays,
configured achievement/cloud writes, and other-platform runtime behavior need
separate tests. No performance benchmark has been run.

References: [SDK API](https://partner.steamgames.com/doc/sdk/api),
[networking sockets](https://partner.steamgames.com/doc/api/ISteamNetworkingSockets),
[lobbies](https://partner.steamgames.com/doc/api/ISteamMatchmaking), and
[cloud read lifetime](https://partner.steamgames.com/doc/api/ISteamRemoteStorage#FileReadAsyncComplete).

## License and provenance

Owned wrapper source is MIT licensed; see [LICENSE](LICENSE). Valve's Steamworks
SDK is separately licensed and is neither included nor relicensed by this package.
The baseline was extracted from `meikyuu-zig` checkpoint
`ada8311ec2c7524dea0d3607c795f5d61c8efa48`; see [CHECKPOINT.md](CHECKPOINT.md).
Extraction and offline validation do not establish production readiness.
