const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
// Native spawn types come from the target's libc headers, never guessed layouts.
const spawn_api = if (builtin.os.tag == .windows) struct {} else @cImport({
    // Exclude Darwin's unrelated Mach extensions (untranslatable bitfields).
    @cDefine("_POSIX_C_SOURCE", "200809L");
    @cInclude("spawn.h");
});
const posix = if (builtin.os.tag == .windows) struct {} else @cImport({
    // Import libc ABI declarations, not glibc's fortified C inline wrappers:
    // Zig 0.16 cannot translate variadic open/openat wrappers in ReleaseSafe.
    // This affects this declaration import only, not native C/C++ hardening.
    if (builtin.os.tag == .linux) @cUndef("_FORTIFY_SOURCE");
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
    @cInclude("paths.h");
    @cInclude("stdlib.h");
    @cInclude("sys/stat.h");
    @cInclude("sys/resource.h");
    if (builtin.os.tag == .macos) @cInclude("crt_externs.h");
});

fn checkPosixError(code: c_int) !void {
    switch (@as(std.posix.E, @enumFromInt(code))) {
        .SUCCESS => {},
        .NOENT => return error.FileNotFound,
        .NOEXEC, .INVAL => return error.InvalidExe,
        .ACCES => return error.AccessDenied,
        .NOTDIR => return error.NotDir,
        .NAMETOOLONG => return error.NameTooLong,
        .MFILE => return error.ProcessFdQuotaExceeded,
        .NFILE => return error.SystemFdQuotaExceeded,
        .NOMEM, .AGAIN => return error.SystemResources,
        else => |err| return std.posix.unexpectedErrno(err),
    }
}

fn closeDescriptor(fd: c_int) void {
    // No retry: close may already have released the descriptor on EINTR.
    _ = posix.close(fd);
}

fn duplicateAboveStdio(fd: c_int) !c_int {
    const duplicate = posix.fcntl(fd, posix.F_DUPFD_CLOEXEC, @as(c_int, 3));
    if (duplicate == -1) try checkPosixError(@intFromEnum(std.posix.errno(-1)));
    return duplicate;
}

fn capturePipe() ![2]c_int {
    var raw: [2]c_int = undefined;
    if (posix.pipe(&raw) != 0) try checkPosixError(@intFromEnum(std.posix.errno(-1)));
    defer for (raw) |fd| closeDescriptor(fd);
    // Relocate BOTH ends even when 0/1/2 were closed. File actions can then
    // install standard streams without clobbering a source or closing a target.
    const read = try duplicateAboveStdio(raw[0]);
    errdefer closeDescriptor(read);
    return .{ read, try duplicateAboveStdio(raw[1]) };
}

