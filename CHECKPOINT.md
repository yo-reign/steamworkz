# Steamworkz goal checkpoint

## Objective

Deliver an independently consumable Steamworks package for production-oriented indie game development in Zig.
Keep native SDK adaptation private inside Steamworkz.
Track source completion separately from platform, device, account, backend, and game-specific release readiness.

Full scope and acceptance criteria: [ROADMAP.md](ROADMAP.md).

## Authority and boundaries

Recorded 2026-10-19.

- The user approved the complete staged scope in ROADMAP.md and waived individual diff approval within that scope.
- The user authorized subagent implementation with parent integration and acceptance.
- The user selected the MIT license for owned wrapper source, not Valve's SDK.
- The user authorized validated library commits and pushes. The parent retains publication authority.
- The user created the public repository and supplied `https://github.com/yo-reign/steamworkz.git` with instructions to push `main`.
- The coordinator verified that destination was public, unarchived, and empty. No agent created the remote.
- Publish only accepted library source after the source-only audit passes. Do not force-push or overwrite intervening remote work.
- Do not commit, amend, or push the game repository.
- The SDK must remain external, consumer-supplied, untracked, and unchanged.
- No SDK headers, libraries, archives, runtime binaries, private logs, credentials, or machine-specific SDK paths may enter Git or the published package.
- Bounded live authority: App ID 480, read-only queries, local socket traffic, temporary private lobbies with departure, and ticket request/cancel.
- No unsolicited invitations, purchases, content publication, account changes, persistent stats/cloud writes, or ticket-byte logging.
- All live checks are serial. Workers use offline tests unless the parent explicitly assigns a bounded live check.
- Retain existing recovery worktrees and evidence. Do not clean them without authority.

## Repository baseline

- Source repository: `meikyuu-zig`, branch `steamworks`.
- Source checkpoint: `ada8311ec2c7524dea0d3607c795f5d61c8efa48`.
- Extracted source: 26 tracked files from `packages/steamworks`.
- Only tracked regular files were copied. The ignored SDK symlink and generated files were not copied.
- New local repository: sibling directory `steamworkz`, branch `main`.
- `origin`: `https://github.com/yo-reign/steamworkz.git`.
- Accepted initial commit: `09638d28a3569a5b8764850759e3938c19f96cb0`, pushed to `main` and verified equal to the remote.
- Its real remote archive hash is `steamworkz-0.1.0-y1J173HvAwAzGaI58AFV96k9X1GNhhVeaPLgwyJ483rT`.
- That hash identifies the initial commit, not later working-tree changes.
- Game implementation remains unchanged at the extraction baseline. Its README and a new migration record are uncommitted.
- Extraction hashes and private execution logs stay outside the published repositories.

## Stage state

| Stage | State | Next gate |
| --- | --- | --- |
| M0: extraction/naming/external SDK | accepted | Focused checks, independent review, corrected evidence wording, active diagnostics, and source audit passed |
| M1: permanent tests | accepted source | Integrated checks, independent reviews and source/archive audit passed; CI execution and non-host runtime remain separate gates |
| M2: networking tools | pending | Test baseline, SDK contracts, exclusive component handoffs |
| M3: platform/saves/input/progression | pending | Per-component ABI/lifecycle plans and isolated implementation |
| M4: content/voice/Remote Play/capture | pending | Per-component ABI/lifecycle plans and isolated implementation |
| Remote package and game migration | partially verified | Initial remote URL/hash consumer builds; game migration and final feature revision remain pending |
| Final acceptance/release record | pending | Integrated review, validation matrix, explicit residual release gates |

## Implementation topology and lane board

The overall delivery is multi-seam. Tests, networking, platform services, content services, and the consumer integration have distinct contracts.
Do not assign the complete delivery to one writer.

The initial bootstrap is one tightly coupled extraction/name/build seam.
Package name, module name, example imports, consumer manifests, SDK lookup, and consumption documentation must migrate together.
It does not add new Steam API features.

| Lane | Repository/cwd | Exclusive ownership | Isolation | Authority | Gate and handoff | Why independent |
| --- | --- | --- | --- | --- | --- | --- |
| bootstrap | `steamworkz` main checkout | Existing package build/manifest, current README, examples, consumer files, and root module documentation for extraction/naming/SDK resolution only | Separate sibling repository; sole writer while active | Edit within scope; offline validation; no stage/commit/push/live/delegation | Preserve existing behavior, native Debug/ReleaseFast tests and consumer build; managed report with changed paths and commands | Name and build migration is a coherent seam before feature expansion |
| test-plan | Read-only `meikyuu-zig` baseline `ada8311` | Evidence and proposed partitions for TEST-01 through TEST-06 | No source writes; managed report only | Inspect source/SDK; no edits or execution of Steam | Exact private test seams, proposed file allowlists, ABI/lifecycle risks, focused checks | Uses immutable original source while bootstrap renames its copy |
| integration/publication | Parent coordinator | ROADMAP, CHECKPOINT, policy/license files, accepted integration, Git state, remote publication and game migration | Parent writes only when no child owns the affected checkout | User-approved library commits/pushes after gates; no game commits/pushes | Exact hashes, tests, independent review where required, source-only publication audit | Owns acceptance and cross-repository ordering, not delegated feature implementation |

