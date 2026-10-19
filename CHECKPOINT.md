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
- `origin`: `https://github.com/yo-reign/steamworkz.git`. The initial bootstrap record is prepared before its first commit/push.
- Game implementation remains unchanged at the extraction baseline. Its README and a new migration record are uncommitted.
- Extraction hashes and private execution logs stay outside the published repositories.

## Stage state

| Stage | State | Next gate |
| --- | --- | --- |
| M0: extraction/naming/external SDK | accepted | Focused checks, independent review, corrected evidence wording, active diagnostics, and source audit passed |
| M1: permanent tests | planned | Exclusive test seams accepted; isolated writers start after bootstrap acceptance |
| M2: networking tools | pending | Test baseline, SDK contracts, exclusive component handoffs |
| M3: platform/saves/input/progression | pending | Per-component ABI/lifecycle plans and isolated implementation |
| M4: content/voice/Remote Play/capture | pending | Per-component ABI/lifecycle plans and isolated implementation |
| Remote package and game migration | pending | Destination verified; publish an accepted immutable source revision and fetch its real hash |
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

Bootstrap and test-plan children completed. Their checkout ownership has ended.
The parent inspected the eight-file extraction diff and the saved validation evidence.
The test plan partitions services fixtures, core callbacks, lifecycle/properties, and build/package/CI ownership.
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
| Relocated source package | Fresh-cache extraction, code identical to current candidate | 47/47 tests and fixtures ran successfully; consumer and smoke compiled/installed, but neither executable was run |
| Source-package audit | Parent candidate: 31 repository files and 29 package files | Exact owned regular text inputs only; no SDK, symlinks, binaries, caches, private reports, or machine paths. Repeat the audit after these final progress-doc edits before committing |
| Active diagnostics | Eleven changed source/document paths | Clean with explicit local SDK configuration; temporary editor configs moved outside source |
| SDK integrity | Official external SDK 1.65 | All 270 files match the original archive; no extras or copied SDK files in the candidate |
| Runtime deployment | Generated macOS install directories | Official adjacent runtime bytes matched supplied SDK; runtime excluded from source package |
| New package independent review | Eight-file extraction diff plus source/distribution policy | OK with notes; the one documentation finding is corrected. Reviewer inspected source/logs without rerunning tests |
| Remote creation/publication | New library | User-created destination verified and configured as origin; initial push follows this accepted checkpoint's final audit |
| Game dependency migration | Remote URL/hash | Not started; waiting for accepted published revision |

## Tooling observations

A repeated local `zig fetch .` recursively copied its generated `zig-pkg` directory and failed with `NameTooLong`.
Only that task-generated ignored directory was removed under explicit supervisor approval.
The successful retry ran from an external project directory against the absolute library path, with fetch caches outside the input tree.
The resulting archive was inspected and contained no copied build runtimes or SDK files.
Do not rerun local fetch from inside the source being packaged.

## Recovery and next action

1. Inspect Git status in both repositories and read this file plus ROADMAP.md.
2. Recover active runs from the supervisor mission record before launching another writer.
3. Repeat the source-only audit for the final progress-document snapshot.
4. Commit the accepted library baseline, then publish to the verified user-supplied remote.
5. Start the planned test writers with exclusive files and isolated worktrees.
6. Continue M2–M4 and keep feature acceptance separate from blocked release gates.
7. Fetch a real immutable library URL/hash before removing the game's vendored source.
8. Do not claim the project is production-validated while required account/hardware/platform gates remain blocked.
