const std = @import("std");
const Context = @import("Context.zig");
const types = @import("types.zig");
const Request = @import("requests.zig").Request;
const c = @cImport({
    @cInclude("services.h");
    @cInclude("core.h");
});
const SteamId = types.SteamId;
const AppId = types.AppId;

fn string(value: [:0]const u8) error{InteriorNul}!void {
    if (std.mem.indexOfScalar(u8, value, 0) != null) return error.InteriorNul;
}
fn name(value: [:0]const u8) error{ InteriorNul, EmptyName }!void {
    try string(value);
    if (value.len == 0) return error.EmptyName;
}
fn borrowed(value: [*c]const u8) []const u8 {
    return if (value == null) "" else std.mem.span(value);
}
fn accepted(value: u8) error{OperationFailed}!void {
    if (value == 0) return error.OperationFailed;
}
fn count(value: i32) error{InvalidNativeResult}!usize {
    if (value < 0) return error.InvalidNativeResult;
    return @intCast(value);
}
fn written(buffer: []u8, value: i32) error{ InvalidNativeResult, BufferTooSmall }![]u8 {
    const size = try count(value);
    if (size > buffer.len) return error.BufferTooSmall;
    return buffer[0..size];
}
fn readResult(buffer: []u8, value: i32, expected: usize) ![]u8 {
    if (value == 0 and expected != 0) return error.ReadFailed;
    return written(buffer, value);
}
fn imageByteCount(width: u32, height: u32) error{TooLarge}!usize {
    const pixels = std.math.mul(usize, width, height) catch return error.TooLarge;
    return std.math.mul(usize, pixels, 4) catch error.TooLarge;
}