Bootstrap, test-plan, and independent review children completed. Their checkout ownership has ended.
The parent accepted and published the eight-file extraction change with the source-only policy/docs.
Three test component writers completed in isolated worktrees from `09638d2`.
The parent inspected their reports/diffs and copied exactly eight allowed files into a fourth integration worktree.
Only the new ticket property was refined: it asserts the declared byte prefix, not an incidental unused-tail policy.
Concrete paths, original/current hashes, and decisions are recorded in the private coordinator lane board and `git worktree list`.

| Test lane | Exclusive files | Current gate |
| --- | --- | --- |
| services | `c/services.cpp`, `src/services.zig` | Accepted after integration, validation and review |
| core | `c/core.cpp` | Accepted after integration, validation and review |
| lifecycle | `src/Client.zig`, `src/Context.zig`, `src/Networking.zig`, `src/events.zig`, `src/types.zig`, new `tests/lifecycle_runner.zig` | Accepted with reviewed runner repair; Context needed no edit |
| build/package/CI | Build/manifest, consumer sources, maintainer checks, manual workflow only | Source and preparation accepted; CI not provisioned or dispatched |
| runner repair | `tests/lifecycle_runner.zig` only, in isolated worktrees | Ownership repair and temporary-path follow-up validated, independently reviewed and integrated |

The original M1 writers ended checkout ownership. The parent inspected the ten build-lane changes and copied all 18 component/integration files into the main library checkout.
The parent also added a CI preflight that rejects overlapping SDK/private-evidence paths before any work-directory creation; focused checks passed.
Two independent read-only reviews completed against a frozen 37-file inventory, verified by the parent before and after review.
Both reports said OK with notes; the runtime report identified one P2 in failed-exec cleanup.
The isolated repair completed and passed focused validation. A fresh read-only review found the original P2 resolved, with no new defect.
The parent then found that the source checker rejects the repair's generic temporary-path literals. They are not leaked SDK paths.
A parent-only follow-up selects a runtime-configured or platform temporary directory without weakening the checker. Its focused checks, actual archive audit and changed-scope review passed.
The parent integrated only the final runner, preserving all other main files and newer shared docs. Both isolated candidates remain retained.
M1 source acceptance is recorded on 2026-10-19. Publication still requires the final document-inclusive archive and staged-tree checks; acceptance is not a production-readiness claim.
Required lifecycle checks use a Zig runner, not a Python dependency of `zig build test`.
Optional maintainer archive checks may use Python's standard library. They must not generate bindings.
CI will be manual and restricted to trusted, externally SDK-provisioned runners. No untrusted pull-request execution or SDK-bearing artifact/cache uploads are permitted.
Runner provisioning and CI execution remain external gates.

Later writer lanes must record exclusive files/contracts, isolation paths, required gates, and a durable handoff before launch.
Use separate worktrees for concurrent mutation.
Wait for all component handoffs before an integration-only pass.
Read-only reviewers may share a checkout only when they do not alter generated or source state.
Do not silently replace a failed subagent with another execution protocol.

## Stable implementation contracts

- Public caller code is Zig. No `@cImport`, SDK struct, native callback registration, or C++ build recipe is required in game code.
- The package compiles its private bridge through Zig against the supplied SDK headers.
- Preserve explicit allocation, borrowed/owned lifetimes, unknown native enum values, and detailed native results.
- Keep owner-thread/session checks active in every optimization mode.
- New optional services must not make existing clients fail initialization merely because an optional interface or feature is unavailable.
- No automatic platform action during module import or default offline tests.
- New input/voice/debug/capture lifecycles require explicit startup and teardown contracts.
- SDK background callbacks require bounded thread-safe handling and cannot call owner-thread-only Steam APIs.
- No generated layout tables, guessed vtables, copied upstream bindings, JavaScript/Node/Bun build tooling, or new C++ standard-library requirement without a justified approved decision.
- Keep declarations private unless production cross-module use or a required callback/entry-point contract requires visibility.
- Test private helpers in their owning source files. Do not introduce test-only public hooks.
- Preserve the game's SDK-free default and existing command/update timing.

## Evidence ledger

