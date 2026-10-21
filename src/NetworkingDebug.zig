//! Explicit SDK diagnostic capture, separate from Client gameplay events.
//! Valve: https://partner.steamgames.com/doc/api/ISteamNetworkingUtils#SetDebugOutputFunction
const std = @import("std");
const builtin = @import("builtin");
const Context = @import("Context.zig");
const c = @cImport({
    @cInclude("networking_debug.h");
});

/// Borrowed owner-thread facade. Client storage must remain stable and alive.
/// Process-wide diagnostics only: records have no session, start-interval or
/// connection provenance. Delayed old callbacks can appear after restart.
/// Never use this stream as gameplay events or evidence of session ownership.
/// Stop explicitly (Client shutdown also stops). Dynamic unloading is unsupported:
/// callback code, records, locks and counters must live until process exit.
pub const Capture = struct {
    lease: Context.Lease,

    pub const Level = enum(i32) {
        bug = 1,
        err = 2,
        important = 3,
        warning = 4,
        message = 5,
        verbose = 6,
        debug = 7,
        everything = 8,
        _,
    };
    pub const Record = struct {
        pub const capacity = 512;
        level: Level,
        len: usize,
        truncated: bool,
        storage: [capacity]u8,

        /// Owned raw bytes, not necessarily UTF-8. Only this prefix is meaningful.
        /// The returned slice borrows this record, not the queue or SDK message.
        pub fn bytes(self: *const Record) []const u8 {
            return self.storage[0..self.len];
        }
    };
    pub const Drain = struct {
        count: usize,
        /// A producer owns the queue; no records were copied. Do not busy-wait.
        busy: bool,
        /// Independent atomic snapshots, wrapping modulo 2^32, not lifetime totals.
        dropped_full: u32,
        dropped_contention: u32,
    };

    /// ISteamNetworkingUtils::SetDebugOutputFunction registers the private bounded
    /// sink, not a caller callback. Accepts levels 1..8; use stop, not zero, to disable.
    /// Registration has no asynchronous completion or delivery guarantee.
    pub fn start(self: Capture, level: Level) error{ AlreadyStarted, InvalidLevel, Unavailable }!void {
        self.lease.check();
        if (started) return error.AlreadyStarted;
        const raw = @intFromEnum(level);
        if (raw < 1 or raw > 8) return error.InvalidLevel;
        // Admission precedes registration so synchronous registration output is
        // captured. Failure always closes admission; persistent state is not reset.
        admission.store(1, .release);
        if (nativeStart(raw) != 1) {
            admission.store(0, .release);
            return error.Unavailable;
        }
        started = true;
        removal_pending = true;
    }

    /// Bounded, single-try queue operation. Copies at most queue capacity records
    /// into caller-owned output. Untouched output entries remain caller-owned.
    /// Records/counters persist across stop/start and may arrive after stop returns.
    pub fn drain(self: Capture, output: []Record) Drain {
        self.lease.check();
        return drainQueue(output);
    }

    /// Disable admission before native removal. Not a quiescence barrier: admitted
    /// producers may finish later. Unavailability never re-enables admission;
    /// cleanup remains pending so stop/shutdown can retry removing the callback.
    pub fn stop(self: Capture) error{Unavailable}!void {
        self.lease.check();
        if (!stopCapture()) return error.Unavailable;
    }
};

/// Internal Client hook: call after checkCanClose, before native shutdown.
/// No recoverable close failure, including when native removal is unavailable.
pub fn shutdown(lease: Context.Lease) void {
    lease.check();
    _ = stopCapture();
}

const queue_capacity = 32;
const Atomic = std.atomic.Value(u32);
var admission = Atomic.init(0);
var queue_lock = Atomic.init(0);
var dropped_full = Atomic.init(0);
var dropped_contention = Atomic.init(0);
var queue: [queue_capacity]Capture.Record = undefined;
var head: usize = 0;
var count: usize = 0;
// Only the live Client owner thread touches registration bookkeeping.
var started = false;
var removal_pending = false;

