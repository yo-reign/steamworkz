//! Borrowed owner-thread screenshot facade. Construction performs no action.
//! The game owns pending input storage and its budget; this facade stores no
//! caller pointers and has no queue, allocation, file loading or handle release.
const std = @import("std");
const Context = @import("Context.zig");
const types = @import("types.zig");
const c = @cImport({
    @cInclude("screenshots.h");
});
const native = if (@import("builtin").is_test) TestApi else c;
const Screenshots = @This();

lease: Context.Lease,

pub const Error = error{ InterfaceUnavailable, InvalidDimensions, InvalidRgbLength, InvalidPath, SubmissionRejected, HookAlreadyOwned, HookAlreadyActive };

/// Submit mutable packed RGB bytes without copying or taking ownership.
/// Positive dimensions must fit native int; width*height*3 must fit uint32 and
/// equal rgb.len. The SDK may modify input: preservation is not promised.
/// A nonzero handle establishes submission only, not readiness or success.
/// Keep the exact storage address valid; do not mutate, resize, free or reuse
/// it until the matching ScreenshotReady event, including a failure result.
/// Malformed/unrelated events do not end the borrow. If completion is lost,
/// retain storage until process exit; Client.deinit is NOT a documented substitute.
/// This conservative wrapper precondition does not claim synchronous SDK copying
/// or a proven native retention duration. Rejected zero creates no accepted borrow.
/// Handles last for the process and have no release API.
pub fn submitRgbBorrowed(self: Screenshots, rgb: []u8, width: i64, height: i64) Error!types.ScreenshotHandle {
    self.lease.check();
    try dimensions(width, height);
    const pixels = std.math.mul(u64, @intCast(width), @intCast(height)) catch return error.InvalidRgbLength;
    const bytes = std.math.mul(u64, pixels, 3) catch return error.InvalidRgbLength;
    if (bytes > std.math.maxInt(u32) or bytes != rgb.len) return error.InvalidRgbLength;
    var handle: u32 = 0;
    try available(native.sw_screenshots_write(rgb.ptr, @intCast(bytes), @intCast(width), @intCast(height), &handle));
    return submission(handle);
}

/// Explicit absolute paths, NUL-free and at most 4096 bytes INCLUDING terminator.
/// Windows requires a drive or complete UNC server/share; device namespaces,
/// current-drive roots and drive-relative paths are rejected. No filesystem
/// access, normalization, extension check or image decoding occurs here.
/// Caller supplies valid JPG/PNG/TGA contents and positive native-int dimensions.
/// A thumbnail must be 200 pixels wide and have the screenshot's aspect ratio.
/// Omitted thumbnail passes NULL. Both path strings and source files must remain
/// stable through matching ScreenshotReady (even failure); malformed/unrelated
/// events do not qualify. If lost, retain until process exit, not Client.deinit.
/// No files are automatically deleted. Nonzero means submission, not readiness
/// or success; zero is rejected and creates no accepted asynchronous borrow.
pub fn submitFile(self: Screenshots, path: [:0]const u8, thumbnail: ?[:0]const u8, width: i64, height: i64) Error!types.ScreenshotHandle {
    self.lease.check();
    try dimensions(width, height);
    try validPath(@import("builtin").os.tag, path);
    if (thumbnail) |value| try validPath(@import("builtin").os.tag, value);
    var handle: u32 = 0;
    try available(native.sw_screenshots_add(path.ptr, if (thumbnail) |value| value.ptr else null, @intCast(width), @intCast(height), &handle));
    return submission(handle);
}

/// Explicit invocation only, not capture acknowledgement. With a hook this
/// requests ScreenshotRequested; it does not submit image bytes.
pub fn trigger(self: Screenshots) Error!void {
    self.lease.check();
    try available(native.sw_screenshots_trigger());
}

/// Refuses local duplicate ownership and pre-existing native hooks. Invocation
/// of the void setter is not acknowledgement; use isHooked to query native state.
/// No other controller may manipulate screenshot hooks during wrapper ownership.
pub fn enableHook(self: Screenshots) Error!void {
    self.lease.check();
    if (self.lease.context.screenshot_hook_owned) return error.HookAlreadyOwned;
    var hooked = false;
    try available(native.sw_screenshots_is_hooked(&hooked));
    if (hooked) return error.HookAlreadyActive;
    try available(native.sw_screenshots_hook(true));
    self.lease.context.screenshot_hook_owned = true;
}

