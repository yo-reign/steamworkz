//! Borrowed owner-thread configuration facade; valid only for its client lease.
//! Construction makes no native calls. Simulation is explicit, process-global
//! opt-in, not a connection-local feature. Reset before closing the client and
//! inspect every outcome. There is no automatic rollback or shutdown reset.
const std = @import("std");
const Context = @import("Context.zig");
const Networking = @import("Networking.zig");
const c = @cImport({
    @cInclude("networking_config.h");
});
const NetworkingConfig = @This();

lease: Context.Lease,

pub const Scope = union(enum) {
    global,
    listen_socket: Networking.ListenSocket,
    connection: Networking.Connection,
};

/// All i32 values are forwarded for SDK validation. The SDK currently requires
/// matching minimum and maximum rates; separate writes are not a transaction.
pub const Int32Option = enum(u32) {
    initial_timeout_ms,
    connected_timeout_ms,
    send_buffer_bytes,
    minimum_send_rate_bytes_per_second,
    maximum_send_rate_bytes_per_second,
    nagle_delay_us,
    _,
};
pub const Error = error{ InterfaceUnavailable, InvalidOption, InvalidScope, InvalidSimulation, OperationFailed };
pub const GetStatus = enum(i32) {
    bad_value = -1,
    bad_scope_object = -2,
    buffer_too_small = -3,
    ok = 1,
    ok_inherited = 2,
    _,
};
pub const DataType = enum(i32) { int32 = 1, int64 = 2, float = 3, string = 4, pointer = 5, _ };
pub const GetOutcome = union(enum) {
    value: i32,
    inherited_value: i32,
    bad_value,
    bad_scope_object,
    buffer_too_small,
    unknown_status,
    malformed_success,
};
/// Owned diagnostics. Unknown native status/type values remain lossless.
/// A value exists only for known success, Int32 and exactly four bytes.
pub const GetResult = struct {
    status: GetStatus,
    data_type: DataType,
    size: usize,
    outcome: GetOutcome,
};

pub fn set(self: NetworkingConfig, scope: Scope, option: Int32Option, value: i32) Error!void {
    self.lease.check();
    return setWith(c, scope, option, value, false);
}
/// Clear this scope's override (global: SDK default; others: inheritance).
pub fn clear(self: NetworkingConfig, scope: Scope, option: Int32Option) Error!void {
    self.lease.check();
    return setWith(c, scope, option, 0, true);
}
pub fn get(self: NetworkingConfig, scope: Scope, option: Int32Option) Error!GetResult {
    self.lease.check();
    return getWith(c, scope, option);
}

pub const Simulation = struct {
    send_loss_percent: f32 = 0,
    receive_loss_percent: f32 = 0,
    send_lag_ms: i32 = 0,
    receive_lag_ms: i32 = 0,
    send_reorder_percent: f32 = 0,
    receive_reorder_percent: f32 = 0,
    reorder_delay_ms: i32 = 0,
};
pub const FieldOutcome = enum { not_attempted, applied, rejected };
pub const SimulationResult = struct {
    send_loss_percent: FieldOutcome,
    receive_loss_percent: FieldOutcome,
    send_lag_ms: FieldOutcome,
    receive_lag_ms: FieldOutcome,
    send_reorder_percent: FieldOutcome,
    receive_reorder_percent: FieldOutcome,
    reorder_delay_ms: FieldOutcome,
};
/// Validate every field before mutation; finite percentages in 0..100 and
/// nonnegative millisecond delays. Applies in Simulation declaration order,
/// stopping at the first rejection. A default Simulation explicitly sets zero
/// overrides; it does not clear them. No rollback of an accepted prefix.
pub fn applySimulation(self: NetworkingConfig, settings: Simulation) Error!SimulationResult {
    self.lease.check();
    return applyWith(c, settings);
}
/// Attempt all seven null clears in declaration order, even after rejection.
/// Clears to SDK defaults, not a previous explicit override. Failures remain
/// visible and the caller is responsible for reset before client close.
pub fn resetSimulation(self: NetworkingConfig) Error!SimulationResult {
    self.lease.check();
    return resetWith(c);
}

