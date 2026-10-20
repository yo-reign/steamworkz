const std = @import("std");

const sources: []const []const u8 = &.{ "c/core.cpp", "c/networking.cpp", "c/networking_config.cpp", "c/networking_debug.cpp", "c/lobbies.cpp", "c/services.cpp" };
const cpp_flags: []const []const u8 = &.{ "-std=c++17", "-fno-exceptions", "-fno-rtti", "-Wall", "-Wextra", "-Werror" };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const sdk = b.option([]const u8, "sdk", "Official Steamworks SDK directory (overrides STEAMWORKS_SDK)") orelse
        b.graph.environ_map.get("STEAMWORKS_SDK") orelse
        @panic("Steamworkz requires the external Steamworks SDK 1.65: pass -Dsdk=/absolute/path/to/sdk or set STEAMWORKS_SDK to the directory containing public and redistributable_bin");
    const sdk_path = b.pathFromRoot(sdk);
    const runtime = runtimeLibrary(b, target.result, sdk_path);
    const use_llvm: ?bool = if (target.result.os.tag == .linux) true else null;
    addToolingStep(b, sdk_path);

    const module = b.addModule("steamworkz", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    configureModule(b, module, sdk_path, runtime);
    module.addCSourceFiles(.{ .files = sources, .flags = cpp_flags });

    const normal_options = b.addOptions();
    normal_options.addOption(bool, "fatal_lifecycle", false);
    module.addOptions("steamworkz_test_options", normal_options);

    const tests = b.addTest(.{ .name = "steamworkz-tests", .root_module = module, .use_llvm = use_llvm, .use_lld = use_llvm });
    const compile_tests = b.step("test-compile", "Compile and link all offline tests without running them");
    compile_tests.dependOn(&tests.step);
    const run_tests = b.addRunArtifact(tests);
    configureRun(b, run_tests, target.result, sdk_path);
    const test_step = b.step("test", "Run offline Zig tests and native ABI/callback fixtures (no Steam login)");
    test_step.dependOn(&run_tests.step);
    const consumer_tests = addConsumerTests(b, target, optimize, sdk_path);
    compile_tests.dependOn(consumer_tests);
    test_step.dependOn(consumer_tests);

    const lifecycle = b.step("test-lifecycle", "Run lifecycle control, runner self-test and five public fatal guards");
    test_step.dependOn(lifecycle);
    const runner = b.addExecutable(.{
        .name = "steamworkz-lifecycle-runner",
        .root_module = b.createModule(.{ .root_source_file = b.path("tests/lifecycle_runner.zig"), .target = target, .optimize = optimize, .link_libc = true }),
        .use_llvm = use_llvm,
        .use_lld = use_llvm,
    });
    compile_tests.dependOn(&runner.step);
    const self_test = b.addRunArtifact(runner);
    self_test.addArg("self-test");
    configureRun(b, self_test, target.result, sdk_path);
    lifecycle.dependOn(&self_test.step);
    for ([_][]const u8{ "wrong-thread", "moved-client", "stale-lease", "outstanding-message", "released-message" }) |name| {
        const fatal_module = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize, .link_libc = true });
        configureModule(b, fatal_module, sdk_path, runtime);
        fatal_module.addCSourceFiles(.{ .files = sources, .flags = cpp_flags });
        const options = b.addOptions();
        options.addOption(bool, "fatal_lifecycle", true);
        fatal_module.addOptions("steamworkz_test_options", options);
        const fatal = b.addTest(.{ .name = b.fmt("fatal-{s}", .{name}), .root_module = fatal_module, .filters = &.{b.fmt("lifecycle fatal {s}", .{name})}, .use_llvm = use_llvm, .use_lld = use_llvm });
        compile_tests.dependOn(&fatal.step);
        // The runner launches these directly, without the build test-server protocol.
        const check = b.addRunArtifact(runner);
        check.addArgs(&.{ "check", name });
        check.addArtifactArg(fatal);
        configureRun(b, check, target.result, sdk_path);
        lifecycle.dependOn(&check.step);
    }
    test_step.dependOn(addNetworkingGuards(b, target, optimize, runner, compile_tests));
    const control = b.addTest(.{ .name = "lifecycle-control", .root_module = module, .filters = &.{"lifecycle control "}, .use_llvm = use_llvm, .use_lld = use_llvm });
    const control_run = b.addRunArtifact(control);
    configureRun(b, control_run, target.result, sdk_path);
    lifecycle.dependOn(&control_run.step);
    compile_tests.dependOn(&control.step);
    const properties = b.addTest(.{ .name = "properties", .root_module = module, .filters = &.{"property "}, .use_llvm = use_llvm, .use_lld = use_llvm });
    const properties_run = b.addRunArtifact(properties);
    configureRun(b, properties_run, target.result, sdk_path);
    b.step("test-properties", "Run deterministic bounded Zig properties").dependOn(&properties_run.step);
    compile_tests.dependOn(&properties.step);
    // Properties already run in the ordinary unfiltered suite.

    const networking_tests = b.addTest(.{
        .name = "networking-tools",
        .root_module = module,
        .filters = &.{ "realTimeStatus ", "detailedStatus ", "NetworkingConfig ", "NetworkingDebug ", "configureLanes ", "sendBatch ", "Metadata copies ", "client shutdown disables diagnostics " },
        .use_llvm = use_llvm,
        .use_lld = use_llvm,
    });
    const networking_run = b.addRunArtifact(networking_tests);
    configureRun(b, networking_run, target.result, sdk_path);
    b.step("test-networking-tools", "Run offline networking tooling and traffic-control Zig tests").dependOn(&networking_run.step);
    compile_tests.dependOn(&networking_tests.step);
    // These tests already run in the ordinary unfiltered suite.

    const fixtures = [_]struct { name: []const u8, source: []const u8, define: []const u8, sdk_link: bool = true }{
        .{ .name = "core", .source = "c/core.cpp", .define = "SW_CORE_TEST" },
        .{ .name = "networking", .source = "c/networking.cpp", .define = "SW_NETWORKING_TEST" },
        .{ .name = "networking-config", .source = "c/networking_config.cpp", .define = "SW_NETWORKING_CONFIG_TEST", .sdk_link = false },
        .{ .name = "networking-debug", .source = "c/networking_debug.cpp", .define = "SW_NETWORKING_DEBUG_TEST", .sdk_link = false },
        .{ .name = "lobbies", .source = "c/lobbies.cpp", .define = "SW_LOBBIES_TEST" },
        .{ .name = "services", .source = "c/services.cpp", .define = "SW_SERVICES_TEST", .sdk_link = false },
    };
    for (fixtures) |fixture| {
        const fixture_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
        // Fully substituted fixtures must fail to link if a native call escapes.
        if (!fixture.sdk_link)
            configureIncludes(b, fixture_module, sdk_path)
        else
            configureModule(b, fixture_module, sdk_path, runtime);
        fixture_module.addCMacro(fixture.define, "1");
        fixture_module.addCSourceFile(.{ .file = b.path(fixture.source), .flags = cpp_flags });
        const executable = b.addExecutable(.{
            .name = b.fmt("steamworkz-{s}-fixtures", .{fixture.name}),
            .root_module = fixture_module,
            .use_llvm = use_llvm,
            .use_lld = use_llvm,
        });
        compile_tests.dependOn(&executable.step);
        const run = b.addRunArtifact(executable);
        configureRun(b, run, target.result, sdk_path);
        test_step.dependOn(&run.step);
        b.step(b.fmt("test-{s}", .{fixture.name}), b.fmt("Run offline {s} native fixtures", .{fixture.name})).dependOn(&run.step);
    }

    const smoke_module = b.createModule(.{ .root_source_file = b.path("examples/smoke.zig"), .target = target, .optimize = optimize });
    smoke_module.addImport("steamworkz", module);
    const smoke = b.addExecutable(.{ .name = "steamworkz-smoke", .root_module = smoke_module, .use_llvm = use_llvm, .use_lld = use_llvm });
    b.installArtifact(smoke);
    installRuntime(b, target.result, sdk_path);
    const live_run = b.addRunArtifact(smoke);
    configureRun(b, live_run, target.result, sdk_path);
    const app = b.option(u32, "app-id", "Development App ID used only by the explicit live-test step") orelse 480;
    live_run.setEnvironmentVariable("SteamAppId", b.fmt("{d}", .{app}));
    live_run.setEnvironmentVariable("SteamGameId", b.fmt("{d}", .{app}));
    if (b.args) |args| live_run.addArgs(args);
    b.step("live-test", "Explicit opt-in: run bounded tests with a running Steam client").dependOn(&live_run.step);
}

