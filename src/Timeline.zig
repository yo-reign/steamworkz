//! Borrowed owner-thread timeline facade. Calls explicitly forward recording
//! metadata; success does not prove recorded content. Construction is inert.
//! Text borrows caller storage for each call and must be complete NUL-free UTF-8.
//! Offsets/durations are seconds; negative offsets refer to the past.
//! Valve: https://partner.steamgames.com/doc/api/ISteamTimeline
const std = @import("std");
const Context = @import("Context.zig");
const c = @import("steamworkz_c");
const native = if (@import("builtin").is_test) TestApi else c;
const Timeline = @This();

lease: Context.Lease,

pub const Mode = enum(i32) { playing = 1, staging = 2, menus = 3, loading_screen = 4, _ };
pub const ClipPriority = enum(i32) { none = 1, standard = 2, featured = 3, _ };
/// Process-lifetime content identity, not memory ownership. Zero is ordinary.
/// Removal requires a live facade; do not use identities from another process.
pub const Marker = enum(u64) { _ };
pub const Error = error{ InterfaceUnavailable, InvalidArgument, RangeCapacity, TokenExhausted, RangeClosed };
/// Fixed wrapper policy, not a native concurrency limit.
pub const range_capacity = @typeInfo(@FieldType(Context, "timeline_ranges")).array.len;
pub const max_duration: f32 = c.SW_TIMELINE_MAX_DURATION;
pub const max_priority: u32 = c.SW_TIMELINE_MAX_PRIORITY;
pub const Event = struct {
    title: [:0]const u8,
    description: [:0]const u8,
    icon: [:0]const u8,
    priority: u32,
};
/// Defaults match AddInstantaneousTimelineEvent in SDK 1.65.
pub const InstantOptions = struct {
    offset: f32 = c.SW_TIMELINE_DEFAULT_OFFSET,
    clip: ClipPriority = @fromBackingInt(@intCast(c.SW_TIMELINE_DEFAULT_CLIP)),
};
/// Defaults match AddRangeTimelineEvent in SDK 1.65.
pub const CompletedOptions = struct {
    offset: f32 = c.SW_TIMELINE_DEFAULT_OFFSET,
    duration: f32 = c.SW_TIMELINE_DEFAULT_DURATION,
    clip: ClipPriority = @fromBackingInt(@intCast(c.SW_TIMELINE_DEFAULT_CLIP)),
};
pub const UpdatePriority = union(enum) { keep_current, set: u32 };
/// All fields are required. Empty text replaces text, never means keep-current.
pub const Update = struct {
    title: [:0]const u8,
    description: [:0]const u8,
    icon: [:0]const u8,
    priority: UpdatePriority,
    clip: ClipPriority,
};

