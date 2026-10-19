# Steamworkz production roadmap

## Goal

Use Steamworks from an indie game's ordinary Zig code through one Zig package.
The consuming game must not contain C++ adapters, SDK layout declarations, or a separate binding-generation pipeline.
Steamworkz owns a private, SDK-compiled C++ bridge and exposes Zig types, errors, slices, allocators, and explicit ownership.

The project, Zig dependency key, and exported module are named `steamworkz`.
Valve's product and API names remain Steamworks.
Factual third-party repository URLs and historical commit subjects must not be renamed.

Target baseline: Zig 0.16.0 and Steamworks SDK 1.65.
Supported build targets: macOS arm64/x86_64, Linux x86_64 with glibc, and Windows x86_64.
Windows GNU is the verified cross-compilation target.

## Distribution boundary

- The repository and published Zig source package contain only owned source, tests, examples, and documentation.
- Do not include Valve SDK headers, libraries, archives, runtime binaries, or a copied SDK directory.
- Users obtain the official SDK under their own Steamworks agreement.
- Users supply the external SDK through `-Dsdk=/absolute/path/to/sdk` or `STEAMWORKS_SDK`.
- Do not download the SDK automatically or embed a developer's local SDK path.
- Zig builds the private bridge against the supplied headers. Do not guess ABI layouts or copy another binding's source.
- Installation may copy the supplied official runtime beside an executable. Generated outputs are not repository/package inputs.
- The wrapper is MIT licensed. Valve's SDK remains separately licensed.
- The game consumes an immutable remote package URL and Zig content hash, not vendored source, a submodule, or a sibling path dependency.
- The user created the public repository and supplied `https://github.com/yo-reign/steamworkz.git`. Publish only accepted, audited source to that destination.

## Status rules

`pending` means not implemented. `active` means one assigned owner is working.
`implemented` means source exists but an acceptance gate remains.
`accepted` requires relevant tests, parent acceptance, and required independent review.
A test that cannot run is `blocked` or `not run`, never passed.
Source acceptance does not establish hardware, remote-service, or production-runtime readiness.

Current execution state, ownership, approvals, and next actions live in [CHECKPOINT.md](CHECKPOINT.md).

## Existing foundation

The source baseline comes from the game's `ada8311ec2c7524dea0d3607c795f5d61c8efa48` checkpoint.
It includes client lifecycle, networking sockets, lobbies, friends/presence/avatars/overlays, apps/DLC queries, authentication, stats/achievements, and basic cloud files.
It also includes copied events, typed requests, bounded message batches, pure numeric addresses, and a dependency-consumer build regression.

Recorded baseline evidence includes 47 package Zig tests, three C++ fixtures, all optimization modes, and four-target compile/link checks.
Some Zig tests analyze declarations rather than execute service behavior.
Historical runtime evidence is macOS arm64 only.
This evidence predates extraction and new features. Revalidate changed contracts rather than relabeling historical checks as new runs.

## Delivery stages

### M0 — Extract and consume the package

| ID | Work | Acceptance | State |
| --- | --- | --- | --- |
| PKG-01 | Extract the owned package into its own local Git repository | Original source retained, source provenance recorded, no SDK or generated output copied | accepted |
| PKG-02 | Rename package, module, examples, current docs, and consumer recipe to Steamworkz | Real consumer uses `@import("steamworkz")`; no obsolete first-party branding | accepted |
| PKG-03 | Require an external user-supplied SDK | Missing SDK produces an actionable error; explicit SDK overrides environment; no automatic SDK download | accepted |
| PKG-04 | Publish immutable source and migrate the game | URL/hash dependency works from a fresh cache without vendored source; default game stays SDK-free | initial publication and remote consumer passed; game migration pending |
| PKG-05 | Audit source-package contents | Manifest/archive exclude SDK, runtime binaries, caches, private reports, credentials, and machine-specific paths | accepted; repeat at each publication |
| PKG-06 | Document installation, lifecycle, migration, and release limits | Public recipes describe only accepted behavior and distinguish development App ID from shipping policy | accepted for bootstrap; expand with each API stage |

### M1 — Strengthen permanent tests

| ID | Work | Acceptance | State |
| --- | --- | --- | --- |
| TEST-01 | Services-adapter fixtures | Exercise argument forwarding and native outputs for friends/apps/images/stats/cloud, including meaningful failures | accepted |
| TEST-02 | Every exposed native call-result path | Lobby create/enter/list, user stats, and async writes cover success, retrieval/I/O failure, malformed payload, correlation, and exactly-once release | accepted |
| TEST-03 | Public fatal lifecycle paths | Subprocess tests cover wrong thread, moved client, stale lease, access after message release, and shutdown with outstanding messages in Debug and ReleaseFast | accepted; all four modes, including reviewed runner cleanup |
| TEST-04 | Bounded parser and decoder properties | Reproducible cases exercise numeric addresses, malformed callback sizes/pointers, unknown enums, and bounded copies | accepted |
| TEST-05 | Consumer and packaging regressions | Supplied target/optimization/SDK propagate; source-only package builds away from checkout; installed runtime matches supplied SDK | accepted; repeat source/archive audit at publication |
| TEST-06 | Repeatable offline CI | Privately provisioned SDK, no SDK publication in caches/artifacts, no required Steam login, no implicit live writes | preparation accepted; actual CI not run |

