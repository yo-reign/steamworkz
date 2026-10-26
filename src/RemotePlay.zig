//! Read-only streaming-session queries plus explicit Together UI/invitations.
//! Sessions may disappear between queries; these identities own no resources.
//! Valve: https://partner.steamgames.com/doc/api/ISteamRemotePlay
const std = @import("std");
const builtin = @import("builtin");
const Context = @import("Context.zig");
const types = @import("types.zig");
const Session = types.RemotePlaySession;
const SteamId = types.SteamId;
const c = @import("steamworkz_c");
const native = if (builtin.is_test) Fake else c;
const RemotePlay = @This();

/// Borrowed owner-thread facade. Client storage must stay alive and unmoved.
/// Session identities own no resources and need no teardown.
lease: Context.Lease,

pub const FormFactor = enum(i32) { unknown = 0, phone = 1, tablet = 2, computer = 3, tv = 4, vr_headset = 5, _ };
pub const Resolution = struct { available: bool, width: i32, height: i32 };
pub const InviteTarget = union(enum) { friend: SteamId, guest };
pub const ClientName = struct {
    status: enum { complete, absent, too_long, buffer_too_small },
    /// Byte length excluding NUL, when a terminator was found within the bound.
    required_length: ?u32,
    /// Borrows caller storage, never SDK storage; non-null for empty success.
    text: ?[]u8,
};

/// Count and sessionAt are separate snapshots, not an atomic enumeration.
pub fn sessionCount(self: RemotePlay) !u32 {
    self.lease.check();
    var count: u32 = 0;
    try status(native.sw_remote_play_session_count(&count));
    return count;
}

/// Preserves zero when out of bounds or the session disappeared after counting.
pub fn sessionAt(self: RemotePlay, index: usize) !Session {
    self.lease.check();
    if (index > std.math.maxInt(c_int)) return error.IndexTooLarge;
    var session: u32 = 0;
    try status(native.sw_remote_play_session_id(@intCast(index), &session));
    return @fromBackingInt(@intCast(session));
}

/// ISteamRemotePlay::BSessionRemotePlayTogether, not a connection-liveness test.
pub fn isTogether(self: RemotePlay, session: Session) !bool {
    self.lease.check();
    try validSession(session);
    return boolean(native.sw_remote_play_together(@backingInt(session)));
}

/// ISteamRemotePlay::GetSessionSteamID; preserves native identities, including
/// .invalid. The returned user ID needs no teardown and proves no lasting session.
pub fn steamId(self: RemotePlay, session: Session) !SteamId {
    self.lease.check();
    try validSession(session);
    var value: u64 = 0;
    try status(native.sw_remote_play_steam_id(@backingInt(session), &value));
    return @fromBackingInt(@intCast(value));
}

/// Zero means invalid/disappeared session OR a non-guest. No guest error inferred.
pub fn guestId(self: RemotePlay, session: Session) !u32 {
    self.lease.check();
    try validSession(session);
    var value: u32 = 0;
    try status(native.sw_remote_play_guest_id(@backingInt(session), &value));
    return value;
}

/// Copies before another native call. The 1024-byte scan (including NUL) is a
/// wrapper bound, not an SDK maximum. No NUL is copied; exact byte capacity is
/// sufficient. Non-complete outcomes leave output unchanged, never truncated.
pub fn clientName(self: RemotePlay, session: Session, output: []u8) !ClientName {
    self.lease.check();
    try validSession(session);
    var required: u32 = 0;
    var copied: u32 = 0;
    const result = native.sw_remote_play_client_name(@backingInt(session), output.ptr, output.len, &required, &copied);
    switch (result) {
        0 => {
            if (copied != required or copied >= 1024 or copied > output.len) return error.MalformedNativeOutput;
            return .{ .status = .complete, .required_length = required, .text = output[0..copied] };
        },
        1, 2 => return .{ .status = if (result == 1) .absent else .too_long, .required_length = null, .text = null },
        3 => {
            if (copied != 0 or required >= 1024 or required <= output.len) return error.MalformedNativeOutput;
            return .{ .status = .buffer_too_small, .required_length = required, .text = null };
        },
        else => {
            try status(result);
            unreachable;
        },
    }
}