/// ISteamTimeline::SetTimelineGameMode changes the timeline's game-state presentation;
/// it does not enable recording or establish that recording is available.
pub fn setMode(self: Timeline, mode: Mode) Error!void {
    self.lease.check();
    const value = @backingInt(mode);
    if (value < 1 or value > 4) return error.InvalidArgument;
    try status(native.sw_timeline_mode(value));
}
/// ISteamTimeline::SetTimelineTooltip; description should be localized by the
/// caller. offset is finite seconds relative to now, not an absolute timestamp.
pub fn setTooltip(self: Timeline, description: [:0]const u8, offset: f32) Error!void {
    self.lease.check();
    try text(description);
    try finite(offset);
    try status(native.sw_timeline_tooltip(description.ptr, offset));
}
/// ISteamTimeline::ClearTimelineTooltip at an offset in seconds relative to now.
pub fn clearTooltip(self: Timeline, offset: f32) Error!void {
    self.lease.check();
    try finite(offset);
    try status(native.sw_timeline_clear_tooltip(offset));
}
/// ISteamTimeline::AddInstantaneousTimelineEvent adds a closed marker. The returned
/// identity has no memory-release obligation; remove explicitly deletes content.
pub fn instant(self: Timeline, event: Event, options: InstantOptions) Error!Marker {
    self.lease.check();
    try validEvent(event);
    try finite(options.offset);
    try validClip(options.clip);
    var handle: u64 = 0;
    try status(native.sw_timeline_instant(event.title.ptr, event.description.ptr, event.icon.ptr, event.priority, options.offset, @backingInt(options.clip), &handle));
    return @fromBackingInt(@intCast(handle));
}
/// ISteamTimeline::AddRangeTimelineEvent adds an already-completed range;
/// duration is 0..max_duration seconds. Unlike start, this creates no open owner.
pub fn completed(self: Timeline, event: Event, options: CompletedOptions) Error!Marker {
    self.lease.check();
    try validEvent(event);
    try finite(options.offset);
    try finite(options.duration);
    if (options.duration < 0 or options.duration > max_duration) return error.InvalidArgument;
    try validClip(options.clip);
    var handle: u64 = 0;
    try status(native.sw_timeline_completed(event.title.ptr, event.description.ptr, event.icon.ptr, event.priority, options.offset, options.duration, @backingInt(options.clip), &handle));
    return @fromBackingInt(@intCast(handle));
}
/// ISteamTimeline::StartRangeTimelineEvent; offset is seconds relative to now.
/// Start has no defaults. End or cancel each acquired range. Callers own timing:
/// SDK range duration is limited to 600 seconds; no elapsed clock is maintained.
pub fn start(self: Timeline, event: Event, offset: f32, clip: ClipPriority) Error!Range {
    self.lease.check();
    try validEvent(event);
    try finite(offset);
    try validClip(clip);
    const context = self.lease.context;
    if (context.timeline_serial == std.math.maxInt(u64)) return error.TokenExhausted;
    for (&context.timeline_ranges) |*slot| {
        if (slot.token != 0) continue;
        var handle: u64 = 0;
        try status(native.sw_timeline_start(event.title.ptr, event.description.ptr, event.icon.ptr, event.priority, offset, @backingInt(clip), &handle));
        context.timeline_serial += 1;
        slot.* = .{ .token = context.timeline_serial, .handle = handle };
        return .{ .lease = self.lease, .token = slot.token };
    }
    return error.RangeCapacity;
}
/// Deletes closed marker content, not native memory. Repeated removal forwards
/// again; closed markers are identities, not tracked owners.
pub fn remove(self: Timeline, marker: Marker) Error!void {
    self.lease.check();
    try status(native.sw_timeline_remove(@backingInt(marker)));
}

/// Token-checked open range owner. Copies alias the same Context slot; after
/// consumption every copy is closed. Missing interfaces preserve retry ownership.
pub const Range = struct {
    lease: Context.Lease,
    token: u64,

    pub fn update(self: Range, value: Update) Error!void {
        self.lease.check();
        const slot = try self.slotIndex();
        try text(value.title);
        try text(value.description);
        try text(value.icon);
        try validClip(value.clip);
        const priority: u32 = switch (value.priority) {
            .keep_current => c.SW_TIMELINE_KEEP_PRIORITY,
            .set => |p| blk: {
                try validPriority(p);
                break :blk p;
            },
        };
        try status(native.sw_timeline_update(self.lease.context.timeline_ranges[slot].handle, value.title.ptr, value.description.ptr, value.icon.ptr, priority, @backingInt(value.clip)));
    }
    /// ISteamTimeline::EndRangeTimelineEvent consumes this open owner and returns
    /// a closed marker. offset is seconds relative to now; negative finite values
    /// are allowed. No implicit elapsed-time tracking or default offset.
    pub fn end(self: Range, offset: f32) Error!Marker {
        self.lease.check();
        const index = try self.slotIndex();
        try finite(offset);
        const slot = &self.lease.context.timeline_ranges[index];
        try status(native.sw_timeline_end(slot.handle, offset));
        const marker: Marker = @fromBackingInt(@intCast(slot.handle));
        slot.* = .{};
        return marker;
    }
    /// ISteamTimeline::RemoveTimelineEvent deletes this open range rather than
    /// completing it. Successful forwarding consumes all copies of the owner.
    pub fn cancel(self: Range) Error!void {
        self.lease.check();
        const index = try self.slotIndex();
        const slot = &self.lease.context.timeline_ranges[index];
        try status(native.sw_timeline_remove(slot.handle));
        slot.* = .{};
    }
    fn slotIndex(self: Range) Error!usize {
        if (self.token != 0) {
            for (self.lease.context.timeline_ranges, 0..) |slot, i| {
                if (slot.token == self.token) return i;
            }
        }
        return error.RangeClosed;
    }
};