/// Unowned is a no-op, never an attempt to undo an external hook. Unavailable
/// interface preserves ownership for explicit retry. An invoked setter clears
/// ownership without promising restoration of previous/external state.
pub fn disableHook(self: Screenshots) Error!void {
    self.lease.check();
    if (!self.lease.context.screenshot_hook_owned) return;
    try available(native.sw_screenshots_hook(false));
    self.lease.context.screenshot_hook_owned = false;
}

/// Queries native state separately from wrapper ownership.
pub fn isHooked(self: Screenshots) Error!bool {
    self.lease.check();
    var hooked = false;
    try available(native.sw_screenshots_is_hooked(&hooked));
    return hooked;
}

/// Client-only best-effort teardown BEFORE SteamAPI_Shutdown and Context release.
/// Attempts unhook once only if owned, then clears state even if unavailable.
/// No capture, submission, wait or proof of pending-input release is implied.
pub fn shutdown(lease: Context.Lease) void {
    lease.check();
    if (lease.context.screenshot_hook_owned) _ = native.sw_screenshots_hook(false);
    lease.context.screenshot_hook_owned = false;
}

fn available(value: bool) Error!void {
    if (!value) return error.InterfaceUnavailable;
}
fn submission(handle: u32) Error!types.ScreenshotHandle {
    if (handle == 0) return error.SubmissionRejected;
    return @enumFromInt(handle);
}
fn dimensions(width: i64, height: i64) Error!void {
    if (width <= 0 or height <= 0 or width > std.math.maxInt(c_int) or height > std.math.maxInt(c_int)) return error.InvalidDimensions;
}
fn validPath(os: std.Target.Os.Tag, path: [:0]const u8) Error!void {
    if (path.len >= 4096 or std.mem.indexOfScalar(u8, path, 0) != null or !absolutePath(os, path)) return error.InvalidPath;
}
fn absolutePath(os: std.Target.Os.Tag, path: []const u8) bool {
    if (os != .windows) return std.fs.path.isAbsolutePosix(path);
    switch (std.fs.path.parsePathWindows(u8, path).kind) {
        .drive_absolute => return true,
        .unc_absolute => {
            // Match Input's lexical policy, including incomplete UNC rejection.
            if (path.len <= 2 or path[2] == '/' or path[2] == '\\') return false;
            var parts = std.mem.tokenizeAny(u8, path[2..], "/\\");
            _ = parts.next() orelse return false;
            return parts.next() != null;
        },
        else => return false,
    }
}

// Every owning-file test uses this inert boundary, never the Steam runtime.
const TestApi = struct {
    var present = true;
    var handle: u32 = 1;
    var hooked = false;
    var calls: usize = 0;
    var setters: usize = 0;
    var triggers: usize = 0;
    var rgb_pointer: ?[*]u8 = null;
    var path_pointer: ?[*:0]const u8 = null;
    var thumbnail_pointer: ?[*:0]const u8 = null;
    var length: u32 = 0;
    var size: [2]c_int = .{ 0, 0 };
    fn reset() void {
        present = true;
        handle = 1;
        hooked = false;
        calls = 0;
        setters = 0;
        triggers = 0;
        rgb_pointer = null;
        path_pointer = null;
        thumbnail_pointer = null;
    }
    fn sw_screenshots_write(rgb: [*]u8, bytes: u32, width: c_int, height: c_int, out: *u32) bool {
        calls += 1;
        if (!present) return false;
        rgb_pointer = rgb;
        length = bytes;
        size = .{ width, height };
        out.* = handle;
        return true;
    }
    fn sw_screenshots_add(path: [*:0]const u8, thumbnail: ?[*:0]const u8, width: c_int, height: c_int, out: *u32) bool {
        calls += 1;
        if (!present) return false;
        path_pointer = path;
        thumbnail_pointer = thumbnail;
        size = .{ width, height };
        out.* = handle;
        return true;
    }
    fn sw_screenshots_trigger() bool {
        calls += 1;
        if (!present) return false;
        triggers += 1;
        return true;
    }
    fn sw_screenshots_hook(value: bool) bool {
        calls += 1;
        if (!present) return false;
        setters += 1;
        hooked = value;
        return true;
    }
    fn sw_screenshots_is_hooked(out: *bool) bool {
        calls += 1;
        if (!present) return false;
        out.* = hooked;
        return true;
    }
};

