# Offline validation (Zig 0.16.0, SDK 1.65)

Obtain the official Steamworks SDK under your own agreement. Keep it outside the
checkout, read-only. Pass `-Dsdk="$STEAMWORKS_SDK"` or export `STEAMWORKS_SDK` to
its absolute directory containing `public` and `redistributable_bin`. An explicit
option takes precedence. No check downloads the SDK or requires Steam login.

## Ordinary build steps — Zig only

```sh
zig build test -Dsdk="$STEAMWORKS_SDK" -Doptimize=Debug
zig build test-core -Dsdk="$STEAMWORKS_SDK"
zig build test-services -Dsdk="$STEAMWORKS_SDK"
zig build test-lifecycle -Dsdk="$STEAMWORKS_SDK"
zig build test-properties -Dsdk="$STEAMWORKS_SDK"
zig build test-networking-tools -Dsdk="$STEAMWORKS_SDK"
zig build test-networking-config test-networking-debug -Dsdk="$STEAMWORKS_SDK"
zig build test-networking-guards -Dsdk="$STEAMWORKS_SDK"
zig build test-platform-tools test-utils test-input -Dsdk="$STEAMWORKS_SDK"
zig build test-platform-guards -Dsdk="$STEAMWORKS_SDK"
zig build test-capabilities test-voice test-remote-play test-timeline test-workshop test-screenshots -Dsdk="$STEAMWORKS_SDK"
zig build test-capability-guards -Dsdk="$STEAMWORKS_SDK"
zig build test-consumer -Dsdk="$STEAMWORKS_SDK"
zig build examples -Dsdk="$STEAMWORKS_SDK" # compile/install only; never execute
zig build test-compile -Dsdk="$STEAMWORKS_SDK" -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseFast
```

- `test` runs the normal Zig suite (including deterministic properties), thirteen
  native fixtures, lifecycle runner self-tests, five original fatal checks,
  networking/platform/capability guards, and the consumer install/negative probes.
  It also compiles/links the client, lobby and message tutorials without running
  them. `examples` installs these programs/runtime; `test-compile` includes their
  compile/link gate for cross-target checks. No offline step launches a tutorial.
  The normal suite deliberately skips eight fatal bodies. The separate lifecycle
  control repeats the passing lifecycle test (and the root discovery test).
- `test-core` first checks inert initialization admission, diagnostic copying,
  exactly-once rollback/dispatch ordering and optional ticket-recipient forwarding.
  Owning Client tests additionally verify reset diagnostics, admission ownership,
  borrowed ticket prefixes and cancellation of malformed accepted ticket lengths.
  It also exercises 1771 bounded acquired-callback cases, including correlated
  secondary capture, Workshop completion retrieval and owned callback arrays.
  Tests invalidate native storage before checking the owned copies. Native enum
  fixtures use initialized official objects and representable unnamed values.
  Its uncalled production paths link Steam; its executed source substitutes the
  new keyboard/leaderboard getters. `test-services` exercises legacy services and
  new cloud/progression calls with every SDK entry/accessor substituted. It links
  libc only, not Steam or the C++ standard library. Existing networking and lobbies
  fixtures also have focused aliases.
- `test-lifecycle` uses private generated `steamworkz_test_options` execution
  selection; only distinct filtered fatal artifacts enable it. The Zig runner
  checks markers, exact panic diagnostics, abnormal exit, bounded output and
  total deadlines. It is for these owned non-descendant-spawning tests, not a
  hostile process-tree sandbox. Runtime lookup is passed to runner and children.
- `test-properties` filters the normal, nonfatal Zig tests by `property `.
- `test-networking-tools` filters telemetry/text, configuration/simulation,
  diagnostic capture, lanes/batch and the Client shutdown-ordering test.
  `test-networking-config` and `test-networking-debug` link their C++ fixtures
  without Steam or a C++ runtime library; all native entry points are substituted.