/// Client teardown hook, before native shutdown while the lease is live.
/// Best-effort cancellation of open wrapper ranges only; never auto-End.
/// Unavailable interfaces prevent cancellation. Slots are cleared for imminent
/// session shutdown, not as proof of deletion. Unused sessions access nothing.
pub fn shutdown(lease: Context.Lease) void {
    lease.check();
    for (&lease.context.timeline_ranges) |*slot| {
        if (slot.token == 0) continue;
        _ = native.sw_timeline_remove(slot.handle);
        slot.* = .{};
    }
}
fn status(value: i32) Error!void {
    if (value == -1) return error.InterfaceUnavailable;
    if (value != 0) unreachable;
}
fn text(value: [:0]const u8) Error!void {
    if (std.mem.indexOfScalar(u8, value, 0) != null or !std.unicode.utf8ValidateSlice(value)) return error.InvalidArgument;
}
fn finite(value: f32) Error!void {
    if (!std.math.isFinite(value)) return error.InvalidArgument;
}
fn validPriority(value: u32) Error!void {
    if (value > max_priority) return error.InvalidArgument;
}
fn validClip(value: ClipPriority) Error!void {
    const n = @backingInt(value);
    if (n < 1 or n > 3) return error.InvalidArgument;
}
fn validEvent(value: Event) Error!void {
    try text(value.title);
    try text(value.description);
    try text(value.icon);
    try validPriority(value.priority);
}

const TestApi = struct {
    var available = true;
    var calls: usize = 0;
    var accessors: usize = 0;
    var ends: usize = 0;
    var removes: usize = 0;
    var next_handle: u64 = 0;
    var last_handle: u64 = 0;
    var priority: u32 = 0;
    var offset: f32 = 0;
    var duration: f32 = 0;
    var clip: i32 = 0;
    fn reset() void {
        available = true;
        calls = 0;
        accessors = 0;
        ends = 0;
        removes = 0;
        next_handle = 0;
    }
    fn forward() i32 {
        accessors += 1;
        if (!available) return -1;
        calls += 1;
        return 0;
    }
    fn sw_timeline_mode(_: i32) i32 {
        return forward();
    }
    fn sw_timeline_tooltip(_: [*:0]const u8, o: f32) i32 {
        offset = o;
        return forward();
    }
    fn sw_timeline_clear_tooltip(o: f32) i32 {
        offset = o;
        return forward();
    }
    fn sw_timeline_instant(_: [*:0]const u8, _: [*:0]const u8, _: [*:0]const u8, p: u32, o: f32, cl: i32, out: *u64) i32 {
        const result = forward();
        if (result != 0) return result;
        priority = p;
        offset = o;
        clip = cl;
        out.* = next_handle;
        return 0;
    }
    fn sw_timeline_completed(t: [*:0]const u8, d: [*:0]const u8, i: [*:0]const u8, p: u32, o: f32, dur: f32, cl: i32, out: *u64) i32 {
        duration = dur;
        return sw_timeline_instant(t, d, i, p, o, cl, out);
    }
    const sw_timeline_start = sw_timeline_instant;
    fn sw_timeline_update(h: u64, _: [*:0]const u8, _: [*:0]const u8, _: [*:0]const u8, p: u32, cl: i32) i32 {
        const result = forward();
        if (result != 0) return result;
        last_handle = h;
        priority = p;
        clip = cl;
        return 0;
    }
    fn sw_timeline_end(h: u64, o: f32) i32 {
        const result = forward();
        if (result != 0) return result;
        last_handle = h;
        offset = o;
        ends += 1;
        return 0;
    }
    fn sw_timeline_remove(h: u64) i32 {
        const result = forward();
        if (result != 0) return result;
        last_handle = h;
        removes += 1;
        return 0;
    }
};
const empty_event: Event = .{ .title = "", .description = "", .icon = "", .priority = 0 };
const empty_update: Update = .{ .title = "", .description = "", .icon = "", .priority = .keep_current, .clip = .none };
fn testCleanup(context: *Context) void {
    TestApi.available = true;
    shutdown(context.lease());
    context.release();
}

test "Timeline defaults, zero markers and explicit facade operations" {
    var context: Context = undefined;
    try context.claim();
    defer testCleanup(&context);
    TestApi.reset();
    const timeline: Timeline = .{ .lease = context.lease() };
    try timeline.setMode(.playing);
    try timeline.setTooltip("", -3);
    try timeline.clearTooltip(-2);
    const marker = try timeline.instant(empty_event, .{});
    try std.testing.expectEqual(@as(u64, 0), @backingInt(marker));
    try std.testing.expectEqual(@as(f32, 0), TestApi.offset);
    try std.testing.expectEqual(@as(i32, c.SW_TIMELINE_DEFAULT_CLIP), TestApi.clip);
    _ = try timeline.completed(empty_event, .{});
    try std.testing.expectEqual(@as(f32, 0), TestApi.duration);
    try timeline.remove(marker);
    try std.testing.expectEqual(@as(usize, 1), TestApi.removes);
}

