//! Borrowed owner-thread Workshop access. No automatic queries or downloads.
//! One query per session is wrapper policy. Query copies share Context ownership;
//! acquire, install cleanup, then send. Pending queries cannot be cancelled here.
//! Valve: https://partner.steamgames.com/doc/api/ISteamUGC
const std = @import("std");
const Context = @import("Context.zig");
const types = @import("types.zig");
const events = @import("events.zig");
const requests = @import("requests.zig");
const c = @import("steamworkz_c");
const native = if (@import("builtin").is_test) TestApi else c;
const Workshop = @This();

lease: Context.Lease,

pub const Error = error{ InterfaceUnavailable, InvalidArgument, MalformedCount, UnterminatedPath, QueryBusy, TokenExhausted, QueryRejected, StaleQuery, QueryAlreadySent, RequestRejected, QueryNotReady, IndexOutOfBounds, QueryPending, ReleaseFailed };
pub const QueryState = @FieldType(Context, "workshop_state");
pub const FileType = enum(i32) {
    community = 0,
    _,
};
pub const Visibility = enum(i32) {
    public = 0,
    friends_only = 1,
    private = 2,
    unlisted = 3,
    _,
};

/// Entirely owned row. Description can be abbreviated by Steam; no long-description
/// query option is enabled. Text accessors return bounded bytes, not guaranteed UTF-8.
pub const Details = struct {
    item: types.WorkshopItem,
    result: types.Result,
    file_type: FileType,
    creator_app: u32,
    consumer_app: u32,
    title: [129]u8,
    description: [8000]u8,
    owner: types.SteamId,
    created: u32,
    updated: u32,
    added_to_list: u32,
    visibility: Visibility,
    banned: bool,
    accepted_for_use: bool,
    tags_truncated: bool,
    tags: [1025]u8,
    file: u64,
    preview_file: u64,
    filename: [260]u8,
    file_size: i32,
    preview_file_size: i32,
    url: [256]u8,
    votes_up: u32,
    votes_down: u32,
    score: f32,
    children: u32,
    total_files_size: u64,

    pub fn titleText(self: *const Details) []const u8 {
        return text(&self.title);
    }
    pub fn descriptionText(self: *const Details) []const u8 {
        return text(&self.description);
    }
    pub fn tagsText(self: *const Details) []const u8 {
        return text(&self.tags);
    }
    pub fn filenameText(self: *const Details) []const u8 {
        return text(&self.filename);
    }
    pub fn urlText(self: *const Details) []const u8 {
        return text(&self.url);
    }
};