fn stopCapture() bool {
    admission.store(0, .release);
    started = false;
    if (!removal_pending) return true;
    if (nativeStop() != 1) return false;
    removal_pending = false;
    return true;
}

fn tryQueue() bool {
    return queue_lock.cmpxchgStrong(0, 1, .acquire, .monotonic) == null;
}
fn unlockQueue() void {
    queue_lock.store(0, .release);
}

// Required private bridge entry point, not a game callback. The parent root must
// analyze this module even when the consumer never references Capture.
export fn sw_networking_debug_sink(level: i32, message: ?[*]const u8) callconv(.c) void {
    if (admission.load(.acquire) == 0) return;
    if (builtin.is_test) pauseAdmittedProducer();
    enqueue(level, message);
}

fn enqueue(level: i32, message: ?[*]const u8) void {
    if (!tryQueue()) {
        _ = dropped_contention.fetchAdd(1, .monotonic);
        return;
    }
    defer unlockQueue();
    if (count == queue_capacity) {
        _ = dropped_full.fetchAdd(1, .monotonic);
        return;
    }
    const record = &queue[(head + count) % queue_capacity];
    record.level = @enumFromInt(level);
    record.len = 0;
    record.truncated = false;
    if (message) |text| {
        while (record.len < Capture.Record.capacity) : (record.len += 1) {
            const byte = text[record.len];
            if (byte == 0) break;
            record.storage[record.len] = byte;
        }
        // Exactly one extra read distinguishes exact fit from real truncation.
        if (record.len == Capture.Record.capacity)
            record.truncated = text[record.len] != 0;
    }
    count += 1;
}

fn drainQueue(output: []Capture.Record) Capture.Drain {
    var result: Capture.Drain = .{
        .count = 0,
        .busy = false,
        .dropped_full = dropped_full.load(.monotonic),
        .dropped_contention = dropped_contention.load(.monotonic),
    };
    if (output.len == 0) return result;
    if (!tryQueue()) {
        result.busy = true;
        return result;
    }
    defer unlockQueue();
    const n = @min(output.len, count);
    for (output[0..n]) |*record| {
        const source = &queue[head];
        record.level = source.level;
        record.len = source.len;
        record.truncated = source.truncated;
        @memcpy(record.storage[0..source.len], source.storage[0..source.len]);
        head = (head + 1) % queue_capacity;
    }
    count -= n;
    result.count = n;
    return result;
}

fn nativeStart(level: i32) c_int {
    if (builtin.is_test) {
        test_native.starts += 1;
        test_native.level = level;
        return if (test_native.available) 1 else 0;
    }
    return c.sw_networking_debug_start(level);
}
fn nativeStop() c_int {
    if (builtin.is_test) {
        std.debug.assert(admission.load(.acquire) == 0);
        test_native.stops += 1;
        // Simulate callback during unregister: it must not be admitted.
        sw_networking_debug_sink(4, "during removal");
        return if (test_native.available) 1 else 0;
    }
    return c.sw_networking_debug_stop();
}

const TestNative = struct { available: bool = true, starts: usize = 0, stops: usize = 0, level: i32 = 0 };
var test_native: if (builtin.is_test) TestNative else void = if (builtin.is_test) .{} else {};
const Pause = struct {
    enabled: bool = false, // Set before spawn; cleared only after join.
    entered: std.Io.Semaphore = .{},
    proceed: std.Io.Semaphore = .{},
};
var test_pause: if (builtin.is_test) Pause else void = if (builtin.is_test) .{} else {};
fn pauseAdmittedProducer() void {
    if (!test_pause.enabled) return;
    test_pause.entered.post(std.testing.io);
    test_pause.proceed.waitUncancelable(std.testing.io);
}
fn discardTestRecords() void {
    var records: [queue_capacity]Capture.Record = undefined;
    _ = drainQueue(&records);
}