test "Timeline finite offsets, duration boundaries, enums, priority and complete text" {
    var context: Context = undefined;
    try context.claim();
    defer testCleanup(&context);
    TestApi.reset();
    const timeline: Timeline = .{ .lease = context.lease() };
    for ([_]f32{ std.math.nan(f32), std.math.inf(f32), -std.math.inf(f32) }) |bad| {
        try std.testing.expectError(error.InvalidArgument, timeline.instant(empty_event, .{ .offset = bad }));
        try std.testing.expectError(error.InvalidArgument, timeline.completed(empty_event, .{ .duration = bad }));
        try std.testing.expectError(error.InvalidArgument, timeline.setTooltip("", bad));
        try std.testing.expectError(error.InvalidArgument, timeline.clearTooltip(bad));
        try std.testing.expectError(error.InvalidArgument, timeline.start(empty_event, bad, .none));
    }
    for ([_]f32{ -0.001, 600.001 }) |bad| try std.testing.expectError(error.InvalidArgument, timeline.completed(empty_event, .{ .duration = bad }));
    for ([_]i32{ 0, -1, 5, std.math.maxInt(i32) }) |bad| try std.testing.expectError(error.InvalidArgument, timeline.setMode(@fromBackingInt(@intCast(bad))));
    for ([_]i32{ 0, -1, 4, std.math.maxInt(i32) }) |bad| try std.testing.expectError(error.InvalidArgument, timeline.instant(empty_event, .{ .clip = @fromBackingInt(@intCast(bad)) }));
    for ([_]u32{ 1001, c.SW_TIMELINE_KEEP_PRIORITY, std.math.maxInt(u32) }) |bad| {
        var event = empty_event;
        event.priority = bad;
        try std.testing.expectError(error.InvalidArgument, timeline.start(event, 0, .none));
        try std.testing.expectError(error.InvalidArgument, timeline.instant(event, .{}));
    }
    for ([_][:0]const u8{ "a\x00b", "\xff", "\xe2\x82" }) |bad| {
        var event = empty_event;
        event.title = bad;
        try std.testing.expectError(error.InvalidArgument, timeline.instant(event, .{}));
        event = empty_event;
        event.description = bad;
        try std.testing.expectError(error.InvalidArgument, timeline.completed(event, .{}));
        event = empty_event;
        event.icon = bad;
        try std.testing.expectError(error.InvalidArgument, timeline.start(event, 0, .none));
        try std.testing.expectError(error.InvalidArgument, timeline.setTooltip(bad, 0));
    }
    try std.testing.expectEqual(@as(usize, 0), TestApi.accessors);
    var event = empty_event;
    event.priority = max_priority;
    event.title = "日本語";
    _ = try timeline.completed(event, .{ .offset = -12, .duration = max_duration, .clip = .featured });
    _ = try timeline.completed(empty_event, .{ .duration = 0 });
    _ = try timeline.instant(event, .{ .offset = -1 });
    try std.testing.expectEqual(@as(f32, -1), TestApi.offset);
}

test "Timeline range copies cannot affect consumed or replacement owners" {
    var context: Context = undefined;
    try context.claim();
    defer testCleanup(&context);
    TestApi.reset();
    const timeline: Timeline = .{ .lease = context.lease() };
    const first = try timeline.start(empty_event, -1, .none);
    const copy = first;
    try first.update(empty_update);
    try std.testing.expectEqual(@as(u32, c.SW_TIMELINE_KEEP_PRIORITY), TestApi.priority);
    try std.testing.expectEqual(@as(u64, 0), context.timeline_ranges[0].handle);
    try std.testing.expect(context.timeline_ranges[0].token != 0);
    var update = empty_update;
    update.priority = .{ .set = max_priority };
    try copy.update(update);
    update.priority = .{ .set = c.SW_TIMELINE_KEEP_PRIORITY };
    try std.testing.expectError(error.InvalidArgument, first.update(update));
    update = empty_update;
    update.title = "\xff";
    try std.testing.expectError(error.InvalidArgument, first.update(update));
    update = empty_update;
    update.description = "x\x00y";
    try std.testing.expectError(error.InvalidArgument, first.update(update));
    update = empty_update;
    update.icon = "\xff";
    try std.testing.expectError(error.InvalidArgument, first.update(update));
    update = empty_update;
    update.clip = @fromBackingInt(@intCast(0));
    try std.testing.expectError(error.InvalidArgument, first.update(update));
    try std.testing.expectError(error.InvalidArgument, first.end(std.math.nan(f32)));
    const marker = try copy.end(-2);
    try std.testing.expectEqual(@as(u64, 0), @backingInt(marker));
    const replacement = try timeline.start(empty_event, 0, .none);
    try std.testing.expect(replacement.token != first.token);
    const before = TestApi.calls;
    try std.testing.expectError(error.RangeClosed, first.update(empty_update));
    try std.testing.expectError(error.RangeClosed, first.end(0));
    try std.testing.expectError(error.RangeClosed, first.cancel());
    try std.testing.expectEqual(before, TestApi.calls);
    try replacement.cancel();
    try std.testing.expectError(error.RangeClosed, replacement.cancel());
    try std.testing.expectError(error.RangeClosed, replacement.update(empty_update));
    try std.testing.expectError(error.RangeClosed, replacement.end(0));
    try std.testing.expectEqual(@as(usize, 1), TestApi.ends);
    try std.testing.expectEqual(@as(usize, 1), TestApi.removes);
}