/// A token-checked resource, not a native handle supplied by a completion event.
/// Release created/ready/failed owners explicitly. Pending/uncertain owners need
/// session shutdown as the final recovery boundary, not query cancellation.
pub const Query = struct {
    lease: Context.Lease,
    token: u64,

    fn context(self: Query) Error!*Context {
        self.lease.check();
        const ctx = self.lease.context;
        if (self.token == 0 or ctx.workshop_active != self.token) return error.StaleQuery;
        return ctx;
    }
    /// Wrapper lifecycle updated by Client dispatch, not a native status query.
    pub fn state(self: Query) Error!QueryState {
        return (try self.context()).workshop_state;
    }
    /// Borrowed identity for correlation, not an ownership transfer. Release the
    /// Query owner, never attempt cleanup through a completion's bare handle.
    pub fn handle(self: Query) Error!types.WorkshopQuery {
        return @fromBackingInt(@intCast((try self.context()).workshop_handle));
    }
    /// Null until successful query completion. Zero is a valid ready count.
    pub fn resultCount(self: Query) Error!?u32 {
        const ctx = try self.context();
        return if (ctx.workshop_state == .ready) ctx.workshop_returned else null;
    }
    /// ISteamUGC::SendQueryUGCRequest. Pump/poll Client even if the Request is
    /// discarded, so query ownership can leave pending. Take SteamUGCQueryCompleted_t
    /// (workshop_query_completed), check result == .ok, then read ready rows and
    /// release. Successful retrieval does not imply every Details.result is .ok.
    pub fn send(self: Query) Error!requests.Request(.workshop_query_completed) {
        const ctx = try self.context();
        if (ctx.workshop_state != .created) return error.QueryAlreadySent;
        var call: u64 = 0;
        try status(native.sw_workshop_send(ctx.workshop_handle, &call));
        if (call == 0) {
            ctx.workshop_state = .failed;
            return error.RequestRejected;
        }
        ctx.workshop_call = call;
        ctx.workshop_state = .pending;
        return requests.Request(.workshop_query_completed).init(@fromBackingInt(@intCast(call)));
    }
    /// Getter bool, per-row result, and query completion result are independent.
    /// False leaves caller storage unchanged. Successful rows survive release.
    pub fn read(self: Query, index: u32, out: *Details) Error!bool {
        const ctx = try self.context();
        if (ctx.workshop_state != .ready) return error.QueryNotReady;
        if (index >= ctx.workshop_returned) return error.IndexOutOfBounds;
        var value: c.struct_sw_workshop_details = std.mem.zeroes(c.struct_sw_workshop_details);
        var found = false;
        try status(native.sw_workshop_details(ctx.workshop_handle, index, &value, &found));
        if (found) out.* = copyDetails(&value);
        return found;
    }
    /// True consumes ownership. Unexpected native false poisons release for this
    /// session; do not retry it. Missing interface preserves explicit retryability.
    pub fn release(self: Query) Error!bool {
        const ctx = try self.context();
        switch (ctx.workshop_state) {
            .pending => return error.QueryPending,
            .release_failed => return error.ReleaseFailed,
            .created, .ready, .failed => {},
            .none => return error.StaleQuery,
        }
        var accepted = false;
        try status(native.sw_workshop_release(ctx.workshop_handle, &accepted));
        if (accepted) clear(ctx) else ctx.workshop_state = .release_failed;
        return accepted;
    }
};

/// ISteamUGC::CreateQueryUGCDetailsRequest creates an unsent Query owner.
/// 1..50 is a wrapper bound, not Steam's native limit. IDs retain input order,
/// duplicates and invalid identities for native per-item result reporting.
pub fn createDetailsQuery(self: Workshop, items: []const types.WorkshopItem) Error!Query {
    self.lease.check();
    const ctx = self.lease.context;
    if (ctx.workshop_active != 0) return error.QueryBusy;
    if (items.len == 0 or items.len > 50) return error.InvalidArgument;
    if (ctx.workshop_serial == std.math.maxInt(u64)) return error.TokenExhausted;
    var ids: [50]u64 = undefined;
    for (items, 0..) |item, i| ids[i] = @backingInt(item);
    var handle: u64 = std.math.maxInt(u64);
    try status(native.sw_workshop_create(&ids, items.len, &handle));
    if (handle == std.math.maxInt(u64)) return error.QueryRejected;
    ctx.workshop_serial += 1;
    ctx.workshop_active = ctx.workshop_serial;
    ctx.workshop_handle = handle;
    ctx.workshop_call = 0;
    ctx.workshop_state = .created;
    ctx.workshop_requested = @intCast(items.len);
    ctx.workshop_returned = 0;
    return .{ .lease = self.lease, .token = ctx.workshop_active };
}

/// Internal Client-only dispatch hook: called after decoding EVERY owned event,
/// before returning/discarding it. Gameplay code must not invoke it to fabricate
/// readiness. No pumping/session acquisition; a matching terminal failure is final.
pub fn observeCompletion(lease: Context.Lease, event: *const events.Event) void {
    lease.check();
    const ctx = lease.context;
    if (ctx.workshop_state != .pending or ctx.workshop_call == 0 or @backingInt(event.call) != ctx.workshop_call) return;
    ctx.workshop_call = 0;
    ctx.workshop_state = .failed;
    switch (event.payload) {
        .workshop_query_completed => |value| {
            if (@backingInt(value.query) != ctx.workshop_handle or value.result != .ok or value.returned > ctx.workshop_requested) return;
            ctx.workshop_returned = value.returned;
            ctx.workshop_state = .ready;
        },
        else => {},
    }
}