Test private helpers in their owning files. Do not expose test-only public wrappers.
Test behavior and lifecycle, not incidental default values or presentation constants.
The bootstrap callback fixture specialized result retrieval to lobby creation and had no dedicated services fixture.
Completed component handoffs expand all five result types, add inert service-adapter coverage, and test actual public fatal paths.
Permanent registration and aggregate native/cross-target checks passed. Independent review then found one P2 in the runner's failed-exec cleanup, originating in Zig 0.16's POSIX spawn-error path.
The parent confirmed the missing reaping assertion fails and assigned a narrow isolated repair. That repair passed focused checks and independent review; the original P2 is resolved.
A separate temporary-path follow-up satisfies the unchanged source checker. Its four-mode/four-target checks, actual archive audit and changed-scope review passed.
The parent integrated the final runner and accepted M1 source after the integrated source/archive audit. Repeat the document-inclusive archive and staged-tree checks at publication. This source acceptance does not establish non-host runtime or service readiness.
CI preparation does not imply runner provisioning, dispatch authority or an executed CI pass.

### M2 — Networking tools and traffic control

| ID | Work | Acceptance | State |
| --- | --- | --- | --- |
| NET-01 | Real-time telemetry | Owned typed status exposes ping, quality, pending bytes, and queue estimates with native result fidelity | pending |
| NET-02 | Detailed diagnostic text | Explicit borrowed/copy/allocation contract handles required capacity and failures without silent truncation | pending |
| NET-03 | Selected typed configuration | Timeouts, buffers, and useful rate controls validate type/scope; unsupported settings are not guessed | pending |
| NET-04 | Development packet simulation | Explicit loss/lag/reordering options with safe reset, deterministic marshalling tests, and no default gameplay changes | pending |
| NET-05 | Debug output | Thread-safe bounded handling of SDK service-thread callbacks; no Steam calls from the callback; defined overflow and teardown behavior | pending |
| NET-06 | Connection lanes | Typed lane configuration and send selection preserve same-lane reliable ordering contract and validate limits | pending |
| NET-07 | Batch sending | Explicit outbound ownership and accepted/rejected/not-attempted outcomes; cleanup covers every partial-failure path | pending |

Keep the existing received-message ownership model. A send accepted locally does not prove delivery.
Do not infer performance gains without measurements.

### M3 — Platform, saves, input, and progression

| ID | Work | Acceptance | State |
| --- | --- | --- | --- |
| UTIL-01 | On-screen text entry | Full-screen/floating keyboards, dismissal events, bounded text retrieval, and cancellation contracts | pending |
| UTIL-02 | Text filtering | Caller-owned output, UTF-8 byte capacity, source/context preservation, unavailable-filter behavior | pending |
| UTIL-03 | Resume and hardware guidance | Owned resume event and SDK 1.65 default-settings guidance; preserve unknown enum values and avoid hardware-name feature gating | pending |
| CLOUD-01 | Dynamic Cloud Sync changes | Owned notification plus bounded change enumeration with clear borrowed/owned path lifetime | pending |
| CLOUD-02 | Write-batch hints | Paired begin/end ownership, failure handling, and teardown policy; explicitly not an atomic save transaction | pending |
| INPUT-01 | Steam Input lifecycle and actions | Explicit init/frame/shutdown integration, action sets, digital/analog actions, and connection changes | pending |
| INPUT-02 | Glyphs and vibration | Typed handles/options, caller-owned copied text where needed, device capability and fallback behavior | pending |
| STATS-01 | Achievement icons | Typed image handles and owned readiness events integrated with existing image access | pending |
| STATS-02 | Leaderboards | Find/query/upload requests, typed handles, copied entries/details, SDK result lifetime and concurrency restrictions | pending |
| STATS-03 | Global achievement percentages | Typed request/readiness and bounded reads; no invented readiness cache | pending |

Steam Input needs an action manifest and game integration. A binding alone does not establish controller support.
Dynamic sync must not be enabled for a game until its save reload/conflict policy handles notifications.

### M4 — Optional game-facing capabilities approved for this pass

| ID | Work | Acceptance | State |
| --- | --- | --- | --- |
| UGC-01 | Workshop subscriptions and downloads | List subscriptions, query installed/download state, request downloads, and expose copied results with explicit query cleanup | pending |
| VOICE-01 | Voice capture and codec access | Explicit recording lifecycle, bounded compressed/decompressed buffers, rate/error fidelity, no hidden audio playback or transmission | pending |
| REMOTE-01 | Remote Play integration | Typed sessions and copied session events/info; explicit invitation/UI actions, no unsolicited side effects | pending |
| CAPTURE-01 | Screenshots | Typed handle, bounded image/file submission, hook/readiness events, explicit user/application intent | pending |
| TIMELINE-01 | Recording markers | Modes, tooltips, instant/range markers and defined handle/lifecycle behavior using SDK 1.65 APIs | pending |