/// Returned strings are borrowed until the next Steam call. Copy retained text.
pub const Friends = struct {
    lease: Context.Lease,
    pub const PersonaState = enum(i32) { offline = 0, online = 1, busy = 2, away = 3, snooze = 4, looking_to_trade = 5, looking_to_play = 6, invisible = 7, _ };
    pub const Overlay = enum { friends, community, players, settings, game_group, stats, achievements };
    pub const AvatarSize = enum(i32) { small, medium, large };
    pub const Avatar = union(enum) { none, pending, image: types.ImageHandle };
    pub const UserInfoOptions = struct { name_only: bool = false };
    pub const ImageSize = struct {
        width: u32,
        height: u32,

        /// Required capacity for readImage's tightly packed RGBA8 pixels.
        pub fn rgbaBytes(self: ImageSize) error{TooLarge}!usize {
            return imageByteCount(self.width, self.height);
        }
    };

    pub fn personaName(self: Friends) []const u8 {
        self.lease.check();
        return borrowed(c.sw_persona_name());
    }
    /// Copies the full name into caller storage, without a terminator or truncation.
    pub fn personaNameCopy(self: Friends, buffer: []u8) error{BufferTooSmall}![]u8 {
        return types.copyText(buffer, self.personaName());
    }
    /// Caller owns the returned bytes and must release them with allocator.free.
    pub fn personaNameAlloc(self: Friends, allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
        return allocator.dupe(u8, self.personaName());
    }
    /// Counts accepted friends, not invitations or blocked users.
    pub fn friendCount(self: Friends) !usize {
        self.lease.check();
        return count(c.sw_friend_count());
    }
    pub fn friendAt(self: Friends, index: usize) !SteamId {
        const i = try types.count(index);
        self.lease.check();
        const user = c.sw_friend_at(i);
        if (user == 0) return error.InvalidIndex;
        return @enumFromInt(user);
    }
    pub fn friendName(self: Friends, user: SteamId) []const u8 {
        self.lease.check();
        return borrowed(c.sw_friend_name(@intFromEnum(user)));
    }
    /// Copies the full name into caller storage, without a terminator or truncation.
    pub fn friendNameCopy(self: Friends, user: SteamId, buffer: []u8) error{BufferTooSmall}![]u8 {
        return types.copyText(buffer, self.friendName(user));
    }
    /// Caller owns the returned bytes and must release them with allocator.free.
    pub fn friendNameAlloc(self: Friends, allocator: std.mem.Allocator, user: SteamId) std.mem.Allocator.Error![]u8 {
        return allocator.dupe(u8, self.friendName(user));
    }
    pub fn state(self: Friends, user: SteamId) PersonaState {
        self.lease.check();
        return @enumFromInt(c.sw_friend_state(@intFromEnum(user)));
    }
    /// True means a request started. False can mean the data was already cached.
    pub fn requestUser(self: Friends, user: SteamId, options: UserInfoOptions) bool {
        self.lease.check();
        return c.sw_request_user(@intFromEnum(user), @intFromBool(options.name_only)) != 0;
    }
    /// A null value removes one key. Steam limits keys to 63 and values to 255 bytes.
    pub fn setPresence(self: Friends, key: [:0]const u8, value: ?[:0]const u8) !void {
        try name(key);
        if (key.len >= 64) return error.TooLarge;
        if (value) |v| {
            try string(v);
            if (v.len >= 256) return error.TooLarge;
        }
        self.lease.check();
        try accepted(c.sw_set_presence(key.ptr, if (value) |v| v.ptr else null));
    }
    pub fn clearPresence(self: Friends) void {
        self.lease.check();
        c.sw_clear_presence();
    }
    pub fn presence(self: Friends, user: SteamId, key: [:0]const u8) ![]const u8 {
        try name(key);
        self.lease.check();
        return borrowed(c.sw_friend_presence(@intFromEnum(user), key.ptr));
    }
    /// Copies the full value into caller storage, without a terminator or truncation.
    pub fn presenceCopy(self: Friends, user: SteamId, key: [:0]const u8, buffer: []u8) ![]u8 {
        return types.copyText(buffer, try self.presence(user, key));
    }
    /// Caller owns the returned bytes and must release them with allocator.free.
    pub fn presenceAlloc(self: Friends, allocator: std.mem.Allocator, user: SteamId, key: [:0]const u8) ![]u8 {
        return allocator.dupe(u8, try self.presence(user, key));
    }
    pub fn requestPresence(self: Friends, user: SteamId) void {
        self.lease.check();
        c.sw_request_presence(@intFromEnum(user));
    }
    /// Sends an invitation. Never call this automatically for arbitrary friends.
    pub fn invite(self: Friends, user: SteamId, connect: [:0]const u8) !void {
        try string(connect);
        self.lease.check();
        try accepted(c.sw_invite_game(@intFromEnum(user), connect.ptr));
    }
    pub fn openOverlay(self: Friends, dialog: Overlay) !void {
        self.lease.check();
        if (c.sw_overlay_enabled() == 0) return error.OverlayUnavailable;
        const value: [:0]const u8 = switch (dialog) {
            .friends => "Friends",
            .community => "Community",
            .players => "Players",
            .settings => "Settings",
            .game_group => "OfficialGameGroup",
            .stats => "Stats",
            .achievements => "Achievements",
        };
        c.sw_open_overlay(value.ptr);
    }
    /// Opens a page. It does not add items to a cart or initiate a purchase.
    pub fn openStore(self: Friends, app: AppId) !void {
        if (app == .invalid) return error.InvalidApp;
        self.lease.check();
        if (c.sw_overlay_enabled() == 0) return error.OverlayUnavailable;
        c.sw_open_store(@intFromEnum(app));
    }
    pub fn openInvite(self: Friends, lobby: SteamId) !void {
        if (lobby == .invalid) return error.InvalidLobby;
        self.lease.check();
        if (c.sw_overlay_enabled() == 0) return error.OverlayUnavailable;
        c.sw_open_invite(@intFromEnum(lobby));
    }
    pub fn avatar(self: Friends, user: SteamId, size: AvatarSize) Avatar {
        self.lease.check();
        const image = c.sw_avatar(@intFromEnum(user), @intFromEnum(size));
        return if (image < 0) .pending else if (image == 0) .none else .{ .image = @enumFromInt(image) };
    }
    /// Query before allocating caller-owned storage; no avatar dimensions are assumed.
    pub fn imageSize(self: Friends, image: types.ImageHandle) !ImageSize {
        if (@intFromEnum(image) <= 0) return error.InvalidImage;
        self.lease.check();
        var size: ImageSize = undefined;
        try accepted(c.sw_image_size(@intFromEnum(image), &size.width, &size.height));
        return size;
    }
    /// Returns the dimensions actually copied, which callers should use to upload pixels.
    pub fn readImage(self: Friends, image: types.ImageHandle, buffer: []u8) !ImageSize {
        const size = try self.imageSize(image);
        const bytes = try size.rgbaBytes();
        if (buffer.len < bytes) return error.BufferTooSmall;
        try accepted(c.sw_image_rgba(@intFromEnum(image), buffer.ptr, try types.count(bytes)));
        return size;
    }
};