/// Internal Client-only final escape before native shutdown and Context release. One
/// best-effort release for created/ready/failed, none for pending/release_failed.
/// Clears wrapper ownership; does not claim cancellation or successful cleanup.
pub fn shutdown(lease: Context.Lease) void {
    lease.check();
    const ctx = lease.context;
    switch (ctx.workshop_state) {
        .created, .ready, .failed => {
            var accepted = false;
            _ = native.sw_workshop_release(ctx.workshop_handle, &accepted);
        },
        .none, .pending, .release_failed => {},
    }
    clear(ctx);
}

pub const SubscriptionOptions = struct { include_locally_disabled: bool = false };
pub const Subscriptions = struct { reported: u32, items: []const types.WorkshopItem };
pub fn subscriptionCount(self: Workshop, options: SubscriptionOptions) Error!u32 {
    self.lease.check();
    var count: u32 = 0;
    try status(native.sw_workshop_count(options.include_locally_disabled, &count));
    return count;
}
/// At most 1024 caller entries. Not an atomic snapshot with subscriptionCount.
/// Returned prefix borrows destination, not SDK memory. Malformed counts publish
/// no prefix and leave destination unchanged. Empty storage avoids native access.
pub fn subscriptions(self: Workshop, destination: []types.WorkshopItem, options: SubscriptionOptions) Error!Subscriptions {
    self.lease.check();
    if (destination.len > 1024) return error.InvalidArgument;
    if (destination.len == 0) return .{ .reported = 0, .items = destination };
    var ids: [1024]u64 = undefined;
    var count: u32 = 0;
    try status(native.sw_workshop_subscriptions(options.include_locally_disabled, &ids, destination.len, &count));
    if (count > destination.len) return error.MalformedCount;
    for (destination[0..count], 0..) |*item, i| item.* = @fromBackingInt(@intCast(ids[i]));
    return .{ .reported = count, .items = destination[0..count] };
}
/// All EItemState bits are retained, including unknown future bits.
pub fn itemState(self: Workshop, item: types.WorkshopItem) Error!u32 {
    self.lease.check();
    var flags: u32 = 0;
    try status(native.sw_workshop_state(@backingInt(item), &flags));
    return flags;
}
pub const InstallInfo = struct { found: bool, size: u64, timestamp: u32, path: ?[]const u8 };
/// Path borrows caller storage and can name a legacy FILE, not a directory.
/// Native false may mutate storage and publishes no valid path. Never opens it.
pub fn installInfo(self: Workshop, item: types.WorkshopItem, path: []u8) Error!InstallInfo {
    self.lease.check();
    if (path.len == 0 or path.len > std.math.maxInt(u32)) return error.InvalidArgument;
    var found = false;
    var size: u64 = 0;
    var timestamp: u32 = 0;
    var length: usize = 0;
    try status(native.sw_workshop_install(@backingInt(item), path.ptr, path.len, &found, &size, &timestamp, &length));
    if (found and (length >= path.len or path[length] != 0)) return error.UnterminatedPath;
    return .{ .found = found, .size = size, .timestamp = timestamp, .path = if (found) path[0..length] else null };
}
pub const DownloadProgress = struct { found: bool, downloaded: u64, total: u64 };
/// ISteamUGC::GetItemDownloadInfo; downloaded/total are bytes. Zero total does
/// not imply completion; counts are preserved even on false.
pub fn downloadProgress(self: Workshop, item: types.WorkshopItem) Error!DownloadProgress {
    self.lease.check();
    var value: DownloadProgress = .{ .found = false, .downloaded = 0, .total = 0 };
    try status(native.sw_workshop_progress(@backingInt(item), &value.found, &value.downloaded, &value.total));
    return value;
}
pub const DownloadOptions = struct { high_priority: bool = false };
/// ISteamUGC::DownloadItem explicitly starts a download. True means wait for
/// workshop_downloaded (DownloadItemResult_t) and inspect result; stop using
/// existing item files until then. That event
/// identifies app/item, NOT a unique request. False priority is wrapper policy.
pub fn downloadItem(self: Workshop, item: types.WorkshopItem, options: DownloadOptions) Error!bool {
    self.lease.check();
    var accepted = false;
    try status(native.sw_workshop_download(@backingInt(item), options.high_priority, &accepted));
    return accepted;
}