/// ISteamRemotePlay::GetSessionClientFormFactor; preserves unknown native values.
/// A device category is not a guarantee of resolution or input capabilities.
pub fn formFactor(self: RemotePlay, session: Session) !FormFactor {
    self.lease.check();
    try validSession(session);
    var value: i32 = 0;
    try status(native.sw_remote_play_form_factor(@backingInt(session), &value));
    return @fromBackingInt(@intCast(value));
}

/// Preserves the native boolean and signed dimensions independently, including
/// zero (unavailable) and negative values; no fabricated dimension failure.
pub fn resolution(self: RemotePlay, session: Session) !Resolution {
    self.lease.check();
    try validSession(session);
    var width: i32 = 0;
    var height: i32 = 0;
    const available = try boolean(native.sw_remote_play_resolution(@backingInt(session), &width, &height));
    return .{ .available = available, .width = width, .height = height };
}

/// ISteamRemotePlay::ShowRemotePlayTogetherUI is an explicit UI action.
/// False preserves native rejection/configuration ambiguity.
pub fn showTogetherUi(self: RemotePlay) !bool {
    self.lease.check();
    return boolean(native.sw_remote_play_show_together_ui());
}

/// ISteamRemotePlay::BSendRemotePlayTogetherInvite; explicit invitation only.
/// True means submission, not acceptance or a connected session. False retains
/// rejection/configuration ambiguity. Only the explicit guest target sends zero.
pub fn invite(self: RemotePlay, target: InviteTarget) !bool {
    self.lease.check();
    const friend_id: u64 = switch (target) {
        .friend => |id| if (id == .invalid) return error.InvalidFriend else @backingInt(id),
        .guest => 0,
    };
    return boolean(native.sw_remote_play_invite(friend_id));
}

fn validSession(session: Session) !void {
    if (session == .invalid) return error.InvalidSession;
}
fn status(value: i32) !void {
    switch (value) {
        0 => {},
        -1 => return error.Unavailable,
        -2 => return error.InvalidArgument,
        else => return error.MalformedNativeOutput,
    }
}
fn boolean(value: i32) !bool {
    return switch (value) {
        -1 => error.Unavailable,
        -2 => error.InvalidArgument,
        0 => false,
        1 => true,
        else => error.MalformedNativeOutput,
    };
}

// Private inert boundary. The owning C++ fixture separately checks the exact
// official signatures and copying; Zig tests cannot acquire an SDK interface.
const Fake = struct {
    var calls: usize = 0;
    var result: i32 = 0;
    var bool_result: i32 = 1;
    var session_value: u32 = 73;
    var form: i32 = 5;
    var width: i32 = -7;
    var height: i32 = 0;
    var last_index: i32 = -1;
    var last_friend: u64 = 999;
    var name_result: i32 = 0;
    var required: u32 = 3;
    var copied: u32 = 3;
    fn reset() void {
        calls = 0;
        result = 0;
        bool_result = 1;
        session_value = 73;
        form = 5;
        width = -7;
        height = 0;
        last_index = -1;
        last_friend = 999;
        name_result = 0;
        required = 3;
        copied = 3;
    }
    fn call() void {
        calls += 1;
    }
    fn checkSession(session: u32) void {
        if (session != 73) @panic("unexpected RemotePlay fixture session");
        call();
    }
    fn sw_remote_play_session_count(value: *u32) i32 {
        call();
        value.* = 1;
        return result;
    }
    fn sw_remote_play_session_id(index: i32, value: *u32) i32 {
        call();
        last_index = index;
        value.* = session_value;
        return result;
    }
    fn sw_remote_play_together(session: u32) i32 {
        checkSession(session);
        return bool_result;
    }
    fn sw_remote_play_steam_id(session: u32, value: *u64) i32 {
        checkSession(session);
        value.* = std.math.maxInt(u64);
        return result;
    }
    fn sw_remote_play_guest_id(session: u32, value: *u32) i32 {
        checkSession(session);
        value.* = 0;
        return result;
    }
    fn sw_remote_play_form_factor(session: u32, value: *i32) i32 {
        checkSession(session);
        value.* = form;
        return result;
    }
    fn sw_remote_play_resolution(session: u32, x: *i32, y: *i32) i32 {
        checkSession(session);
        x.* = width;
        y.* = height;
        return bool_result;
    }
    fn sw_remote_play_client_name(session: u32, output: [*]u8, capacity: usize, needed: *u32, written: *u32) i32 {
        checkSession(session);
        needed.* = required;
        written.* = copied;
        if (name_result == 0 and copied == 3 and capacity >= 3) @memcpy(output[0..3], "abc");
        return name_result;
    }
    fn sw_remote_play_show_together_ui() i32 {
        call();
        return bool_result;
    }
    fn sw_remote_play_invite(friend_id: u64) i32 {
        call();
        last_friend = friend_id;
        return bool_result;
    }
};