test "NetworkingDebug registration validation, unavailable removal, and idempotent shutdown" {
    var context: Context = undefined;
    try context.claim();
    defer {
        test_native.available = true;
        shutdown(context.lease());
        context.release();
    }
    const capture: Capture = .{ .lease = context.lease() };
    test_native = .{};
    discardTestRecords();
    shutdown(context.lease());
    try std.testing.expectEqual(0, test_native.stops);
    try std.testing.expectError(error.InvalidLevel, capture.start(@enumFromInt(0)));
    try std.testing.expectError(error.InvalidLevel, capture.start(@enumFromInt(9)));
    try std.testing.expectEqual(0, test_native.starts);
    test_native.available = false;
    try std.testing.expectError(error.Unavailable, capture.start(.warning));
    try std.testing.expectEqual(0, admission.load(.acquire));
    test_native.available = true;
    for (1..9) |level| {
        try capture.start(@enumFromInt(level));
        try std.testing.expectEqual(@as(i32, @intCast(level)), test_native.level);
        try std.testing.expectError(error.AlreadyStarted, capture.start(.message));
        try capture.stop();
    }
    try std.testing.expectEqual(0, count);
    try capture.start(.message);
    test_native.available = false;
    try std.testing.expectError(error.Unavailable, capture.stop());
    try std.testing.expectEqual(0, admission.load(.acquire));
    shutdown(context.lease());
    try std.testing.expect(removal_pending);
    test_native.available = true;
    shutdown(context.lease());
    const stops = test_native.stops;
    shutdown(context.lease());
    try capture.stop();
    try std.testing.expectEqual(stops, test_native.stops);
}

test "NetworkingDebug FIFO, raw bytes, exact fit, bounded oversized copy and owned drain" {
    discardTestRecords();
    admission.store(1, .release);
    defer admission.store(0, .release);
    sw_networking_debug_sink(12345, "");
    sw_networking_debug_sink(-42, "raw\xff");
    var exact: [Capture.Record.capacity:0]u8 = @splat('e');
    sw_networking_debug_sink(4, &exact);
    // No terminator is readable beyond capacity+1. The callback must not scan on.
    const oversized: [Capture.Record.capacity + 1]u8 = @splat('x');
    enqueue(8, &oversized);
    var output: [5]Capture.Record = undefined;
    output[4].len = 77;
    const first = drainQueue(output[0..1]);
    try std.testing.expectEqual(1, first.count);
    try std.testing.expectEqual(12345, @intFromEnum(output[0].level));
    try std.testing.expectEqualStrings("", output[0].bytes());
    const rest = drainQueue(output[1..]);
    try std.testing.expectEqual(3, rest.count);
    try std.testing.expectEqual(-42, @intFromEnum(output[1].level));
    try std.testing.expectEqualStrings("raw\xff", output[1].bytes());
    try std.testing.expectEqualSlices(u8, &exact, output[2].bytes());
    try std.testing.expect(!output[2].truncated);
    try std.testing.expectEqualSlices(u8, oversized[0..Capture.Record.capacity], output[3].bytes());
    try std.testing.expect(output[3].truncated);
    try std.testing.expectEqual(77, output[4].len);
    @memset(&exact, 'z');
    sw_networking_debug_sink(1, "replacement");
    try std.testing.expectEqual(@as(u8, 'e'), output[2].bytes()[0]);
    discardTestRecords();
    try std.testing.expectEqual(0, drainQueue(&output).count);
}

test "NetworkingDebug full versus contention drops, bounded drain, wrapping counters" {
    discardTestRecords();
    const full_before = dropped_full.load(.monotonic);
    for (0..queue_capacity) |_| enqueue(1, "first");
    enqueue(1, "newest dropped");
    try std.testing.expectEqual(full_before +% 1, dropped_full.load(.monotonic));
    const contention_before = dropped_contention.load(.monotonic);
    var output: [queue_capacity + 1]Capture.Record = undefined;
    {
        try std.testing.expect(tryQueue());
        defer unlockQueue();
        enqueue(1, "contended");
        try std.testing.expect(drainQueue(&output).busy);
        try std.testing.expectEqual(0, drainQueue(output[0..0]).count);
    }
    try std.testing.expectEqual(contention_before +% 1, dropped_contention.load(.monotonic));
    try std.testing.expectEqual(queue_capacity, drainQueue(&output).count);
    for (output[0..queue_capacity]) |*record| try std.testing.expectEqualStrings("first", record.bytes());
    // No producers exist in this test. Demonstrate the documented counter wrap.
    const saved = dropped_contention.load(.monotonic);
    defer dropped_contention.store(saved, .monotonic);
    dropped_contention.store(std.math.maxInt(u32), .monotonic);
    {
        try std.testing.expect(tryQueue());
        defer unlockQueue();
        enqueue(1, "wrap");
    }
    try std.testing.expectEqual(0, dropped_contention.load(.monotonic));
}