| Check | Revision/scope | Result |
| --- | --- | --- |
| Source working tree | `ada8311` before extraction | Clean |
| Destination | Before extraction | Existing empty directory |
| Extraction inventory | 26 tracked owned package files | Copied with hashes; no SDK, symlink, runtime, or cache copied |
| Native offline tests/install | Extracted code, Debug and ReleaseFast | 47/47 Zig tests, three C++ fixtures, real consumer, and smoke compile/install passed in each mode |
| SDK setup contracts | Root and independent consumer | Missing SDK fails actionably; environment fallback and explicit-option precedence passed |
| Relocated source package | Bootstrap source before final documentation edits | 47/47 tests and fixtures ran successfully; consumer and smoke compiled/installed, but neither executable was run |
| Source-package audit | Final `09638d2` snapshot: 31 repository files and 29 package files | Actual Zig package and staged Git archive passed after final bootstrap document edits; no SDK, symlinks, binaries, caches, private reports, or machine paths |
| Active diagnostics | Eleven changed source/document paths | Clean with explicit local SDK configuration; temporary editor configs moved outside source |
| SDK integrity | Official external SDK 1.65 | All 270 files match the original archive; no extras or copied SDK files in the candidate |
| Runtime deployment | Generated macOS install directories | Official adjacent runtime bytes matched supplied SDK; runtime excluded from source package |
| New package independent review | Eight-file extraction diff plus source/distribution policy | OK with notes; the one documentation finding is corrected. Reviewer inspected source/logs without rerunning tests |
| Remote creation/publication | `09638d2` | Parent committed/pushed exactly 31 validated source files; committed tree equals audited staging; remote main equals local |
| Real immutable package fetch | Archive of `09638d2` | Fetch succeeded; computed hash equals the audited local package hash |
| Independent remote consumer | URL/hash dependency outside both repositories | Native Debug compile/link/install passed; installed runtime matches supplied SDK; consumer not executed |
| M1 services component | Isolated Debug/ReleaseFast fixture and ordinary tests | Five inert groups exercise 56 adapters; no Steam linkage in new fixture; 50/50 Zig tests plus existing fixtures passed; Linux/Windows compile/link passed |
| M1 core component | Isolated Debug/ReleaseFast fixture | 948 acquired-callback cases cover five completion types and 30 broadcasts; four-target compile/link passed; real identity formatting is intentionally substituted offline |
| M1 lifecycle/property component | Isolated Debug/ReleaseFast harness | 52 normal tests passed, five fatal bodies skipped normally; all five public fatal checks and bounded-runner controls passed; Linux/Windows/Intel macOS compile/link only |
| M1 native aggregate | Debug, ReleaseSafe, ReleaseFast, ReleaseSmall; macOS arm64 | Each passed 34/34 steps: 55 normal passes/five deliberate skips, plus repeated control/discovery passes, five fatal checks, runner controls, four fixtures and consumer/probes |
| M1 cross-target graph | ReleaseFast, all four supported targets; additional Linux x86_64_v3 | Each passed 22/22 compile/link steps; no destination execution |
| M1 consumer linkage/contracts | Separate consumer, all four modes | Native-backed wrapper and SDK import retained; positive install and two intended compile failures passed; unrelated SDK failure rejected |
| M1 worker package audit | Pre-parent-document snapshot: 37 source files, 34 package members | Actual archive membership/bytes passed; relocated ReleaseFast tests/install and independent archive/hash consumer passed; two runtime copies matched SDK; pure installed consumer ran without SDK/search overrides |
| M1 CI preparation | Manual trusted-main macOS arm64 self-hosted workflow | Static/shell/YAML checks passed; no provisioning or dispatch; raw logs and build/runtime outputs remain private |
| Parent CI boundary check | Exact preflight, normal and optimized Python | Twenty controls passed for valid, missing, relative, same/nested and symlink-overlap paths; the preflight made no writes |
| Parent active diagnostics | Nineteen changed paths, excluding deliberate compile-fail sources | Three Python optional-value findings fixed and rechecked; a generic C++ output-style warning is inapplicable to this libc-only fixture; no other findings |
| Parent checker checks | Explicit optional-value guards and archive-stream cleanup | Normal/optimized self-controls, syntax and missing-argument rejection passed |
| M1 SDK integrity | External SDK after integration | All 270 files still match the original archive, with no extras; no candidate file equals an SDK file |
| Parent review-snapshot audit | Current pre-repair snapshot: 37 source files, 34 package members | Actual fetched archive membership and bytes passed; unchanged execution matrices were not repeated |
| M1 independent reviews | Frozen combined candidate, read-only | Both reports OK with notes; one runtime P2 confirmed; no build/distribution/CI defect found; parent blocks acceptance pending repair |
| Parent failed-exec regression | External scratch runner with one added reaping assertion | Native Debug self-test failed: expected CHILD, found SUCCESS; confirms missing-executable cleanup gap, not a production Steam API defect |
| Runner ownership repair | Isolated runner-only change | Four lifecycle modes each passed 21/21 steps and 2/2 adjacent controls, plus five fatal checks and runner controls; four-target compile/link passed; fresh review resolved the original P2 |
| Darwin cleanup assertion | External probes against repaired assertion | Original Zig zombie is rejected; a separately owned persistent live child reaches the deadline; bounded observation does not count as cleanup |
| Temporary-path follow-up | Parent-only runner change; source checker unchanged | Four lifecycle modes passed with inherited, unset, custom-with-spaces and empty temporary-directory settings; four-target compile/link, active diagnostics and actual 37-source/34-package audit passed; independent review found no defect |
| M1 final integration | Exact 18-path handoff, final reviewed runner and shared docs | Final runner copied alone; other main files preserved; integrated 37-source/34-package audit passed; only progress docs differ from the reviewed/executed candidate |
| Game dependency migration | Remote URL/hash | Source migration and final feature revision remain pending; game changes stay uncommitted |

