# Steamworkz

Steamworks **SDK 1.65** for **Zig 0.17.0**. Game code uses Zig APIs; Steamworkz
builds the private C++ bridge against your own official SDK. It covers selected
Steamworks features, not the entire SDK.

- **Multiplayer:** networking sockets, lobbies, authentication, and traffic diagnostics.
- **Game services:** friends, apps/DLC, stats, achievements, leaderboards, and cloud saves.
- **Platform features:** Steam Input, text utilities, voice, Remote Play, Workshop
  downloads, screenshots, and Timeline markers.

Supported targets: macOS arm64/x86_64, Linux x86_64 with glibc, and Windows
x86_64 (GNU cross-compilation verified). See the [API index](docs/api.md) for
entry points and Valve references.

## Requirements

- Zig 0.17.0 and the official Steamworks SDK 1.65, obtained under your own
  Steamworks agreement. The SDK is **not included** or downloaded by this package.
- An extracted, external **`sdk` directory** containing `public` and
  `redistributable_bin`. Do not copy or symlink it into this repository.
- A running, logged-in Steam client and an appropriate App ID to run your game;
  neither is needed for offline tests.

Set the SDK path in your shell, or pass `-Dsdk=/absolute/path/to/sdk` to each
build. The explicit option takes precedence over `STEAMWORKS_SDK`.

```sh
export STEAMWORKS_SDK=/absolute/path/to/sdk
```

## Consume as a package

From your game project (with a `build.zig.zon`), fetch an immutable revision:

```sh
zig fetch --save=steamworkz https://github.com/yo-reign/steamworkz/archive/6817b395d1d5911f8331179fa0cdbcbff6dddc3a.tar.gz
```

This is a Zig 0.17-compatible revision, not a mutable branch. Select a different
published commit when upgrading. Zig records the URL and calculated hash in
`build.zig.zon`; review and commit that pin rather than guessing a hash.

A minimal `build.zig` follows. Adapt the executable name and source path to your
game; if you already have a build, integrate the dependency and runtime steps
into it instead of replacing it.

```zig
const std = @import("std");
const steamworkz_build = @import("steamworkz");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const sdk = b.pathResolve(&.{
        b.fmt("{f}", .{b.root}),
        b.option([]const u8, "sdk", "Official Steamworks SDK directory") orelse
            b.graph.environ_map.get("STEAMWORKS_SDK") orelse
            @panic("Pass -Dsdk=/absolute/path/to/sdk or set STEAMWORKS_SDK"),
    });
    const steamworkz = b.dependency("steamworkz", .{
        .target = target,
        .optimize = optimize,
        .sdk = sdk,
    });

    const use_llvm: ?bool = if (target.result.os.tag == .linux) true else null;
    const exe = b.addExecutable(.{
        .name = "my-game",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = use_llvm,
        .use_lld = use_llvm,
    });
    exe.root_module.addImport("steamworkz", steamworkz.module("steamworkz"));
    if (target.result.os.tag == .linux) exe.each_lib_rpath = false;
    b.installArtifact(exe);
    steamworkz_build.installRuntime(b, target.result, sdk);
}
```

```sh
zig build                      # uses STEAMWORKS_SDK
zig build -Dsdk=/absolute/path/to/sdk  # or supply it explicitly
```