test "RemotePlay snapshots preserve disappearing sessions and ambiguous values" {
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    Fake.reset();
    const remote: RemotePlay = .{ .lease = context.lease() };
    const session: Session = @fromBackingInt(@intCast(73));
    try std.testing.expectEqual(@as(u32, 1), try remote.sessionCount());
    try std.testing.expectEqual(session, try remote.sessionAt(0));
    Fake.session_value = 0;
    try std.testing.expectEqual(Session.invalid, try remote.sessionAt(std.math.maxInt(c_int)));
    try std.testing.expectEqual(std.math.maxInt(c_int), Fake.last_index);
    try std.testing.expect(try remote.isTogether(session));
    try std.testing.expectEqual(std.math.maxInt(u64), @backingInt(try remote.steamId(session)));
    try std.testing.expectEqual(@as(u32, 0), try remote.guestId(session));
    for ([_]i32{ 6, -1, std.math.minInt(i32), std.math.maxInt(i32) }) |value| {
        Fake.form = value;
        try std.testing.expectEqual(value, @backingInt(try remote.formFactor(session)));
    }
    try std.testing.expectEqual(Resolution{ .available = true, .width = -7, .height = 0 }, try remote.resolution(session));
    Fake.bool_result = 0;
    try std.testing.expectEqual(Resolution{ .available = false, .width = -7, .height = 0 }, try remote.resolution(session));
    Fake.width = 0;
    try std.testing.expectEqual(Resolution{ .available = false, .width = 0, .height = 0 }, try remote.resolution(session));
    try std.testing.expect(!try remote.isTogether(session));
}

test "RemotePlay local validation prevents native calls" {
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    Fake.reset();
    const remote: RemotePlay = .{ .lease = context.lease() };
    try std.testing.expectError(error.IndexTooLarge, remote.sessionAt(@as(usize, std.math.maxInt(c_int)) + 1));
    try std.testing.expectError(error.InvalidSession, remote.isTogether(.invalid));
    try std.testing.expectError(error.InvalidSession, remote.steamId(.invalid));
    try std.testing.expectError(error.InvalidSession, remote.guestId(.invalid));
    try std.testing.expectError(error.InvalidSession, remote.clientName(.invalid, &.{}));
    try std.testing.expectError(error.InvalidSession, remote.formFactor(.invalid));
    try std.testing.expectError(error.InvalidSession, remote.resolution(.invalid));
    try std.testing.expectError(error.InvalidFriend, remote.invite(.{ .friend = .invalid }));
    try std.testing.expectEqual(@as(usize, 0), Fake.calls);
}