fn clear(ctx: *Context) void {
    ctx.workshop_active = 0;
    ctx.workshop_handle = std.math.maxInt(u64);
    ctx.workshop_call = 0;
    ctx.workshop_state = .none;
    ctx.workshop_requested = 0;
    ctx.workshop_returned = 0;
}
fn status(value: i32) Error!void {
    return switch (value) {
        0 => {},
        -1 => error.InterfaceUnavailable,
        -2 => error.InvalidArgument,
        -3 => error.MalformedCount,
        -4 => error.UnterminatedPath,
        else => unreachable,
    };
}
fn text(bytes: []const u8) []const u8 {
    return bytes[0 .. std.mem.indexOfScalar(u8, bytes, 0) orelse bytes.len];
}
fn copyDetails(value: *const c.struct_sw_workshop_details) Details {
    return .{
        .item = @fromBackingInt(@intCast(value.item)),
        .result = @fromBackingInt(@intCast(value.result)),
        .file_type = @fromBackingInt(@intCast(value.file_type)),
        .creator_app = value.creator_app,
        .consumer_app = value.consumer_app,
        .title = @bitCast(value.title),
        .description = @bitCast(value.description),
        .owner = @fromBackingInt(@intCast(value.owner)),
        .created = value.created,
        .updated = value.updated,
        .added_to_list = value.added_to_list,
        .visibility = @fromBackingInt(@intCast(value.visibility)),
        .banned = value.banned,
        .accepted_for_use = value.accepted_for_use,
        .tags_truncated = value.tags_truncated,
        .tags = @bitCast(value.tags),
        .file = value.file,
        .preview_file = value.preview_file,
        .filename = @bitCast(value.filename),
        .file_size = value.file_size,
        .preview_file_size = value.preview_file_size,
        .url = @bitCast(value.url),
        .votes_up = value.votes_up,
        .votes_down = value.votes_down,
        .score = value.score,
        .children = value.children,
        .total_files_size = value.total_files_size,
    };
}

const TestApi = struct {
    var available = true;
    var accepted = true;
    var handle: u64 = 0;
    var call: u64 = 71;
    var calls: usize = 0;
    var releases: usize = 0;
    var last_handle: u64 = 99;
    var ids: [50]u64 = @splat(0);
    var count: u32 = 3;
    var disabled = true;
    var priority = true;
    var scratch: c.struct_sw_workshop_details = std.mem.zeroes(c.struct_sw_workshop_details);
    fn reset() void {
        available = true;
        accepted = true;
        handle = 0;
        call = 71;
        calls = 0;
        releases = 0;
        last_handle = 99;
        count = 3;
        disabled = true;
        priority = true;
        scratch = std.mem.zeroes(c.struct_sw_workshop_details);
    }
    fn invoke() bool {
        if (!available) return false;
        calls += 1;
        return true;
    }
    fn sw_workshop_create(input: [*]const u64, n: usize, out: *u64) i32 {
        if (!invoke()) return -1;
        @memcpy(ids[0..n], input[0..n]);
        out.* = handle;
        return 0;
    }
    fn sw_workshop_send(h: u64, out: *u64) i32 {
        if (!invoke()) return -1;
        last_handle = h;
        out.* = call;
        return 0;
    }
    fn sw_workshop_release(h: u64, out: *bool) i32 {
        if (!invoke()) return -1;
        releases += 1;
        last_handle = h;
        out.* = accepted;
        return 0;
    }
    fn sw_workshop_details(h: u64, _: u32, out: *c.struct_sw_workshop_details, found: *bool) i32 {
        if (!invoke()) return -1;
        last_handle = h;
        out.* = scratch;
        found.* = accepted;
        return 0;
    }
    fn sw_workshop_count(include: bool, out: *u32) i32 {
        if (!invoke()) return -1;
        disabled = include;
        out.* = count;
        return 0;
    }
    fn sw_workshop_subscriptions(include: bool, out: [*]u64, capacity: usize, n: *u32) i32 {
        if (!invoke()) return -1;
        disabled = include;
        n.* = count;
        for (out[0..capacity], 0..) |*id, i| id.* = if (i % 2 == 0) 17 else 0;
        return 0;
    }
    fn sw_workshop_state(_: u64, out: *u32) i32 {
        if (!invoke()) return -1;
        out.* = 0x80000045;
        return 0;
    }
    fn sw_workshop_install(_: u64, out: [*]u8, capacity: usize, found: *bool, size: *u64, timestamp: *u32, length: *usize) i32 {
        if (!invoke()) return -1;
        @memset(out[0..capacity], 'x');
        found.* = accepted;
        size.* = std.math.maxInt(u64);
        timestamp.* = 31;
        length.* = capacity - 1;
        if (accepted and capacity > 1) out[capacity - 1] = 0;
        return 0;
    }
    fn sw_workshop_progress(_: u64, found: *bool, downloaded: *u64, total: *u64) i32 {
        if (!invoke()) return -1;
        found.* = accepted;
        downloaded.* = 99;
        total.* = 0;
        return 0;
    }
    fn sw_workshop_download(_: u64, high: bool, out: *bool) i32 {
        if (!invoke()) return -1;
        priority = high;
        out.* = accepted;
        return 0;
    }
};
const test_items = [_]types.WorkshopItem{ @fromBackingInt(@intCast(17)), @fromBackingInt(@intCast(0)), @fromBackingInt(@intCast(17)) };
fn completion(call: u64, handle: u64, result: types.Result, returned: u32) events.Event {
    return .{ .call = @fromBackingInt(@intCast(call)), .callback_id = 3401, .payload = .{ .workshop_query_completed = .{
        .query = @fromBackingInt(@intCast(handle)),
        .result = result,
        .returned = returned,
        .total = 100,
        .cached = true,
        .cursor = @splat(0),
    } } };
}