The build installs the official runtime beside the executable in `zig-out/bin`.
Deploy that runtime beside **each executable** that loads it. On Linux, apply the
LLVM/LLD and `each_lib_rpath` settings above to every Steam-linked artifact; the
latter prevents a developer SDK path from leaking into its runtime search path.
For cached run steps, other deployment layouts, and Linux inspection, see
[building and deployment](docs/building.md#runtime-deployment).

## Client and event loop

A minimal `src/main.zig` initializes Steam and pumps one frame. In a game, run
the pump and drain the events **every frame**, including menus and pauses.

```zig
const std = @import("std");
const steam = @import("steamworkz");

pub fn main() !void {
    var client: steam.Client = undefined;
    var diagnostic: steam.Client.Diagnostic = .{};
    client.init(&diagnostic) catch |err| {
        std.debug.print("Steam initialization failed: {t}: {s}\n", .{ err, diagnostic.text() });
        return err;
    };
    defer client.deinit();

    client.runFrame();
    while (client.nextEvent()) |event| {
        switch (event.payload) {
            .overlay => |overlay| std.debug.print("Overlay active: {}\n", .{overlay.active}),
            else => {},
        }
    }
}
```

To try this outside Steam, start and log in to Steam first. For a development
check on a Unix-like shell, run `SteamAppId=480 SteamGameId=480 ./zig-out/bin/my-game`,
or use your own App ID. This sets the ID for that process only; shipping and
relaunch policy are separate. Running the program **initializes Steam**.

Key contracts:

- Initialize one `Client` in stable storage; never move or copy it while live.
  Use its services and tear it down on the initializing thread. Initialize before
  the graphics window if you need overlay support.
- Release owned resources (such as message batches, connections, lobbies, tickets,
  and cloud write batches) before `client.deinit()`. Some input, such as pending
  [screenshot buffers](docs/services.md#screenshots-and-asynchronous-input-borrowing),
  can outlive the client. Service facades are borrowed; SDK-backed text generally
  must be copied before another Steam call.
- A returned `Request` means a call was accepted, not that it succeeded. Match
  completions with `request.take(&event)`, then check the operation's result.
  Dropping a request does not cancel native work.

See [lifecycle and requests](docs/lifecycle.md), [networking and lobbies](docs/networking.md),
and [services and optional capabilities](docs/services.md) for ownership, errors,
and feature-specific teardown rules.

## Examples and development commands

The focused examples are compiled and installed by `zig build examples`, **not
executed**. Running them initializes Steam:

| Example | Demonstrates | Additional action when run |
| --- | --- | --- |
| [`client.zig`](examples/client.zig) | Initialization, copied text, event loop | Read-only queries |
| [`lobby.zig`](examples/lobby.zig) | Requests and membership cleanup | Creates and leaves a private lobby |
| [`messages.zig`](examples/messages.zig) | Send and receive ownership | Exchanges messages on a local socket pair |

To work on Steamworkz itself, clone the repository, set `STEAMWORKS_SDK` as above,
and run from the checkout:

```sh
git clone https://github.com/yo-reign/steamworkz.git
cd steamworkz
zig build test                              # offline tests and fixtures
zig build examples                          # compile/install examples only
zig build install                           # install smoke program and runtime
zig build test-compile -Dtarget=x86_64-windows-gnu  # cross-compile only
zig build tooling                           # local C++ editor configuration
```

`zig build test` requires the SDK but does not initialize Steam or perform
account or service actions. Zig may fetch pinned build dependencies on the first
build. Use `-Doptimize=debug`, `safe`, `fast`, or `small`;
see [offline validation](tests/offline/README.md) for focused tests and package
checks. The separate `zig build live-test` **does** initialize Steam, exchange
local messages, create a temporary private lobby, and request/cancel a ticket.
Run it only when those actions are authorized; see [live checks](docs/building.md#live-checks).

## Editor setup

Use matching Zig 0.17.0 and ZLS 0.17.0. Start the editor with `STEAMWORKS_SDK`
set, and enable your project's Steamworkz build option if it is optional. Do not
commit machine-specific SDK paths. See [editor setup](docs/building.md#editor-setup)
for ZLS configuration and troubleshooting.

## Documentation and status

- [API index](docs/api.md) and [public Zig declarations](src/root.zig) — entry
  points, ownership contracts, and links to Valve's references.
- [Building and deployment](docs/building.md) — runtime lookup, examples,
  editor setup, and explicit live checks.
- [Migration notes](docs/migration.md) — Zig 0.17 and earlier API changes.
- [Development records](docs/development/README.md) — the [roadmap](docs/development/ROADMAP.md)
  and [checkpoint](docs/development/CHECKPOINT.md), including scope, evidence,
  readiness, and remaining validation gates.

Offline tests and compile/link checks do not establish live-service, hardware,
other-platform runtime, or performance readiness. Steamworkz does not implement
game replication, authority, prediction, or save-conflict policy.

## License

The wrapper is [MIT licensed](LICENSE). Valve's Steamworks SDK is separately
licensed and is not included in this repository or its source package.