fn spawnCapture(allocator: std.mem.Allocator, io: Io, argv: []const []const u8) !std.process.Child {
    if (builtin.os.tag == .windows)
        return std.process.spawn(io, .{ .argv = argv, .stdin = .ignore, .stdout = .pipe, .stderr = .pipe });

    try io.checkCancel();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arguments = try arena.allocator().allocSentinel(?[*:0]u8, argv.len, null);
    for (argv, 0..) |arg, index| arguments[index] = (try arena.allocator().dupeZ(u8, arg)).ptr;

    const stdout = try capturePipe();
    defer closeDescriptor(stdout[1]);
    errdefer closeDescriptor(stdout[0]);
    const stderr = try capturePipe();
    defer closeDescriptor(stderr[1]);
    errdefer closeDescriptor(stderr[0]);
    var actions: spawn_api.posix_spawn_file_actions_t = undefined;
    try checkPosixError(spawn_api.posix_spawn_file_actions_init(&actions));
    defer _ = spawn_api.posix_spawn_file_actions_destroy(&actions);
    try checkPosixError(spawn_api.posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", posix.O_RDONLY, 0));
    try checkPosixError(spawn_api.posix_spawn_file_actions_adddup2(&actions, stdout[1], 1));
    try checkPosixError(spawn_api.posix_spawn_file_actions_adddup2(&actions, stderr[1], 2));
    for (stdout ++ stderr) |fd| try checkPosixError(spawn_api.posix_spawn_file_actions_addclose(&actions, fd));

    // Unlike Zig 0.16's post-fork error path, libc owns failed-exec cleanup.
    // On success, transfer PID and read ends together, with no intervening
    // cancel point. Even an exit-127 child is owned and must be waited on.
    return .{
        .id = try spawnWithPath(io, arguments, &actions),
        .thread_handle = {},
        .stdin = null,
        .stdout = .{ .handle = stdout[0], .flags = .{ .nonblocking = false } },
        .stderr = .{ .handle = stderr[0], .flags = .{ .nonblocking = false } },
        .request_resource_usage_statistics = false,
    };
}

// CLI: check <case> <test-executable> | self-test
// Fatal artifacts select one lifecycle or public-guard test and enable
// steamworkz_test_options.fatal_lifecycle. Normal artifacts set it false.
const cases = [_]struct { name: []const u8, diagnostic: []const u8 }{
    .{ .name = "wrong-thread", .diagnostic = "Steamworks calls must use the client owner thread" },
    .{ .name = "moved-client", .diagnostic = "Steamworks client is closed or moved" },
    .{ .name = "stale-lease", .diagnostic = "Steamworks handle belongs to an earlier client session" },
    .{ .name = "released-message", .diagnostic = "Steamworks message has been released" },
    .{ .name = "outstanding-message", .diagnostic = "Release all Steamworks messages before closing the client" },
    .{ .name = "outstanding-cloud-batch", .diagnostic = "End the Steamworks cloud write batch before closing the client" },
};
const output_limit = 64 * 1024;
const deadline_ms = 10_000;
const stream_fixture_name = "streams with spaces ' \" \\ \t\n";

fn spawnWithPath(io: Io, arguments: [:null]?[*:0]u8, actions: *const spawn_api.posix_spawn_file_actions_t) !posix.pid_t {
    const file = std.mem.span(arguments[0].?);
    if (std.mem.indexOfScalar(u8, file, '/') != null) return spawnAt(io, arguments[0].?, arguments, actions);

    // Darwin's spawnp may run invalid executables through /bin/sh. Search with
    // spawn instead; match Zig's default PATH and its skipping of empty entries.
    const environment_path = posix.getenv("PATH");
    const path = if (environment_path == null) Io.Threaded.default_PATH else std.mem.span(environment_path);
    var entries = std.mem.splitScalar(u8, path, ':');
    var denied = false;
    var last_error: anyerror = error.FileNotFound;
    while (entries.next()) |directory| {
        if (directory.len == 0) continue;
        var buffer: [std.posix.PATH_MAX]u8 = undefined;
        const candidate = std.fmt.bufPrintZ(&buffer, "{s}/{s}", .{ directory, file }) catch return error.NameTooLong;
        return spawnAt(io, candidate, arguments, actions) catch |err| {
            switch (err) {
                error.AccessDenied => denied = true,
                error.FileNotFound, error.NotDir => {},
                else => return err,
            }
            last_error = err;
            continue;
        };
    }
    return if (denied) error.AccessDenied else last_error;
}

fn spawnAt(io: Io, path: [*:0]const u8, arguments: [:null]?[*:0]u8, actions: *const spawn_api.posix_spawn_file_actions_t) !posix.pid_t {
    try io.checkCancel();
    const environ = if (builtin.os.tag == .macos) posix._NSGetEnviron().* else std.c.environ;
    var pid: posix.pid_t = undefined;
    try checkPosixError(spawn_api.posix_spawn(&pid, path, actions, null, arguments.ptr, environ));
    return pid;
}

const Capture = struct {
    allocator: std.mem.Allocator,
    io: Io,
    argv: []const []const u8,
    child: ?std.process.Child = null,
    term: ?std.process.Child.Term = null,
    failure: ?anyerror = null,
    stdout: []u8 = &.{},
    stderr: []u8 = &.{},

    fn run(self: *Capture) void {
        self.collect() catch |err| {
            self.failure = err;
        };
    }

    fn collect(self: *Capture) !void {
        self.child = try spawnCapture(self.allocator, self.io, self.argv);
        var buffer: Io.File.MultiReader.Buffer(2) = undefined;
        var reader: Io.File.MultiReader = undefined;
        reader.init(self.allocator, self.io, buffer.toStreams(), &.{ self.child.?.stdout.?, self.child.?.stderr.? });
        defer reader.deinit();
        while (reader.fill(256, .none)) |_| {
            if (reader.reader(0).buffered().len > output_limit or reader.reader(1).buffered().len > output_limit)
                return error.StreamTooLong;
        } else |err| switch (err) {
            error.EndOfStream => {},
            else => return err,
        }
        try reader.checkAnyError();
        self.stdout = try reader.toOwnedSlice(0);
        self.stderr = try reader.toOwnedSlice(1);

        // This is only a wait view, NOT another owner. Zig 0.16 POSIX wait
        // clears its Child even on cancellation. Keep the actual owner intact
        // for hard termination/reaping, and never let the view close pipes.
        // Windows wait closes process/thread handles only on success.
        var wait_view = self.child.?;
        wait_view.stdin = null;
        wait_view.stdout = null;
        wait_view.stderr = null;
        self.term = try wait_view.wait(self.io);
    }

    // Called only after all capture work has joined, including when the timer
    // won but wait completed concurrently. A successful wait has already reaped
    // the child (and closed Windows process handles): never signal that PID.
    fn cleanup(self: *Capture) void {
        if (self.child) |*child| {
            if (self.term != null) {
                child.id = null;
                child.thread_handle = undefined;
                if (child.stdout) |file| file.close(self.io);
                if (child.stderr) |file| file.close(self.io);
                child.stdout = null;
                child.stderr = null;
            } else {
                if (builtin.os.tag != .windows) std.posix.kill(child.id.?, .KILL) catch @panic("cannot terminate lifecycle child");
                child.kill(self.io); // Windows terminates; POSIX reaps after SIGKILL.
            }
            std.debug.assert(child.id == null and child.stdout == null and child.stderr == null);
        }
    }

    fn deinit(self: *Capture) void {
        self.allocator.free(self.stdout);
        self.allocator.free(self.stderr);
    }
};

fn timer(io: Io, deadline: Io.Clock.Timestamp) Io.Cancelable!void {
    try deadline.wait(io);
}

fn boundedRun(capture: *Capture, milliseconds: u32) !void {
    const Outcome = union(enum) { done: void, deadline: Io.Cancelable!void };
    var results: [2]Outcome = undefined;
    var race = Io.Select(Outcome).init(capture.io, &results);
    // Start the timer first so spawn, pipe reads AND final wait share one budget.
    const deadline = Io.Clock.Timestamp.fromNow(capture.io, .{ .raw = .fromMilliseconds(milliseconds), .clock = .awake });
    defer {
        race.cancelDiscard();
        capture.cleanup();
    }
    try race.concurrent(.deadline, timer, .{ capture.io, deadline });
    try race.concurrent(.done, Capture.run, .{capture});
    const outcome = try race.await();
    race.cancelDiscard();
    if (outcome == .deadline or Io.Clock.Timestamp.now(capture.io, .awake).compare(.gte, deadline)) return error.DeadlineExceeded;
    if (capture.failure) |err| return err;
}

fn validate(term: std.process.Child.Term, stdout: []const u8, stderr: []const u8, name: []const u8, diagnostic: []const u8) !void {
    switch (term) {
        .exited => |code| if (code == 0) return error.NormalExit,
        .signal => {},
        else => return error.UnexpectedTermination,
    }
    var marker_buffer: [128]u8 = undefined;
    const marker = try std.fmt.bufPrint(&marker_buffer, "STEAMWORKZ_FATAL_READY:{s}\n", .{name});
    const marker_at = std.mem.indexOf(u8, stderr, marker) orelse return error.MissingMarker;
    const after_marker = stderr[marker_at + marker.len ..];
    var panic_buffer: [256]u8 = undefined;
    const panic_text = try std.fmt.bufPrint(&panic_buffer, "panic: {s}\n", .{diagnostic});
    if (std.mem.indexOf(u8, after_marker, panic_text) == null) return error.MissingPanic;
    // Do not count a test failure, another panic, or loader diagnostics as the
    // intended failure, even if the expected text appears elsewhere in output.
    for ([_][]const u8{ "FAIL (", "error: '", "dyld[", "Library not loaded", "error while loading shared libraries" }) |bad| {
        if (std.mem.indexOf(u8, stderr, bad) != null or std.mem.indexOf(u8, stdout, bad) != null)
            return error.UnrelatedFailure;
    }
    const first_panic = std.mem.indexOf(u8, stderr, "panic: ") orelse return error.MissingPanic;
    if (!std.mem.startsWith(u8, stderr[first_panic..], panic_text)) return error.UnrelatedFailure;
    if (std.mem.indexOf(u8, stderr[first_panic + panic_text.len ..], "panic: ") != null) return error.UnrelatedFailure;
}

fn check(allocator: std.mem.Allocator, io: Io, name: []const u8, executable: []const u8) !void {
    for (cases) |case| {
        if (!std.mem.eql(u8, name, case.name)) continue;
        var capture: Capture = .{ .allocator = allocator, .io = io, .argv = &.{executable} };
        defer capture.deinit();
        try boundedRun(&capture, deadline_ms);
        validate(capture.term.?, capture.stdout, capture.stderr, name, case.diagnostic) catch |err| {
            std.debug.print("lifecycle {s}: {s}\n{s}\n{s}\n", .{ name, @errorName(err), capture.stdout, capture.stderr });
            return err;
        };
        return;
    }
    return error.UnknownCase;
}

fn fixture(allocator: std.mem.Allocator, io: Io, executable: []const u8, name: []const u8) !void {
    if (builtin.os.tag != .windows) {
        if (std.mem.eql(u8, name, "spawn-closed-stdio")) {
            // Force raw pipe ends to alias standard descriptors in this isolated
            // fixture, without closing any of the self-test parent's streams.
            for (0..3) |fd| closeDescriptor(@intCast(fd));
            var capture: Capture = .{ .allocator = allocator, .io = io, .argv = &.{ executable, "--fixture", stream_fixture_name } };
            defer capture.deinit();
            {
                defer capture.cleanup();
                try capture.collect();
            }
            try verifyReaped(&capture);
            try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, capture.term.?);
            try std.testing.expectEqualStrings("stdout bytes\n", capture.stdout);
            try std.testing.expectEqualStrings("stderr bytes\n", capture.stderr);
            return;
        }
        if (std.mem.eql(u8, name, "spawn-fd-exhaustion")) {
            closeDescriptor(0);
            closeDescriptor(1);
            const spare = try duplicateAboveStdio(2);
            closeDescriptor(spare);
            var original: posix.struct_rlimit = undefined;
            if (posix.getrlimit(posix.RLIMIT_NOFILE, &original) != 0) return error.GetLimitFailed;
            var limit = original;
            limit.rlim_cur = @intCast(spare + 1);
            if (posix.setrlimit(posix.RLIMIT_NOFILE, &limit) != 0) return error.SetLimitFailed;
            defer if (posix.setrlimit(posix.RLIMIT_NOFILE, &original) != 0) @panic("cannot restore descriptor limit");
            // pipe acquires 0/1 and the first duplicate acquires spare. The
            // second duplicate must fail, exercising partial pipe cleanup.
            const before = try countDescriptors();
            try std.testing.expectError(error.ProcessFdQuotaExceeded, spawnCapture(allocator, io, &.{executable}));
            try std.testing.expectEqual(before, try countDescriptors());
            return;
        }
        if (std.mem.eql(u8, name, "spawn-path")) return pathSearchTest(allocator, io, executable);
        if (std.mem.eql(u8, name, stream_fixture_name)) {
            var byte: u8 = undefined;
            try std.testing.expectEqual(@as(isize, 0), posix.read(0, &byte, 1));
            try Io.File.stdout().writeStreamingAll(io, "stdout bytes\n");
            try Io.File.stderr().writeStreamingAll(io, "stderr bytes\n");
            return;
        }
    }
    const marker = "STEAMWORKZ_FATAL_READY:control\n";
    const panic_text = "thread 1 panic: control diagnostic\n";
    if (!std.mem.eql(u8, name, "missing-marker")) try Io.File.stderr().writeStreamingAll(io, marker);
    if (std.mem.eql(u8, name, "panic")) @panic("control diagnostic");
    if (std.mem.eql(u8, name, "wrong-panic")) @panic("unrelated diagnostic");
    if (std.mem.eql(u8, name, "nonzero")) std.process.exit(1);
    if (std.mem.eql(u8, name, "normal") or std.mem.eql(u8, name, "missing-marker") or std.mem.eql(u8, name, "loader") or std.mem.eql(u8, name, "unrelated")) {
        try Io.File.stderr().writeStreamingAll(io, panic_text);
        if (std.mem.eql(u8, name, "normal")) return;
        if (std.mem.eql(u8, name, "loader")) try Io.File.stderr().writeStreamingAll(io, "Library not loaded: fixture\n");
        if (std.mem.eql(u8, name, "unrelated")) try Io.File.stderr().writeStreamingAll(io, "FAIL (TestUnexpectedResult)\n");
        std.process.exit(1);
    }
    if (std.mem.eql(u8, name, "overflow") or std.mem.eql(u8, name, "overflow-stderr")) {
        const bytes: [4096]u8 = @splat('x');
        const file = if (std.mem.eql(u8, name, "overflow")) Io.File.stdout() else Io.File.stderr();
        while (true) try file.writeStreamingAll(io, &bytes);
    }
    if (std.mem.eql(u8, name, "closed-pipes")) {
        Io.File.stdout().close(io);
        Io.File.stderr().close(io);
    }
    if (std.mem.eql(u8, name, "race")) {
        try io.sleep(.fromMilliseconds(2), .awake);
        return;
    }
    if (std.mem.eql(u8, name, "ignore-term")) {
        if (builtin.os.tag != .windows) std.posix.sigaction(.TERM, &.{ .handler = .{ .handler = std.posix.SIG.IGN }, .mask = std.posix.sigemptyset(), .flags = 0 }, null);
    } else if (!std.mem.eql(u8, name, "hang") and !std.mem.eql(u8, name, "closed-pipes")) return error.UnknownFixture;
    while (true) try io.sleep(.fromSeconds(60), .awake);
}

