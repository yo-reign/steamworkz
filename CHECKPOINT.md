# Steamworkz goal checkpoint

## Objective

Deliver an independently consumable Steamworks package for production-oriented indie game development in Zig.
Keep native SDK adaptation private inside Steamworkz.
Track source completion separately from platform, device, account, backend, and game-specific release readiness.

Full scope and acceptance criteria: [ROADMAP.md](ROADMAP.md).

## Current DX batch — 2026-10-21

The user approved all seven [DX follow-up items](ROADMAP.md#dx--approved-usability-and-robustness-follow-up)
as a bounded implementation batch after reviewing the research proposal:
declaration-local docs, navigable request results, editor setup, focused examples,
Linux build/deployment consistency, initialization/ticket failure tests, and
compile-time private-schema checks. Individual diff approval is waived only
inside this scope. Parent integration and independent acceptance remain required.

**Current state: DX source accepted; publication authorized.**
The user additionally authorized fixing existing bugs/issues uncovered during
this work without further patch-approval pauses. Reproduced defects repaired here
include the packed Input-enum reference and ReleaseSafe POSIX-header translation
failures. A Windows DLL-import constant-expression error in the new private
initialization adapter was also corrected before the final matrix.
After source acceptance, the user authorized committing and normally pushing the
accepted changes to both repositories, with fresh build/run checks first. The
user selected offline checks only. No game dependency repin or live Steam action
is authorized. The game keeps its immutable published dependency; only its
companion editor README changes. SDK inputs stay external and read-only.

All four isolated component owners delivered handoffs and released their lanes.
The parent integrated the components, examples and shared docs, and remains the
sole writer. Four independent, read-only reviews covered request/schema/editor
behavior, native lifecycle and regression fixes, build/deployment/examples, and
API documentation. A final narrow review of the Windows adapter, checker cleanup
and status evidence found no issues. These were source/evidence reviews, not
independent test executions; the parent verified frozen/current source hashes.
Exact hashes, worktrees, attempted checks, failed controls and protocols remain
in the private coordinator record, not the source package.
Do not start another writer without recovering current ownership first.

### Integrated DX evidence

| Gate | Observed result |
| --- | --- |
| Native Linux Debug, ReleaseSafe, ReleaseFast, ReleaseSmall | `test test-compile install examples`: 691/691 steps in each mode; 135/143 reported passes comprise 133 ordinary Zig tests and two repeated controls, with eight intentional fatal-body skips; native fixtures and fatal-guard groups also pass |
| Independent native consumers | Install/link and two negative API probes: 10/10 steps in each mode; consumer applications not executed |
| Cross compile/link/install | ReleaseFast macOS arm64/x86_64, Windows x86_64 GNU and Linux x86_64 GNU: 52/52 steps each; foreign targets not executed |
| Linux deployment | Six executables per native mode: smoke, three tutorials and two consumers; Steam linkage, `$ORIGIN`, identical adjacent runtime bytes, relocation success and missing-runtime failure checked without executing application code |
| Actual source package | 71 owned source inputs, 68 archive/package members; fetched-archive equality, relocated tests/install and independent hash-consumer checks passed; no consumer application execution |
| Configured editor checks | Zig/ZLS 0.16.0: SDK availability alone leaves the game dependency disabled; explicit enablement resolves the integrated module and completion fields; 23 changed Zig documents have explicit empty diagnostics |
| Configured native diagnostics | Exact-source clangd production and fixture probes for `core.cpp` and `input.cpp` have explicit empty diagnostics; an automatic probe lacking SDK headers is retained separately, not counted as clean |
| Checker quality | Ordinary and optimized Python negative controls and Ruff pass; inherited checker warnings were repaired without relaxing checks |
| Preservation | All 270 SDK files, the original SDK archive, 65 immutable cached dependency files, game code/build/pin, repository HEADs and empty indexes remain unchanged |

The Linux consumer now uses LLVM/LLD; owned linked artifacts disable automatic
SDK RPATHs while retaining explicit adjacent-runtime lookup. Input copies packed
enum bits without an aligned reference. The POSIX declaration import disables
fortified inline wrappers only inside Linux `@cImport`; native C/C++ hardening
and release-active lifecycle guards remain intact. Windows adapter calls stay
statically resolved and use the same official SDK entry points.

**Known nonblocking editor trade-off:** unchanged Request callers now resolve
`created.result`, `created.lobby` and `entered.lobby`, but ZLS 0.16.0 still gives
an overbroad generic hover and regresses `take` method go-to-definition to null.
Independent review confirmed the regression. Bounded static mapping and alias
experiments did not restore both behaviors; callers retain their syntax and
semantics, and direct `src/requests.zig` navigation remains the documented fallback.
This is not claimed as complete generic-editor support.

During the implementation/acceptance checks above, no smoke, tutorial, game,
installed consumer or Steam-service scenario was run. Offline fixtures/guards
were executed; tutorial entry points were compiled and installed only.

### Authorized pre-publication offline recheck

The subsequent build/run request was explicitly limited to offline checks:

- Library Debug and ReleaseFast graphs passed again: 691/691 steps per mode,
  with the same test-count and intentional-skip meanings recorded above.
- Independent consumers built with their negative probes: 10/10 steps per mode.
  The inspected, value-only consumer main executed and exited successfully in
  both modes; its retained native-backed exports were not called.
- The SDK-free game passed 49/49 tests and 11/11 build steps in each mode, then
  rendered three frames and shut down normally in both Debug and ReleaseFast.
- The Steam-enabled game passed 62/62 offline tests and 15/15 build steps in
  each mode. Its executable was not launched. It still consumes the immutable
  M4 pin, not the newly accepted sibling library source.

No Steam initialization, live smoke, tutorial, account/service action or
persistent stats/cloud write was performed in this recheck. Native non-Linux,
device, backend, multi-account and performance gates remain separate.

## Historical M0–M4 authority and boundaries

Recorded 2026-10-19; this is not blanket authority for later work.

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
- Accepted M1 commit: `fbd5131000b82b61ab36609415fb4585e4168add`, pushed to `main` and verified equal to the remote.
- Its actual immutable archive hash is `steamworkz-0.1.0-y1J172fnBQBlVblT8pEFQj1UHx3ZBlxcG8QaDfFalEkR`.
- The M1 pin is a test-baseline checkpoint, not the final M2–M4 feature revision for game migration.
- Accepted M2 commit: `b41b7e4be92c78415c38dc1b98fa69737bbd2a84`, normally pushed and verified equal to remote main.
- Its actual immutable package hash is `steamworkz-0.1.0-y1J17_I_CAB4GtAGgEIBlZwaWq_eQfR5cHrDEUH_IQq7`.
- A fresh M2 URL/hash consumer passed build/install, negative probes, production linkage and runtime-byte checks without application execution.
- Accepted M3 commit: `24fcb9673532867ffc51e996f5ca87eb2acfa735`, normally pushed and verified equal to remote main.
- Its actual immutable package hash is `steamworkz-0.1.0-y1J17xtWDABEb_0isyM9YGnqFgyiJegzPDmjJZukLow6`.
- A fresh M3 URL/hash consumer passed build/install, negative probes, production linkage and runtime-byte checks without application execution.
- All five M4 component writers delivered handoffs and ended checkout ownership. Parent source, frozen-input, SDK and retained-artifact inspection is complete.
- Shared M4 integration, aggregate matrices, package/linkage checks and three independent reviews passed. The parent accepted M4 source on 2026-10-20.
- Accepted M4 was published as `ef3a395f1050372c285d6588f797b6c4d056bd6e`; its verified package hash is `steamworkz-0.1.0-y1J174YfEAAPq4ubpOlR7aUQIlgx3e01lnMsMKrFlVoN`.
- The actual 65-member archive and fresh immutable consumer passed publication checks. The game migrated to that pin without vendoring or a sibling dependency.
- The main-based game port was published on branch `steamworkz` at `555d3c62166a767f0c084194e97b04d25819bb8f`; the later Linux build fix and validation record are published through `3137046a5d0019d0274544371f43a552dcf03ef3`.
- Library README guidance was subsequently published at `e494f4176540d842dc28d101f9ac5fc7959f4476`, the baseline for the DX batch. Its publication revision is recorded by Git history; local validation archive hashes are not new game dependency pins.
- Acceptance and publication do not establish native-service or performance readiness.
- Extraction hashes and private execution logs stay outside the published repositories.

## Stage state

| Stage | State | Next gate |
| --- | --- | --- |
| M0: extraction/naming/external SDK | accepted and published | Focused checks, independent review, corrected evidence wording, active diagnostics, and source audit passed |
| M1: permanent tests | accepted and published | Integrated checks, independent reviews and source/archive audit passed; CI execution and non-host runtime remain separate gates |
| M2: networking tools | accepted and published | Final source/index/archive and immutable-consumer gates passed; live/platform/performance readiness remains separate |
| M3: platform/saves/input/progression | accepted and published | Integrated gates, reviews/correction and final source/index/archive/immutable-consumer checks passed |
| M4: content/voice/Remote Play/capture | accepted and published | Integration, matrices, package/linkage, reviews and immutable publication/consumer gates passed for ef3a395 |
| Remote package and game migration | accepted and published | Game consumes ef3a395; macOS/Arch game matrices and bounded graphical checks have separate records; optional-service/other-host gates remain |
| DX: usability and robustness follow-up | accepted; publication authorized | Seven items, regression fixes, matrices, deployment, editor/package audits, reviews and fresh offline build/run checks complete; documented ZLS trade-off remains; normal publication authorized, repin/live actions not authorized |
| Final acceptance/release record | pending | App-specific live, device, multi-account/backend and performance gates remain open |

See the game's [migration record](https://github.com/yo-reign/meikyuu-zig/blob/3137046a5d0019d0274544371f43a552dcf03ef3/docs/steamworkz-migration.md)
and [Arch validation](https://github.com/yo-reign/meikyuu-zig/blob/3137046a5d0019d0274544371f43a552dcf03ef3/docs/arch-linux-validation.md)
for post-extraction evidence. Published M4's existing headless smoke passed on
macOS arm64 in Debug/ReleaseFast (local socket pairs, one private lobby and ticket
readiness/cancel submission). Arch's enabled game initialized and rendered three
frames before its RUNPATH-only fix; post-fix checks were offline/loader-only.
Neither result validates the new DX batch or optional native services.

## Historical implementation topology and lane board

The following M0–M4 records preserve their original sequence. A statement that a
gate was pending describes that historical point, not the current stage table.

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
M1 source acceptance is recorded on 2026-10-19. The parent audited the final document-inclusive package and staged tree, then committed and pushed accepted source.
The real immutable archive matched the validated package hash. A fresh URL/hash consumer built and installed successfully; neither consumer nor smoke was executed. Acceptance is not a production-readiness claim.
Required lifecycle checks use a Zig runner, not a Python dependency of `zig build test`.
Optional maintainer archive checks may use Python's standard library. They must not generate bindings.
CI will be manual and restricted to trusted, externally SDK-provisioned runners. No untrusted pull-request execution or SDK-bearing artifact/cache uploads are permitted.
Runner provisioning and CI execution remain external gates.

M2 contract planning is complete. The parent read the scout report and inspected the SDK/source contracts.
The parent recomputed all 37 planning-source hashes and verified the baseline HEAD and clean status.
That evidence establishes unchanged planning source, not API implementation or service behavior.
Ignored ZLS build-runner caches were also generated during inspection. They remain outside source inputs; no project-test or Steam execution follows from them.

M2 is multi-seam. Three isolated first-wave writers completed from accepted M1.
The parent inspected all three handoffs. The later lanes/batch writer also completed in a fresh worktree based on the inspected telemetry files.
All component and review ownership has ended. The parent accepted the integrated source and copied its exact 24-path delta into main:

| Networking lane | Exclusive files | Gate and handoff |
| --- | --- | --- |
| telemetry/text | `src/Networking.zig`, `c/networking.h`, `c/networking.cpp` | Owned telemetry and native text-sizing contracts; native Debug/ReleaseFast tests, four-target compile/link, diagnostics and exact source report |
| configuration/simulation | New `src/NetworkingConfig.zig`, `c/networking_config.h`, `c/networking_config.cpp` | Typed scalar status/inheritance and explicit partial/reset outcomes; external native/cross-target harness, diagnostics and source report |
| debug capture | New `src/NetworkingDebug.zig`, `c/networking_debug.h`, `c/networking_debug.cpp` | Bounded service-thread queue, persistent lifetime and explicit shutdown; concurrency, linkage and target checks with source report |
| lanes/batch | Three existing Networking files plus the parent-supplied `c/types.h` input | Accepted after integration, allocation/transfer/received-lane gates and independent review |
| shared integration | Parent only | Client shutdown/accessors, native/root/build/manifest/checker registration, received-lane metadata, docs, aggregate validation and independent review |

Concrete worktrees, frozen inputs, task contracts and managed report paths are recorded in the private coordinator board.
All worker checks are offline. Actual SDK configuration setters and debug registration must be substituted in fixtures.
Configuration reset clears overrides to SDK defaults. It does not restore prior explicit overrides. Partial apply and reset failures remain visible.
Debug storage is process-wide and persistent. Clearing a callback is not quiescence; delayed records have no session provenance guarantee.
The configuration/simulation writer completed its three-file handoff. The parent inspected the source, external harness, final logs and diagnostics.
Its native Debug/ReleaseFast gates passed four focused Zig tests and the inert C++ fixture. Four-target compile/link and retained native-import checks passed.
The parent recomputed the three reported hashes, all 37 frozen source hashes and all 270 SDK hashes. The index remains empty.
The telemetry handoff also passed native Debug/ReleaseFast regression graphs and four-target compile/link probes.
Its three new owning-file tests and substituted networking fixture passed. The parent inspected source, hashes, guard/linkage logs and active diagnostics.
Debug capture passed five new owning-file tests, three imported Context tests and its inert C++ fixture in Debug/ReleaseFast.
Four-target checks linked actual production sink/bridge variants, including a no-capture-use retention regression. Production consumers were not executed.
The parent inspected debug source, exact hashes, the matrix and diagnostic logs. ZLS AST diagnostics and compiler semantic checks remain distinct evidence.
No production implementation blocker was found in those handoffs. Component results alone did not complete shared registration, integrated checks or independent review.
Telemetry retained its generated cache because producer idleness was uncertain. Debug relocated its cache intact under the conditional approval.
The parent verified the retained cache inventory. No deletion, overwrite or general cleanup authority was granted.

The lanes/batch handoff preserves telemetry and fills the parent-owned incoming-lane field from the official SDK member.
Its native Debug/ReleaseFast graphs passed 34/34 steps, with 61 main passes/five skips and two repeated lifecycle controls.
Three new owning-file tests, two native fixture groups, 36 external lease controls and four-target eight-step compile/link graphs passed.
The parent read the complete increment and evidence, recomputed three changed and 34 frozen hashes, and verified all 270 SDK inputs.
Empty payloads use one SDK-owned storage byte with logical size zero and unchanged ownership callbacks.
Fixtures check this choice and allocation failure at every batch position. Live batch semantics and performance remain unvalidated.
The existing consumer install step's two runtime deployments were explicitly confirmed as allowed generated output and byte-matched by the parent.
No SDK input or source/package boundary changed. Automatic tooling caches remain retained.

The parent copied ten exact component files and current progress docs into a separate integration worktree.
Shared changes add borrowed Client accessors, diagnostic shutdown ordering, root sink retention, six-fixture registration and production consumer coverage.
A single SDK-free guard artifact reuses the existing lifecycle runner for 24 method/input selections across three lease failures.
Initial Debug checks passed 17 focused tests, both new native fixtures and all 72 guard cases. ReleaseFast consumer compilation/installation passed without execution.
Source inspection also found incomplete debug-test unwind paths. Scoped cleanup now releases test locks, joins acquired producers and releases test Context ownership.
An external negative control rejected the original paused-producer unwind and accepted the repaired cleanup before propagating the intended test error.
Production callback code is unchanged. Initial checks did not substitute for the final integrated matrix or independent review.

The integrated candidate then passed Debug, ReleaseSafe, ReleaseFast and ReleaseSmall: 117/117 steps per mode.
Each normal run had 71 passes and six deliberate skips. Two repeated lifecycle controls produced the aggregate 73/79 count; these are not 73 distinct behavioral tests.
Each graph also ran six C++ fixtures, five original fatal checks, all 72 new SDK-free guard cases and runner controls, plus consumer/probes and smoke installation.
All four ReleaseFast target graphs passed 31/31 compile/link/install steps. No destination executable ran.
Object inspection covered 77 retained artifacts, including 20 consumers and 33 SDK-free fixture/guard artifacts. Production imports and real callback sinks were present; no wrapper C++ runtime dependency was found.
Twenty changed paths passed active SDK-aware diagnostics. Configuration's integrated Zig diagnostic gate is complete.
The actual fetched archive contained 42 package files from 45 repository inputs. Its relocated ReleaseFast graph passed, and an independent archive/hash consumer built/installed and passed negative API probes.
Only that consumer's inspected pure main ran. Native-backed exports, smoke programs, Steam sessions and CI dispatch remained unexecuted. Runtime copies matched the SDK.
Three external linkage-audit attempts exposed metadata-parser/artifact-selection errors, not product link failures. Corrected checks passed; all scripts/logs remain retained.
The external package checker was also updated to copy every explicitly allowlisted consumer file, including the no-capture fixture. Normal and optimized-Python controls passed.
Independent package/build review found no issues. Runtime review found no production P0/P1 defect and identified two test-only P2 cleanup omissions.
The received-lane test now defers message release before fallible assertions. The registration test restores fake availability, shuts capture down with a live lease, then releases Context.
Twelve SDK-free injected-error controls reproduced the original cleanup failures and verified repaired error propagation in Debug/ReleaseFast.
Focused integrated tests then passed 17/17 in all four modes. The changed tests compiled/linked for all four targets without destination execution; both changed files passed active diagnostics.
All other 43 source files and production code were unchanged. A scoped re-review found both findings resolved with no new defect.
The parent reverified the fixed 45-file source and 42-member actual package, accepted M2 source, then copied the exact 24-path delta into main.
The parent completed final document-inclusive source, package, index and Git archive audits. The exact 24-path change contains 45 regular source files and 42 package members.
Commit `b41b7e4` was normally pushed. Its actual immutable package matched the audited hash, and a fresh consumer passed build/install and negative probes.
Both installed consumers retained the required production imports and callback sinks. Runtime bytes matched the SDK, with no wrapper C++ runtime dependency.
These consumers and smoke programs were not executed. All 270 SDK input files remained unchanged.
Live networking-tool behavior, non-host runtime and performance remain separate readiness gates. No M2 Steam session or CI dispatch occurred.

The user paused after M2 publication, then resumed the approved work. M3 is active against the accepted M2 source.
The parent read the completed SDK scout report, inspected SDK/web contracts and wrapper seams, and verified 45 unchanged planning inputs and all 270 SDK inputs.
Nine ignored planning-cache files are retained separately. An inspected manifest names the ZLS build runner; generated state is not project-test evidence.
The parent prepared shared optional-service ownership fields in a separate worktree. Five private Context tests passed in both Debug and ReleaseFast; active SDK-aware diagnostics and formatting/whitespace checks passed.
Utilities, Input and cloud writers completed their isolated handoffs and ended checkout ownership. The parent read all reports and checked exact source/frozen-input/SDK hashes.
Utilities added `src/Utils.zig` and `c/utils.{h,cpp}`. Input added `src/Input.zig` and `c/input.{h,cpp}`. Cloud changed only its three existing service files.
The parent inspected all component code and selected evidence without repeating completed component matrices. Input and progression source inspection is complete.
Utilities reports 15 tests per native mode, Input 12, and cloud 75 main-suite passes plus six intentional skips. These totals include imported tests, not only new cases.
Component four-target links and inert native fixtures passed. Production probes and destination executables were not run.
Input's standard predefined-macro findings were classified as false positives without suppression. One accidental empty artifact was preserved by an explicitly approved intact rename.
Input's manifest paths now use a fully qualified lexical Windows policy, without filesystem access or a new encoding restriction.
The parent prepared six shared progression schema files. Six focused value/event/request/session tests plus root discovery passed in Debug and ReleaseFast; active diagnostics were clean.
The sequential progression writer completed `src/services.zig` and `c/services.{h,cpp}` and ended ownership. The parent verified its exact increment, 42 frozen inputs, SDK270 and selected artifacts.
The parent created a separate integration checkout with exact component/schema overlays and current main progress documents. It refined enum output copying and utility test cleanup, then added shared callback, Client lifecycle, build, consumer and guard integration.
Keyboard text is copied during matching dismissal conversion. Input uses explicit manual frame updates; default Client initialization/frame behavior stays unchanged.
Write batches are owned hints, not transactions. Acquired batches must end before client close.
Leaderboard capture uses a bounded owned row/detail prefix. Matching completion and complete native row access control later download admission.
Uncertain cleanup blocks further downloads until a new session. No native release API or unbounded drain is invented.
Initial Debug/ReleaseFast checks passed 24 focused Zig tests and four fixtures, including 1228 bounded core callback cases.
All four native modes passed the offline test graph: 96 main passes and seven deliberate skips, plus two repeated lifecycle controls. The 98/105 aggregate is not 98 distinct main tests.
Each mode covered eight native fixtures, five original fatal checks, 72 networking guards, 228 platform/batch guards, runner controls and consumer/probes.
The first Debug aggregate failed only smoke compilation: its drain helper still used a const Client pointer. The one-signature repair passed a separate 5/5-step install check; unchanged Debug tests were not repeated.
The other three modes passed 352/352 aggregate test/install steps. Four ReleaseFast target graphs passed 36/36 compile/link/install steps each, without destination execution.
Inspection covered 104 artifacts: 16 production consumers, 56 SDK-free fixtures/guards and other fixtures/smoke outputs. The main consumers retained 76 required native imports; runtime copies matched SDK bytes and no wrapper C++ runtime was found.
The first external linkage assertion used two incorrect expected Utils symbol names. Correct SDK-derived names passed against unchanged binaries; both inspection attempts remain retained.
Twenty-five changed code/build/checker paths passed active SDK-aware diagnostics. The libc-only core fixture's C++ printing-style finding remains explicitly inapplicable, not suppressed in source.
Compiler-emitted constants for all four targets measured Zig Event at 28,856 bytes and private SwEvent at 28,848 bytes. No target execution or performance claim follows from these sizes.
Source inventory now contains 52 owned files. Synthetic Windows path fixtures were adjusted without changing their values or weakening the source checker.
The actual fetched package contained 49 members from 52 source inputs. Relocated ReleaseFast tests/install passed 352/352 steps.
An independent archive/hash consumer built and installed successfully. Only its inspected pure main ran; native-backed exports and smoke remained unexecuted.
Normal and optimized-Python checker controls passed. Runtime copies matched the external SDK, whose exact 270-file membership and bytes remain unchanged.
Three independent read-only reviews completed against the frozen candidate. Completion/resource ownership found no issues; distribution review found no defect and stated its evidence limits.
Utils/Input review identified one P1 forwarding discrepancy: RunFrame passed false although SDK 1.65 declares a true reserved default. No physical-input failure was demonstrated.
After all reviewers ended ownership, the parent changed only c/input.cpp: the argument, fixture expectation and a contract comment.
The corrected assertion rejects the original call with SIGABRT in Debug and ReleaseFast, without Steam linkage.
Fixed focused graphs passed 7/7 steps, 24 tests and one deliberate skipped fatal body, plus the Input fixture, in both modes.
Four-target fixture compile/link and production consumer installation passed. Twelve new artifacts retained the required native imports and SDK-free fixture boundary; installed runtimes matched the SDK.
An initial inspection incorrectly required incidental Mach-O lobby imports on ELF. Same-format baseline comparisons passed against unchanged binaries without another build.
Two pi-lens probes timed out and remain inconclusive. Separate SDK-aware production/fixture clangd LSP probes completed with no findings.
The changed actual package audit passed with 52 sources and 49 members. Unchanged complete matrices were not repeated.
A fresh scoped reviewer confirmed the original P1 is resolved, with no new issue. The parent read the report and rechecked all 52 corrected source hashes and empty index.
The parent accepted M3 source on 2026-10-20. Final document-inclusive package, indexed-source and Git archive audits passed for the exact 29-path delta.
Commit `24fcb967` was normally pushed. The actual immutable package matched the audited hash, and a fresh consumer passed build/install and negative probes.
Production imports and debug sinks remained present. Installed runtime bytes matched the external SDK, whose 270 files remained unchanged.
Neither publication consumer nor smoke was executed. The game HEAD, existing migration-document bytes and empty index remained unchanged.
No M3 native-service execution, CI dispatch or performance evidence is established.

The M4 read-only scout completed against accepted M3. The parent consumed its report and checked the SDK/source references.
The parent verified all 52 source hashes, baseline HEAD, empty index and no ignored planning paths. All 270 SDK files remained unchanged.
Official documentation supplements the header analysis. Generated search advice did not establish pending-query release or screenshot buffer retention guarantees.
The parent accepted first-wave Voice, Remote Play and Timeline contracts, including exact default arguments and explicit lifecycle policies.
A separate shared checkout adds Context voice/range state and a typed Remote Play session identity.
Five Context tests and seven type tests passed in Debug/ReleaseFast. Both changed files passed active LSP diagnostics, formatting and whitespace checks.
Three detached component writers delivered exact three-file handoffs and ended ownership.
The parent read the reports and source, then checked all new-source hashes, 52 frozen inputs per lane, SDK270, unchanged HEADs and empty indexes.
Ignored tooling caches/configuration remain inventoried and retained. These integrity checks do not replace artifact inspection or independent acceptance.
The parent prepared five Workshop/screenshot schema/state files. Each native mode passed five Context, seven type, two capability-event and one request-kind test.
Both Debug and ReleaseFast passed. Active LSP reported five clean paths without an inconclusive result.
Two further detached checkouts contain those exact validated overlays and 52 frozen inputs each.
Workshop and Screenshots delivered their three-file handoffs and ended ownership. The parent owns all shared integration.
The parent checked their exact sources, 52 frozen inputs per lane, SDK270, baseline HEADs and empty indexes.
The parent inspected all five component implementations and retained validation evidence without repeating unchanged matrices.
First-wave artifact inspection covered 58 reported paths, including 12 runtime copies. Final-wave inspection covered 49 paths, including eight runtime copies.
All 20 inspected production consumers retain required native imports. Inspected SDK-free artifacts have no Steam dependency, and no wrapper C++ runtime was found.
Production consumers remained unexecuted. Screenshots and Voice probes retain Context acquisition paths, not native initialization.
Workshop provides module-local completion/shutdown hooks. The parent must add Client call sites and native conversion during integration.
Pending queries are not released as cancellation. Global session shutdown does not establish a query-specific successful release.
Screenshot submission requires conservative borrowing through matching readiness, without an undocumented synchronous-copy promise.
Standard __cplusplus checks were classified as lint false positives, without source suppression or a workaround.
A narrowly approved test-only aborting pure-virtual entry point supports Timeline's real SDK-derived default-argument fixture. Parent inspection verified production absence, using COFF-object evidence on Windows.
Remote Play's initial ZLS timeout remains inconclusive. A corrected same-protocol probe completed with an explicit empty diagnostic response.
Workshop's final diagnostic protocol is clean and retained. Its initial raw ZLS transcript and related files were overwritten during a rerun and cannot be recovered from the retained evidence.
That retention violation remains disclosed. No retrospective cleanup approval or complete initial-protocol claim is made.
Parent integration will refine Workshop enum-output copying and correct inherited callback fixtures that populate two narrow enums outside their valid ranges.
The latter is a test-fixture defect, not a demonstrated production callback failure. Original source and evidence remain retained.
The parent integrated all ten owned callbacks, Workshop completion observation, action-free accessors and live-lease optional teardown.
Public roots, five bridge/fixture additions, package inventories and retained consumer exports are registered.
The initial Debug/ReleaseFast focused graphs passed 22/22 steps with 35 Zig tests and six native fixtures. Core covered 1771 bounded poll cases.
Both modes passed 313 new SDK-free capability guard checks across 106 method/input selections. Consumer installation and negative probes also passed without execution.
The parent then found generated cache files inside the integration checkout. The nested consumer had incorrectly rooted a cwd-relative cache path at the source build root.
The source checker correctly rejected the 353 generated inputs. No ignore rule or source boundary was weakened.
The parent corrected cache forwarding and prepared an exact 68-source successor, retaining the original checkout and generated cache in place.
External absolute-cache, external spaced-relative-cache and source-cwd consumer cases passed, with exact source membership and bytes unchanged.
The maintainer checker now exercises external-cwd relocated builds and verifies package inputs remain unchanged afterward. That full regression passed.
All four optimization modes passed 678/678 aggregate steps. Each mode passed 130 main tests, two repeated lifecycle controls, 13 native fixtures and 313 M4 guards.
Eight fatal bodies skipped in the ordinary suite. Their isolated checks ran separately, including the existing networking/platform/lifecycle guards and runner controls.
All four ReleaseFast target graphs passed 44/44 compile/link/install steps. No cross-target program executed.
A 28-path active diagnostic batch reported no language-server findings or inconclusive paths. One test-only printf recommendation was inapplicable to the libc-only fixture.
The actual source-package audit checked 68 repository inputs and 65 package members. Relocated ReleaseFast tests, independent archive consumer probes and runtime bytes passed.
Only the inspected pure archive-consumer main executed. Its retained native exports and the smoke application remained uncalled.
The parent inspected 173 artifacts, including 20 retained production consumers and 117 SDK-free fixture/guard artifacts. Primary consumers retained 121 required native imports.
Loader paths, callback sinks, Windows PDB publics, runtime byte equality and absence of a wrapper C++ runtime passed.
An inspector initially missed the COFF import-pointer prefix. Corrected metadata inspection reused unchanged binaries and checked 16 production Timeline objects without the test-only ABI shim.
No generated artifact was deleted or relocated, and the game remains unchanged.
Three fresh independent reviews found no current issue in content ownership, capability lifecycles or distribution. The parent read every report.
Post-review checks confirmed all 68 source inputs, SDK270, original incident cache, main/game state and empty indexes remained unchanged.
Ten ignored ZLS cache files appeared during a consumer-build source read. They remain retained; the original 41 ignored files were unchanged.
Review transcripts contain no explicit build/test/LSP command. The exact automatic hook was not traced, so the review is not described as producing no generated state.
Historical official-page response IDs no longer resolved. The content reviewer inspected fresh retained official pages and a labeled line-wrapped derivative instead.
The parent accepted M4 source on 2026-10-20. Final document-inclusive source/package/index audits and immutable publication checks remain next gates.
M4 source acceptance does not authorize real downloads, microphone capture, invitations, screenshots or recording changes.

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
| M1 publication | Commit `fbd5131`, exact 21-path change and 37-file tree | Staged blobs and actual Git archive matched the audited source; remote main equals local |
| M1 immutable consumer | Real published archive and fresh external consumer | Exact 34-member package/hash matched; Debug build/install and negative probes passed; adjacent runtime bytes matched; no consumer or smoke execution |
| M2 contract planning | Read-only accepted-M1 snapshot and SDK declarations | Parent inspected the report and verified all 37 source hashes, baseline HEAD and clean status; no execution inferred from planning |
| M2 native aggregate | Integrated candidate before the final two test-only fixes; all four modes | 117/117 steps per mode, 71 main passes/six skips, two repeated controls, six C++ fixtures, 72 new lease guards and existing fatal/runner checks |
| M2 target graphs | Four ReleaseFast targets | 31/31 compile/link/install steps each; no destination execution |
| M2 linkage and diagnostics | Retained artifacts and changed integrated paths | 77 artifact inspections, including 20 consumers/33 SDK-free artifacts; production imports/sinks present and no wrapper C++ runtime; 20 active SDK-aware diagnostic paths clean |
| M2 actual package consumption | 45 source files and 42 archive members | Relocated ReleaseFast graph and independent archive/hash consumer/probes passed; only inspected pure main ran; runtime bytes matched |
| M2 independent review and fixes | Runtime and package/build reviews plus two owning-file test repairs | Package review OK; both runtime P2 cleanup findings fixed; 12 injected-error controls, 17 focused tests in each mode, four-target changed-test links and active diagnostics passed; scoped re-review OK |
| M2 source acceptance | Fixed candidate and main integration | Exact fixed-source/archive audit passed; 270 SDK files unchanged; 24 reviewed paths copied into main |
| M2 publication | Commit `b41b7e4`, tree `bc753d13a1f661c196c390e76636a823127e9d71` | Final 45-file indexed/Git archive inputs matched the audited source; normal push and remote equality passed |
| M2 immutable consumer | Actual 42-member package and fresh URL/hash dependency | Exact package hash matched; Debug build/install, negative probes, imports/sink retention and runtime-byte checks passed; no consumer or smoke execution |
| M3 integrated offline graph | Candidate before the final one-file Input correction; four native modes | 96 main passes/seven skips plus two repeated controls, eight fixtures and 228 platform/batch guards per mode; Debug tests and repaired smoke install have separate successful records |
| M3 target/linkage/package gates | Integrated candidate and actual 52-source/49-member package | Four 36/36 compile/link/install graphs, 104 artifact inspections, relocated tests/install and archive/hash consumer passed; only pure consumer main ran |
| M3 independent reviews | Completion ownership, Utils/Input and distribution | One P1 reserved-argument forwarding discrepancy found; no other defect reported |
| M3 Input correction | Only c/input.cpp changed after broad review | Two negative controls, focused Debug/ReleaseFast tests, four-target fixture/consumer links, 12 artifact inspections, direct SDK-aware LSP and changed package audit passed; scoped re-review OK |
| M3 source acceptance | Corrected 52-file candidate, 2026-10-20 | All reports read and corrected hashes checked; no native/device/performance readiness claim |
| M3 publication | Commit `24fcb967`, tree `e1d35b79343ada9284a9214cfdaf7ed098712c4c` | Exact 29-path delta, 52 indexed/Git archive sources and 49 package members matched; normal push and remote equality passed |
| M3 immutable consumer | Actual package and fresh Debug URL/hash dependency | Build/install, negative probes, native imports/sinks and runtime-byte checks passed; no consumer or smoke execution |
| Game dependency migration | Published ef3a395 URL/hash and subsequent game records | Migration completed; main-based port published on steamworkz and later Arch results recorded through 3137046; game dependency remains immutable |

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

1. Inspect Git status in both repositories and read the current stage/authority sections above plus ROADMAP.md.
2. Recover the current DX mission, lane ownership, component handoffs and private evidence before launching another writer. M0–M4 extraction/publication is already complete.
3. Integrate only approved component files after their owners finish. Preserve SDK inputs, recovery worktrees, failed attempts and the game's immutable dependency.
4. Complete the pending offline/native-Linux, request-navigation, example and private-fixture gates against the exact integrated source; do not substitute historical matrices for changed-scope checks.
5. Keep normal test passes, deliberate fatal-body skips, repeated controls, compilation-only examples and actual execution distinct. No current live action or CI dispatch is authorized.
6. Obtain the fresh integrated review and document-inclusive source/archive audit before accepting the batch. Generated runtime copies belong only in external build outputs.
7. New commits/pushes and a future immutable game repin require separate approval. Never invent a package hash, use a mutable branch URL or overwrite remote work.
8. Preserve the historical evidence ledger and remaining device/account/backend/performance limits. Source acceptance is not production certification.