## Tooling observations

A repeated local `zig fetch .` recursively copied its generated `zig-pkg` directory and failed with `NameTooLong`.
Only that task-generated ignored directory was removed under explicit supervisor approval.
The successful retry ran from an external project directory against the absolute library path, with fetch caches outside the input tree.
The resulting archive was inspected and contained no copied build runtimes or SDK files.
Do not rerun local fetch from inside the source being packaged.

The services fixture first used values outside the SDK C++ persona enum's valid range; corrected representable unknown values passed without sanitizer suppression.
The core fixture first called the SDK identity formatter before initialization; a private approved test-only formatter now tests copying/forwarding, not Valve's formatter.
The lifecycle runner handles Zig 0.16 wait cancellation explicitly and tests closed-pipe and SIGTERM-ignoring hangs. It is not a hostile-process-tree sandbox.
Review found a separate spawn-error issue: Zig 0.16's POSIX backend can lose PID and pipe ownership after fork when exec fails. The missing-executable control did not assert cleanup.
An external reproduction added that assertion and failed. The short-lived runner exits afterward, limiting the leak's lifetime; successful-spawn fatal checks and production Steam APIs are not affected.
The completed repair uses header-derived POSIX spawn declarations and retains Windows spawning. It closes owned descriptors on failures and transfers successful PID/read-end ownership together.
Direct spawn plus private PATH lookup avoids Darwin's shell fallback for invalid executables.
On Darwin only, a failed-spawn assertion permits bounded observation of kernel discard. A waitable child always fails; successful-spawn cleanup remains immediate.
Actual missing/invalid exec, descriptor, closed-stdio and partial-acquisition controls passed. The independent ownership review resolved the original P2.
The source check then rejected two generic temporary-path literals. The follow-up uses runtime/platform path selection and caller-owned buffers; it does not relax source-content checks. Its validation, independent review and main integration passed.

The build lane retained intermediate checker path-pattern/driver-project failures and the Windows object-probe limitation; final executable-compilation probes and package checks passed.
Symbol inspection found that a bare uncalled export could be omitted. The consumer now retains its address without calling it; all four modes show the wrapper and native SDK import. No compiler/linker override was added.
The new checker has an explicit owned-file inventory and limited content signatures; it is not a universal secret/provenance detector or hostile archive sandbox.
The parent made optional-value guards explicit in the maintainer checker after active diagnostics and now closes each extracted member stream explicitly.
Temporary SDK-specific editor configuration was retained outside source after checking the candidate.
The worker's local package hash identifies its earlier snapshot, not a published revision or later parent document changes.
No new Steam session, hardware or remote-service evidence is claimed by M1.

Two integration-launch attempts stopped before creating a child: one resolved the mission in the wrong project, and one used the wrong workflow call signature.
The parent reported both failures, verified unchanged inputs, read the tool guide, and validated the corrected same-protocol workflow before retrying.
No alternate CLI agent or new authority was used.

## Recovery and next action

1. Inspect Git status in both repositories and read this file plus ROADMAP.md.
2. Recover active runs from the supervisor mission record before launching another writer.
3. Recover the completed combined reviews, ownership-repair review and temporary-path follow-up review. Their frozen inventories and execution evidence are retained; the final runner is integrated.
4. Preserve the distinction between 55 normal passes, five skips, repeated controls and intentional fatal checks. M1 adds no new Steam session or non-host runtime evidence.
5. For publication, audit the final document-inclusive source snapshot and exact staged tree. Verify the remote before pushing; do not overwrite intervening work. Record the resulting immutable revision/hash in the coordinator evidence.
6. Continue M2–M4 and keep feature acceptance separate from blocked release gates.
7. Fetch a real immutable library URL/hash before removing the game's vendored source.
8. Do not claim the project is production-validated while required account/hardware/platform gates remain blocked.