const NativeScope = struct { kind: u32, handle: u32 };
fn nativeScope(scope: Scope) Error!NativeScope {
    const result: NativeScope = switch (scope) {
        .global => .{ .kind = 0, .handle = 0 },
        .listen_socket => |h| .{ .kind = 1, .handle = @intFromEnum(h) },
        .connection => |h| .{ .kind = 2, .handle = @intFromEnum(h) },
    };
    _ = std.math.cast(isize, result.handle) orelse return error.InvalidScope;
    return result;
}
fn nativeOption(option: Int32Option) Error!u32 {
    const value = @intFromEnum(option);
    if (value >= 6) return error.InvalidOption;
    return value;
}
fn available(result: i32) Error!void {
    switch (result) {
        0 => {},
        -1 => return error.InterfaceUnavailable,
        // The private ABI only returns -2 on inputs validated by this module.
        else => return error.OperationFailed,
    }
}
fn setWith(comptime api: type, scope: Scope, option: Int32Option, value: i32, clear_value: bool) Error!void {
    const s = try nativeScope(scope);
    const key = try nativeOption(option);
    var accepted = false;
    try available(api.sw_config_set(s.kind, s.handle, key, value, clear_value, &accepted));
    if (!accepted) return error.OperationFailed;
}
fn getWith(comptime api: type, scope: Scope, option: Int32Option) Error!GetResult {
    const s = try nativeScope(scope);
    const key = try nativeOption(option);
    var out: c.sw_config_get_result = std.mem.zeroes(c.sw_config_get_result);
    try available(api.sw_config_get(s.kind, s.handle, key, &out));
    return decodeGet(out);
}
fn decodeGet(out: c.sw_config_get_result) GetResult {
    const status: GetStatus = @enumFromInt(out.status);
    const outcome: GetOutcome = switch (status) {
        .ok, .ok_inherited => if (out.data_type != @intFromEnum(DataType.int32) or out.size != @sizeOf(i32))
            .malformed_success
        else if (status == .ok)
            .{ .value = out.value }
        else
            .{ .inherited_value = out.value },
        .bad_value => .bad_value,
        .bad_scope_object => .bad_scope_object,
        .buffer_too_small => .buffer_too_small,
        _ => .unknown_status,
    };
    return .{ .status = status, .data_type = @enumFromInt(out.data_type), .size = out.size, .outcome = outcome };
}
fn marshalSimulation(s: Simulation) Error!c.sw_config_simulation {
    for ([_]f32{ s.send_loss_percent, s.receive_loss_percent, s.send_reorder_percent, s.receive_reorder_percent }) |percent| {
        if (!std.math.isFinite(percent) or percent < 0 or percent > 100) return error.InvalidSimulation;
    }
    if (s.send_lag_ms < 0 or s.receive_lag_ms < 0 or s.reorder_delay_ms < 0) return error.InvalidSimulation;
    return .{
        .send_loss_percent = s.send_loss_percent,
        .receive_loss_percent = s.receive_loss_percent,
        .send_lag_ms = s.send_lag_ms,
        .receive_lag_ms = s.receive_lag_ms,
        .send_reorder_percent = s.send_reorder_percent,
        .receive_reorder_percent = s.receive_reorder_percent,
        .reorder_delay_ms = s.reorder_delay_ms,
    };
}
fn decodeSimulation(out: c.sw_config_simulation_result) SimulationResult {
    var result: SimulationResult = undefined;
    inline for (std.meta.fields(SimulationResult), 0..) |field, i| {
        @field(result, field.name) = switch (out.fields[i]) {
            0 => .not_attempted,
            1 => .applied,
            2 => .rejected,
            else => @panic("Invalid private configuration outcome"),
        };
    }
    return result;
}
fn applyWith(comptime api: type, settings: Simulation) Error!SimulationResult {
    const native = try marshalSimulation(settings);
    var out: c.sw_config_simulation_result = std.mem.zeroes(c.sw_config_simulation_result);
    try available(api.sw_config_simulation_apply(&native, &out));
    return decodeSimulation(out);
}
fn resetWith(comptime api: type) Error!SimulationResult {
    var out: c.sw_config_simulation_result = std.mem.zeroes(c.sw_config_simulation_result);
    try available(api.sw_config_simulation_reset(&out));
    return decodeSimulation(out);
}