- `test-networking-guards` reuses the same bounded Zig runner. One SDK-free test
  executable serves 24 method/input selections across closed, stale and foreign
  leases (72 checks per mode). Private environment variables select each child
  case. Owning-file helpers stay private. Bridge stubs abort if reached, so a
  broken guard cannot call Steam or pass as the required lease panic. Normal
  return/local validation failure also cannot pass. No second process runner or
  Python dependency was added.
- `test-platform-tools` filters Utils, Input, cloud, progression, event ownership
  and Client correlation/shutdown tests. Utils/Input Zig tests inject native calls;
  `test-utils` and `test-input` also substitute every native call/accessor and link
  without Steam. No manifest/glyph files, UI, vibration, account or network action
  runs in these tests. Synthetic Windows path tests establish lexical behavior,
  not encoding acceptance, file existence or native manifest loading.
- `test-platform-guards` uses one SDK-free artifact and the existing bounded runner:
  73 facade/owner method-input selections × three lease failures, four Client
  methods × closed/foreign failures, plus acquired-cloud-batch close refusal =
  228 checks per mode. Client itself owns the current Context, not an old captured
  generation. Empty, invalid, pending/failed-state and consumed-owner paths cannot
  bypass the lease. Fake calls or aborting stubs cannot satisfy the expected panic.
- `test-capabilities` filters Voice, Remote Play, Timeline, Workshop, Screenshots,
  owned events and Client observation/teardown tests. Its native fixture aliases
  substitute every exercised SDK method/accessor and link without Steam or a C++
  runtime. Timeline's default-argument fixture derives from the official interface.
  Its aborting pure-virtual entry point exists only under SW_TIMELINE_TEST.
  No microphone, invitation, screenshot, hook, recording, download or content-file
  operation occurs. Query rows and screenshot input have separate lifetimes.
  Inert tests validate wrapper policy, not an undocumented SDK retention promise.
- `test-capability-guards` uses one SDK-free artifact and the existing runner:
  101 facade/owner/hook method-input selections × three lease failures, plus five
  Client accessors × closed/foreign failures = 313 checks per mode. Empty, invalid,
  repeated, consumed, pending, poisoned and capacity/exhaustion paths are covered.
  Client owns the current Context, not a captured old generation. Fake native
  calls, aborting stubs and ordinary errors cannot satisfy the expected panic.
- `test-consumer` builds a separate dependency project using LLVM/LLD on Linux
  (other platforms retain default selection); it does not run its executable or recurse into
  dependency tests. Target, CPU model/features, optimization and explicit SDK
  propagate. Uncalled initialization/shutdown/networking/platform/capability
  exports retain real production paths, including reachable ownership transitions,
  callback conversion and separate post-completion Workshop row reads. They are not
  application recipes and must remain unexecuted. A second no-capture consumer
  forces the real C++ registration symbol to survive dead stripping, which checks
  the required Zig sink without starting capture. Both consumers are install-only.
  Linux Steam-linked artifacts disable automatic per-library RPATHs, preserving
  the explicit `$ORIGIN` path. Consumers with other nonstandard dynamic libraries
  must supply their own explicit deployment paths, as in the published recipe.
  Cached offline runs still receive process-local lookup through `configureRun`.
  Positive code checks typed handles, unknown values, address round-trip and
  request completion semantics. `check-negative` in that project expects
  `Request(.overlay)` to fail with `This event does not complete an exposed
  API-call request` and implicit integer-to-`ImageHandle` to fail with
  `expected type 'types.ImageHandle', found 'comptime_int'`. Unrelated SDK/build
  failures cannot satisfy those diagnostics; positive installation must also pass.
- `test-compile` builds normal/control/property/networking/platform/capability
  tests, five original fatal artifacts, three SDK-free guard artifacts, target
  runner, thirteen fixtures and independent consumer/probes without
  running target programs. It invokes a host Zig build process for the consumer,
  not a target executable. It does not install/run the smoke example.
