const std = @import("std");
const types = @import("types.zig");
const Event = @import("events.zig").Event;
const Payload = @FieldType(Event, "payload");

/// Failures while retrieving or decoding a completion, not operation results.
pub const Error = error{ ResultUnavailable, IoFailure, MalformedResult, UnexpectedResult };

/// Allocation-free correlation for an API-call result. Keep one tracker per
/// operation and discard it when its client session ends. This does not pump
/// events, own a native resource, or provide native cancellation.
pub fn Request(comptime kind: std.meta.Tag(Payload)) type {
    switch (kind) {
        .lobby_created, .lobby_entered, .lobby_list, .stats_received, .cloud_written => {},
        else => @compileError("This event does not complete an exposed API-call request"),
    }
    return struct {
        const Self = @This();
        pub const Value = @FieldType(Payload, @tagName(kind));

        /// Becomes invalid after the first matching completion, including failure.
        call: types.ApiCall = .invalid,

        /// An invalid SDK call handle means the request was not accepted.
        pub fn init(call: types.ApiCall) error{RequestRejected}!Self {
            if (call == .invalid) return error.RequestRejected;
            return .{ .call = call };
        }

        pub fn isPending(self: Self) bool {
            return self.call != .invalid;
        }

        /// Null means no pending request matched this event. A matching event
        /// completes this tracker once, without consuming the event for others.
        /// The returned value is an owned copy. Check its operation result: a
        /// successful retrieval does not imply successful lobby/stats/cloud work.
        pub fn take(self: *Self, event: *const Event) Error!?Value {
            if (!self.isPending() or self.call != event.call) return null;
            self.call = .invalid;
            return switch (event.payload) {
                kind => |value| value,
                .call_failed => |reason| switch (reason) {
                    .result_unavailable => error.ResultUnavailable,
                    .io_failure => error.IoFailure,
                },
                .malformed => error.MalformedResult,
                else => error.UnexpectedResult,
            };
        }
    };
}

test "requests ignore broadcasts and unrelated events then complete only once" {
    var request = try Request(.lobby_created).init(@enumFromInt(42));
    var event: Event = .{
        .call = .invalid,
        .callback_id = 513,
        .payload = .{ .lobby_created = .{ .lobby = @enumFromInt(123), .result = .ok } },
    };
    try std.testing.expect(try request.take(&event) == null);
    event.call = @enumFromInt(43);
    try std.testing.expect(try request.take(&event) == null);
    try std.testing.expect(request.isPending());
    event.call = request.call;
    const before = event;
    const value = (try request.take(&event)).?;
    try std.testing.expectEqual(@as(types.SteamId, @enumFromInt(123)), value.lobby);
    try std.testing.expectEqual(types.Result.ok, value.result);
    try std.testing.expect(!request.isPending());
    try std.testing.expect(try request.take(&event) == null);
    try std.testing.expectEqualDeep(before, event);
}

test "request failures consume only the matching tracker and preserve their cause" {
    const cases = [_]struct { payload: Payload, failure: Error }{
        .{ .payload = .{ .call_failed = .result_unavailable }, .failure = error.ResultUnavailable },
        .{ .payload = .{ .call_failed = .io_failure }, .failure = error.IoFailure },
        .{ .payload = .malformed, .failure = error.MalformedResult },
        .{ .payload = .unhandled, .failure = error.UnexpectedResult },
        .{ .payload = .{ .lobby_list = 3 }, .failure = error.UnexpectedResult },
    };
    for (cases) |case| {
        var request = try Request(.lobby_created).init(@enumFromInt(42));
        var event: Event = .{ .call = @enumFromInt(43), .callback_id = 0, .payload = case.payload };
        try std.testing.expect(try request.take(&event) == null);
        try std.testing.expect(request.isPending());
        event.call = request.call;
        try std.testing.expectError(case.failure, request.take(&event));
        try std.testing.expect(!request.isPending());
        try std.testing.expect(try request.take(&event) == null);
    }
}

test "completion retrieval preserves unsuccessful and unknown operation results" {
    var request = try Request(.lobby_created).init(@enumFromInt(42));
    const event: Event = .{
        .call = request.call,
        .callback_id = 513,
        .payload = .{ .lobby_created = .{ .lobby = .invalid, .result = @enumFromInt(123456) } },
    };
    const value = (try request.take(&event)).?;
    try std.testing.expectEqual(@as(i32, 123456), @intFromEnum(value.result));
    try std.testing.expectEqual(types.SteamId.invalid, value.lobby);
}

test "each exposed asynchronous operation has a typed completion" {
    const cases = .{
        .{ .lobby_created, Payload{ .lobby_created = .{ .lobby = @enumFromInt(1), .result = .ok } } },
        .{ .lobby_entered, Payload{ .lobby_entered = .{ .lobby = @enumFromInt(1), .response = .full, .locked = true } } },
        .{ .lobby_list, Payload{ .lobby_list = 7 } },
        .{ .stats_received, Payload{ .stats_received = .{ .game = 480, .user = @enumFromInt(2), .result = .fail } } },
        .{ .cloud_written, Payload{ .cloud_written = .access_denied } },
    };
    inline for (cases) |case| {
        const T = Request(case[0]);
        std.testing.refAllDecls(T);
        try std.testing.expectError(error.RequestRejected, T.init(.invalid));
        var request = try T.init(@enumFromInt(1));
        const event: Event = .{ .call = request.call, .callback_id = 0, .payload = case[1] };
        const value: T.Value = (try request.take(&event)).?;
        try std.testing.expectEqualDeep(@field(case[1], @tagName(case[0])), value);
        request = .{}; // Discarding a tracker does not call Steam or cancel work.
        try std.testing.expect(!request.isPending());
        try std.testing.expect(try request.take(&event) == null);
    }
}