test "NetworkingDebug admitted producer survives stop, client release and restart" {
    discardTestRecords();
    test_native = .{};
    var old: Context = undefined;
    try old.claim();
    var old_open = true;
    defer if (old_open) {
        shutdown(old.lease());
        old.release();
    };
    try (Capture{ .lease = old.lease() }).start(.warning);
    sw_networking_debug_sink(3, "queued before stop");
    const full_before = dropped_full.load(.monotonic);
    const contention_before = dropped_contention.load(.monotonic);
    test_pause = .{ .enabled = true };
    defer test_pause.enabled = false; // After the producer cleanup below.
    const Producer = struct {
        fn run() void {
            sw_networking_debug_sink(6, "old admitted producer");
        }
    };
    const producer = try std.Thread.spawn(.{}, Producer.run, .{});
    var joined = false;
    defer if (!joined) {
        test_pause.proceed.post(std.testing.io);
        producer.join();
    };
    test_pause.entered.waitUncancelable(std.testing.io);
    shutdown(old.lease());
    old.release();
    old_open = false;
    var next: Context = undefined;
    try next.claim();
    defer {
        shutdown(next.lease());
        next.release();
    }
    const capture: Capture = .{ .lease = next.lease() };
    try capture.start(.debug);
    test_pause.proceed.post(std.testing.io);
    producer.join();
    joined = true;
    test_pause.enabled = false;
    var output: [2]Capture.Record = undefined;
    try std.testing.expectEqual(2, capture.drain(&output).count);
    try std.testing.expectEqualStrings("queued before stop", output[0].bytes());
    try std.testing.expectEqualStrings("old admitted producer", output[1].bytes());
    try std.testing.expectEqual(full_before, dropped_full.load(.monotonic));
    try std.testing.expectEqual(contention_before, dropped_contention.load(.monotonic));
    try capture.stop();
    // Static queue/counters are not reset by either lifecycle operation.
    try std.testing.expectEqual(0, capture.drain(&output).count);
}

test "NetworkingDebug bounded concurrent producers and drainer conserve attempts" {
    discardTestRecords();
    admission.store(1, .release);
    defer admission.store(0, .release);
    const before_full = dropped_full.load(.monotonic);
    const before_contention = dropped_contention.load(.monotonic);
    const Producer = struct {
        fn run() void {
            for (0..2000) |_| sw_networking_debug_sink(4, "concurrent");
        }
    };
    var threads: [3]std.Thread = undefined;
    var spawned: usize = 0;
    var joined: usize = 0;
    defer for (threads[joined..spawned]) |thread| thread.join();
    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, Producer.run, .{});
        spawned += 1;
    }
    var drained: usize = 0;
    var output: [7]Capture.Record = undefined;
    for (0..2000) |_| {
        const result = drainQueue(&output);
        drained += result.count;
        for (output[0..result.count]) |*record| try std.testing.expectEqualStrings("concurrent", record.bytes());
    }
    while (joined < spawned) : (joined += 1) threads[joined].join();
    admission.store(0, .release);
    var remaining: [queue_capacity]Capture.Record = undefined;
    drained += drainQueue(&remaining).count;
    const full = dropped_full.load(.monotonic) -% before_full;
    const contention = dropped_contention.load(.monotonic) -% before_contention;
    try std.testing.expectEqual(6000, drained + full + contention);
}