const Fake = struct {
    var calls: usize = 0;
    var local_result: i32 = 0;
    var accepted = true;
    var scope: u32 = 0;
    var handle: u32 = 0;
    var option: u32 = 0;
    var value: i32 = 0;
    var cleared = false;
    var get_result: c.sw_config_get_result = std.mem.zeroes(c.sw_config_get_result);
    var simulation: c.sw_config_simulation = std.mem.zeroes(c.sw_config_simulation);
    var outcomes: c.sw_config_simulation_result = .{ .fields = @splat(1) };
    fn sw_config_set(s: u32, h: u32, key: u32, v: i32, clear_value: bool, out: *bool) i32 {
        calls += 1;
        scope = s;
        handle = h;
        option = key;
        value = v;
        cleared = clear_value;
        out.* = accepted;
        return local_result;
    }
    fn sw_config_get(s: u32, h: u32, key: u32, out: *c.sw_config_get_result) i32 {
        calls += 1;
        scope = s;
        handle = h;
        option = key;
        out.* = get_result;
        return local_result;
    }
    fn sw_config_simulation_apply(settings: *const c.sw_config_simulation, out: *c.sw_config_simulation_result) i32 {
        calls += 1;
        simulation = settings.*;
        cleared = false;
        out.* = outcomes;
        return local_result;
    }
    fn sw_config_simulation_reset(out: *c.sw_config_simulation_result) i32 {
        calls += 1;
        cleared = true;
        out.* = outcomes;
        return local_result;
    }
};

test "NetworkingConfig scalar scope option routing and native rejection" {
    Fake.local_result = 0;
    Fake.accepted = true;
    const scopes = [_]Scope{ .global, .{ .listen_socket = @enumFromInt(0xffffffff) }, .{ .connection = .invalid } };
    for (scopes, 0..) |scope, index| for (0..6) |key| {
        for ([_]i32{ std.math.minInt(i32), -1, 0, std.math.maxInt(i32) }) |value| {
            try setWith(Fake, scope, @enumFromInt(key), value, false);
            try std.testing.expectEqual(index, Fake.scope);
            try std.testing.expectEqual(@as(u32, if (index == 1) 0xffffffff else 0), Fake.handle);
            try std.testing.expectEqual(key, Fake.option);
            try std.testing.expectEqual(value, Fake.value);
            try std.testing.expect(!Fake.cleared);
            try setWith(Fake, scope, @enumFromInt(key), value, true);
            try std.testing.expect(Fake.cleared);
            _ = try getWith(Fake, scope, @enumFromInt(key));
            try std.testing.expectEqual(index, Fake.scope);
            try std.testing.expectEqual(key, Fake.option);
        }
    };
    Fake.calls = 0;
    try std.testing.expectError(error.InvalidOption, setWith(Fake, .global, @enumFromInt(6), 0, false));
    try std.testing.expectError(error.InvalidOption, getWith(Fake, .global, @enumFromInt(0xffffffff)));
    try std.testing.expectEqual(0, Fake.calls);
    Fake.accepted = false;
    try std.testing.expectError(error.OperationFailed, setWith(Fake, .global, .initial_timeout_ms, 0, false));
    try std.testing.expectError(error.OperationFailed, setWith(Fake, .global, .initial_timeout_ms, 0, true));
    Fake.local_result = -1;
    try std.testing.expectError(error.InterfaceUnavailable, setWith(Fake, .global, .initial_timeout_ms, 0, false));
    try std.testing.expectError(error.InterfaceUnavailable, getWith(Fake, .global, .initial_timeout_ms));
}