pub const Apps = struct {
    lease: Context.Lease,
    pub const Dlc = struct { app: AppId, available: bool, name: []const u8 };
    pub const Download = struct { downloaded: u64, total: u64 };
    pub fn subscribed(self: Apps) bool {
        self.lease.check();
        return c.sw_subscribed() != 0;
    }
    pub fn owns(self: Apps, app: AppId) bool {
        self.lease.check();
        return c.sw_owns_app(@intFromEnum(app)) != 0;
    }
    /// Installation does not prove ownership.
    pub fn installed(self: Apps, app: AppId) bool {
        self.lease.check();
        return c.sw_app_installed(@intFromEnum(app)) != 0;
    }
    pub fn dlcInstalled(self: Apps, app: AppId) bool {
        self.lease.check();
        return c.sw_dlc_installed(@intFromEnum(app)) != 0;
    }
    pub fn dlcCount(self: Apps) !usize {
        self.lease.check();
        return count(c.sw_dlc_count());
    }
    /// The returned name borrows the caller's buffer.
    pub fn dlc(self: Apps, index: usize, buffer: []u8) !Dlc {
        if (buffer.len == 0) return error.BufferTooSmall;
        const i = try types.count(index);
        const capacity = try types.count(buffer.len);
        self.lease.check();
        var app: u32 = 0;
        var available: u8 = 0;
        @memset(buffer, 0);
        try accepted(c.sw_dlc_data(i, &app, &available, buffer.ptr, capacity));
        return .{ .app = @enumFromInt(app), .available = available != 0, .name = types.text(buffer) };
    }
    pub fn dlcProgress(self: Apps, app: AppId) !Download {
        self.lease.check();
        var result: Download = undefined;
        try accepted(c.sw_dlc_progress(@intFromEnum(app), &result.downloaded, &result.total));
        return result;
    }
    pub fn language(self: Apps) []const u8 {
        self.lease.check();
        return borrowed(c.sw_game_language());
    }
    pub fn availableLanguages(self: Apps) []const u8 {
        self.lease.check();
        return borrowed(c.sw_available_languages());
    }
    pub fn owner(self: Apps) SteamId {
        self.lease.check();
        return @enumFromInt(c.sw_app_owner());
    }
    pub fn buildId(self: Apps) i32 {
        self.lease.check();
        return c.sw_build_id();
    }
    /// Treat launch text as untrusted input, not executable console commands.
    pub fn launchCommandLine(self: Apps, buffer: []u8) ![]const u8 {
        if (buffer.len == 0) return error.BufferTooSmall;
        const capacity = try types.count(buffer.len);
        self.lease.check();
        @memset(buffer, 0);
        const result = c.sw_launch_command_line(buffer.ptr, capacity);
        if (result >= capacity) return error.BufferTooSmall;
        return written(buffer, result);
    }
};

