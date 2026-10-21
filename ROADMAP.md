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
| PKG-04 | Publish immutable source and migrate the game | URL/hash dependency works from a fresh cache without vendored source; default game stays SDK-free | accepted and published through M4; game consumes immutable ef3a395 |
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

SDK contract planning is complete against the accepted M1 checkpoint. The parent inspected the report and verified the unchanged planning source.
Telemetry/text, configuration/simulation and debug capture are implemented in isolation. The parent read all three handoffs and inspected their source and component evidence without finding a production implementation blocker.
Lanes/batch and received-lane conversion also completed their isolated gates. The parent inspected the exact increment, ownership paths and execution evidence.
All component writers ended ownership. The parent copied ten component files into a separate integration worktree and added shared lifecycle/build/consumer registration.
The integrated candidate passed all four native optimization modes and all four target compile/link/install graphs. Active diagnostics, retained production imports and the actual archive/consumer check passed.
Private debug-test unwind cleanup was repaired and negatively tested, without changing production callback code.
Independent package/build review found no issues. Runtime review found two test-only cleanup omissions; both were repaired, validated in the affected scope and re-reviewed with no issues.
The parent accepted M2 source after the fixed-source package audit and copied the exact candidate into main.
Final document-inclusive archive and staged-tree checks passed. Commit `b41b7e4` was normally pushed, and its actual immutable URL/hash consumer passed build/install and negative probes.
New native-service behavior and performance remain separate readiness gates.

| ID | Work | Acceptance | State |
| --- | --- | --- | --- |
| NET-01 | Real-time telemetry | Owned typed status exposes ping, quality, pending bytes, and queue estimates with native result fidelity | accepted |
| NET-02 | Detailed diagnostic text | Caller-storage API preserves native sizing/failure results and documents short-buffer mutation | accepted |
| NET-03 | Selected typed configuration | Timeouts, buffers, and useful rate controls validate type/scope; unsupported settings are not guessed | accepted |
| NET-04 | Development packet simulation | Explicit loss/lag/reordering options with safe reset, deterministic marshalling tests, and no default gameplay changes | accepted |
| NET-05 | Debug output | Thread-safe bounded handling of SDK service-thread callbacks; no Steam calls from the callback; defined overflow and teardown behavior | accepted |
| NET-06 | Connection lanes | Typed lane configuration and send selection preserve same-lane reliable ordering contract and validate limits | accepted |
| NET-07 | Batch sending | Explicit outbound ownership and accepted/rejected/not-attempted outcomes; cleanup covers every partial-failure path | accepted |

Simulation reset clears selected overrides to SDK defaults. It does not restore older explicit values or provide atomic rollback.
Debug capture uses persistent process-wide storage. Stop does not establish callback quiescence, and restart does not establish session provenance.
Both capabilities require explicit opt-in. Existing client initialization gains no default action or optional-interface requirement.
Keep the existing received-message ownership model. A send accepted locally does not prove delivery.
Do not infer performance gains without measurements.

### M3 — Platform, saves, input, and progression

The parent read the completed SDK contract report and verified the planning source and SDK inputs against accepted M2.
Utilities, Input and cloud component handoffs completed in isolated worktrees. The parent read all reports and checked their exact source boundaries.
Progression followed cloud without overlapping ownership. All four writers ended ownership; the parent inspected all source handoffs, exact frozen inputs and selected evidence.
The parent integrated correlated callback-time capture, Client ownership transitions, optional teardown, public roots, build/consumer registration and SDK-free guards in a separate checkout.
Four-mode offline test graphs passed, including 228 new platform/batch guards per mode. A missed const pointer in the smoke helper was repaired and its Debug install rechecked separately.
Four ReleaseFast target graphs passed 36/36 compile/link/install steps. Artifact inspection confirmed native import/sink retention, runtime bytes and no wrapper C++ runtime dependency.
Active SDK-aware diagnostics passed. Event storage was measured without a performance claim.
The actual 52-source/49-member package audit passed, with relocated tests/install and an independent archive/hash consumer. Only its pure main ran.
Three independent reviews completed. Ownership and distribution reviews found no defect; Input review found one reserved-argument forwarding discrepancy.
The parent changed RunFrame to match the SDK's true default and corrected its fixture. Negative controls reject the original call in Debug and ReleaseFast.
The fixed focused graphs passed 24 tests, one intentional skip and the Input fixture in both modes. Four-target fixture/consumer links, active diagnostics and the changed actual package audit passed.
A scoped independent re-review confirmed the defect is resolved, with no new finding. The other 51 source files remained unchanged.
The parent accepted M3 source on 2026-10-20. Final document-inclusive package, indexed-source and Git archive audits passed.
Commit `24fcb967` was normally pushed. Its actual immutable URL/hash consumer passed build/install, negative probes and production-linkage/runtime-byte checks without execution.
The full four-mode graphs above precede the narrow correction; the focused checks supplement them without repeating unchanged work.
Source acceptance does not establish native-service readiness. No M3 native-service execution is implied.