test "Workshop acquisition validates bounds, native sentinel, zero handle and nonwrapping token" {
    TestApi.reset();
    var ctx: Context = undefined;
    try ctx.claim();
    defer ctx.release();
    const w: Workshop = .{ .lease = ctx.lease() };
    defer shutdown(w.lease);
    try std.testing.expectError(error.InvalidArgument, w.createDetailsQuery(&.{}));
    const many: [51]types.WorkshopItem = @splat(.invalid);
    try std.testing.expectError(error.InvalidArgument, w.createDetailsQuery(&many));
    ctx.workshop_serial = std.math.maxInt(u64);
    try std.testing.expectError(error.TokenExhausted, w.createDetailsQuery(&test_items));
    try std.testing.expectEqual(@as(usize, 0), TestApi.calls);
    ctx.workshop_serial = 0;
    TestApi.handle = std.math.maxInt(u64);
    try std.testing.expectError(error.QueryRejected, w.createDetailsQuery(&test_items));
    TestApi.available = false;
    try std.testing.expectError(error.InterfaceUnavailable, w.createDetailsQuery(&test_items));
    TestApi.available = true;
    TestApi.handle = 0;
    const q = try w.createDetailsQuery(&test_items);
    defer _ = q.release() catch false;
    try std.testing.expectEqualSlices(u64, &.{ 17, 0, 17 }, TestApi.ids[0..3]);
    try std.testing.expectEqual(@as(u64, 0), @backingInt(try q.handle()));
    try std.testing.expectEqual(QueryState.created, try q.state());
    try std.testing.expectEqual(@as(?u32, null), try q.resultCount());
    try std.testing.expectError(error.QueryBusy, w.createDetailsQuery(&test_items));
    try std.testing.expect(try q.release());
    const replacement = try w.createDetailsQuery(&test_items);
    defer _ = replacement.release() catch false;
    const before = TestApi.releases;
    try std.testing.expectError(error.StaleQuery, q.release());
    try std.testing.expectError(error.StaleQuery, q.send());
    try std.testing.expectEqual(before, TestApi.releases);
}

test "Workshop send rejection retains ownership and missing interface permits retry" {
    TestApi.reset();
    var ctx: Context = undefined;
    try ctx.claim();
    defer ctx.release();
    const w: Workshop = .{ .lease = ctx.lease() };
    defer shutdown(w.lease);
    const q = try w.createDetailsQuery(&test_items);
    defer _ = q.release() catch false;
    const copy = q;
    TestApi.available = false;
    try std.testing.expectError(error.InterfaceUnavailable, q.send());
    try std.testing.expectEqual(QueryState.created, try q.state());
    TestApi.available = true;
    TestApi.call = 0;
    try std.testing.expectError(error.RequestRejected, q.send());
    try std.testing.expectEqual(QueryState.failed, try q.state());
    try std.testing.expectError(error.QueryAlreadySent, copy.send());
    TestApi.available = false;
    try std.testing.expectError(error.InterfaceUnavailable, q.release());
    try std.testing.expectEqual(QueryState.failed, try q.state());
    TestApi.available = true;
    try std.testing.expect(try copy.release());
}