/// SDK 1.65 synchronizes current-user stats at launch. No RequestCurrentStats call is needed.
pub const Stats = struct {
    lease: Context.Lease,
    pub const Achievement = struct { unlocked: bool, unlocked_at: u32 };
    pub const Attribute = enum { name, description, hidden };
    pub fn getInt(self: Stats, key: [:0]const u8) !i32 {
        try name(key);
        self.lease.check();
        var value: i32 = 0;
        try accepted(c.sw_stat_int(key.ptr, &value));
        return value;
    }
    pub fn getFloat(self: Stats, key: [:0]const u8) !f32 {
        try name(key);
        self.lease.check();
        var value: f32 = 0;
        try accepted(c.sw_stat_float(key.ptr, &value));
        return value;
    }
    pub fn setInt(self: Stats, key: [:0]const u8, value: i32) !void {
        try name(key);
        self.lease.check();
        try accepted(c.sw_set_stat_int(key.ptr, value));
    }
    pub fn setFloat(self: Stats, key: [:0]const u8, value: f32) !void {
        try name(key);
        if (!std.math.isFinite(value)) return error.InvalidValue;
        self.lease.check();
        try accepted(c.sw_set_stat_float(key.ptr, value));
    }
    pub fn achievement(self: Stats, key: [:0]const u8) !Achievement {
        try name(key);
        self.lease.check();
        var unlocked: u8 = 0;
        var time: u32 = 0;
        try accepted(c.sw_achievement(key.ptr, &unlocked, &time));
        return .{ .unlocked = unlocked != 0, .unlocked_at = time };
    }
    pub fn unlock(self: Stats, key: [:0]const u8) !void {
        try name(key);
        self.lease.check();
        try accepted(c.sw_unlock_achievement(key.ptr));
    }
    pub fn clear(self: Stats, key: [:0]const u8) !void {
        try name(key);
        self.lease.check();
        try accepted(c.sw_clear_achievement(key.ptr));
    }
    /// Displays progress. Reaching the maximum does not unlock the achievement.
    pub fn indicateProgress(self: Stats, key: [:0]const u8, current: u32, maximum: u32) !void {
        try name(key);
        if (maximum == 0 or current > maximum) return error.InvalidValue;
        self.lease.check();
        try accepted(c.sw_achievement_progress(key.ptr, current, maximum));
    }
    pub fn achievementCount(self: Stats) u32 {
        self.lease.check();
        return c.sw_achievement_count();
    }
    pub fn achievementName(self: Stats, index: u32) ![]const u8 {
        self.lease.check();
        if (index >= c.sw_achievement_count()) return error.InvalidIndex;
        return borrowed(c.sw_achievement_name(index));
    }
    pub fn attribute(self: Stats, key: [:0]const u8, attr: Attribute) ![]const u8 {
        try name(key);
        self.lease.check();
        const field: [:0]const u8 = switch (attr) {
            .name => "name",
            .description => "desc",
            .hidden => "hidden",
        };
        return borrowed(c.sw_achievement_attribute(key.ptr, field.ptr));
    }
    /// Acceptance is not completion. Observe stats_stored and its Steam result.
    pub fn store(self: Stats) !void {
        self.lease.check();
        try accepted(c.sw_store_stats());
    }
    /// Wait for the matching successful stats_received event before reading that user's data.
    /// Steam can evict it later: after stats_unloaded for that user, request again and wait.
    pub fn requestUser(self: Stats, user: SteamId) error{RequestRejected}!Request(.stats_received) {
        self.lease.check();
        return Request(.stats_received).init(@enumFromInt(c.sw_request_user_stats(@intFromEnum(user))));
    }
    /// Read after a successful stats_received from requestUser.
    /// After stats_unloaded for this user, request again and wait before reading.
    pub fn getUserInt(self: Stats, user: SteamId, key: [:0]const u8) !i32 {
        try name(key);
        self.lease.check();
        var value: i32 = 0;
        try accepted(c.sw_user_stat_int(@intFromEnum(user), key.ptr, &value));
        return value;
    }
    /// Read after a successful stats_received from requestUser.
    /// After stats_unloaded for this user, request again and wait before reading.
    pub fn getUserFloat(self: Stats, user: SteamId, key: [:0]const u8) !f32 {
        try name(key);
        self.lease.check();
        var value: f32 = 0;
        try accepted(c.sw_user_stat_float(@intFromEnum(user), key.ptr, &value));
        return value;
    }
    /// Read after a successful stats_received from requestUser.
    /// After stats_unloaded for this user, request again and wait before reading.
    pub fn userAchievement(self: Stats, user: SteamId, key: [:0]const u8) !Achievement {
        try name(key);
        self.lease.check();
        var unlocked: u8 = 0;
        var time: u32 = 0;
        try accepted(c.sw_user_achievement(@intFromEnum(user), key.ptr, &unlocked, &time));
        return .{ .unlocked = unlocked != 0, .unlocked_at = time };
    }
};