test "NetworkingConfig getter statuses types sizes and inheritance are distinct" {
    Fake.local_result = 0;
    for ([_]i32{ -3, -2, -1, 0, 1, 2, 3, std.math.minInt(i32), std.math.maxInt(i32) }) |status| {
        for ([_]i32{ 0, 1, 2, 3, 4, 5, -999, std.math.maxInt(i32) }) |data_type| {
            for ([_]usize{ 0, 3, 4, 8, std.math.maxInt(usize) }) |size| {
                Fake.get_result = .{ .status = status, .data_type = data_type, .size = size, .value = -987654 };
                const result = try getWith(Fake, .global, .nagle_delay_us);
                try std.testing.expectEqual(status, @intFromEnum(result.status));
                try std.testing.expectEqual(data_type, @intFromEnum(result.data_type));
                try std.testing.expectEqual(size, result.size);
                const expected: std.meta.Tag(GetOutcome) = switch (status) {
                    -3 => .buffer_too_small,
                    -2 => .bad_scope_object,
                    -1 => .bad_value,
                    1, 2 => if (data_type != 1 or size != 4) .malformed_success else if (status == 1) .value else .inherited_value,
                    else => .unknown_status,
                };
                try std.testing.expectEqual(expected, std.meta.activeTag(result.outcome));
                switch (result.outcome) {
                    .value, .inherited_value => |value| try std.testing.expectEqual(-987654, value),
                    else => {},
                }
            }
        }
    }
}

test "NetworkingConfig simulation validates all fields before native access" {
    Fake.local_result = 0;
    inline for (std.meta.fields(Simulation)) |field| {
        const bad_values = if (field.type == f32) [_]f32{ -1, 101, std.math.nan(f32), std.math.inf(f32), -std.math.inf(f32) } else [_]i32{-1};
        for (bad_values) |value| {
            var settings: Simulation = .{};
            @field(settings, field.name) = value;
            Fake.calls = 0;
            try std.testing.expectError(error.InvalidSimulation, applyWith(Fake, settings));
            try std.testing.expectEqual(0, Fake.calls);
        }
    }
    const settings: Simulation = .{ .send_loss_percent = 0, .receive_loss_percent = 100, .send_lag_ms = 123, .receive_lag_ms = 456, .send_reorder_percent = 12.5, .receive_reorder_percent = 98.75, .reorder_delay_ms = std.math.maxInt(i32) };
    _ = try applyWith(Fake, settings);
    inline for (std.meta.fields(Simulation)) |field| try std.testing.expectEqual(@field(settings, field.name), @field(Fake.simulation, field.name));
    Fake.local_result = -1;
    try std.testing.expectError(error.InterfaceUnavailable, applyWith(Fake, .{}));
    try std.testing.expectError(error.InterfaceUnavailable, resetWith(Fake));
}

test "NetworkingConfig simulation preserves every partial and reset outcome" {
    Fake.local_result = 0;
    for (0..8) |reject| {
        for (0..7) |i| Fake.outcomes.fields[i] = if (reject == 0 or i + 1 < reject) 1 else if (i + 1 == reject) 2 else 0;
        const result = try applyWith(Fake, .{});
        inline for (std.meta.fields(SimulationResult), 0..) |field, i| {
            const expected: FieldOutcome = if (reject == 0 or i + 1 < reject) .applied else if (i + 1 == reject) .rejected else .not_attempted;
            try std.testing.expectEqual(expected, @field(result, field.name));
        }
        try std.testing.expect(!Fake.cleared);
        inline for (std.meta.fields(Simulation)) |field| try std.testing.expectEqual(@as(field.type, 0), @field(Fake.simulation, field.name));
        for (0..7) |i| Fake.outcomes.fields[i] = if (i + 1 == reject) 2 else 1;
        const reset = try resetWith(Fake);
        try std.testing.expect(Fake.cleared);
        inline for (std.meta.fields(SimulationResult), 0..) |field, i| try std.testing.expectEqual(if (i + 1 == reject) FieldOutcome.rejected else FieldOutcome.applied, @field(reset, field.name));
    }
}
