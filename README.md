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
git clone https://github.com/yo-reign/steamworkz.git
cd steamworkz
zig build test -Dsdk=/absolute/path/to/sdk
zig build install -Dsdk=/absolute/path/to/sdk
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
| `zig build test` | Run offline Zig tests, thirteen C++ fixtures, lifecycle/networking/platform/capability guards, and the consumer/probes |
| `zig build test-core` / `test-services` | Run the focused native callback or inert service-adapter fixture |
| `zig build test-lifecycle` | Check public fatal guards in separate bounded processes, with passing controls |
| `zig build test-properties` | Run deterministic bounded parser/text/event properties |
| `zig build test-networking-tools` | Run focused telemetry, configuration, simulation, capture, lane and batch Zig tests |
| `zig build test-networking-config` / `test-networking-debug` | Run the new SDK-free native adapter fixtures |
| `zig build test-networking-guards` | Check new API leases before empty, invalid and native paths in bounded SDK-free subprocesses |
| `zig build test-platform-tools` | Run focused Utils, Input, cloud, progression and callback-ownership Zig tests |
| `zig build test-utils` / `test-input` | Run SDK-free native adapter fixtures |
| `zig build test-platform-guards` | Check new public leases and acquired cloud-batch close refusal in bounded SDK-free subprocesses |
| `zig build test-capabilities` | Run focused Voice, Remote Play, Timeline, Workshop, screenshot and integrated ownership tests |
| `zig build test-voice` / `test-remote-play` / `test-timeline` / `test-workshop` / `test-screenshots` | Run SDK-free native fixtures |
| `zig build test-capability-guards` | Check optional-capability leases before validation, state changes and native access |
| `zig build test-compile -Dtarget=x86_64-linux-gnu` | Compile/link tests, fatal artifacts, runner, fixtures and consumer/probes without target execution |
| `zig build test-consumer` | Compile/link/install a dependency consumer and check expected compile failures, without running the consumer |
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
regression. It checks target, CPU model/features, optimization and SDK propagation.
It retains uncalled initialization, shutdown, networking, platform/progression and
optional-capability exports so optimized builds must link the production APIs. A second consumer never references capture;
a linker retention check still requires the native trampoline's real Zig sink.
Neither consumer registers a callback or runs those exports during these checks.
The fixture also rejects unsupported request kinds and implicit integer image
handles with the intended compiler diagnostics.
It installs the consumer and official runtime only into an ignored cache output.
It constructs a cached-run command but never executes it or initializes Steam.
The package manifest includes the fixture sources, not its generated outputs.
The independent fixture uses the same SDK option/environment precedence.

Normal tests skip the intentional panic bodies. Separate filtered executables
check their markers, panic diagnostics, termination and total-process deadlines.
No Python is needed by ordinary Zig builds or tests. The optional maintainer
source/archive/runtime checker uses Python's standard library; see
[offline validation](tests/offline/README.md). It can explicitly run the pure
installed consumer, never the live smoke program. Prepared CI is manual and
restricted to trusted SDK-provisioned runners; it has not been executed.
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
if (target.result.os.tag == .linux) {
    // Keep SDK lookup at link time; preserve the explicit $ORIGIN runtime path.
    exe.each_lib_rpath = false;
}