This is bounded game-facing coverage, not a commitment to mirror every method in each SDK interface.
Workshop publishing/modification, unrestricted file loading, audio mixing, and gameplay replication are not included.

## Integration and release gates

| ID | Gate | Required evidence | Current state |
| --- | --- | --- | --- |
| LIVE-01 | Local networking | Actual listen/connect/accept and closure, reliable/unreliable traffic, multi-message batches, bounded failures | pending; bounded App 480 authority |
| LIVE-02 | Real P2P/relay | Two consenting test accounts/machines, failures, disconnect/reconnect, and transport diagnostics | blocked: accounts/machines |
| LIVE-03 | Multi-client lobbies | Join/search, metadata propagation, chat, membership changes, and owner departure | blocked: accounts/machines |
| LIVE-04 | Authentication | Ticket readiness/cancel locally; peer validation/revocation and backend verification separately | local pending; peer/backend blocked |
| LIVE-05 | Persistent stats/cloud | Configured test app, store outcomes, save round trips, failure cases, cache reload, and cleanup | blocked: app setup and write approval |
| LIVE-06 | Input/overlay/handheld | Physical controllers, actual overlay/keyboard behavior, suspend/resume, and relevant handheld tests | blocked: hardware/session setup |
| LIVE-07 | New service integration | Workshop download, voice device, Remote Play, screenshots, and recording checks with explicit side-effect approval | blocked: setup/approval |
| PLATFORM-01 | Compile/link matrix | Four supported targets, all relevant modules/examples/fixtures/consumer, no target execution claims | pending after changes |
| PLATFORM-02 | Native runtime matrix | Execute offline tests and installed consumer on Windows/Linux/Intel macOS in addition to arm64 macOS | blocked: hosts |
| PLATFORM-03 | Full game builds/runtime | Preserve SDK-free game and validate enabled game on supported deployment hosts | native pending; other hosts blocked |
| PERF-01 | Performance | Measured event, send/receive, allocation, and frame-time costs under representative workloads | pending; no current benchmark claim |
| REVIEW-01 | Independent acceptance | Fresh read-only review of exact integrated source, ABI, ownership, tests, package and game migration | pending |
| RELEASE-01 | Production readiness record | Exact source revision, successful gates, known limits, and remaining app-specific obligations | pending |

Authorized live checks use App ID 480 only: read-only queries, local socket traffic, temporary private lobbies with departure, and ticket issue/cancellation.
Do not purchase, publish content, invite other users, persist stats/cloud writes, change account settings, or log ticket bytes.
Do not run multiple live clients in parallel on this machine.
New live scenarios need specific authority even when their API implementation is approved.

## Deliberate constraints, not unfinished framework work

- One stable-address client and owner-thread service access remain explicit contracts.
- Requests correlate completions. The game owns timeouts, retry policy, session reset, and uncertain-outcome cleanup.
- Discarding a request does not cancel native work. Do not invent cancellation.
- Shared lobby-search caches require serialized searches and prompt result copying.
- SDK strings and copied event text have different lifetimes. Document them explicitly.
- Synchronous cloud reads can block and can return prefixes. Complete-file callers verify capacity and returned length.
- Do not restore delayed async cloud reads. A future design must copy data during native completion with explicit storage ownership.
- Zig cannot prevent copying every live owner. Keep runtime checks active in all optimization modes.
- Separate user/lobby ID types and optional heap-allocated client helpers remain recorded future API decisions, not prerequisites for this delivery.
- Steam supplies platform services and transport. The game owns serialization, authority, replication, prediction, reconnection, and game-state migration.
- Economies/inventory/purchases, VR, dedicated-server administration, custom signaling, and server browsing remain excluded.

## References

- [Steamworks API](https://partner.steamgames.com/doc/sdk/api)
- [Networking sockets](https://partner.steamgames.com/doc/api/ISteamNetworkingSockets)
- [Networking utilities](https://partner.steamgames.com/doc/api/ISteamNetworkingUtils)
- [Utilities](https://partner.steamgames.com/doc/api/ISteamUtils)
- [Steam Cloud](https://partner.steamgames.com/doc/features/cloud)
- [Remote storage](https://partner.steamgames.com/doc/api/ISteamRemoteStorage)
- [Steam Input](https://partner.steamgames.com/doc/features/steam_controller)
- [Stats and leaderboards](https://partner.steamgames.com/doc/api/ISteamUserStats)
- [Workshop](https://partner.steamgames.com/doc/api/ISteamUGC)
- [Remote Play](https://partner.steamgames.com/doc/api/ISteamRemotePlay)
- [Screenshots](https://partner.steamgames.com/doc/api/ISteamScreenshots)
- [Timeline](https://partner.steamgames.com/doc/api/ISteamTimeline)

The supplied SDK 1.65 headers are the authority for ABI and version-specific declarations.