- Plain `zig build install` compiles/installs the smoke example and official
  runtime. Never run `live-test` as part of offline/package validation.

Use `-j2` to bound each build invocation. Nested consumer builds and the optional
maintainer checker also limit each invocation to two jobs.
Use all four optimization modes for native aggregate gates. Use ReleaseFast
`test-compile` for `aarch64-macos`, `x86_64-macos`, `x86_64-linux-gnu` and
`x86_64-windows-gnu`; e.g. `-Dcpu=x86_64_v3` additionally exercises CPU features on
an x86_64 target. Compile/link is not non-host runtime evidence. Inline owned leaderboard storage
also enlarges all events. Compiler-emitted constants for the four targets measure
Zig Event at 28,856 bytes and private C SwEvent at 28,848 bytes. This is not a
runtime performance measurement. Physical Input, keyboard/overlay, native cloud,
leaderboard/global-percentage behavior and backend configuration need separate
authorized execution. Workshop, Voice, Remote Play, screenshot and Timeline native
behavior also require separate device/app setup and side-effect authority.

## Optional maintainer source/package check

Python **3.9+ standard library only**, Git, Zig 0.16.0 and the external SDK are
required. On Linux, deployment checks additionally require a native x86_64 glibc
host and binutils `readelf` on PATH. They invoke the ELF interpreter's `--list`
mode with its cache disabled, not the application entry point or library
initializers. Python is never invoked by ordinary Zig build/test/consumer steps.
Inspect `tests/consumer/main.zig` before opting into execution: its main uses only
pure value APIs; all retained native-backed exports must remain uncalled.

```sh
python3 tests/offline/check.py --self-test
python3 tests/offline/check.py --sdk "$STEAMWORKS_SDK" \
  --evidence "$PRIVATE_EVIDENCE/new-run" --run-consumer
```

The evidence directory must be new and disjoint from both source and SDK. It is
retained on failure, mode 0700, with private files. Do not publish it. The checker:

1. Inventories current tracked plus nonignored untracked sources against an exact
   owned-file allowlist. This includes uncommitted candidate changes, not stale
   HEAD bytes. Ignored caches/config/SDK paths are never copied. New owned files
   require deliberate inventory and manifest updates. Git and repository-only
   CI/policy inputs are omitted from the actual Zig package by its manifest.
2. Copies regular UTF-8 source only into a fresh snapshot. It rejects symlinks,
   NUL/binary inputs, known private-key/token signatures and machine-path forms.
3. Runs `zig fetch` from an external driver cwd with an external fresh cache,
   against the absolute snapshot. No cache, install or `zig-pkg` output is created
   in the input snapshot (checked for mutation afterward).
4. Audits the **actual fetched tar.gz**: exact required file membership and bytes,
   hash prefix, no absolute/traversal/backslash/drive-ambiguous paths, links,
   special files, duplicate files or unexpected directories. Budgets: 128 members,
   1 MiB per file, 8 MiB archive/expanded/source totals. Expected sources exclude
   SDK/runtimes/binaries, caches, reports, credentials and local editor configs.
   The checker writes only validated member bytes, not `extractall`.
5. Runs relocated ReleaseFast aggregate tests plus smoke compile/install with
   fresh external caches. Separately builds an external consumer using a local
   archive URL and the **computed Zig package hash**, with another fresh cache.
   Only the in-package consumer fixture uses a sibling path dependency.
6. Compares both generated installed runtimes byte-for-byte with the supplied SDK.
   On Linux, checks smoke, the three tutorials and both consumers with `readelf`: `libsteam_api.so`
   must remain a dependency and `$ORIGIN` must be the only RUNPATH/RPATH entry.
   Loader-only checks must resolve the adjacent runtime both installed and in a
   fresh relocated copy. Another executable-only copy must fail specifically for
   missing `libsteam_api.so`. SDK inputs and original installs are never moved or
   hidden. Loader checks remove all `LD_*` overrides and disable the loader cache;
   a globally installed Steam runtime that masks the missing copy fails the check.
   With `--run-consumer`, runs only the pure installed consumer from an unrelated
   cwd, removing SDK/runtime search overrides; this separately tests adjacent
   runtime loading. It never runs the smoke executable.