test "Workshop matching success ignores broadcasts unrelated and duplicate completions" {
    TestApi.reset();
    var ctx: Context = undefined;
    try ctx.claim();
    defer ctx.release();
    const w: Workshop = .{ .lease = ctx.lease() };
    defer shutdown(w.lease);
    const q = try w.createDetailsQuery(&test_items);
    defer _ = q.release() catch false;
    var request = try q.send();
    try std.testing.expectEqual(@as(u64, 71), @backingInt(request.call));
    try std.testing.expectError(error.QueryAlreadySent, q.send());
    const before = TestApi.calls;
    try std.testing.expectError(error.QueryPending, q.release());
    try std.testing.expectEqual(before, TestApi.calls);
    var event = completion(0, 0, .ok, 3);
    observeCompletion(w.lease, &event);
    event.call = @fromBackingInt(@intCast(72));
    observeCompletion(w.lease, &event);
    try std.testing.expectEqual(QueryState.pending, try q.state());
    event.call = request.call;
    observeCompletion(w.lease, &event);
    try std.testing.expectEqual(QueryState.ready, try q.state());
    try std.testing.expectEqual(@as(?u32, 3), try q.resultCount());
    try std.testing.expectEqual(@as(u64, 0), ctx.workshop_call);
    try std.testing.expect((try request.take(&event)).?.result == .ok);
    event.payload = .malformed;
    observeCompletion(w.lease, &event);
    try std.testing.expectEqual(QueryState.ready, try q.state());
    try std.testing.expectError(error.QueryAlreadySent, q.send());
}

test "Workshop every matching failure category is terminal and never trusts callback handle" {
    TestApi.reset();
    var ctx: Context = undefined;
    try ctx.claim();
    defer ctx.release();
    const w: Workshop = .{ .lease = ctx.lease() };
    defer shutdown(w.lease);
    const Payload = @FieldType(events.Event, "payload");
    const failures = [_]Payload{
        .{ .call_failed = .result_unavailable }, .{ .call_failed = .io_failure },    .malformed,                          .unhandled,
        .{ .lobby_list = 7 },                    completion(71, 99, .ok, 3).payload, completion(71, 0, .fail, 3).payload, completion(71, 0, @fromBackingInt(@intCast(123456)), 3).payload,
        completion(71, 0, .ok, 4).payload,
    };
    for (failures) |payload| {
        const q = try w.createDetailsQuery(&test_items);
        defer _ = q.release() catch false;
        _ = try q.send();
        var event: events.Event = .{ .call = @fromBackingInt(@intCast(71)), .callback_id = 0, .payload = payload };
        observeCompletion(w.lease, &event);
        try std.testing.expectEqual(QueryState.failed, try q.state());
        try std.testing.expectEqual(@as(u64, 0), ctx.workshop_call);
        var row: Details = undefined;
        try std.testing.expectError(error.QueryNotReady, q.read(0, &row));
        event = completion(71, 0, .ok, 3);
        observeCompletion(w.lease, &event);
        try std.testing.expectEqual(QueryState.failed, try q.state());
        try std.testing.expect(try q.release());
        try std.testing.expectEqual(@as(u64, 0), TestApi.last_handle);
    }
}