fn selfTest(allocator: std.mem.Allocator, io: Io, executable: []const u8) !void {
    const controls = [_]struct { name: []const u8, expected: ?anyerror }{
        .{ .name = "panic", .expected = null },
        .{ .name = "normal", .expected = error.NormalExit },
        .{ .name = "missing-marker", .expected = error.MissingMarker },
        .{ .name = "loader", .expected = error.UnrelatedFailure },
        .{ .name = "unrelated", .expected = error.UnrelatedFailure },
        .{ .name = "wrong-panic", .expected = error.MissingPanic },
        .{ .name = "nonzero", .expected = error.MissingPanic },
        .{ .name = "overflow", .expected = error.StreamTooLong },
        .{ .name = "overflow-stderr", .expected = error.StreamTooLong },
        .{ .name = "ignore-term", .expected = error.DeadlineExceeded },
        .{ .name = "hang", .expected = error.DeadlineExceeded },
        .{ .name = "closed-pipes", .expected = error.DeadlineExceeded },
    };
    for (controls) |control| {
        var capture: Capture = .{ .allocator = allocator, .io = io, .argv = &.{ executable, "--fixture", control.name } };
        defer capture.deinit();
        const started = Io.Clock.Timestamp.now(io, .awake);
        const result = boundedRun(&capture, if (control.expected != null and control.expected.? == error.DeadlineExceeded) 1000 else deadline_ms);
        const validated = if (result) |_| validate(capture.term.?, capture.stdout, capture.stderr, "control", "control diagnostic") else |err| err;
        if (control.expected) |expected| {
            try std.testing.expectError(expected, validated);
        } else try validated;
        if (control.expected != null and control.expected.? == error.DeadlineExceeded) try std.testing.expect(started.untilNow(io).raw.toMilliseconds() < 5000);
        if (std.mem.eql(u8, control.name, "closed-pipes")) {
            // Captured output is transferred only after BOTH pipes reach EOF.
            // This proves the timeout interrupted wait, not a pending read.
            try std.testing.expectEqualStrings("STEAMWORKZ_FATAL_READY:control\n", capture.stderr);
            try std.testing.expectEqual(error.Canceled, capture.failure.?);
        }
        try verifyReaped(&capture);
    }
    // Exercise the completion/cancellation boundary repeatedly. Either winner
    // is valid; cleanup must reap exactly once and close the pipes exactly once.
    for (0..32) |index| {
        var capture: Capture = .{ .allocator = allocator, .io = io, .argv = &.{ executable, "--fixture", "race" } };
        defer capture.deinit();
        const budget = ([_]u32{ 1, 4, 10, 25 })[index % 4];
        boundedRun(&capture, budget) catch |err| if (err != error.DeadlineExceeded) return err;
        try verifyReaped(&capture);
    }
    try verifySpawnFailure(allocator, io, "/steamworkz-nonexistent-lifecycle-fixture", error.FileNotFound);
    if (builtin.os.tag != .windows) {
        const path = try temporaryTemplate(allocator, "steamworkz-invalid-executable");
        defer allocator.free(path);
        const fd = posix.mkstemp(path.ptr);
        if (fd == -1) return error.CreateInvalidExecutableFailed;
        defer _ = posix.unlink(path.ptr);
        {
            defer closeDescriptor(fd);
            const file: Io.File = .{ .handle = fd, .flags = .{ .nonblocking = false } };
            try file.writeStreamingAll(io, "\x00not an executable\n");
            if (posix.fchmod(fd, 0o700) != 0) return error.ChmodFailed;
        }
        // Real executable permission plus invalid contents reaches libc's exec
        // failure, not a preflight or a synthetic error. Repeat to expose leaks.
        for (0..3) |_| {
            try verifySpawnFailure(allocator, io, path, error.InvalidExe);
            try verifySpawnFailure(allocator, io, "/steamworkz-nonexistent-lifecycle-fixture", error.FileNotFound);
        }
        for ([_][]const u8{ "spawn-closed-stdio", "spawn-fd-exhaustion", "spawn-path", "normal" }) |name| {
            const before = try countDescriptors();
            var capture: Capture = .{ .allocator = allocator, .io = io, .argv = &.{ executable, "--fixture", name } };
            defer capture.deinit();
            try boundedRun(&capture, deadline_ms);
            try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, capture.term.?);
            try verifyReaped(&capture);
            try std.testing.expectEqual(before, try countDescriptors());
        }
    }
}