`commands.json` records exact commands/status; separate logs contain raw compiler
and test output; `audit.json` records source SHA-256s, archive SHA-256, actual Zig
hash, members, runtime hash, host/version and whether pure execution occurred.
Checker self-controls exercise valid archives, missing/duplicate/changed/unexpected
members, links/traversal, unsafe names and content signatures, plus missing Steam
linkage, path-qualified dependencies, leaked/empty search paths and invalid ELF
interpreter metadata. Nonzero loader status in a `*-missing.log` is the expected
negative control, not a failed build.

For a focused Linux deployment check of existing trusted owned install prefixes
(no builds, archive audit, or application execution):

```sh
python3 tests/offline/check.py --sdk "$STEAMWORKS_SDK" \
  --evidence "$PRIVATE_EVIDENCE/new-deployment-run" \
  --linux-install "$SMOKE_PREFIX" --linux-install "$CONSUMER_PREFIX"
```

Each prefix must contain at least one of the installed smoke/tutorial/consumer executables
under `bin`. The same source allowlist audit still runs; `deployment.json` records
source hashes and checked artifacts. Use separate Debug and ReleaseFast installs.
Do not use this focused mode as a substitute for the full source/package check.

Limits: this is a bounded audit of trusted owned source, **not** a general archive
sandbox, arbitrary-code sandbox, comprehensive credential scanner or proof of
copyright provenance. Reviewed source can execute build code. Signature checks do
not detect every secret or SDK snippet hidden in text. SDK authenticity/version
and source review remain maintainer responsibilities. No Steam session, service,
account, hardware or network behavior is established. Non-host runtime checks and
independent acceptance review remain separate gates.

## Prepared SDK-private CI (not execution evidence)

`.github/workflows/offline.yml` is manual `workflow_dispatch` only, restricted to
`yo-reign/steamworkz` on `refs/heads/main`. No PR, push, schedule or untrusted-branch
trigger may be added to SDK-bearing runners. Protect main and restrict workflow
changes/dispatch to trusted maintainers before provisioning or execution.

The user must supply an isolated trusted self-hosted **macOS ARM64** runner with
labels `steamworkz-sdk-165` and `zig-0-16-0` (plus the standard self-hosted/macOS/ARM64
labels), Zig 0.16.0, Python 3.9+, Git, Bash, standard macOS process tools, and the
external read-only SDK. Set `STEAMWORKS_SDK` and `STEAMWORKZ_PRIVATE_ROOT` in the
runner environment; the latter is a precreated private runner-local directory
outside the checkout and SDK, not a hosted artifact area. Before creating a work
directory, the workflow rejects missing, relative or overlapping SDK/private-root
paths, including overlaps through symlinks. The runner must permit
child termination/core-dump policy appropriate for intentional panic tests and
have enough local disk for retained caches/logs. Restrict runner access/groups;
never share this runner with untrusted repositories/jobs. Keep crash reports
private as well. Runtime lookup and compiler diagnostics can reveal SDK snippets
and machine paths.

The workflow fetches only the exact trusted dispatched source revision over public
HTTPS with credential helpers disabled; no third-party checkout action or persisted
credential is needed. All raw output goes to mode-private runner-local logs.
Only fixed sanitized status/version text reaches hosted logs. There are no cache
or artifact uploads, SDK provisioning/download, or automatic evidence cleanup.
Authorized maintainers inspect failures locally and manage retention privately.

Workflow preparation is not a CI pass. Runner provisioning, repository protections,
separate dispatch authority, actual execution and independent parent acceptance
remain external gates. Generated runtime/install/cache evidence must never enter
Git or package archives.
