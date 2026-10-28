# Services and optional capabilities

See also [client lifecycle and requests](lifecycle.md) and the [API index](api.md).

In this guide: [friends, apps, stats and cloud](#game-services),
[keyboard and utilities](#keyboard-resume-and-text-utilities), [Input](#explicit-steam-input),
[cloud batches](#cloud-notifications-and-batch-ownership), [leaderboards](#leaderboards-icons-and-global-percentages),
[borrowed text](#borrowed-and-owned-text), [voice](#voice-capture-and-decoding),
[Remote Play](#remote-play-sessions-and-explicit-invitations), [Timeline](#timeline-markers-and-open-ranges),
[Workshop](#workshop-query-ownership-and-item-access), and [screenshots](#screenshots-and-asynchronous-input-borrowing).

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

### Borrowed and owned text

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