pub const Cloud = struct {
    lease: Context.Lease,
    pub const Quota = struct { total: u64, available: u64 };
    pub const File = struct { name: []const u8, size: usize };
    pub fn enabledForAccount(self: Cloud) bool {
        self.lease.check();
        return c.sw_cloud_account_enabled() != 0;
    }
    pub fn enabledForApp(self: Cloud) bool {
        self.lease.check();
        return c.sw_cloud_app_enabled() != 0;
    }
    pub fn exists(self: Cloud, path: [:0]const u8) !bool {
        try name(path);
        self.lease.check();
        return c.sw_cloud_exists(path.ptr) != 0;
    }
    pub fn fileSize(self: Cloud, path: [:0]const u8) !usize {
        try name(path);
        self.lease.check();
        if (c.sw_cloud_exists(path.ptr) == 0) return error.FileNotFound;
        return count(c.sw_cloud_file_size(path.ptr));
    }
    /// Synchronous bounded read for small files; disk IO can stall the render thread.
    /// Success can return only a prefix when buffer is smaller than the file (including empty).
    /// Complete-file consumers must provide capacity for fileSize and verify the returned length.
    /// Async reads are not exposed: their SDK data must be copied inside the native callback.
    pub fn read(self: Cloud, path: [:0]const u8, buffer: []u8) ![]u8 {
        try name(path);
        const capacity = try types.count(buffer.len);
        self.lease.check();
        if (c.sw_cloud_exists(path.ptr) == 0) return error.FileNotFound;
        const expected = @min(buffer.len, try count(c.sw_cloud_file_size(path.ptr)));
        if (expected == 0) return buffer[0..0];
        return readResult(buffer, c.sw_cloud_read(path.ptr, buffer.ptr, capacity), expected);
    }
    pub fn write(self: Cloud, path: [:0]const u8, bytes: []const u8) !void {
        try name(path);
        const size = try types.count(bytes.len);
        self.lease.check();
        try accepted(c.sw_cloud_write(path.ptr, bytes.ptr, size));
    }
    /// Steam copies the input during this call. Observe cloud_written for completion.
    pub fn writeAsync(self: Cloud, path: [:0]const u8, bytes: []const u8) !Request(.cloud_written) {
        try name(path);
        const size = std.math.cast(u32, bytes.len) orelse return error.TooLarge;
        self.lease.check();
        return Request(.cloud_written).init(@enumFromInt(c.sw_cloud_write_async(path.ptr, bytes.ptr, size)));
    }
    /// Deletes this one named cloud file. Call only on explicit application intent.
    pub fn delete(self: Cloud, path: [:0]const u8) !void {
        try name(path);
        self.lease.check();
        try accepted(c.sw_cloud_delete(path.ptr));
    }
    pub fn quota(self: Cloud) !Quota {
        self.lease.check();
        var result: Quota = undefined;
        try accepted(c.sw_cloud_quota(&result.total, &result.available));
        return result;
    }
    pub fn fileCount(self: Cloud) !usize {
        self.lease.check();
        return count(c.sw_cloud_file_count());
    }
    pub fn fileAt(self: Cloud, index: usize) !File {
        const i = try types.count(index);
        self.lease.check();
        if (i >= c.sw_cloud_file_count()) return error.InvalidIndex;
        var size: i32 = 0;
        const path = c.sw_cloud_file_at(i, &size);
        if (path == null) return error.InvalidNativeResult;
        return .{ .name = borrowed(path), .size = try count(size) };
    }
};

test "text checks reject silent C truncation and empty operation names" {
    try std.testing.expectError(error.InteriorNul, string("first\x00second"));
    try std.testing.expectError(error.EmptyName, name(""));
    try name("save.dat");
    try string("");
}