fn addNetworkingGuards(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, runner: *std.Build.Step.Compile, compile_tests: *std.Build.Step) *std.Build.Step {
    const use_llvm: ?bool = if (target.result.os.tag == .linux) true else null;
    const module = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize, .link_libc = true });
    module.addIncludePath(b.path("c"));
    module.addCSourceFile(.{ .file = b.path("tests/networking_guards.cpp"), .flags = cpp_flags });
    const options = b.addOptions();
    options.addOption(bool, "fatal_lifecycle", true);
    module.addOptions("steamworkz_test_options", options);
    // One SDK-free executable serves every case. A broken guard must never reach
    // Steam: bridge stubs abort, which cannot match the required lease diagnostic.
    const executable = b.addTest(.{
        .name = "networking-guards",
        .root_module = module,
        .filters = &.{"networking fatal guard"},
        .use_llvm = use_llvm,
        .use_lld = use_llvm,
    });
    compile_tests.dependOn(&executable.step);
    const step = b.step("test-networking-guards", "Check networking leases before empty, invalid and native paths without Steam linkage");
    const methods = [_][]const u8{
        "telemetry_empty",     "telemetry_excess",   "detailed_empty",
        "lanes_empty",         "lanes_weight",       "lanes_native",
        "batch_empty",         "batch_lane",         "batch_native",
        "config_set_invalid",  "config_set_native",  "config_clear_invalid",
        "config_clear_native", "config_get_invalid", "config_get_native",
        "simulation_invalid",  "simulation_native",  "simulation_reset",
        "debug_start_invalid", "debug_start_native", "debug_drain_empty",
        "debug_drain_storage", "debug_stop",         "debug_shutdown",
    };
    for ([_]struct { lease: []const u8, diagnostic: []const u8 }{
        .{ .lease = "closed", .diagnostic = "moved-client" },
        .{ .lease = "stale", .diagnostic = "stale-lease" },
        .{ .lease = "foreign", .diagnostic = "wrong-thread" },
    }) |case| {
        for (methods) |method| {
            const check = b.addRunArtifact(runner);
            check.step.name = b.fmt("networking guard {s}/{s}", .{ case.lease, method });
            check.addArgs(&.{ "check", case.diagnostic });
            check.addArtifactArg(executable);
            check.setEnvironmentVariable("STEAMWORKZ_GUARD_LEASE", case.lease);
            check.setEnvironmentVariable("STEAMWORKZ_GUARD_METHOD", method);
            step.dependOn(&check.step);
        }
    }
    return step;
}

