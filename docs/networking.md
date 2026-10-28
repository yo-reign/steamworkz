# Networking and lobbies

See also [client lifecycle and requests](lifecycle.md) and the [API index](api.md).

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
        std.log.err("Steam rejected the send: {d}", .{@backingInt(result)});
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
See [`examples/smoke.zig`](../examples/smoke.zig) for complete socket-pair and poll-group cleanup.

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

## Telemetry and detailed text

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
the untouched-short-buffer contract of the [`Copy` methods](services.md#borrowed-and-owned-text).
There is no implicit allocation or resize/retry loop.

## Lanes and outbound batches

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

## Explicit configuration and simulation

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

## Process-wide diagnostic capture

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

## Lobbies

`client.lobbies()` provides create/join/leave, filtered searches, cached list
results, ownership/membership, metadata, invitations, binary chat, and game-server
associations. `.lobby_game_created` carries the associated `GameServer` value.
Serialize searches: native filters and search results use shared cache/state.
Consume or copy one result list before starting the next. No cancellation is
invented for native operations that have none. Empty metadata remains ambiguous;
it is not reported as a fabricated missing-key error. Invitations require explicit
application/user intent.