fn temporaryTemplate(allocator: std.mem.Allocator, name: []const u8) ![:0]u8 {
    const configured = posix.getenv("TMPDIR");
    const directory: []const u8 = if (configured != null and configured[0] != 0) std.mem.span(configured) else posix._PATH_TMP;
    return std.fmt.allocPrintSentinel(allocator, "{s}{s}{s}-XXXXXX", .{
        directory,
        if (std.mem.endsWith(u8, directory, "/")) "" else "/",
        name,
    }, 0);
}

fn pathSearchTest(allocator: std.mem.Allocator, io: Io, executable: []const u8) !void {
    // Environment changes and temporary lookup entries live only in this fixture.
    const directory = try temporaryTemplate(allocator, "steamworkz-spawn-path");
    defer allocator.free(directory);
    if (posix.mkdtemp(directory.ptr) == null) return error.CreateDirectoryFailed;
    defer _ = posix.rmdir(directory.ptr);
    if (posix.setenv("TMPDIR", directory.ptr, 1) != 0) return error.SetEnvironmentFailed;
    const configured_path = try temporaryTemplate(allocator, "configured");
    defer allocator.free(configured_path);
    const configured_fd = posix.mkstemp(configured_path.ptr);
    if (configured_fd == -1) return error.CreateConfiguredTemporaryFailed;
    closeDescriptor(configured_fd);
    defer _ = posix.unlink(configured_path.ptr);
    try std.testing.expectEqualStrings(directory, std.fs.path.dirname(configured_path).?);
    const target = try Io.Dir.cwd().realPathFileAlloc(io, executable, allocator);
    defer allocator.free(target);
    const success = try std.fmt.allocPrintSentinel(allocator, "{s}/success", .{directory}, 0);
    defer allocator.free(success);
    if (posix.symlink(target, success) != 0) return error.SymlinkFailed;
    defer _ = posix.unlink(success);
    const invalid = try std.fmt.allocPrintSentinel(allocator, "{s}/invalid", .{directory}, 0);
    defer allocator.free(invalid);
    const fd = posix.open(invalid, posix.O_CREAT | posix.O_EXCL | posix.O_WRONLY, @as(posix.mode_t, 0o700));
    if (fd == -1) return error.CreateInvalidExecutableFailed;
    closeDescriptor(fd); // Empty, executable file: ENOEXEC, never shell fallback.
    defer _ = posix.unlink(invalid);
    const path = try std.fmt.allocPrintSentinel(allocator, ":{s}::/steamworkz-missing-path", .{directory}, 0);
    defer allocator.free(path);
    if (posix.setenv("PATH", path, 1) != 0) return error.SetEnvironmentFailed;
    var capture: Capture = .{ .allocator = allocator, .io = io, .argv = &.{ "success", "--fixture", stream_fixture_name } };
    defer capture.deinit();
    try boundedRun(&capture, deadline_ms);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, capture.term.?);
    try std.testing.expectEqualStrings("stdout bytes\n", capture.stdout);
    try std.testing.expectEqualStrings("stderr bytes\n", capture.stderr);
    try verifyReaped(&capture);
    try verifySpawnFailure(allocator, io, "missing", error.FileNotFound);
    try verifySpawnFailure(allocator, io, "invalid", error.InvalidExe);
    if (posix.chmod(invalid, 0o600) != 0) return error.ChmodFailed;
    // EACCES must survive a later ENOENT from the final PATH entry.
    try verifySpawnFailure(allocator, io, "invalid", error.AccessDenied);
    if (posix.setenv("PATH", invalid, 1) != 0) return error.SetEnvironmentFailed;
    try verifySpawnFailure(allocator, io, "missing", error.NotDir);
    if (posix.setenv("PATH", "", 1) != 0) return error.SetEnvironmentFailed;
    try verifySpawnFailure(allocator, io, "success", error.FileNotFound);
    if (posix.unsetenv("PATH") != 0) return error.SetEnvironmentFailed;
    try verifySpawnFailure(allocator, io, "steamworkz-nonexistent-lifecycle-fixture", error.FileNotFound);
}