test "Timeline unavailable acquisition and cleanup preserve authoritative slots" {
    var context: Context = undefined;
    try context.claim();
    defer testCleanup(&context);
    TestApi.reset();
    const timeline: Timeline = .{ .lease = context.lease() };
    TestApi.available = false;
    try std.testing.expectError(error.InterfaceUnavailable, timeline.start(empty_event, 0, .none));
    try std.testing.expectEqual(@as(u64, 0), context.timeline_serial);
    try std.testing.expectEqual(@as(u64, 0), context.timeline_ranges[0].token);
    TestApi.available = true;
    const range = try timeline.start(empty_event, 0, .none);
    TestApi.available = false;
    try std.testing.expectError(error.InterfaceUnavailable, range.update(empty_update));
    try std.testing.expectError(error.InterfaceUnavailable, range.end(0));
    try std.testing.expectError(error.InterfaceUnavailable, range.cancel());
    try std.testing.expectEqual(range.token, context.timeline_ranges[0].token);
    TestApi.available = true;
    try range.cancel();
    try std.testing.expectEqual(@as(usize, 1), TestApi.removes);
}

test "Timeline capacity and nonwrapping serial are checked before native acquisition" {
    var context: Context = undefined;
    try context.claim();
    defer testCleanup(&context);
    TestApi.reset();
    const timeline: Timeline = .{ .lease = context.lease() };
    var owners: [range_capacity]Range = undefined;
    for (&owners) |*owner| owner.* = try timeline.start(empty_event, 0, .none);
    const before = TestApi.accessors;
    try std.testing.expectError(error.RangeCapacity, timeline.start(empty_event, 0, .none));
    try std.testing.expectEqual(before, TestApi.accessors);
    try owners[0].cancel();
    _ = try timeline.start(empty_event, 0, .none);
    shutdown(context.lease());
    context.timeline_serial = std.math.maxInt(u64) - 1;
    const last = try timeline.start(empty_event, 0, .none);
    try std.testing.expectEqual(std.math.maxInt(u64), last.token);
    try last.cancel();
    const exhausted_before = TestApi.accessors;
    try std.testing.expectError(error.TokenExhausted, timeline.start(empty_event, 0, .none));
    try std.testing.expectEqual(exhausted_before, TestApi.accessors);
}

test "Timeline shutdown cancels only open ranges once and permits later Context acquisition" {
    var context: Context = undefined;
    {
        try context.claim();
        defer testCleanup(&context);
        TestApi.reset();
        const timeline: Timeline = .{ .lease = context.lease() };
        shutdown(context.lease());
        try std.testing.expectEqual(@as(usize, 0), TestApi.accessors);
        _ = try timeline.instant(empty_event, .{});
        _ = try timeline.completed(empty_event, .{});
        const closed = try timeline.start(empty_event, 0, .none);
        _ = try closed.end(0);
        _ = try timeline.start(empty_event, 0, .none);
        _ = try timeline.start(empty_event, 0, .none);
        shutdown(context.lease());
        try std.testing.expectEqual(@as(usize, 2), TestApi.removes);
        try std.testing.expectEqual(@as(usize, 1), TestApi.ends);
        const after = TestApi.accessors;
        shutdown(context.lease());
        try std.testing.expectEqual(after, TestApi.accessors);
        const missing = try timeline.start(empty_event, 0, .none);
        TestApi.available = false;
        shutdown(context.lease());
        try std.testing.expectEqual(@as(usize, 2), TestApi.removes);
        try std.testing.expectError(error.RangeClosed, missing.cancel());
    }
    try context.claim();
    defer testCleanup(&context);
    try std.testing.expectEqual(@as(u64, 0), context.timeline_serial);
}
