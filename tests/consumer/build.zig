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
        module.resolved_target.?.result.abi != target.result.abi or
        module.resolved_target.?.result.cpu.model != target.result.cpu.model or
        !module.resolved_target.?.result.cpu.features.eql(target.result.cpu.features))
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

    const negative = b.step("check-negative", "Verify public API misuse fails with the intended diagnostics");
    for ([_]struct { source: []const u8, diagnostic: []const u8 }{
        .{ .source = "invalid_request.zig", .diagnostic = "error: This event does not complete an exposed API-call request" },
        .{ .source = "invalid_image.zig", .diagnostic = "error: expected type 'types.ImageHandle', found 'comptime_int'" },
    }) |probe| {
        const invalid = b.addExecutable(.{
            .name = probe.source,
            .root_module = b.createModule(.{ .root_source_file = b.path(probe.source), .target = target, .optimize = optimize }),
        });
        // Executable compilation avoids COFF's multiple-object build-obj limit.
        // These probes have exported functions but no runnable entry point.
        invalid.entry = .disabled;
        invalid.root_module.addImport("steamworkz", module);
        invalid.expect_errors = .{ .contains = probe.diagnostic };
        negative.dependOn(&invalid.step);
    }

    // Check the cached-run recipe is constructible, but never execute a target
    // binary: this fixture must also work for cross-target compile/link checks.
    const run = b.addRunArtifact(exe);
    steamworkz_build.configureRun(b, run, target.result, sdk);
}