// Read-only leak detection, not cleanup: never close or reap an unowned resource.
fn countDescriptors() !usize {
    var limit: posix.struct_rlimit = undefined;
    if (posix.getrlimit(posix.RLIMIT_NOFILE, &limit) != 0 or limit.rlim_cur > std.math.maxInt(c_int)) return error.GetLimitFailed;
    var count: usize = 0;
    for (0..@intCast(limit.rlim_cur)) |fd| {
        if (posix.fcntl(@as(c_int, @intCast(fd)), posix.F_GETFD) != -1) {
            count += 1;
        } else if (std.posix.errno(-1) != .BADF) return error.DescriptorProbeFailed;
    }
    return count;
}

fn verifySpawnFailure(allocator: std.mem.Allocator, io: Io, executable: []const u8, expected: anyerror) !void {
    const before = if (builtin.os.tag != .windows) try countDescriptors() else 0;
    var capture: Capture = .{ .allocator = allocator, .io = io, .argv = &.{executable} };
    defer capture.deinit();
    try std.testing.expectError(expected, boundedRun(&capture, deadline_ms));
    try verifyReaped(&capture);
    if (builtin.os.tag != .windows) try std.testing.expectEqual(before, try countDescriptors());
}

fn verifyReaped(capture: *const Capture) !void {
    if (capture.child) |child| {
        try std.testing.expect(child.id == null);
        try std.testing.expect(child.stdout == null and child.stderr == null);
    }
    // This standalone runner owns no other children. Windows is handle-based.
    if (builtin.os.tag != .windows) {
        const failed_darwin_spawn = builtin.os.tag == .macos and capture.child == null and capture.failure != null;
        const deadline = Io.Clock.Timestamp.fromNow(capture.io, .{ .raw = .fromMilliseconds(1000), .clock = .awake });
        while (true) {
            var status: c_int = 0;
            const result = std.posix.system.waitpid(-1, &status, std.posix.W.NOHANG);
            if (result < 0) return std.testing.expectEqual(std.posix.E.CHILD, std.posix.errno(result));
            // A positive result has REAPED a leaked child: always fail, never
            // mistake this observational assertion for successful cleanup.
            if (result > 0) return error.UnreapedChild;
            if (!failed_darwin_spawn) return error.UnexpectedLiveChild;
            // Darwin can expose a transient live child during its internal
            // failed-spawn discard, without returning a PID to the caller.
            // Require ECHILD, never a waitable child, before a bounded deadline.
            if (Io.Clock.Timestamp.now(capture.io, .awake).compare(.gte, deadline)) return error.ChildDiscardDeadlineExceeded;
            try std.Thread.yield();
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len == 4 and std.mem.eql(u8, args[1], "check")) return check(init.gpa, init.io, args[2], args[3]);
    if (args.len == 2 and std.mem.eql(u8, args[1], "self-test")) return selfTest(init.gpa, init.io, args[0]);
    if (args.len == 3 and std.mem.eql(u8, args[1], "--fixture")) return fixture(init.gpa, init.io, args[0], args[2]);
    return error.InvalidArguments;
}