test "Screenshots RGB rejects dimensions and byte mismatch before native access" {
    TestApi.reset();
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    const screenshots: Screenshots = .{ .lease = context.lease() };
    var rgb: [6]u8 = @splat(0);
    for ([_][2]i64{ .{ 0, 1 }, .{ 1, 0 }, .{ -1, 1 }, .{ 1, -1 }, .{ std.math.maxInt(i64), 2 }, .{ 1, @as(i64, std.math.maxInt(i32)) + 1 } }) |size| {
        try std.testing.expectError(error.InvalidDimensions, screenshots.submitRgbBorrowed(&rgb, size[0], size[1]));
    }
    for ([_][2]i64{ .{ 1, 1 }, .{ 3, 1 }, .{ 65536, 65536 }, .{ std.math.maxInt(i32), std.math.maxInt(i32) } }) |size| {
        try std.testing.expectError(error.InvalidRgbLength, screenshots.submitRgbBorrowed(&rgb, size[0], size[1]));
    }
    try std.testing.expectError(error.InvalidRgbLength, screenshots.submitRgbBorrowed(rgb[0..0], 1, 1));
    try std.testing.expectEqual(@as(usize, 0), TestApi.calls);
}

test "Screenshots RGB forwards exact mutable storage and preserves submission distinctions" {
    TestApi.reset();
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    const screenshots: Screenshots = .{ .lease = context.lease() };
    var rgb: [6]u8 = @splat(0);
    for ([_]u32{ 1, std.math.maxInt(u32) }) |handle| {
        TestApi.handle = handle;
        try std.testing.expectEqual(handle, @intFromEnum(try screenshots.submitRgbBorrowed(&rgb, 2, 1)));
        try std.testing.expectEqual(rgb[0..].ptr, TestApi.rgb_pointer.?);
        try std.testing.expectEqual(@as(u32, 6), TestApi.length);
        try std.testing.expectEqual([2]c_int{ 2, 1 }, TestApi.size);
    }
    TestApi.handle = 0;
    try std.testing.expectError(error.SubmissionRejected, screenshots.submitRgbBorrowed(&rgb, 2, 1));
    TestApi.present = false;
    try std.testing.expectError(error.InterfaceUnavailable, screenshots.submitRgbBorrowed(&rgb, 2, 1));
    // Inert forwarding proves neither real retention duration nor readiness.
}

test "Screenshots path validation is lexical bounded and filesystem free" {
    for ([_][:0]const u8{ "/shot", "/unknown.extension", "/a/../b" }) |path| try validPath(.linux, path);
    for ([_][:0]const u8{ "", "relative", "/a\x00b" }) |path| try std.testing.expectError(error.InvalidPath, validPath(.linux, path));
    for ([_][:0]const u8{ "C:" ++ "\\shot", "d:" ++ "/shot", "\\\\server\\share", "//server/share/shot" }) |path| try validPath(.windows, path);
    for ([_][:0]const u8{ "C:shot", "\\shot", "/shot", "\\\\server", "\\\\server\\", "\\\\?\\C:" ++ "\\shot", "\\\\.\\device", "///server/share" }) |path| try std.testing.expectError(error.InvalidPath, validPath(.windows, path));
    var longest: [4095:0]u8 = @splat('a');
    longest[0] = '/';
    try validPath(.linux, &longest);
    var excess: [4096:0]u8 = @splat('a');
    excess[0] = '/';
    try std.testing.expectError(error.InvalidPath, validPath(.linux, &excess));
}