| ID | Work | Acceptance | State |
| --- | --- | --- | --- |
| UTIL-01 | On-screen text entry | Full-screen/floating keyboards, dismissal events, bounded text retrieval, and cancellation contracts | accepted |
| UTIL-02 | Text filtering | Caller-owned output, UTF-8 byte capacity, source/context preservation, unavailable-filter behavior | accepted |
| UTIL-03 | Resume and hardware guidance | Owned resume event and SDK 1.65 default-settings guidance; preserve unknown enum values and avoid hardware-name feature gating | accepted |
| CLOUD-01 | Dynamic Cloud Sync changes | Owned notification plus bounded change enumeration with clear borrowed/owned path lifetime | accepted |
| CLOUD-02 | Write-batch hints | Paired begin/end ownership, failure handling, and teardown policy; explicitly not an atomic save transaction | accepted |
| INPUT-01 | Steam Input lifecycle and actions | Explicit init/frame/shutdown integration, action sets, digital/analog actions, and connection changes | accepted |
| INPUT-02 | Glyphs and vibration | Typed handles/options, caller-owned copied text where needed, device capability and fallback behavior | accepted |
| STATS-01 | Achievement icons | Typed image handles and owned readiness events integrated with existing image access | accepted |
| STATS-02 | Leaderboards | Find/query/upload requests, typed handles, copied entries/details, SDK result lifetime and concurrency restrictions | accepted |
| STATS-03 | Global achievement percentages | Typed request/readiness and bounded reads; no invented readiness cache | accepted |

Steam Input needs an action manifest and game integration. A binding alone does not establish controller support.
Dynamic sync must not be enabled for a game until its save reload/conflict policy handles notifications.

### M4 — Optional game-facing capabilities approved for this pass

The read-only SDK/source contract report is complete and consumed by the parent.
The parent verified all 52 planning-source files and 270 SDK files remained unchanged.
Voice, Remote Play and Timeline contracts now have parent-approved lifecycle, argument and bounded-output rules.
Voice, Remote Play and Timeline writers delivered their three-file handoffs and ended ownership.
Five shared schema/state files passed focused Debug/ReleaseFast tests and active diagnostics.
Workshop and Screenshots also delivered their isolated handoffs and ended ownership.
The parent inspected all five components and checked exact sources, frozen inputs, SDK integrity, empty indexes and retained artifacts.
The parent integrated owned callbacks, lifecycle hooks, public roots, build/consumer registration and SDK-free lease guards.
Initial Debug/ReleaseFast checks passed 35 focused Zig tests, six native fixtures and 313 new guard cases per mode.
An external-cwd consumer build exposed a cache-path defect. The parent corrected it and retained the affected checkout and generated files intact.
Three corrected consumer/cache-path cases passed with exact source membership unchanged. A clean source-only successor is the active candidate.
All four native optimization modes passed 678/678 aggregate steps. Each mode passed 130 main tests and two repeated lifecycle controls, with eight expected fatal-body skips.
All four ReleaseFast target graphs passed 44/44 compile/link/install steps without destination execution.
The actual 65-member package passed source/archive checks, relocated tests, consumer probes and runtime-byte checks. Only the inspected pure consumer main executed.
The parent inspected 173 retained artifacts. Twenty consumers retained required production imports, and 117 fixture/guard artifacts had no Steam dependency.
Three fresh read-only reviews found no current issue in content ownership, capability lifecycles or distribution.
The parent confirmed all 68 reviewed source inputs and SDK270 remained unchanged, then accepted M4 source on 2026-10-20.
Final document-inclusive publication and immutable-consumer checks subsequently passed for `ef3a395`; the game consumes that published revision. Native-service readiness remains separate.
Workshop's initial raw ZLS protocol was overwritten during its final rerun. The final clean protocol is retained; the earlier retention loss remains disclosed.
No new live-action authority follows from planning or the approved API scope.

| ID | Work | Acceptance | State |
| --- | --- | --- | --- |
| UGC-01 | Workshop subscriptions and downloads | List subscriptions, query installed/download state, request downloads, and expose copied results with explicit query cleanup | accepted |
| VOICE-01 | Voice capture and codec access | Explicit recording lifecycle, bounded compressed/decompressed buffers, rate/error fidelity, no hidden audio playback or transmission | accepted |
| REMOTE-01 | Remote Play integration | Typed sessions and copied session events/info; explicit invitation/UI actions, no unsolicited side effects | accepted |
| CAPTURE-01 | Screenshots | Typed handle, bounded image/file submission, hook/readiness events, explicit user/application intent | accepted |
| TIMELINE-01 | Recording markers | Modes, tooltips, instant/range markers and defined handle/lifecycle behavior using SDK 1.65 APIs | accepted |

This is bounded game-facing coverage, not a commitment to mirror every method in each SDK interface.
Workshop publishing/modification, unrestricted file loading, audio mixing, and gameplay replication are not included.

### DX — Approved usability and robustness follow-up