test "RemotePlay unavailable interface maps every method without Steam" {
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    Fake.reset();
    Fake.result = -1;
    Fake.bool_result = -1;
    Fake.name_result = -1;
    const remote: RemotePlay = .{ .lease = context.lease() };
    const session: Session = @fromBackingInt(@intCast(73));
    try std.testing.expectError(error.Unavailable, remote.sessionCount());
    try std.testing.expectError(error.Unavailable, remote.sessionAt(0));
    try std.testing.expectError(error.Unavailable, remote.isTogether(session));
    try std.testing.expectError(error.Unavailable, remote.steamId(session));
    try std.testing.expectError(error.Unavailable, remote.guestId(session));
    try std.testing.expectError(error.Unavailable, remote.clientName(session, &.{}));
    try std.testing.expectError(error.Unavailable, remote.formFactor(session));
    try std.testing.expectError(error.Unavailable, remote.resolution(session));
    try std.testing.expectError(error.Unavailable, remote.showTogetherUi());
    try std.testing.expectError(error.Unavailable, remote.invite(.guest));
    try std.testing.expectEqual(@as(usize, 10), Fake.calls);
}

test "RemotePlay invitation targets and explicit UI retain native rejection" {
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    Fake.reset();
    const remote: RemotePlay = .{ .lease = context.lease() };
    try std.testing.expect(try remote.showTogetherUi());
    try std.testing.expect(try remote.invite(.{ .friend = @fromBackingInt(@intCast(123456)) }));
    try std.testing.expectEqual(@as(u64, 123456), Fake.last_friend);
    try std.testing.expect(try remote.invite(.guest));
    try std.testing.expectEqual(@as(u64, 0), Fake.last_friend);
    Fake.bool_result = 0;
    try std.testing.expect(!try remote.showTogetherUi());
    try std.testing.expect(!try remote.invite(.{ .friend = @fromBackingInt(@intCast(123456)) }));
    try std.testing.expect(!try remote.invite(.guest));
    Fake.bool_result = 2;
    try std.testing.expectError(error.MalformedNativeOutput, remote.showTogetherUi());
}

test "RemotePlay copied client name distinguishes empty absent long and short" {
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    Fake.reset();
    const remote: RemotePlay = .{ .lease = context.lease() };
    const session: Session = @fromBackingInt(@intCast(73));
    var output: [3]u8 = @splat(0x7f);
    const name = try remote.clientName(session, &output);
    try std.testing.expectEqual(.complete, name.status);
    try std.testing.expectEqual(@as(?u32, 3), name.required_length);
    try std.testing.expectEqualStrings("abc", name.text.?);
    try std.testing.expectEqual(output[0..].ptr, name.text.?.ptr);
    Fake.required = 0;
    Fake.copied = 0;
    const empty = try remote.clientName(session, &.{});
    try std.testing.expectEqual(.complete, empty.status);
    try std.testing.expectEqual(@as(usize, 0), empty.text.?.len);
    for ([_]i32{ 1, 2, 3 }) |result| {
        Fake.name_result = result;
        Fake.required = 4;
        @memset(&output, 0x7f);
        const missing = try remote.clientName(session, &output);
        const expected: @TypeOf(missing.status) = if (result == 1) .absent else if (result == 2) .too_long else .buffer_too_small;
        try std.testing.expectEqual(expected, missing.status);
        try std.testing.expectEqual(@as(?u32, if (result == 3) 4 else null), missing.required_length);
        try std.testing.expect(missing.text == null);
        try std.testing.expectEqualSlices(u8, &.{ 0x7f, 0x7f, 0x7f }, &output);
    }
    Fake.name_result = 0;
    Fake.copied = 4;
    try std.testing.expectError(error.MalformedNativeOutput, remote.clientName(session, &output));
    Fake.copied = 2;
    try std.testing.expectError(error.MalformedNativeOutput, remote.clientName(session, &output));
    Fake.name_result = 3;
    try std.testing.expectError(error.MalformedNativeOutput, remote.clientName(session, &output));
    Fake.copied = 0;
    Fake.required = 1024;
    try std.testing.expectError(error.MalformedNativeOutput, remote.clientName(session, &output));
}