test "Screenshots file forwards stable pointers optional NULL and dimensions" {
    TestApi.reset();
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    const screenshots: Screenshots = .{ .lease = context.lease() };
    const path = if (@import("builtin").os.tag == .windows) "C:" ++ "\\shot" else "/shot";
    const thumb = if (@import("builtin").os.tag == .windows) "C:" ++ "\\thumb" else "/thumb";
    try std.testing.expectError(error.InvalidPath, screenshots.submitFile("relative", null, 2, 1));
    try std.testing.expectError(error.InvalidPath, screenshots.submitFile(path, "relative", 2, 1));
    try std.testing.expectError(error.InvalidDimensions, screenshots.submitFile(path, null, -1, 1));
    try std.testing.expectEqual(@as(usize, 0), TestApi.calls);
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(try screenshots.submitFile(path, null, 2, 1)));
    try std.testing.expectEqual(path.ptr, TestApi.path_pointer.?);
    try std.testing.expect(TestApi.thumbnail_pointer == null);
    TestApi.handle = std.math.maxInt(u32);
    try std.testing.expectEqual(TestApi.handle, @intFromEnum(try screenshots.submitFile(path, thumb, 400, 200)));
    try std.testing.expectEqual(thumb.ptr, TestApi.thumbnail_pointer.?);
    try std.testing.expectEqual([2]c_int{ 400, 200 }, TestApi.size);
    TestApi.handle = 0;
    try std.testing.expectError(error.SubmissionRejected, screenshots.submitFile(path, null, 2, 1));
    TestApi.present = false;
    try std.testing.expectError(error.InterfaceUnavailable, screenshots.submitFile(path, null, 2, 1));
}

test "Screenshots hook ownership is shared across facade copies and protects external hooks" {
    TestApi.reset();
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    const screenshots: Screenshots = .{ .lease = context.lease() };
    const copy = screenshots;
    defer {
        TestApi.present = true;
        shutdown(context.lease());
    }
    try copy.disableHook();
    try std.testing.expectEqual(@as(usize, 0), TestApi.calls);
    TestApi.hooked = true;
    try std.testing.expectError(error.HookAlreadyActive, screenshots.enableHook());
    try copy.disableHook();
    try std.testing.expect(TestApi.hooked);
    try std.testing.expectEqual(@as(usize, 0), TestApi.setters);
    TestApi.hooked = false;
    try screenshots.enableHook();
    const calls = TestApi.calls;
    try std.testing.expectError(error.HookAlreadyOwned, copy.enableHook());
    try std.testing.expectEqual(calls, TestApi.calls);
    try std.testing.expect(try copy.isHooked());
    TestApi.hooked = false; // Native query is not the ownership flag.
    try std.testing.expect(!try copy.isHooked());
    try std.testing.expect(context.screenshot_hook_owned);
    TestApi.present = false;
    try std.testing.expectError(error.InterfaceUnavailable, copy.disableHook());
    try std.testing.expect(context.screenshot_hook_owned);
    TestApi.present = true;
    try copy.disableHook();
    try std.testing.expect(!context.screenshot_hook_owned);
    try std.testing.expectEqual(@as(usize, 2), TestApi.setters);
    try screenshots.disableHook();
    try std.testing.expectEqual(@as(usize, 2), TestApi.setters);
}

test "Screenshots shutdown is bounded best effort and trigger remains separate" {
    TestApi.reset();
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    const screenshots: Screenshots = .{ .lease = context.lease() };
    defer {
        TestApi.present = true;
        shutdown(context.lease());
    }
    shutdown(context.lease());
    try std.testing.expectEqual(@as(usize, 0), TestApi.calls);
    TestApi.present = false;
    try std.testing.expectError(error.InterfaceUnavailable, screenshots.enableHook());
    try std.testing.expectError(error.InterfaceUnavailable, screenshots.isHooked());
    try std.testing.expectError(error.InterfaceUnavailable, screenshots.trigger());
    try std.testing.expect(!context.screenshot_hook_owned);
    TestApi.present = true;
    try screenshots.enableHook();
    try screenshots.trigger();
    try std.testing.expectEqual(@as(usize, 1), TestApi.triggers);
    shutdown(context.lease());
    try std.testing.expect(!TestApi.hooked);
    try screenshots.enableHook();
    TestApi.present = false;
    const calls = TestApi.calls;
    shutdown(context.lease());
    shutdown(context.lease());
    try std.testing.expectEqual(calls + 1, TestApi.calls);
    try std.testing.expect(!context.screenshot_hook_owned);
    try std.testing.expectEqual(@as(usize, 1), TestApi.triggers);
}
