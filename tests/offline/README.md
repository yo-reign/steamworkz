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
zig build test-consumer -Dsdk="$STEAMWORKS_SDK"
zig build test-compile -Dsdk="$STEAMWORKS_SDK" -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseFast
```

- `test` runs the normal Zig suite (including deterministic properties), six
  native fixtures, lifecycle runner self-tests, five original fatal checks,
  networking guards, and the independent consumer install/negative probes.
  The normal suite deliberately skips six fatal bodies. The separate lifecycle
  control repeats the passing lifecycle test (and the root discovery test).
- `test-core` exercises 948 bounded acquired-callback cases. `test-services`
  exercises five service groups with every SDK entry/accessor substituted; it
  links libc only, not Steam or the C++ standard library. Existing networking and
  lobbies fixtures also have focused aliases.
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
- `test-consumer` builds a separate dependency project with the consumer's default
  compiler/linker selection; it does not run its executable or recurse into
  dependency tests. Target, CPU model/features, optimization and explicit SDK
  propagate. Uncalled initialization/shutdown/networking exports retain real
  production paths, including a reachable ownership transition. They are not
  application recipes and must remain unexecuted. A second no-capture consumer
  forces the real C++ registration symbol to survive dead stripping, which checks
  the required Zig sink without starting capture. Both consumers are install-only.
  Positive code checks typed handles, unknown values, address round-trip and
  request completion semantics. `check-negative` in that project expects
  `Request(.overlay)` to fail with `This event does not complete an exposed
  API-call request` and implicit integer-to-`ImageHandle` to fail with
  `expected type 'types.ImageHandle', found 'comptime_int'`. Unrelated SDK/build
  failures cannot satisfy those diagnostics; positive installation must also pass.
- `test-compile` builds normal/control/property/networking tests, five original
  fatal artifacts, the SDK-free guard artifact, target runner, six fixtures and
  independent consumer/probes without
  running target programs. It invokes a host Zig build process for the consumer,
  not a target executable. It does not install/run the smoke example.
- Plain `zig build install` compiles/installs the smoke example and official
  runtime. Never run `live-test` as part of offline/package validation.

Use all four optimization modes for native aggregate gates. Use ReleaseFast
`test-compile` for `aarch64-macos`, `x86_64-macos`, `x86_64-linux-gnu` and
`x86_64-windows-gnu`; e.g. `-Dcpu=x86_64_v3` additionally exercises CPU features on
an x86_64 target. Compile/link is not non-host runtime evidence.

## Optional maintainer source/package check

Python **3.9+ standard library only**, Git, Zig 0.16.0 and the external SDK are
required. Python is never invoked by ordinary Zig build/test/consumer steps.
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
   With `--run-consumer`, runs only the pure installed consumer from an unrelated
   cwd, removing SDK/runtime search overrides; this separately tests adjacent
   runtime loading. It never runs the smoke executable.

`commands.json` records exact commands/status; separate logs contain raw compiler
and test output; `audit.json` records source SHA-256s, archive SHA-256, actual Zig
hash, members, runtime hash, host/version and whether pure execution occurred.
Checker self-controls exercise valid archives, missing/duplicate/changed/unexpected
members, links/traversal, unsafe names and content signatures.

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