fn addConsumerTests(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, sdk: []const u8) *std.Build.Step {
    // Build a separate project through the public dependency recipe. Only
    // installation and compile-fail probes run, never package tests or target binaries.
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "install", "check-negative", "--build-file" });
    run.addFileArg(b.path("tests/consumer/build.zig"));
    run.addArgs(&.{ "--cache-dir", b.pathFromRoot(b.cache_root.path orelse ".") });
    run.addArgs(&.{ "--global-cache-dir", b.graph.global_cache_root.path orelse "." });
    run.addArgs(&.{
        b.fmt("-Dtarget={s}", .{target.query.zigTriple(b.allocator) catch @panic("OOM")}),
        b.fmt("-Dcpu={s}", .{target.query.serializeCpuAlloc(b.allocator) catch @panic("OOM")}),
        b.fmt("-Doptimize={s}", .{@tagName(optimize)}),
        b.fmt("-Dsdk={s}", .{sdk}),
        "--prefix",
    });
    _ = run.addOutputDirectoryArg("consumer-install");
    // Let the nested Zig build track all package/SDK inputs, rather than caching
    // this command solely by its arguments and the fixture's build.zig.
    run.has_side_effects = true;
    const step = b.step("test-consumer", "Compile/link and install an external consumer without running it");
    step.dependOn(&run.step);
    return step;
}

