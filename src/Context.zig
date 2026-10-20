const std = @import("std");

const Context = @This();
var active_owner = std.atomic.Value(usize).init(0);
var next_generation = std.atomic.Value(u64).init(1);

owner_thread: std.Thread.Id,
generation: u64,
messages: usize = 0,
keyboard_state: enum { none, gamepad, floating } = .none,
keyboard_app_id: u32 = 0,
input_state: enum { inactive, active, init_failed, shutdown_failed } = .inactive,
cloud_batch_serial: u64 = 0,
cloud_batch_active: u64 = 0,
leaderboard_download_call: u64 = 0,
leaderboard_download_blocked: bool = false,
leaderboard_upload_call: u64 = 0,
voice_state: enum { inactive, recording, draining } = .inactive,
timeline_serial: u64 = 0,
/// Wrapper-owned open ranges only. Closed native markers are not resource owners.
timeline_ranges: [16]struct { token: u64 = 0, handle: u64 = 0 } = @splat(.{}),
workshop_serial: u64 = 0,
workshop_active: u64 = 0,
workshop_handle: u64 = std.math.maxInt(u64),
workshop_call: u64 = 0,
workshop_state: enum { none, created, pending, ready, failed, release_failed } = .none,
workshop_requested: u32 = 0,
workshop_returned: u32 = 0,
screenshot_hook_owned: bool = false,

/// A borrowed interface. The client must remain at its original address.
pub const Lease = struct {
    context: *Context,
    generation: u64,

    /// Misuse is a programming error in every optimization mode.
    pub fn check(self: Lease) void {
        self.validate() catch |err| switch (err) {
            error.Closed => @panic("Steamworks client is closed or moved"),
            error.StaleHandle => @panic("Steamworks handle belongs to an earlier client session"),
            error.WrongThread => @panic("Steamworks calls must use the client owner thread"),
        };
    }

    fn validate(self: Lease) error{ Closed, StaleHandle, WrongThread }!void {
        try self.context.validateOwner();
        if (self.generation != self.context.generation) return error.StaleHandle;
    }

    pub fn acquireMessage(self: Lease) void {
        self.check();
        self.context.messages += 1;
    }

    pub fn releaseMessage(self: Lease) void {
        self.check();
        if (self.context.messages == 0) @panic("Steamworks message released more than once");
        self.context.messages -= 1;
    }
};

pub fn claim(self: *Context) error{AlreadyInitialized}!void {
    if (active_owner.cmpxchgStrong(0, @intFromPtr(self), .acq_rel, .acquire) != null)
        return error.AlreadyInitialized;
    self.* = .{
        .owner_thread = std.Thread.getCurrentId(),
        .generation = next_generation.fetchAdd(1, .monotonic),
    };
}

pub fn lease(self: *Context) Lease {
    return .{ .context = self, .generation = self.generation };
}

fn validateOwner(self: *const Context) error{ Closed, WrongThread }!void {
    if (active_owner.load(.acquire) != @intFromPtr(self)) return error.Closed;
    if (self.owner_thread != std.Thread.getCurrentId()) return error.WrongThread;
}

pub fn check(self: *const Context) void {
    self.validateOwner() catch |err| switch (err) {
        error.Closed => @panic("Steamworks client is closed or moved"),
        error.WrongThread => @panic("Steamworks calls must use the client owner thread"),
    };
}

fn validateClose(self: *const Context) error{ Closed, WrongThread, OutstandingMessages, OutstandingCloudBatch }!void {
    try self.validateOwner();
    if (self.messages != 0) return error.OutstandingMessages;
    if (self.cloud_batch_active != 0) return error.OutstandingCloudBatch;
}

pub fn checkCanClose(self: *const Context) void {
    self.validateClose() catch |err| switch (err) {
        error.Closed => @panic("Steamworks client is closed or moved"),
        error.WrongThread => @panic("Steamworks calls must use the client owner thread"),
        error.OutstandingMessages => @panic("Release all Steamworks messages before closing the client"),
        error.OutstandingCloudBatch => @panic("End the Steamworks cloud write batch before closing the client"),
    };
}

pub fn release(self: *Context) void {
    self.checkCanClose();
    active_owner.store(0, .release);
}