test "Workshop false release cannot retry and shutdown is bounded for every state" {
    const states = [_]QueryState{ .created, .pending, .ready, .failed, .release_failed };
    for (states) |state_value| {
        TestApi.reset();
        var ctx: Context = undefined;
        try ctx.claim();
        defer ctx.release();
        const w: Workshop = .{ .lease = ctx.lease() };
        defer shutdown(w.lease);
        const q = try w.createDetailsQuery(&test_items);
        defer _ = q.release() catch false;
        ctx.workshop_state = state_value;
        shutdown(w.lease);
        const expected: usize = if (state_value == .pending or state_value == .release_failed) 0 else 1;
        try std.testing.expectEqual(expected, TestApi.releases);
        shutdown(w.lease);
        try std.testing.expectEqual(expected, TestApi.releases);
        try std.testing.expectEqual(QueryState.none, ctx.workshop_state);
    }
    // Each shutdown ends its session; never demonstrate in-session abandonment.
    for ([_]bool{ false, true }) |missing_interface| {
        TestApi.reset();
        var ctx: Context = undefined;
        try ctx.claim();
        defer ctx.release();
        const w: Workshop = .{ .lease = ctx.lease() };
        defer shutdown(w.lease);
        const q = try w.createDetailsQuery(&test_items);
        defer _ = q.release() catch false;
        if (missing_interface) {
            TestApi.available = false;
        } else {
            TestApi.accepted = false;
            try std.testing.expect(!try q.release());
            try std.testing.expectError(error.ReleaseFailed, q.release());
            try std.testing.expectError(error.QueryBusy, w.createDetailsQuery(&test_items));
        }
        const before = TestApi.releases;
        shutdown(w.lease);
        try std.testing.expectEqual(before, TestApi.releases);
        try std.testing.expectEqual(QueryState.none, ctx.workshop_state);
    }
}

test "Workshop Details copies own every field, bound text and survive scratch overwrite and release" {
    TestApi.reset();
    var ctx: Context = undefined;
    try ctx.claim();
    defer ctx.release();
    const w: Workshop = .{ .lease = ctx.lease() };
    defer shutdown(w.lease);
    const q = try w.createDetailsQuery(&test_items);
    defer _ = q.release() catch false;
    _ = try q.send();
    var event = completion(71, 0, .ok, 1);
    observeCompletion(w.lease, &event);
    var value = std.mem.zeroes(c.struct_sw_workshop_details);
    value.item = 17;
    value.result = 123456;
    value.file_type = 234567;
    value.creator_app = 19;
    value.consumer_app = 23;
    value.title = @splat('t');
    value.description = @splat('d');
    value.owner = 29;
    value.created = 31;
    value.updated = 37;
    value.added_to_list = 41;
    value.visibility = 345678;
    value.banned = true;
    value.accepted_for_use = true;
    value.tags_truncated = true;
    value.tags = @splat('g');
    value.file = 43;
    value.preview_file = 47;
    value.filename = @splat('f');
    value.file_size = -53;
    value.preview_file_size = -59;
    value.url = @splat('u');
    value.votes_up = 61;
    value.votes_down = 67;
    value.score = 0.25;
    value.children = 71;
    value.total_files_size = std.math.maxInt(u64);
    TestApi.scratch = value;
    var out: Details = undefined;
    try std.testing.expect(try q.read(0, &out));
    // Fieldwise cross-language mapping is independently asserted in the C++ fixture.
    inline for (@typeInfo(Details).@"struct".field_names) |field_name| {
        const actual = @field(out, field_name);
        const raw = @field(value, field_name);
        switch (@typeInfo(@TypeOf(actual))) {
            .@"enum" => try std.testing.expectEqual(raw, @backingInt(actual)),
            .array => try std.testing.expectEqualSlices(u8, std.mem.asBytes(&raw), &actual),
            else => try std.testing.expectEqual(raw, actual),
        }
    }
    try std.testing.expectEqual(@as(usize, 129), out.titleText().len);
    try std.testing.expectEqual(@as(usize, 8000), out.descriptionText().len);
    try std.testing.expectEqual(@as(usize, 1025), out.tagsText().len);
    try std.testing.expectEqual(@as(usize, 260), out.filenameText().len);
    try std.testing.expectEqual(@as(usize, 256), out.urlText().len);
    const saved = out;
    TestApi.scratch = std.mem.zeroes(c.struct_sw_workshop_details);
    TestApi.accepted = false;
    try std.testing.expect(!try q.read(0, &out));
    try std.testing.expectEqualDeep(saved, out);
    try std.testing.expectError(error.IndexOutOfBounds, q.read(1, &out));
    TestApi.accepted = true;
    try std.testing.expect(try q.release());
    try std.testing.expectEqualDeep(saved, out);
    try std.testing.expectError(error.StaleQuery, q.read(0, &out));
    out.title[2] = 0;
    try std.testing.expectEqualStrings("tt", out.titleText());
}

