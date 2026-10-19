const std = @import("std");
const steamworkz_build = @import("steamworkz");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const sdk = b.pathFromRoot(b.option([]const u8, "sdk", "Official Steamworks SDK directory (overrides STEAMWORKS_SDK)") orelse
        b.graph.environ_map.get("STEAMWORKS_SDK") orelse
        @panic("Steamworkz requires the external Steamworks SDK 1.65: pass -Dsdk=/absolute/path/to/sdk or set STEAMWORKS_SDK to the directory containing public and redistributable_bin"));
    const steamworkz = b.dependency("steamworkz", .{
        .target = target,
        .optimize = optimize,
        .sdk = sdk,
    });
    const module = steamworkz.module("steamworkz");
    if (module.optimize.? != optimize or
        module.resolved_target.?.result.cpu.arch != target.result.cpu.arch or
        module.resolved_target.?.result.os.tag != target.result.os.tag or
        module.resolved_target.?.result.abi != target.result.abi)
        @panic("Steamworkz dependency did not preserve consumer build options");

    // Use default compiler/linker selection, like an independent consuming game.
    const exe = b.addExecutable(.{
        .name = "steamworkz-consumer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("steamworkz", module);
    b.installArtifact(exe);
    steamworkz_build.installRuntime(b, target.result, sdk);

    // Check the cached-run recipe is constructible, but never execute a target
    // binary: this fixture must also work for cross-target compile/link checks.
    const run = b.addRunArtifact(exe);
    steamworkz_build.configureRun(b, run, target.result, sdk);
}
