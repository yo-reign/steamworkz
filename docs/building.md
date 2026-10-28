# Building, deployment and editor setup

Start with the [README](../README.md) for prerequisites, package setup and common commands.

## Focused examples

```sh
zig build examples -Dsdk=/absolute/path/to/sdk
```

This compiles/installs three short programs without executing them:

| Source | Teaches | Actions if you explicitly run it |
| --- | --- | --- |
| [`examples/client.zig`](../examples/client.zig) | Stable Client storage, diagnostic handling, copied names and frame/event pumping | Initializes Steam and makes read-only queries |
| [`examples/lobby.zig`](../examples/lobby.zig) | Request correlation, operation results, membership cleanup and uncertain outcomes | Requests one private lobby and leaves observed owned membership |
| [`examples/messages.zig`](../examples/messages.zig) | Send acceptance and received-batch `defer` cleanup | Exchanges a message over a local socket pair |

The executables are `steamworkz-example-client`, `steamworkz-example-lobby` and
`steamworkz-example-messages` in `zig-out/bin`. They require a running Steam client
and an explicitly supplied development App ID when launched outside Steam. They
never relaunch the app or create an app-id file. For an authorized manual check,
set `SteamAppId=480` and `SteamGameId=480` for that process only; use your own app
when appropriate. Building or testing does **not** launch these programs.

Their short polling loops are demonstration policy, not a scheduler to embed in
a game. Use your existing frame loop and keep all calls on the initializing
thread. The broader [`smoke.zig`](../examples/smoke.zig) is a live validation program,
not the starting application template.

There is **no JavaScript, Node, Bun, alignment generator, or separate binding
build step**. `build.zig` compiles our small C++ bridge against Valve's headers.
Packed SDK structures never cross into Zig. Our private C boundary contains
ordinary C values; aggregates cross through pointers. The bridge uses the
SDK's flat exports and inline value helpers, not guessed layouts or vtables.
It does not require an additional C++ standard library.

## Runtime deployment

Put the official runtime beside every executable that loads it: `libsteam_api.dylib`
on macOS, `libsteam_api.so` on Linux, or `steam_api64.dll` on Windows. The
[consumer build](../README.md#consume-as-a-package)'s `installRuntime` call
installs it into `zig-out/bin`; deploy it beside the game in other layouts. The
macOS library uses `@loader_path/libsteam_api.dylib`. SDK redistribution remains
subject to Valve's terms.

For a cached `b.addRunArtifact(exe)`, configure process-local runtime lookup:

```zig
const run_cmd = b.addRunArtifact(exe);
steamworkz_build.configureRun(b, run_cmd, target.result, sdk);
run_cmd.addPassthruArgs();
b.step("run", "Run the game").dependOn(&run_cmd.step);
```

This assumes the variables from the README's consumer build. Running the game
may initialize Steam.

## Linux deployment search paths

`$ORIGIN` means the directory containing the executable. Steamworkz supplies this
explicit runtime search path so the installed game can find its adjacent
`libsteam_api.so` after the game folder is moved. The SDK is needed to build the
game, not as a directory installed on players' machines.

Zig can also automatically add link-time library directories to RUNPATH,
including the developer's SDK directory. The `each_lib_rpath = false` setting
in the [consumer build](../README.md#consume-as-a-package) disables those
automatic entries while retaining explicit paths such as `$ORIGIN`. Without it,
a missing adjacent runtime can be masked by the SDK copy.

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

## Editor setup

Use matching **Zig 0.17.0 and ZLS 0.17.0**. Check the compiler selected by the
editor as well as the terminal. A stale Zig PATH entry can report valid 0.17
builtins as errors. Start the editor/language server with
`STEAMWORKS_SDK` available, or supply the library's `sdk` build option through a
local `zls.build.json`. A terminal export does not update an already-running editor.
The SDK stays external. The package build handles C translation. No manual header
copy or binding-generation command is needed.

ZLS evaluates the build graph to discover imports. If your project conditionally
adds Steamworkz, enable your project's option for the editor too. For example,
if your build defines a `steamworks-enabled` option, place this **local editor
configuration** beside your `build.zig`:

```json
{
  "build_options": [
    { "name": "steamworks-enabled", "value": "true" }
  ]
}
```

Keep the SDK path in the editor's environment rather than in versioned JSON.
Use the option name defined by your build; `steamworks-enabled` is only an example.
Omit this override when Steamworkz is always imported. Library development itself
needs only the SDK configuration described above.
See [ZLS per-build configuration](https://zigtools.org/zls/configure/per-build/).

After reloading ZLS, try `@import("steamworkz")` → `Client.init`, then a service
method and its request result. Navigation should open the dependency **revision
pinned by your project**, not an unrelated checkout. A successful SDK-free
build configuration can still omit Steamworkz entirely; unresolved Steam imports
in that mode do not mean the package is broken.

Earlier ZLS 0.16 checks found a generic-navigation limitation: lobby completion
fields resolved, but `take` hover and method navigation remained ambiguous.
Those checks are historical, not evidence about ZLS 0.17. If navigation fails,
open [`Request`](../src/requests.zig) directly. The compiler still specializes and
checks the exact completion type without caller annotations.

For the private C++ adapter, `zig build tooling -Dsdk=...` writes a gitignored
`compile_commands.json` for clangd. It is not needed to use the public Zig API;
keep generated configuration and its SDK paths out of the source package.

## Live checks

Start Steam and log in, then explicitly opt in:

```sh
zig build live-test -Dsdk=/absolute/path/to/sdk
```

This build step sets development App ID **480** for its child process only.
`-Dapp-id=YOUR_ID` selects another app you may use. It does not write an app-id file
or implement shipping/relaunch policy. The smoke program performs read-only
queries and local socket-pair traffic, creates a temporary private lobby and sets
its metadata, and requests/cancels a ticket. It does not invite friends, open
overlays, purchase, or modify cloud saves/stats.

For focused offline steps and the optional source/package checker, see
[offline validation](../tests/offline/README.md).