const steamworkz_build = @import("steamworkz");
steamworkz_build.installRuntime(b, target.result, sdk);
// For a cached `b.addRunArtifact(exe)` rather than the installed executable:
steamworkz_build.configureRun(b, run_cmd, target.result, sdk);
```

This excerpt assumes your build already defines `target`, `optimize`, `exe`, and
`run_cmd`. Game source needs only `@import("steamworkz")`; no SDK headers,
`@cImport`, C++ adapter, or separate bridge build recipe belongs in game code.
Build and install your consuming game with:

```sh
zig build install -Dsdk=/absolute/path/to/sdk
```

The same SDK environment fallback and missing-configuration error apply.
These commands compile/install only. Application code explicitly initializes
Steam with `Client.init`; see [Client and event loop](#client-and-event-loop).

Put a runtime beside **each executable that loads it**:
`libsteam_api.dylib` on macOS, `libsteam_api.so` on Linux, or `steam_api64.dll` on
Windows. Linux executables get an `$ORIGIN` search path. The macOS library uses
`@loader_path/libsteam_api.dylib`; an unrelated rpath does not fix a missing
adjacent library. Cached build-run/test processes use a process-local library
search path. SDK redistribution and app deployment remain subject to Valve's
terms; SDK headers are not included in this package's source distribution.

### Linux deployment search paths

`$ORIGIN` means the directory containing the executable. Steamworkz supplies this
explicit runtime search path so the installed game can find its adjacent
`libsteam_api.so` after the game folder is moved. The SDK is needed to build the
game, not as a directory installed on players' machines.

Zig 0.16 can also automatically add link-time library directories to RUNPATH,
including the developer's SDK directory. The `each_lib_rpath = false` setting
above disables those automatic entries while retaining explicit paths such as
`$ORIGIN`. Without it, a missing adjacent runtime can be masked by the SDK copy.

Apply this setting to every Linux executable or test artifact that links
Steamworkz, not just the main executable. It belongs to the consuming
`std.Build.Step.Compile`: importing a module or passing a dependency option cannot
set it for the final executable. It affects all dynamic libraries in that
artifact; provide explicit RPATHs for any other nonstandard deployment directories.
`configureRun` still supplies process-local lookup for cached run/test binaries;
it does not replace this installed-executable setting.

Inspect your installed Linux game with `readelf -d` (replace `my-game` below):

```sh
readelf -d zig-out/bin/my-game
```

Check that `NEEDED` names `libsteam_api.so`, RUNPATH includes `$ORIGIN`, and the SDK
directory is absent. Ship the supplied runtime beside the game; do not substitute
a globally installed copy. Copy the install folder elsewhere and verify library
resolution with `LD_LIBRARY_PATH` and `LD_PRELOAD` unset. A loader-only inspection
checks deployment without initializing Steam; actual game execution is a separate
live check.

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
`send` and `sendRaw` use lane zero. `sendRaw` accepts SDK bits when advanced or
future flags are necessary. Use `sendBatch`, including a singleton, for other lanes.
`SendOptions.no_delay` applies only to unreliable messages.
It remains independent of `no_nagle`.
`close(connection, .{ .debug = "done", .linger = true })` uses named options.
Close, listener cleanup, and poll-group mutation now return error unions.
`closeListen` closes associated incoming connections ungracefully, as the SDK
specifies. Complete any intended graceful connection shutdown before closing the
listener.
A socket pair uses `socketPair(.{ .network_loopback = false })`.

A received batch borrows caller-provided storage and owns its initialized messages.
Do not copy a live batch or message, move messages out, or overwrite live slots.
No received-message ownership-transfer API exists.
One `defer batch.deinit()` releases the entire batch, including unread messages.
Individual messages may be deinitialized early while the client remains open.
Batch cleanup skips their released native handles.
Message bytes expire when their message is released.

A receive batch contains at most 64 messages. Invalid native batches release their
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

### Telemetry and detailed text

`realTimeStatus(connection, lanes)` returns an owned status or the exact native
rejection. `lanes` is caller-owned storage for the requested lane prefix (0..255).
On native rejection, lane outputs remain unchanged. Empty storage requests only
the connection status. Snapshots retain unknown states/results, signed readings
and floating-point values without normalization. The jitter query clears the
SDK's high-water mark. Overall queue time is not a multi-lane queue estimate;
use the per-lane readings when lanes are configured.

`detailedStatus(connection, buffer)` preserves native failure (`-1`), completion
(`0`) and positive required-capacity results. Unexpected negative values remain
explicit. Empty storage performs the native null/zero sizing query. Complete text
must terminate inside the supplied capacity; its returned slice excludes NUL and
borrows the buffer. A short buffer can be modified or truncated. This is **not**
the untouched-short-buffer contract of the `Copy` methods below. There is no
implicit allocation or resize/retry loop.

### Lanes and outbound batches

`configureLanes` accepts 1..255 `LaneConfig` values. Priorities are arbitrary i32
values; lower numbers have strict priority. Positive u16 weights share bandwidth
only among equal priorities. Check the returned `Result`; the SDK validates the
connection and rejects lane-count reductions. Reconfiguration can reset balancing.
Steamworkz neither caches the count nor configures lanes automatically.

```zig
const result = try net.configureLanes(connection, &.{
    .{ .priority = 0, .weight = 1 },
    .{ .priority = 10, .weight = 1 },
});
if (result != .ok) return error.LanesRejected;
var outcomes: [1]steam.Networking.BatchSendOutcome = undefined;
const sent = try net.sendBatch(&.{.{
    .connection = connection,
    .payload = bytes,
    .lane = 1,
    .options = .{ .reliability = .reliable },
}}, &outcomes);
// Inspect sent[0]: accepted, rejected, not_attempted, or unexpected_result.
_ = sent;
```

Descriptors and payloads are borrowed only for the call. The entire batch is
validated before native access or allocation. Each payload is copied into an
SDK-allocated message. An empty payload uses one storage byte with logical size
zero and unchanged SDK ownership callbacks. Pre-transfer errors send nothing,
release every acquired message and leave caller outcomes untouched.

One native call transfers **all** messages, including failures and skipped entries.
No outbound owner or release callback escapes. The returned slice borrows caller
outcome storage; it needs no cleanup. Positive numbers mean local acceptance,
negative results preserve EResult, and zero means not attempted after an earlier
failure on that connection. Malformed encodings retain their raw i64 without
losing other entries. No retry, rollback or delivery guarantee is added.

`max_send_batch` is a separate wrapper bound of 64, not an SDK or receive limit.
`max_send_size` is the SDK's 512-KiB per-message limit. Outgoing lanes are 0..254;
the SDK checks whether the selected lane is configured. Empty batches make no
native call, but still check the lease. No throughput improvement is claimed.

Received `Metadata.lane` is separate from `channel` and retains the native u16.
Message numbers are scoped to connection **and lane**. Reliable ordering holds
within a lane, not across lanes. Receive ownership and payload lifetime are unchanged.

### Explicit configuration and simulation

`client.networkingConfig()` returns a borrowed `NetworkingConfig`. Construction
makes no native call. `set`, `get` and `clear` support global, listener and connection
scopes for initial/connected timeouts, send-buffer size, minimum/maximum send rate,
and Nagle delay. Values remain i32 for SDK validation. Setter booleans become
`OperationFailed`, not fabricated EResult values. Getter status, type and size
remain available; only correctly typed/sized success exposes an i32 value.
Inherited values and malformed success remain distinct. The SDK currently requires
matching minimum/maximum rates; two setters do not form a transaction.

`applySimulation` is explicit process-global opt-in. Its fixed order is send/receive
loss, send/receive lag, send/receive reorder, then shared reorder delay. All fields
are validated first: finite percentages in 0..100 and nonnegative millisecond delays.
Application stops at the first native rejection. Each field reports applied,
rejected or not attempted; the accepted prefix is not rolled back.

`resetSimulation` attempts all seven clears even after a rejection. It restores
SDK defaults, **not earlier explicit values**. A default `Simulation` sets zero
overrides; it does not clear them. Reset before client close and inspect every
outcome. There is no automatic reset, snapshot, rollback or default gameplay change.

### Process-wide diagnostic capture

`client.networkingDebug()` returns a borrowed `NetworkingDebug` capture facade.
Call `start(level)` explicitly; a duplicate start returns `AlreadyStarted`.
Active levels are 1..8. Use `stop()` rather than level zero. Client initialization
and `runFrame` gain no registration or new optional-interface requirement.

`drain(records)` copies bounded owned records into caller storage. `Record.bytes()`
returns the meaningful raw byte prefix, not necessarily UTF-8. Unknown levels and
truncation remain explicit. A full or contended queue drops the newest record;
independent u32 drop-counter snapshots wrap modulo 2^32. A busy drain copies
nothing. Try again on a later frame; do not spin. The callback uses static storage,
lock-free atomics and one queue acquisition attempt, without allocation, logging,
waiting or Steam calls. This is not a universal wall-clock timing guarantee.

Records and counters persist across stop/start and client sessions. They have no
connection, session or start-interval provenance. Do not use them as gameplay events.
Stop disables admission before unregistering; failure never re-enables admission.
Removal does not prove quiescence: admitted producers can finish afterward, and
delayed old callbacks can arrive after restart. Client teardown disables capture
before native shutdown, after checking outstanding received messages and cloud
write batches. Optional keyboard and Input cleanup also runs while the lease is live.
Callback code/storage must remain valid until process exit; dynamic unloading is
unsupported. Facade methods still require a live owner-thread lease, even for empty
or inactive operations. Treat diagnostics as private data; do not publish ticket material.

### Lobbies

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

### Keyboard, resume and text utilities

`client.utils()` is an action-free borrowed facade. `showGamepad(options)` and
`showFloating(options)` share one wrapper pending slot. This is wrapper ownership,
not a claim about the native service's concurrency limit. Native rejection leaves
the slot free. `dismissGamepad`/`dismissFloating` report acceptance only; they do
not clear the slot early or invent a cancellation event. A matching dismissal or
Client teardown ends wrapper ownership. Teardown attempts one pending-mode dismiss;
it makes no native utility call when unused.

`.gamepad_dismissed` owns submitted/AppID/match metadata and `GamepadText` capture.
Only a pending matching AppID triggers the secondary getters, before native
callback release. Unrelated events are `untracked`; cancellation skips getters.
The 1024-byte storage, including NUL, is a **wrapper bound**, not the SDK maximum.
Reported and queried lengths, complete/empty, canceled, too-large, unavailable,
retrieval-failed and malformed outcomes remain distinct. `capture.text()` borrows
only the owned payload. No delayed native text getter is exposed.
`.floating_dismissed` and `.resumed` are ordinary owned notifications.

Gamepad descriptions/existing text and filter inputs require NUL-free UTF-8;
empty text is allowed. `max_characters` is not a byte capacity. Floating geometry
uses signed pixel coordinates and positive dimensions. Call `initFilter` explicitly
and inspect its availability boolean. `filterText` needs nonoverlapping caller
storage for all input bytes plus NUL. Its signed filtered-character count is not
the returned byte length. No allocation, truncation retry or implicit initialization
occurs. `defaultConfig` retains unknown hardware hints; it does not change settings
or gate behavior on a hardware name.

### Explicit Steam Input

`client.input()` makes no native call. Check `start(options)` for `.started` before
using Input; `.rejected` requires a new Client session. Startup uses `Init(true)`.
Device callbacks are an explicit `device_callbacks` option, not a default Client
behavior. After startup, call Input `runFrame()` **before** action reads, then call
Client `runFrame()` and drain events. Client pumping does not update Input for you.
Use only this manual-dispatch path, not ordinary/direct-action callback systems.

`stop()` distinguishes `.stopped`, `.inactive` and `.rejected`. Rejected shutdown
also requires a new session; it is not retried automatically. A missing interface
before a lifecycle call preserves state. Final Client teardown makes at most one
best-effort Shutdown attempt for active or failed initialization; it skips an
unused feature and a previously rejected explicit shutdown. This is not a native
cleanup-success guarantee. The exported `shutdown` integration hooks belong to
Client teardown, not application-driven restart logic.

Controller, action-set, digital and analog handles are distinct u64 value types,
not resource owners. `.all` is the SDK's special controller selector. Controller,
layer and origin reads use bounded caller storage (16/16/8); malformed counts and
short output fail without publishing partial arrays. Digital state and activity
are separate. Analog mode, float bits, mouse deltas and unknown outputs are kept,
without clamping or a fabricated inactive-action error. `.input_connected` and
`.input_disconnected` carry owned controller values.

Glyph PNG/SVG paths and localized origin/action text are copied immediately.
Null, empty and short-buffer results differ. No glyph or manifest file is opened
by an offline test. `setManifestPath` requires an active Input session and a
lexically fully qualified absolute path; existence/loading remains the SDK's job.
Windows accepts drive-absolute paths and complete UNC shares, but rejects
current-drive-rooted, drive-relative, incomplete UNC and device-namespace paths.
The namespace restriction is wrapper policy. Input strings reject embedded NUL;
the wrapper does **not** add a new UTF-8 acceptance rule for them. Valid future
origins through 32767 are allowed. Vibration forwards raw u16 motors; return from
a void native call does not prove capability, delivery, duration or a stop effect.

### Cloud notifications and batch ownership

`.cloud_changed` is a notification, not a captured change-list snapshot.
`localChangeCount` preserves signed native failure separately from an empty list.
`localChangeAt` checks current bounds and copies the path before another native
call. Enumerate promptly on the owner thread before another pump. Null/empty/short
paths and unknown change/path types remain distinct. An absolute local path is
**not** automatically a cloud API filename. Nothing reads/reloads a save, resolves
conflicts or enables dynamic sync automatically.

`beginWriteBatch()` acquires a single `WriteBatch` owner only after native success.
A native false means an existing native batch; the wrapper must not end it.
Do not copy a live owner. Explicitly call `end()` before `Client.deinit`; close is
refused while a wrapper batch remains acquired. End outcomes are `.ended`,
`.no_native_batch` and `.already_closed`. Missing interface retains ownership;
either native boolean consumes it. Stale tokens cannot end a later batch. Even a
repeated end requires the original live owner-thread session. There is no automatic
end, retry, rollback, flush, transaction, durability or save-commit guarantee.

### Leaderboards, icons and global percentages

`Stats.achievementIcon` returns a typed image handle. Zero does not identify
whether fetching or absence caused it. `.achievement_icon` owns game ID, all 128
name bytes, achieved-version flag and image handle; pixel/GPU ownership remains
with the image APIs and caller.

`findLeaderboard` finds only; it never creates. Check both the found flag and
`Leaderboard` handle. Names are nonempty NUL-free UTF-8 shorter than the 128-byte
terminated bound. `leaderboardMetadata` copies its optional name immediately and
preserves empty names, signed counts and unknown sort/display values.

`downloadLeaderboard` supports inclusive positive global ranks and bounded
around-user offsets. `downloadLeaderboardUsers` forwards 1..100 supplied IDs,
including duplicates and invalid IDs, without filtering them. The wrapper allows
one outstanding download and owns at most **100 rows × 64 details** in the result.
Only the exact pending nonzero call triggers callback-time row reads. Each bounded
index is attempted once; after a failure, later reads serve cleanup only. The
published rows are the valid contiguous prefix before the first failure.

Inspect capture status, reported/copied counts, failure index/detail metadata and
`all_rows_accessed`, not just request retrieval. A matching completion clears the
pending call. Only a complete capture or understood invalid-detail capture with
all rows accessed permits another download. Uncertain retrieval, oversized counts,
failed reads or unknown outcomes block downloads until a new Client session.
Restart is not proof that a particular native allocation was released. There is
no public entry-set handle, delayed row reader, unbounded drain or invented release
API. Dropping a Request does not release the slot: keep pumping and draining.
Pending/blocked download state does not prevent Client close.

`uploadLeaderboard` is independently serialized to one outstanding upload. It
supports keep-best/force-update, an i32 score and 0..64 details. Check success,
changed, score and signed new/previous ranks. Any matching completion releases
this slot, including retrieval or operation failure. Native acceptance is not
backend success. The SDK limit is ten uploads per ten minutes; there is no hidden
queue, scheduler, retry, timeout or cancellation.

Await successful `requestGlobalPercentages` completion before reading current
native percentages. No readiness cache is maintained. First/next queries each
perform one bounded step and return an owned name, raw float value and achieved
flag only for an item. `no_data_or_end` preserves the native ambiguity; unexpected
negative cursors stay explicit. Iterators are opaque, not array indexes or owners;
do not retain them across refresh, pump or session. Per-name false differs from
interface absence. No stable snapshot or unbounded enumeration is provided.

Inline rows enlarge **every** Event. With Zig 0.16.0, compiler-emitted measurements
for all four supported targets give `@sizeOf(Event) = 28,856` bytes; the private C
`SwEvent` is 28,848 bytes. This is a storage measurement, not a performance benchmark.
Budget stack/queue/copy storage explicitly; no callback allocation is hidden.

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

## Optional capabilities

`voice()`, `remotePlay()`, `timeline()`, `workshop()` and `screenshots()` return
borrowed, action-free facades. Every operation checks the owner-thread/session
lease first, including invalid arguments, empty buffers and repeated cleanup.
Default Client initialization and frame pumping acquire no new optional interface
and perform no new capability action. Start each feature explicitly.

### Voice capture and decoding

`client.voice()` exposes `start`, `stop`, `state`, `available`, `read`, `decode`
and `optimalSampleRate`. A successful void start invocation enters `recording`.
It does not establish microphone readiness. Starting again rejects both recording
and draining states. Stop invokes native stop once and enters `draining`.
Inactive or already-draining stops make no native call. Missing interfaces retain
state for an explicit retry.

After stopping, read the native tail until `read` returns `.not_recording`.
`.no_data` does not finish draining. Neither does `.not_recording` from `available`.
Explicit reads remain available in any wrapper state. Client teardown stops an
active recording once, without draining, waiting or promising tail delivery.

Compressed output uses caller-owned `[]u8`. Decode writes mono signed 16-bit PCM
to caller-owned `[]i16` at 11025..48000 Hz. Input and output must not overlap.
`bytes_written` always counts bytes, while the PCM slice length counts samples.
Native results and raw counts survive failure. Only `.ok` with valid bounds
publishes a slice. An odd PCM byte count is malformed, not truncated success.
`.buffer_too_small` may report a count beyond capacity without publishing a slice.
Native failure can still modify the destination. `available` is a snapshot, and
`optimalSampleRate` is an uncached value, not a readiness flag.

There is no arbitrary-PCM encoder, deprecated uncompressed capture, playback,
transmission, audio mixing, hidden allocation or library-owned audio thread.

### Remote Play sessions and explicit invitations

`sessionCount` and `sessionAt` are separate snapshots. Sessions can disappear
between calls. `RemotePlaySession.invalid` is zero and owns no resource.
Session methods expose Together status, Steam ID, guest ID, form factor, copied
client name and resolution. Guest ID zero retains its invalid/non-guest ambiguity.
Resolution preserves its boolean and signed dimensions independently.

`clientName` scans at most 1024 bytes including NUL, a wrapper policy rather than
an SDK limit. Complete text borrows caller storage and excludes NUL. Null, empty,
unterminated/too-long and short-buffer results differ. Short output stays unchanged.
No SDK string pointer escapes. Form factors retain unknown values.

`showTogetherUi` and `invite` are explicit actions. `.friend` requires a nonzero
Steam ID. Only `.guest` deliberately sends zero. True reports submission, not
acceptance or a connected session. False retains native configuration/rejection
ambiguity. No automatic invitation or UI action occurs.

Owned connection/disconnection events carry session identities. Guest-invite
URLs are sensitive owned bytes. Do not log or open them automatically.
Avatar-loaded events preserve session, signed image handle and signed dimensions.
This facade does not query avatars, direct input or cursors.

### Timeline markers and open ranges

`client.timeline()` exposes mode, tooltip, instantaneous/completed markers and
tracked open ranges. Calls forward recording metadata, not proof of saved content.
`Timeline.Marker` is a process-lifetime identity, not memory ownership. **Zero is
valid.** Closed-marker `remove` explicitly requests content deletion.

`instant` and `completed` options use SDK defaults. `start(event, offset, clip)`
requires explicit arguments and returns a token-checked `Range`. The wrapper
allows 16 open ranges, not an asserted SDK limit. Capacity and serial exhaustion
are checked before native acquisition. Copies share the same Context slot.
`update` replaces all title/description/icon text, even when empty. Its priority
can be `.keep_current` or a new value. `end(offset)` consumes ownership and returns
the marker. `cancel()` removes once and consumes ownership. Copies cannot affect
a consumed or replacement range. Missing interfaces preserve retryable ownership.

Titles, descriptions and icons require NUL-free UTF-8. Creation priorities are
0..1000. Offsets must be finite, and negative offsets are allowed. Completed
durations are 0..600 seconds. Open-range timing and the SDK duration limit remain
the caller's responsibility. No hidden elapsed clock or default end offset exists.

Client teardown attempts cancellation of each open range once. It never auto-ends
ranges, deletes closed markers, resets mode or clears tooltips. Cleared wrapper
slots do not prove successful native deletion. No phase, recording-control or
recording-existence API is exposed.

### Workshop query ownership and item access

`client.workshop()` exposes bounded details queries, subscription enumeration,
item state, install/download information and explicit download submission.
It does not search, publish, modify content or change subscriptions.

`createDetailsQuery(items)` accepts 1..50 supplied identities, preserving order,
duplicates and invalid item IDs. Fifty is a wrapper bound. Only one query can be
owned per Client session. `WorkshopQuery.invalid` is `UINT64_MAX`. **Zero is valid.**
Creation is separate from `Query.send`, so cleanup can be installed immediately.

A Query token, not an event's native handle, controls ownership. `send()` can run
once from `created`. Rejected submission leaves a releasable failed owner. An
accepted send returns `Request(.workshop_query_completed)` and enters `pending`.
Dropping that tracker neither cancels the request nor releases the query.

Client observes each decoded event before returning it. Only the matching nonzero
call can finish the pending query. `ready` requires the expected payload, matching
owned handle, `.ok` result and a returned count no larger than the requested count.
Retrieval/I/O failure, malformed or unexpected payload, wrong handle, oversized
count or non-OK result enters `failed`. Broadcasts, unrelated calls and duplicate
completions cannot reopen the owner. Inspect request retrieval and operation result
separately from Query state.

The event owns query/result/count/cache/cursor metadata, **not rows**. `resultCount`
is null until ready. `read(index, &details)` requires a ready query and a checked
index. Its getter boolean and the row's own Result are separate. False leaves
caller storage unchanged. A successful `Details` row owns every copied field and
fixed array, and survives query release. Bounded text views exclude NUL but do not
promise UTF-8 or a full unabbreviated description. Unknown enum values, signed
legacy sizes and total file size remain intact. No content file is opened.

`release()` is allowed from created, ready or failed. True consumes the owner,
so copied or repeated owners cannot release a replacement query. A missing
interface preserves retryability. Unexpected native false enters `release_failed`
and blocks further release or new queries for that session. Pending release
returns `QueryPending`. There is no in-session abandon or invented cancellation.

Client teardown attempts release once for created/ready/failed owners. It skips
pending/release-failed owners, clears wrapper state and proceeds to native session
shutdown. It does not pump, wait or cancel. Global shutdown is a recovery boundary,
not evidence of query-specific release, cancellation, delivery or reclamation.

`subscriptionCount` and `subscriptions` explicitly default
`include_locally_disabled` to false, matching the SDK. They are not an atomic
snapshot. Enumeration accepts at most 1024 caller entries. Empty storage avoids
native access. An oversized returned count publishes no prefix and leaves output
unchanged. All item-state flags remain available.

`installInfo` preserves native availability, byte size and timestamp. A successful
path must terminate inside caller storage. False can modify that storage without
publishing a path. A legacy path can identify a file, not a directory.
`downloadProgress` preserves availability and both byte counts. Zero total does
not prove completion. `downloadItem` explicitly submits a download, with wrapper
default `high_priority = false`. After acceptance, stop using existing item files
until `.workshop_downloaded`. That broadcast identifies app/item, not a unique
request. `.workshop_item_installed` also retains legacy content and manifest IDs.

### Screenshots and asynchronous input borrowing

`client.screenshots()` exposes RGB/file submission, trigger and explicit hook
control. `ScreenshotHandle.invalid` is zero. A nonzero handle reports submission,
not readiness or operation success. These process-lifetime identities own no
releasable allocation and do not block Client close.

`submitRgbBorrowed(rgb, width, height)` requires **mutable** RGB storage, positive
dimensions and exactly `width * height * 3` bytes, with checked native widths.
There is no hidden copy, allocation, decode, queue or image loading.
The SDK documents asynchronous writing but does not establish a synchronous copy
or a precise mutation/retention interval. Steamworkz therefore requires this
conservative borrowing policy:

- Keep the allocation at its exact address until the matching `.screenshot_ready`.
- Do not modify, resize, free or reuse it while pending. The SDK may modify it.
- Matching readiness ends the borrow even when its Result reports failure.
- Unrelated or malformed events do not end borrowing.
- If completion is lost, retain storage until process exit. Client teardown is not
  a documented substitute for readiness.

A zero-handle rejection is not an accepted asynchronous borrow. The caller owns
pending storage, handle matching and memory budgets. The facade stores or frees
no input pointer. Install the application's pending-storage policy before opting
into submission.

`submitFile` requires explicit absolute paths, including an optional thumbnail.
Null thumbnail forwards NULL. Each terminated path must fit the 4096-byte wrapper
bound and contain no embedded NUL. Windows paths must be fully qualified drive or
UNC paths, not drive-relative, current-drive-rooted, incomplete UNC or device
namespaces. Validation is lexical, without normalization or filesystem access.
JPG/PNG/TGA format, dimensions, and a 200-pixel-wide same-aspect thumbnail remain
caller obligations. Path strings and source files must remain stable until
matching readiness under the same conservative borrowing rule.

`enableHook` rejects existing wrapper ownership and an already-active native hook.
A void native invocation establishes wrapper ownership, not acknowledgement.
`isHooked` independently queries native state. Disabling an unowned hook does
nothing. A missing interface while owned preserves an explicit retry. Do not mix
hook controllers. Teardown attempts one unhook only when owned, then clears its
flag. It does not capture, submit, wait or release pending input storage.
`trigger` is separate. Under a hook it requests `.screenshot_requested`, not an
automatic image submission.

All optional-capability execution in the offline suite uses inert substitutes.
Real downloads, microphone capture, invitations, screenshots/hooks and recording
changes require separate authorized scenarios, device/app setup and validation.

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
Added event tags require updating exhaustive switches. The M3 `nextEvent` method
also requires `*Client` rather than `*const Client` for ownership transitions.

## Scope and validation limits

No game replication, authority, prediction, serialization, tick synchronization,
or scene-readiness protocol is provided. The library also omits legacy P2P,
SteamVR, inventory/purchases, server browsing/administration, custom signaling,
Workshop mutation/publication/subscription changes, unrestricted content loading,
audio mixing/playback/transmission, motion/LED/DualSense Input controls, and direct
Input action callbacks.

Offline tests cover ownership, init-failure rollback, actual public lifecycle
panic paths, message validation/release, request validation, all exposed native
completion paths, callback copying, malformed payloads and deterministic
address/text/event properties. Inert service fixtures check SDK argument/output
forwarding without invoking Steam services. Public method bodies are also
analyzed; analysis is not service execution. C++ fixtures compile against the
SDK rather than copied layouts. Offline identity text is substituted because
Valve's formatter requires a live interface.

Current execution state and evidence are recorded in [CHECKPOINT.md](CHECKPOINT.md);
planned work and acceptance gates are in [ROADMAP.md](ROADMAP.md). Historical
macOS arm64 live evidence predates extraction and is distinct from new offline
checks and cross-target compile/link success. Remote/multi-account
connections, authentication validation against a peer/backend, graphical overlays,
configured achievement/cloud writes, native leaderboard/percentage behavior,
physical Input/keyboard/glyph/handheld behavior, and other-platform runtime behavior
need separate tests. Voice devices, Remote Play, Workshop downloads, screenshot
borrowing and native recording behavior also remain separate readiness gates.
Offline M3/M4 coverage is not native-service readiness.
No performance benchmark has been run.

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