test "image byte counts and returned buffer lengths are bounded" {
    const size: Friends.ImageSize = .{ .width = 2, .height = 3 };
    try std.testing.expectEqual(@as(usize, 24), try size.rgbaBytes());
    const oversized: Friends.ImageSize = .{ .width = std.math.maxInt(u32), .height = std.math.maxInt(u32) };
    try std.testing.expectError(error.TooLarge, oversized.rgbaBytes());
    var buffer: [4]u8 = .{ 1, 2, 3, 4 };
    try std.testing.expectEqualSlices(u8, &.{ 1, 2 }, try written(&buffer, 2));
    try std.testing.expectError(error.InvalidNativeResult, written(&buffer, -1));
    try std.testing.expectError(error.BufferTooSmall, written(&buffer, 5));
}

test "cloud readResult distinguishes failures and returns successful borrowed prefixes" {
    var buffer: [4]u8 = .{ 1, 2, 3, 4 };
    try std.testing.expectError(error.ReadFailed, readResult(&buffer, 0, 4));
    try std.testing.expectEqual(@as(usize, 0), (try readResult(&buffer, 0, 0)).len);
    const prefix = try readResult(&buffer, 2, buffer.len);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2 }, prefix);
    try std.testing.expectEqual(buffer[0..].ptr, prefix.ptr);
    try std.testing.expectEqualSlices(u8, &buffer, try readResult(&buffer, 4, buffer.len));
}

test "native boolean failure does not invent a more precise Steam result" {
    try std.testing.expectError(error.OperationFailed, accepted(0));
    try accepted(1);
}

test "invalid typed image handles are rejected before calling Steam" {
    var context: Context = undefined;
    const friends: Friends = .{ .lease = .{ .context = &context, .generation = 0 } };
    try std.testing.expectError(error.InvalidImage, friends.imageSize(.invalid));
    try std.testing.expectError(error.InvalidImage, friends.imageSize(@enumFromInt(-1)));
}

test "Friends rejects oversized presence and invalid overlay targets before Steam" {
    var context: Context = undefined;
    const friends: Friends = .{ .lease = .{ .context = &context, .generation = 0 } };
    try std.testing.expectError(error.TooLarge, friends.setPresence("k" ** 64, null));
    try std.testing.expectError(error.TooLarge, friends.setPresence("key", "v" ** 256));
    try std.testing.expectError(error.InvalidApp, friends.openStore(.invalid));
    try std.testing.expectError(error.InvalidLobby, friends.openInvite(.invalid));
}

test "Stats rejects nonfinite values and impossible achievement progress before Steam" {
    var context: Context = undefined;
    const stats: Stats = .{ .lease = .{ .context = &context, .generation = 0 } };
    for ([_]f32{ std.math.nan(f32), std.math.inf(f32), -std.math.inf(f32) }) |value| {
        try std.testing.expectError(error.InvalidValue, stats.setFloat("stat", value));
    }
    try std.testing.expectError(error.InvalidValue, stats.indicateProgress("achievement", 0, 0));
    try std.testing.expectError(error.InvalidValue, stats.indicateProgress("achievement", 3, 2));
}

test "Apps rejects empty output storage and oversized DLC indices before Steam" {
    var context: Context = undefined;
    const apps: Apps = .{ .lease = .{ .context = &context, .generation = 0 } };
    var empty: [0]u8 = .{};
    try std.testing.expectError(error.BufferTooSmall, apps.dlc(0, &empty));
    try std.testing.expectError(error.BufferTooSmall, apps.launchCommandLine(&empty));
    var buffer: [16]u8 = undefined;
    try std.testing.expectError(error.TooLarge, apps.dlc(@as(usize, std.math.maxInt(i32)) + 1, &buffer));
}

test "analyze all public service methods" {
    std.testing.refAllDecls(Friends);
    std.testing.refAllDecls(Apps);
    std.testing.refAllDecls(Stats);
    std.testing.refAllDecls(Cloud);
}