fn addToolingStep(b: *std.Build, sdk: []const u8) void {
    const Entry = struct { directory: []const u8, file: []const u8, arguments: []const []const u8 };
    var entries: [sources.len]Entry = undefined;
    for (sources, &entries) |source, *entry| {
        const file = b.pathFromRoot(source);
        entry.* = .{
            .directory = b.pathFromRoot("."),
            .file = file,
            .arguments = b.allocator.dupe([]const u8, &.{
                "clang++", "-std=c++17",        "-fno-exceptions", "-fno-rtti",
                "-I",      b.pathFromRoot("c"), "-isystem",        b.pathJoin(&.{ sdk, "public" }),
                "-c",      file,
            }) catch @panic("OOM"),
        };
    }
    const json = std.json.Stringify.valueAlloc(b.allocator, entries, .{ .whitespace = .indent_2 }) catch @panic("OOM");
    const update = b.addUpdateSourceFiles();
    update.addBytesToSource(json, "compile_commands.json");
    b.step("tooling", "Generate local C++ editor configuration (not source bindings)").dependOn(&update.step);
}

const Runtime = struct { directory: []const u8, filename: []const u8, library: []const u8 };

fn runtimeLibrary(b: *std.Build, target: std.Target, sdk: []const u8) Runtime {
    if (target.cpu.arch != .x86_64 and !(target.os.tag == .macos and target.cpu.arch == .aarch64))
        @panic("Steamworks supports macOS arm64/x86_64 and Windows/Linux x86_64 in this package");
    return switch (target.os.tag) {
        .macos => .{ .directory = b.pathJoin(&.{ sdk, "redistributable_bin", "osx" }), .filename = "libsteam_api.dylib", .library = "steam_api" },
        .linux => if (target.abi.isGnu()) .{ .directory = b.pathJoin(&.{ sdk, "redistributable_bin", "linux64" }), .filename = "libsteam_api.so", .library = "steam_api" } else @panic("The supplied Linux Steamworks library requires a glibc target"),
        .windows => .{ .directory = b.pathJoin(&.{ sdk, "redistributable_bin", "win64" }), .filename = "steam_api64.dll", .library = "steam_api64" },
        else => @panic("Unsupported Steamworks target OS"),
    };
}

fn configureIncludes(b: *std.Build, module: *std.Build.Module, sdk: []const u8) void {
    module.addIncludePath(b.path("c"));
    module.addSystemIncludePath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "public" }) });
}

fn configureModule(b: *std.Build, module: *std.Build.Module, sdk: []const u8, runtime: Runtime) void {
    configureIncludes(b, module, sdk);
    module.addLibraryPath(.{ .cwd_relative = runtime.directory });
    module.linkSystemLibrary(runtime.library, .{});
    if (module.resolved_target.?.result.os.tag == .linux) module.addRPathSpecial("$ORIGIN");
}

/// Install the unmodified official redistributable beside the consuming binary.
pub fn installRuntime(b: *std.Build, target: std.Target, sdk: []const u8) void {
    const runtime = runtimeLibrary(b, target, sdk);
    const step = b.addInstallFileWithDir(.{ .cwd_relative = b.pathJoin(&.{ runtime.directory, runtime.filename }) }, .bin, runtime.filename);
    b.getInstallStep().dependOn(&step.step);
}

/// Cached build-run/test binaries are not beside the installed redistributable.
/// Set process-local lookup paths without changing SDK files or global settings.
pub fn configureRun(b: *std.Build, run: *std.Build.Step.Run, target: std.Target, sdk: []const u8) void {
    const runtime = runtimeLibrary(b, target, sdk);
    switch (target.os.tag) {
        .macos, .linux => {
            const key = if (target.os.tag == .macos) "DYLD_LIBRARY_PATH" else "LD_LIBRARY_PATH";
            const previous = run.getEnvMap().get(key) orelse "";
            // An empty trailing component would add the working directory on Linux.
            const value = if (previous.len != 0) b.fmt("{s}:{s}", .{ runtime.directory, previous }) else runtime.directory;
            run.setEnvironmentVariable(key, value);
        },
        .windows => run.addPathDir(runtime.directory),
        else => unreachable,
    }
}