test "client ownership rejects duplicate claims and stale leases" {
    var first: Context = undefined;
    var second: Context = undefined;
    try first.claim();
    const old = first.lease();
    try std.testing.expectError(error.AlreadyInitialized, second.claim());
    try old.validate();
    first.release();
    try std.testing.expectError(error.Closed, old.validate());
    try first.claim();
    defer first.release();
    try std.testing.expectError(error.StaleHandle, old.validate());
    try first.lease().validate();
}

test "message ownership tracks independent received messages" {
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    const borrowed = context.lease();
    borrowed.acquireMessage();
    borrowed.acquireMessage();
    try std.testing.expectError(error.OutstandingMessages, context.validateClose());
    borrowed.releaseMessage();
    try std.testing.expectEqual(@as(usize, 1), context.messages);
    try std.testing.expectError(error.OutstandingMessages, context.validateClose());
    borrowed.releaseMessage();
    try std.testing.expectEqual(@as(usize, 0), context.messages);
    try context.validateClose();
}

test "cloud write-batch ownership prevents premature session release" {
    var context: Context = undefined;
    try context.claim();
    defer {
        context.cloud_batch_active = 0;
        context.release();
    }
    context.cloud_batch_active = 7;
    try std.testing.expectError(error.OutstandingCloudBatch, context.validateClose());
    context.cloud_batch_active = 0;
    try context.validateClose();
}

test "a renewed session resets optional service ownership" {
    var context: Context = undefined;
    try context.claim();
    context.keyboard_state = .gamepad;
    context.keyboard_app_id = 73;
    context.input_state = .shutdown_failed;
    context.cloud_batch_serial = 19;
    context.leaderboard_download_call = 31;
    context.leaderboard_download_blocked = true;
    context.leaderboard_upload_call = 37;
    context.voice_state = .draining;
    context.timeline_serial = 43;
    context.timeline_ranges[0] = .{ .token = 41, .handle = 0 };
    context.timeline_ranges[1] = .{ .token = 43, .handle = 47 };
    context.workshop_serial = 53;
    context.workshop_active = 53;
    context.workshop_handle = 0;
    context.workshop_call = 59;
    context.workshop_state = .pending;
    context.workshop_requested = 3;
    context.workshop_returned = 2;
    context.screenshot_hook_owned = true;
    const generation = context.generation;
    context.release();
    try context.claim();
    defer context.release();
    try std.testing.expect(context.generation != generation);
    try std.testing.expect(context.keyboard_state == .none);
    try std.testing.expectEqual(@as(u32, 0), context.keyboard_app_id);
    try std.testing.expect(context.input_state == .inactive);
    try std.testing.expectEqual(@as(u64, 0), context.cloud_batch_serial);
    try std.testing.expectEqual(@as(u64, 0), context.cloud_batch_active);
    try std.testing.expectEqual(@as(u64, 0), context.leaderboard_download_call);
    try std.testing.expect(!context.leaderboard_download_blocked);
    try std.testing.expectEqual(@as(u64, 0), context.leaderboard_upload_call);
    try std.testing.expect(context.voice_state == .inactive);
    try std.testing.expectEqual(@as(u64, 0), context.timeline_serial);
    for (context.timeline_ranges) |slot| {
        try std.testing.expectEqual(@as(u64, 0), slot.token);
        try std.testing.expectEqual(@as(u64, 0), slot.handle);
    }
    try std.testing.expectEqual(@as(u64, 0), context.workshop_serial);
    try std.testing.expectEqual(@as(u64, 0), context.workshop_active);
    try std.testing.expectEqual(std.math.maxInt(u64), context.workshop_handle);
    try std.testing.expectEqual(@as(u64, 0), context.workshop_call);
    try std.testing.expect(context.workshop_state == .none);
    try std.testing.expectEqual(@as(u32, 0), context.workshop_requested);
    try std.testing.expectEqual(@as(u32, 0), context.workshop_returned);
    try std.testing.expect(!context.screenshot_hook_owned);
}

test "copied contexts and foreign threads cannot use the active session" {
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    const moved = context;
    try std.testing.expectError(error.Closed, moved.validateOwner());
    const Probe = struct {
        fn run(borrowed: Lease, result: *?anyerror) void {
            borrowed.validate() catch |err| {
                result.* = err;
            };
        }
    };
    var result: ?anyerror = null;
    const thread = try std.Thread.spawn(.{}, Probe.run, .{ context.lease(), &result });
    thread.join();
    try std.testing.expectEqual(error.WrongThread, result.?);
    try context.lease().validate();
}