test "Workshop subscription and item operations preserve bounds defaults flags and false outputs" {
    TestApi.reset();
    var ctx: Context = undefined;
    try ctx.claim();
    defer ctx.release();
    const w: Workshop = .{ .lease = ctx.lease() };
    defer shutdown(w.lease);
    try std.testing.expectEqual(@as(u32, 3), try w.subscriptionCount(.{}));
    try std.testing.expect(!TestApi.disabled);
    _ = try w.subscriptionCount(.{ .include_locally_disabled = true });
    try std.testing.expect(TestApi.disabled);
    var items: [3]types.WorkshopItem = @splat(.invalid);
    const result = try w.subscriptions(&items, .{});
    try std.testing.expectEqual(@as(u32, 3), result.reported);
    try std.testing.expectEqualSlices(types.WorkshopItem, &test_items, result.items);
    try std.testing.expect(!TestApi.disabled);
    TestApi.count = 4;
    items[0] = @fromBackingInt(@intCast(99));
    try std.testing.expectError(error.MalformedCount, w.subscriptions(&items, .{ .include_locally_disabled = true }));
    try std.testing.expectEqual(@as(u64, 99), @backingInt(items[0]));
    try std.testing.expect(TestApi.disabled);
    const before = TestApi.calls;
    var many: [1025]types.WorkshopItem = undefined;
    try std.testing.expectError(error.InvalidArgument, w.subscriptions(&many, .{}));
    _ = try w.subscriptions(&.{}, .{});
    try std.testing.expectEqual(before, TestApi.calls);
    try std.testing.expectEqual(@as(u32, 0x80000045), try w.itemState(.invalid));
    var path: [8]u8 = undefined;
    TestApi.accepted = false;
    const install = try w.installInfo(.invalid, &path);
    try std.testing.expect(!install.found and install.path == null and path[0] == 'x');
    try std.testing.expectEqual(std.math.maxInt(u64), install.size);
    try std.testing.expectEqual(@as(u32, 31), install.timestamp);
    const progress = try w.downloadProgress(.invalid);
    try std.testing.expect(!progress.found and progress.downloaded == 99 and progress.total == 0);
    try std.testing.expect(!try w.downloadItem(.invalid, .{}));
    try std.testing.expect(!TestApi.priority);
    TestApi.accepted = true;
    try std.testing.expectEqualStrings("xxxxxxx", (try w.installInfo(.invalid, &path)).path.?);
    try std.testing.expectError(error.UnterminatedPath, w.installInfo(.invalid, path[0..1]));
    try std.testing.expectError(error.InvalidArgument, w.installInfo(.invalid, path[0..0]));
    try std.testing.expect(try w.downloadItem(.invalid, .{ .high_priority = true }));
    try std.testing.expect(TestApi.priority);
    TestApi.available = false;
    try std.testing.expectError(error.InterfaceUnavailable, w.subscriptionCount(.{}));
    try std.testing.expectError(error.InterfaceUnavailable, w.subscriptions(&items, .{}));
    try std.testing.expectError(error.InterfaceUnavailable, w.itemState(.invalid));
    try std.testing.expectError(error.InterfaceUnavailable, w.installInfo(.invalid, &path));
    try std.testing.expectError(error.InterfaceUnavailable, w.downloadProgress(.invalid));
    try std.testing.expectError(error.InterfaceUnavailable, w.downloadItem(.invalid, .{}));
}

fn intentionalFailure(w: Workshop) !void {
    const q = try w.createDetailsQuery(&test_items);
    defer _ = q.release() catch false;
    return error.IntentionalFailure;
}
test "Workshop cleanup is installed immediately on acquisition before a failing path" {
    TestApi.reset();
    var ctx: Context = undefined;
    try ctx.claim();
    defer ctx.release();
    const w: Workshop = .{ .lease = ctx.lease() };
    defer shutdown(w.lease);
    try std.testing.expectError(error.IntentionalFailure, intentionalFailure(w));
    try std.testing.expectEqual(@as(usize, 1), TestApi.releases);
    try std.testing.expectEqual(QueryState.none, ctx.workshop_state);
}