The user approved this bounded batch on 2026-10-21 after source/SDK/wrapper research
and ZLS/native-Linux probes. Keep the existing flat-export bridge, explicit
ownership and caller syntax. All seven items are source-accepted. The user
subsequently authorized commits and normal pushes to both repositories after
fresh offline build/run checks; no live Steam actions or game dependency repin
are authorized. See [CHECKPOINT.md](CHECKPOINT.md) for validation counts,
publication boundaries and the disclosed ZLS method-navigation trade-off.

| ID | Work | Acceptance |
| --- | --- | --- |
| DX-01 | Declaration-local documentation and Valve crosswalk | Accurate hover-level ownership, results, cleanup and native API references; no semantic changes in the documentation lane |
| DX-02 | Navigable request completion types | Existing Request/take callers retain behavior and resolve completion fields through ZLS; no new async framework |
| DX-03 | Tested editor setup | Document SDK configuration separately from optional dependency enablement; no machine paths or local editor overrides committed |
| DX-04 | Focused learning examples and current status docs | Compile-checked startup, lobby and message recipes never auto-run; historical readiness limits remain explicit |
| DX-05 | Linux build/deployment consistency | Consumer uses the supported linker; owned artifacts retain explicit runtime lookup without embedding SDK paths; negative deployment controls |
| DX-06 | Initialization/ticket failure coverage | Inert private fixtures prove rollback, diagnostics, recipient forwarding and cancellation, including negative controls |
| DX-07 | Private schema consistency | Compile-time leaderboard status/capacity agreement; unknown values still preserved; no generated bindings |

## Integration and release gates

| ID | Gate | Required evidence | Current state |
| --- | --- | --- | --- |
| LIVE-01 | Local networking | Actual listen/connect/accept and closure, reliable/unreliable traffic, multi-message batches, bounded failures | M4 legacy socket-pair/poll-group smoke passed on macOS arm64; broader listen/peer/failure and M2-tool scenarios remain open |
| LIVE-02 | Real P2P/relay | Two consenting test accounts/machines, failures, disconnect/reconnect, and transport diagnostics | blocked: accounts/machines |
| LIVE-03 | Multi-client lobbies | Join/search, metadata propagation, chat, membership changes, and owner departure | blocked: accounts/machines |
| LIVE-04 | Authentication | Ticket readiness/cancel locally; peer validation/revocation and backend verification separately | M4 local ticket readiness/cancel submission passed on macOS arm64; peer/backend blocked |
| LIVE-05 | Persistent stats/cloud | Configured test app, store outcomes, save round trips, failure cases, cache reload, and cleanup | blocked: app setup and write approval |
| LIVE-06 | Input/overlay/handheld | Physical controllers, actual overlay/keyboard behavior, suspend/resume, and relevant handheld tests | blocked: hardware/session setup |
| LIVE-07 | New service integration | Workshop download, voice device, Remote Play, screenshots, and recording checks with explicit side-effect approval | blocked: setup/approval |
| PLATFORM-01 | Compile/link matrix | Four supported targets, all relevant modules/examples/fixtures/consumer, no target execution claims | DX changed-scope ReleaseFast matrix passed for macOS arm64/x86_64, Windows x86_64 GNU and Linux x86_64 GNU; 52/52 steps each; foreign execution remains untested |
| PLATFORM-02 | Native runtime matrix | Execute offline tests and installed consumer on Windows/Linux/Intel macOS in addition to arm64 macOS | DX Linux offline graphs passed in all four modes; fresh Debug/ReleaseFast pure consumers ran without Steam initialization; smoke/tutorials remain compile/install/loader-only; Windows/Intel macOS execution remains unestablished |
| PLATFORM-03 | Full game builds/runtime | Preserve SDK-free game and validate enabled game on supported deployment hosts | Historical macOS arm64/Arch matrices passed; fresh pre-publication Debug/ReleaseFast SDK-free game runs rendered three frames and enabled offline tests passed; enabled graphics still refer to the earlier pre-RUNPATH-fix run; other runtime gates remain open |
| PERF-01 | Performance | Measured event, send/receive, allocation, and frame-time costs under representative workloads | pending; no current benchmark claim |
| REVIEW-01 | Independent acceptance | Fresh read-only review of exact integrated source, ABI, ownership, tests, package and game migration | Historical M4/migration and Linux fix reviewed; four DX risk reviews and the final integration-delta review complete; parent verified source identity; one documented nonblocking ZLS regression remains |
| RELEASE-01 | Production readiness record | Exact source revision, successful gates, known limits, and remaining app-specific obligations | pending |

The completed game migration and historical runtime evidence are recorded in the
[game migration record](https://github.com/yo-reign/meikyuu-zig/blob/3137046a5d0019d0274544371f43a552dcf03ef3/docs/steamworkz-migration.md)
and [Arch checkpoint](https://github.com/yo-reign/meikyuu-zig/blob/3137046a5d0019d0274544371f43a552dcf03ef3/docs/arch-linux-validation.md).
They do not validate changes made after those revisions.

Historical live authority covered App ID 480 only: read-only queries, local socket traffic, temporary private lobbies with departure, and ticket issue/cancellation. The current DX batch is offline-only.
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
