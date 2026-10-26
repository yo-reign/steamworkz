//! Borrowed Client facades for friends/presence, app queries, stats and cloud.
//! Each facade uses the owner's live thread/session; obtaining one does no work.
//! Valve interfaces are ISteamFriends, ISteamApps, ISteamUserStats and
//! ISteamRemoteStorage respectively; reference links live on each facade.
const std = @import("std");
const Context = @import("Context.zig");
const types = @import("types.zig");
const Request = @import("requests.zig").Request;
const c = @import("steamworkz_c");
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

/// ISteamFriends queries and explicit social/overlay actions; image access uses
/// ISteamUtils. Returned SDK strings expire at the next Steam call, pump or close.
/// Use the Copy/Alloc variants for retained names and presence.
/// Valve: https://partner.steamgames.com/doc/api/ISteamFriends
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

    /// ISteamFriends::GetPersonaName: local user's UTF-8 display name, not an ID.
    /// Borrows SDK storage until the next Steam call/pump/close. Use personaNameCopy
    /// for caller storage or personaNameAlloc for an allocator-owned copy.
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
    /// ISteamFriends::GetFriendCount with k_EFriendFlagImmediate: accepted friends,
    /// not invitations or blocked users.
    pub fn friendCount(self: Friends) !usize {
        self.lease.check();
        return count(c.sw_friend_count());
    }
    /// ISteamFriends::GetFriendByIndex with k_EFriendFlagImmediate. Use zero-based
    /// indices below friendCount; the list may change between calls. InvalidIndex
    /// means the SDK returned an invalid ID, not a stable enumeration snapshot.
    pub fn friendAt(self: Friends, index: usize) !SteamId {
        const i = try types.count(index);
        self.lease.check();
        const user = c.sw_friend_at(i);
        if (user == 0) return error.InvalidIndex;
        return @fromBackingInt(@intCast(user));
    }
    /// ISteamFriends::GetFriendPersonaName: cached UTF-8 name; not proof of friendship.
    /// Names may arrive asynchronously (requestUser / persona_changed). Borrows SDK
    /// storage until the next Steam call/pump/close; retain via friendNameCopy/Alloc.
    pub fn friendName(self: Friends, user: SteamId) []const u8 {
        self.lease.check();
        return borrowed(c.sw_friend_name(@backingInt(user)));
    }
    /// Copies the full name into caller storage, without a terminator or truncation.
    pub fn friendNameCopy(self: Friends, user: SteamId, buffer: []u8) error{BufferTooSmall}![]u8 {
        return types.copyText(buffer, self.friendName(user));
    }
    /// Caller owns the returned bytes and must release them with allocator.free.
    pub fn friendNameAlloc(self: Friends, allocator: std.mem.Allocator, user: SteamId) std.mem.Allocator.Error![]u8 {
        return allocator.dupe(u8, self.friendName(user));
    }
    /// ISteamFriends::GetFriendPersonaState: cached state, preserving unknown values.
    /// Offline can also mean Steam has no state information for this user.
    pub fn state(self: Friends, user: SteamId) PersonaState {
        self.lease.check();
        return @fromBackingInt(@intCast(c.sw_friend_state(@backingInt(user))));
    }
    /// ISteamFriends::RequestUserInformation. True starts a fetch; wait for
    /// PersonaStateChange_t (persona_changed) for this user. False can mean cached
    /// data. name_only avoids an avatar download; no typed Request is returned.
    pub fn requestUser(self: Friends, user: SteamId, options: UserInfoOptions) bool {
        self.lease.check();
        return c.sw_request_user(@backingInt(user), @intFromBool(options.name_only)) != 0;
    }
    /// ISteamFriends::SetRichPresence publishes local presence. A null value removes
    /// one key. Steam limits keys to 63 and values to 255 bytes (excluding NUL).
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
    /// ISteamFriends::ClearRichPresence removes all local rich-presence keys.
    pub fn clearPresence(self: Friends) void {
        self.lease.check();
        c.sw_clear_presence();
    }
    /// ISteamFriends::GetFriendRichPresence: cached text; empty is not a fetch status.
    /// Borrows SDK storage until the next Steam call/pump/close. Use presenceCopy/Alloc
    /// to retain it, or requestPresence to refresh the user's cache.
    pub fn presence(self: Friends, user: SteamId, key: [:0]const u8) ![]const u8 {
        try name(key);
        self.lease.check();
        return borrowed(c.sw_friend_presence(@backingInt(user), key.ptr));
    }
    /// Copies the full value into caller storage, without a terminator or truncation.
    pub fn presenceCopy(self: Friends, user: SteamId, key: [:0]const u8, buffer: []u8) ![]u8 {
        return types.copyText(buffer, try self.presence(user, key));
    }
    /// Caller owns the returned bytes and must release them with allocator.free.
    pub fn presenceAlloc(self: Friends, allocator: std.mem.Allocator, user: SteamId, key: [:0]const u8) ![]u8 {
        return allocator.dupe(u8, try self.presence(user, key));
    }
    /// ISteamFriends::RequestFriendRichPresence; observe FriendRichPresenceUpdate_t
    /// (presence_changed) for this user. Void submission, not completion.
    pub fn requestPresence(self: Friends, user: SteamId) void {
        self.lease.check();
        c.sw_request_presence(@backingInt(user));
    }
    /// ISteamFriends::InviteUserToGame sends connect text, not a connection.
    /// Native acceptance does not mean the invitee joined. Use only explicit intent.
    pub fn invite(self: Friends, user: SteamId, connect: [:0]const u8) !void {
        try string(connect);
        self.lease.check();
        try accepted(c.sw_invite_game(@backingInt(user), connect.ptr));
    }
    /// ISteamFriends::ActivateGameOverlay after ISteamUtils::IsOverlayEnabled.
    /// Explicit UI action; OverlayUnavailable means the precheck failed, while
    /// success only means the void activation was invoked.
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
        c.sw_open_store(@backingInt(app));
    }
    /// ISteamFriends::ActivateGameOverlayInviteDialog opens lobby-invite UI;
    /// it does not itself invite anyone. Fails with OverlayUnavailable if disabled.
    pub fn openInvite(self: Friends, lobby: SteamId) !void {
        if (lobby == .invalid) return error.InvalidLobby;
        self.lease.check();
        if (c.sw_overlay_enabled() == 0) return error.OverlayUnavailable;
        c.sw_open_invite(@backingInt(lobby));
    }
    /// ISteamFriends::GetSmallFriendAvatar / GetMediumFriendAvatar / GetLargeFriendAvatar.
    /// No image allocation is owned here. For pending large avatars, wait for
    /// AvatarImageLoaded_t (avatar_loaded), then query again. Read image handles via
    /// imageSize/readImage; do not assume fixed dimensions.
    pub fn avatar(self: Friends, user: SteamId, size: AvatarSize) Avatar {
        self.lease.check();
        const image = c.sw_avatar(@backingInt(user), @backingInt(size));
        return if (image < 0) .pending else if (image == 0) .none else .{ .image = @fromBackingInt(@intCast(image)) };
    }
    /// ISteamUtils::GetImageSize; query before allocating caller-owned RGBA storage.
    /// Works for achievement icons too; no avatar dimensions are assumed.
    pub fn imageSize(self: Friends, image: types.ImageHandle) !ImageSize {
        if (@backingInt(image) <= 0) return error.InvalidImage;
        self.lease.check();
        var size: ImageSize = undefined;
        try accepted(c.sw_image_size(@backingInt(image), &size.width, &size.height));
        return size;
    }
    /// ISteamUtils::GetImageRGBA copies tightly packed RGBA8 into caller storage.
    /// Require imageSize().rgbaBytes() capacity; returns dimensions for the copied
    /// pixels. No GPU upload or image cache is created by this wrapper.
    pub fn readImage(self: Friends, image: types.ImageHandle, buffer: []u8) !ImageSize {
        const size = try self.imageSize(image);
        const bytes = try size.rgbaBytes();
        if (buffer.len < bytes) return error.BufferTooSmall;
        try accepted(c.sw_image_rgba(@backingInt(image), buffer.ptr, try types.count(bytes)));
        return size;
    }
};

/// ISteamApps read-only license, installation and language queries.
/// Borrowed language strings must be copied before another Steam call/pump/close.
/// Valve: https://partner.steamgames.com/doc/api/ISteamApps
pub const Apps = struct {
    lease: Context.Lease,
    pub const Dlc = struct { app: AppId, available: bool, name: []const u8 };
    pub const Download = struct { downloaded: u64, total: u64 };
    /// ISteamApps::BIsSubscribed: active user's license for the current app.
    pub fn subscribed(self: Apps) bool {
        self.lease.check();
        return c.sw_subscribed() != 0;
    }
    /// ISteamApps::BIsSubscribedApp checks entitlement, not installation.
    pub fn owns(self: Apps, app: AppId) bool {
        self.lease.check();
        return c.sw_owns_app(@backingInt(app)) != 0;
    }
    /// ISteamApps::BIsAppInstalled; installation does not prove ownership.
    pub fn installed(self: Apps, app: AppId) bool {
        self.lease.check();
        return c.sw_app_installed(@backingInt(app)) != 0;
    }
    /// ISteamApps::BIsDlcInstalled checks both ownership and installation of DLC.
    pub fn dlcInstalled(self: Apps, app: AppId) bool {
        self.lease.check();
        return c.sw_dlc_installed(@backingInt(app)) != 0;
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
        return .{ .app = @fromBackingInt(@intCast(app)), .available = available != 0, .name = types.text(buffer) };
    }
    /// ISteamApps::GetDlcDownloadProgress; downloaded and total are byte counts.
    /// Native false becomes OperationFailed, not a zero-progress reading.
    pub fn dlcProgress(self: Apps, app: AppId) !Download {
        self.lease.check();
        var result: Download = undefined;
        try accepted(c.sw_dlc_progress(@backingInt(app), &result.downloaded, &result.total));
        return result;
    }
    /// ISteamApps::GetCurrentGameLanguage; borrowed language name, not a locale enum.
    /// Copy before another Steam call, pump or close.
    pub fn language(self: Apps) []const u8 {
        self.lease.check();
        return borrowed(c.sw_game_language());
    }
    /// ISteamApps::GetAvailableGameLanguages; borrowed comma-separated language names.
    /// Copy before another Steam call, pump or close.
    pub fn availableLanguages(self: Apps) []const u8 {
        self.lease.check();
        return borrowed(c.sw_available_languages());
    }
    /// ISteamApps::GetAppOwner; license owner may differ from the active user.
    pub fn owner(self: Apps) SteamId {
        self.lease.check();
        return @fromBackingInt(@intCast(c.sw_app_owner()));
    }
    /// ISteamApps::GetAppBuildId; current native build identifier, not an AppId.
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

/// ISteamUserStats. SDK 1.65 synchronizes current-user stats at launch; no
/// RequestCurrentStats call is needed. Setters change local state; store submits
/// persistence. Backend stat/achievement names and types must match app setup.
/// Valve: https://partner.steamgames.com/doc/api/ISteamUserStats
pub const Stats = struct {
    lease: Context.Lease,
    pub const Achievement = struct { unlocked: bool, unlocked_at: u32 };
    pub const Attribute = enum { name, description, hidden };
    pub const Leaderboard = types.Leaderboard;
    pub const LeaderboardEntry = types.LeaderboardEntry;
    pub const LeaderboardEntries = types.LeaderboardEntries;
    pub const Sort = enum(i32) { none = 0, ascending = 1, descending = 2, _ };
    pub const Display = enum(i32) { none = 0, numeric = 1, time_seconds = 2, time_milliseconds = 3, _ };
    /// Name borrows caller storage only. Null and empty names are distinct.
    pub const LeaderboardMetadata = struct { name: ?[]const u8, entry_count: i32, sort: Sort, display: Display };
    pub const DownloadWindow = union(enum) {
        global: struct { first_rank: u32, last_rank: u32 },
        around_user: struct { before: u32, after: u32 },
    };
    pub const UploadOptions = struct {
        method: enum { keep_best, force_update } = .keep_best,
        score: i32,
        details: []const i32 = &.{},
    };
    /// Opaque native cursor, not a row index or resource owner. Never retain
    /// across a percentage refresh, event pump or session change.
    pub const PercentageIterator = enum(i32) { invalid = -1, _ };
    pub const GlobalPercentage = struct {
        iterator: PercentageIterator,
        name_length: u32,
        name_bytes: [128]u8,
        percent: f32,
        achieved: bool,
        pub fn nameBytes(self: *const GlobalPercentage) []const u8 {
            return self.name_bytes[0..self.name_length];
        }
    };
    pub const PercentageStep = union(enum) {
        item: GlobalPercentage,
        /// Native -1 cannot distinguish unavailable data from end of iteration.
        no_data_or_end,
        unexpected_iterator: i32,
    };

    fn boundedName(key: [:0]const u8) !void {
        try name(key);
        if (key.len >= 128) return error.TooLarge;
    }
    fn leaderboardName(key: [:0]const u8) !void {
        try boundedName(key);
        if (!std.unicode.utf8ValidateSlice(key)) return error.InvalidUtf8;
    }
    fn validLeaderboard(board: Leaderboard) !void {
        if (board == .invalid) return error.InvalidLeaderboard;
    }
    fn available(result: u8) !void {
        if (result == 0) return error.InterfaceUnavailable;
    }
    fn windowRange(window: DownloadWindow) !struct { around: u8, first: i32, last: i32 } {
        return switch (window) {
            .global => |range| blk: {
                if (range.first_rank == 0 or range.last_rank < range.first_rank or range.last_rank > std.math.maxInt(i32)) return error.InvalidRange;
                if (range.last_rank - range.first_rank >= 100) return error.TooLarge;
                break :blk .{ .around = 0, .first = @intCast(range.first_rank), .last = @intCast(range.last_rank) };
            },
            .around_user => |range| blk: {
                if (range.before >= 100 or range.after >= 100 or range.before + range.after >= 100) return error.TooLarge;
                break :blk .{ .around = 1, .first = -@as(i32, @intCast(range.before)), .last = @intCast(range.after) };
            },
        };
    }
    fn downloadReady(self: Stats) !void {
        if (self.lease.context.leaderboard_download_blocked) return error.DownloadBlocked;
        if (self.lease.context.leaderboard_download_call != 0) return error.DownloadPending;
    }
    fn trackDownload(self: Stats, call: u64) !Request(.leaderboard_entries) {
        const request = try Request(.leaderboard_entries).init(@fromBackingInt(@intCast(call)));
        self.lease.context.leaderboard_download_call = call;
        return request;
    }

    /// Zero is preserved; it does not distinguish fetching from no image.
    pub fn achievementIcon(self: Stats, key: [:0]const u8) !types.ImageHandle {
        return self.achievementIconWith(c, key);
    }
    fn achievementIconWith(self: Stats, comptime native: type, key: [:0]const u8) !types.ImageHandle {
        self.lease.check();
        try boundedName(key);
        var image: i32 = 0;
        try available(native.sw_stats_achievement_icon(key.ptr, &image));
        return @fromBackingInt(@intCast(image));
    }
    /// ISteamUserStats::FindLeaderboard; never creates a backend leaderboard.
    /// Take the LeaderboardFindResult_t (leaderboard_found) completion and check
    /// found before using leaderboard; request acceptance alone proves neither.
    pub fn findLeaderboard(self: Stats, key: [:0]const u8) !Request(.leaderboard_found) {
        return self.findLeaderboardWith(c, key);
    }
    fn findLeaderboardWith(self: Stats, comptime native: type, key: [:0]const u8) !Request(.leaderboard_found) {
        self.lease.check();
        try leaderboardName(key);
        var call: u64 = 0;
        try available(native.sw_stats_find_leaderboard(key.ptr, &call));
        return Request(.leaderboard_found).init(@fromBackingInt(@intCast(call)));
    }
    /// Immediately copies the full SDK name without NUL or truncation.
    pub fn leaderboardMetadata(self: Stats, board: Leaderboard, buffer: []u8) !LeaderboardMetadata {
        return self.leaderboardMetadataWith(c, board, buffer);
    }
    fn leaderboardMetadataWith(self: Stats, comptime native: type, board: Leaderboard, buffer: []u8) !LeaderboardMetadata {
        self.lease.check();
        try validLeaderboard(board);
        var out: c.sw_stats_leaderboard_metadata = undefined;
        const status = native.sw_stats_leaderboard_metadata_copy(@backingInt(board), buffer.ptr, buffer.len, &out);
        switch (status) {
            c.SW_STATS_TEXT_OK, c.SW_STATS_TEXT_NULL => {},
            c.SW_STATS_TEXT_UNAVAILABLE => return error.InterfaceUnavailable,
            c.SW_STATS_TEXT_SHORT => return error.BufferTooSmall,
            else => return error.InvalidNativeResult,
        }
        if (out.name_length > buffer.len) return error.InvalidNativeResult;
        return .{ .name = if (status == c.SW_STATS_TEXT_NULL) null else buffer[0..out.name_length], .entry_count = out.entry_count, .sort = @fromBackingInt(@intCast(out.sort)), .display = @fromBackingInt(@intCast(out.display)) };
    }
    /// Must pump/drain completion even if Request is discarded: it does not
    /// cancel or clear the session slot. Uncertain native cleanup blocks further
    /// downloads until a new session; restarting is not a native release claim.
    pub fn downloadLeaderboard(self: Stats, board: Leaderboard, window: DownloadWindow) !Request(.leaderboard_entries) {
        return self.downloadLeaderboardWith(c, board, window);
    }
    fn downloadLeaderboardWith(self: Stats, comptime native: type, board: Leaderboard, window: DownloadWindow) !Request(.leaderboard_entries) {
        self.lease.check();
        try self.downloadReady();
        try validLeaderboard(board);
        const range = try windowRange(window);
        var call: u64 = 0;
        try available(native.sw_stats_download(@backingInt(board), range.around, range.first, range.last, &call));
        return self.trackDownload(call);
    }
    /// 1..100 exact IDs, including duplicates/invalid IDs for SDK validation.
    /// Shares downloadLeaderboard's mandatory draining and uncertainty policy.
    pub fn downloadLeaderboardUsers(self: Stats, board: Leaderboard, users: []const SteamId) !Request(.leaderboard_entries) {
        return self.downloadLeaderboardUsersWith(c, board, users);
    }
    fn downloadLeaderboardUsersWith(self: Stats, comptime native: type, board: Leaderboard, users: []const SteamId) !Request(.leaderboard_entries) {
        self.lease.check();
        try self.downloadReady();
        try validLeaderboard(board);
        if (users.len == 0 or users.len > 100) return error.InvalidUserCount;
        var ids: [100]u64 = undefined;
        for (users, 0..) |user, i| ids[i] = @backingInt(user);
        var call: u64 = 0;
        try available(native.sw_stats_download_users(@backingInt(board), &ids, @intCast(users.len), &call));
        return self.trackDownload(call);
    }
    /// Explicit persistent action. Native limit: ten uploads per ten minutes,
    /// one outstanding upload. No scheduler/retry. Drain matching completion
    /// even when discarding Request; acceptance is not operation success.
    pub fn uploadLeaderboard(self: Stats, board: Leaderboard, options: UploadOptions) !Request(.leaderboard_uploaded) {
        return self.uploadLeaderboardWith(c, board, options);
    }
    fn uploadLeaderboardWith(self: Stats, comptime native: type, board: Leaderboard, options: UploadOptions) !Request(.leaderboard_uploaded) {
        self.lease.check();
        if (self.lease.context.leaderboard_upload_call != 0) return error.UploadPending;
        try validLeaderboard(board);
        if (options.details.len > 64) return error.TooLarge;
        var call: u64 = 0;
        try available(native.sw_stats_upload(@backingInt(board), @intFromBool(options.method == .force_update), options.score, options.details.ptr, @intCast(options.details.len), &call));
        const request = try Request(.leaderboard_uploaded).init(@fromBackingInt(@intCast(call)));
        self.lease.context.leaderboard_upload_call = call;
        return request;
    }
    /// ISteamUserStats::RequestGlobalAchievementPercentages. Take the matching
    /// GlobalAchievementPercentagesReady_t (global_percentages_ready) and check
    /// result == .ok before reading percentages; no implicit fetch on reads.
    pub fn requestGlobalPercentages(self: Stats) !Request(.global_percentages_ready) {
        return self.requestGlobalPercentagesWith(c);
    }
    fn requestGlobalPercentagesWith(self: Stats, comptime native: type) !Request(.global_percentages_ready) {
        self.lease.check();
        var call: u64 = 0;
        try available(native.sw_stats_request_global_percentages(&call));
        return Request(.global_percentages_ready).init(@fromBackingInt(@intCast(call)));
    }
    /// Wait for a successful request before reading. No readiness cache or
    /// stable snapshot is promised. Each read performs exactly one native step.
    pub fn firstGlobalPercentage(self: Stats) !PercentageStep {
        return self.percentageStepWith(c, null);
    }
    pub fn nextGlobalPercentage(self: Stats, previous: PercentageIterator) !PercentageStep {
        return self.percentageStepWith(c, previous);
    }
    fn percentageStepWith(self: Stats, comptime native: type, previous: ?PercentageIterator) !PercentageStep {
        self.lease.check();
        if (previous) |cursor| if (@backingInt(cursor) < 0) return error.InvalidIterator;
        var out: c.sw_stats_percentage = undefined;
        switch (native.sw_stats_percentage_step(@intFromBool(previous == null), if (previous) |cursor| @backingInt(cursor) else 0, &out)) {
            c.SW_STATS_PERCENTAGE_ITEM => {},
            c.SW_STATS_PERCENTAGE_UNAVAILABLE => return error.InterfaceUnavailable,
            c.SW_STATS_PERCENTAGE_END => return .no_data_or_end,
            c.SW_STATS_PERCENTAGE_NEGATIVE => return .{ .unexpected_iterator = out.iterator },
            c.SW_STATS_PERCENTAGE_UNTERMINATED => return error.UnterminatedName,
            else => return error.InvalidNativeResult,
        }
        if (out.name_length >= 128 or out.iterator < 0) return error.InvalidNativeResult;
        return .{ .item = .{ .iterator = @fromBackingInt(@intCast(out.iterator)), .name_length = out.name_length, .name_bytes = out.name, .percent = @bitCast(out.percent_bits), .achieved = out.achieved != 0 } };
    }
    /// Null means native false, not missing interface. Wait for successful
    /// global percentages request first. Float bits are not clamped.
    pub fn globalPercentage(self: Stats, key: [:0]const u8) !?f32 {
        return self.globalPercentageWith(c, key);
    }
    fn globalPercentageWith(self: Stats, comptime native: type, key: [:0]const u8) !?f32 {
        self.lease.check();
        try boundedName(key);
        var bits: u32 = 0;
        return switch (native.sw_stats_achievement_percentage(key.ptr, &bits)) {
            -1 => error.InterfaceUnavailable,
            0 => null,
            1 => @as(f32, @bitCast(bits)),
            else => error.InvalidNativeResult,
        };
    }
    /// ISteamUserStats::GetStat (int32): cached current-user stat by backend name.
    /// Native false is OperationFailed, not a default zero.
    pub fn getInt(self: Stats, key: [:0]const u8) !i32 {
        try name(key);
        self.lease.check();
        var value: i32 = 0;
        try accepted(c.sw_stat_int(key.ptr, &value));
        return value;
    }
    /// ISteamUserStats::GetStat (float): cached current-user stat by backend name.
    /// Native false is OperationFailed; returned native float bits are preserved.
    pub fn getFloat(self: Stats, key: [:0]const u8) !f32 {
        try name(key);
        self.lease.check();
        var value: f32 = 0;
        try accepted(c.sw_stat_float(key.ptr, &value));
        return value;
    }
    /// ISteamUserStats::SetStat (int32) changes local cached state; call store to persist.
    pub fn setInt(self: Stats, key: [:0]const u8, value: i32) !void {
        try name(key);
        self.lease.check();
        try accepted(c.sw_set_stat_int(key.ptr, value));
    }
    /// ISteamUserStats::SetStat (float) changes local state; rejects non-finite input.
    /// Call store to submit persistence, then inspect stats_stored.result.
    pub fn setFloat(self: Stats, key: [:0]const u8, value: f32) !void {
        try name(key);
        if (!std.math.isFinite(value)) return error.InvalidValue;
        self.lease.check();
        try accepted(c.sw_set_stat_float(key.ptr, value));
    }
    /// ISteamUserStats::GetAchievementAndUnlockTime. unlocked_at is Unix seconds;
    /// zero can mean locked or an unlocked achievement without a recorded time.
    pub fn achievement(self: Stats, key: [:0]const u8) !Achievement {
        try name(key);
        self.lease.check();
        var unlocked: u8 = 0;
        var time: u32 = 0;
        try accepted(c.sw_achievement(key.ptr, &unlocked, &time));
        return .{ .unlocked = unlocked != 0, .unlocked_at = time };
    }
    /// ISteamUserStats::SetAchievement updates local state; store submits persistence.
    pub fn unlock(self: Stats, key: [:0]const u8) !void {
        try name(key);
        self.lease.check();
        try accepted(c.sw_unlock_achievement(key.ptr));
    }
    /// ISteamUserStats::ClearAchievement resets local unlock state; store submits it.
    /// Destructive achievement change: use only explicit application intent.
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
    /// ISteamUserStats::GetAchievementName: backend name at a zero-based index.
    /// Borrows SDK text until another Steam call/pump/close; copy before retaining.
    pub fn achievementName(self: Stats, index: u32) ![]const u8 {
        self.lease.check();
        if (index >= c.sw_achievement_count()) return error.InvalidIndex;
        return borrowed(c.sw_achievement_name(index));
    }
    /// ISteamUserStats::GetAchievementDisplayAttribute: localized name/description
    /// or the native hidden string. Borrows SDK text until another Steam call/pump/close.
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
    /// ISteamUserStats::StoreStats submits cached changes. Observe UserStatsStored_t
    /// (stats_stored) and its result; acceptance does not establish persistence.
    pub fn store(self: Stats) !void {
        self.lease.check();
        try accepted(c.sw_store_stats());
    }
    /// Wait for the matching successful stats_received event before reading that user's data.
    /// Steam can evict it later: after stats_unloaded for that user, request again and wait.
    pub fn requestUser(self: Stats, user: SteamId) error{RequestRejected}!Request(.stats_received) {
        self.lease.check();
        return Request(.stats_received).init(@fromBackingInt(@intCast(c.sw_request_user_stats(@backingInt(user)))));
    }
    /// Read after a successful stats_received from requestUser.
    /// After stats_unloaded for this user, request again and wait before reading.
    pub fn getUserInt(self: Stats, user: SteamId, key: [:0]const u8) !i32 {
        try name(key);
        self.lease.check();
        var value: i32 = 0;
        try accepted(c.sw_user_stat_int(@backingInt(user), key.ptr, &value));
        return value;
    }
    /// Read after a successful stats_received from requestUser.
    /// After stats_unloaded for this user, request again and wait before reading.
    pub fn getUserFloat(self: Stats, user: SteamId, key: [:0]const u8) !f32 {
        try name(key);
        self.lease.check();
        var value: f32 = 0;
        try accepted(c.sw_user_stat_float(@backingInt(user), key.ptr, &value));
        return value;
    }
    /// Read after a successful stats_received from requestUser.
    /// After stats_unloaded for this user, request again and wait before reading.
    pub fn userAchievement(self: Stats, user: SteamId, key: [:0]const u8) !Achievement {
        try name(key);
        self.lease.check();
        var unlocked: u8 = 0;
        var time: u32 = 0;
        try accepted(c.sw_user_achievement(@backingInt(user), key.ptr, &unlocked, &time));
        return .{ .unlocked = unlocked != 0, .unlocked_at = time };
    }
};

/// ISteamRemoteStorage named cloud files and explicit write-batch hints.
/// Paths passed to file operations are Steam filenames, not arbitrary OS paths.
/// Writes/deletes affect persistent saves; no conflict or retry policy is supplied.
/// Valve: https://partner.steamgames.com/doc/api/ISteamRemoteStorage
pub const Cloud = struct {
    lease: Context.Lease,
    pub const Quota = struct { total: u64, available: u64 };
    pub const File = struct { name: []const u8, size: usize };
    pub const LocalChangeType = enum(i32) { invalid = 0, file_updated = 1, file_deleted = 2, _ };
    pub const FilePathType = enum(i32) { invalid = 0, absolute = 1, api_filename = 2, _ };
    /// Path borrows only the caller's output storage, never SDK memory.
    pub const LocalChange = struct { path: []const u8, change: LocalChangeType, path_type: FilePathType };
    pub const LocalChangeError = error{ InterfaceUnavailable, NativeCountFailed, InvalidIndex, NullPath, BufferTooSmall, InvalidNativeResult };

    /// Live query, not a callback-time snapshot. Enumerate promptly on the owner
    /// thread before another pump; separate calls do not form a stable snapshot.
    pub fn localChangeCount(self: Cloud) LocalChangeError!usize {
        return self.localChangeCountWith(c);
    }
    fn localChangeCountWith(self: Cloud, comptime native: type) LocalChangeError!usize {
        self.lease.check();
        var value: i32 = 0;
        if (native.sw_cloud_local_change_count(&value) == 0) return error.InterfaceUnavailable;
        if (value < 0) return error.NativeCountFailed;
        return @intCast(value);
    }
    /// Copies immediately, without NUL or truncation. Empty paths succeed; null
    /// paths fail. Short storage is unchanged. Bounds are checked against the
    /// current count, not an earlier notification or localChangeCount call.
    /// Absolute paths are NOT filenames for read/write/delete. This does not read
    /// files, reload saves, resolve conflicts or enable dynamic sync.
    pub fn localChangeAt(self: Cloud, index: usize, buffer: []u8) LocalChangeError!LocalChange {
        return self.localChangeAtWith(c, index, buffer);
    }
    fn localChangeAtWith(self: Cloud, comptime native: type, index: usize, buffer: []u8) LocalChangeError!LocalChange {
        self.lease.check();
        const i = std.math.cast(i32, index) orelse return error.InvalidIndex;
        var output: c.sw_cloud_local_change = undefined;
        switch (native.sw_cloud_local_change_copy(i, buffer.ptr, buffer.len, &output)) {
            c.SW_CLOUD_CHANGE_OK => {},
            c.SW_CLOUD_CHANGE_UNAVAILABLE => return error.InterfaceUnavailable,
            c.SW_CLOUD_CHANGE_COUNT_FAILED => return error.NativeCountFailed,
            c.SW_CLOUD_CHANGE_INVALID_INDEX => return error.InvalidIndex,
            c.SW_CLOUD_CHANGE_NULL_PATH => return error.NullPath,
            c.SW_CLOUD_CHANGE_SHORT_BUFFER => return error.BufferTooSmall,
            else => return error.InvalidNativeResult,
        }
        if (output.path_length > buffer.len) return error.InvalidNativeResult;
        return .{ .path = buffer[0..output.path_length], .change = @fromBackingInt(@intCast(output.change)), .path_type = @fromBackingInt(@intCast(output.path_type)) };
    }

    pub const BeginWriteBatchError = error{ BatchAlreadyActive, TokenExhausted, InterfaceUnavailable, NativeBatchAlreadyActive };
    /// Acquires a hint only: no transaction, flush, durability or rollback claim.
    /// Caller must explicitly end the acquired owner before Client.deinit.
    pub fn beginWriteBatch(self: Cloud) BeginWriteBatchError!WriteBatch {
        return self.beginWriteBatchWith(c);
    }
    fn beginWriteBatchWith(self: Cloud, comptime native: type) BeginWriteBatchError!WriteBatch {
        self.lease.check();
        const context = self.lease.context;
        if (context.cloud_batch_active != 0) return error.BatchAlreadyActive;
        if (context.cloud_batch_serial == std.math.maxInt(u64)) return error.TokenExhausted;
        context.cloud_batch_serial += 1;
        switch (native.sw_cloud_begin_write_batch()) {
            -1 => return error.InterfaceUnavailable,
            0 => return error.NativeBatchAlreadyActive,
            else => {},
        }
        context.cloud_batch_active = context.cloud_batch_serial;
        return .{ .lease = self.lease, .token = context.cloud_batch_active };
    }

    /// Single logical owner: do not copy a live value. A move must abandon the
    /// source. Tokens prevent stale copies ending later batches; they cannot
    /// make two copies independent owners. No automatic teardown or retry.
    pub const WriteBatch = struct {
        lease: Context.Lease,
        token: u64,
        pub const EndOutcome = enum { ended, no_native_batch, already_closed };
        pub const EndError = error{ InterfaceUnavailable, StaleBatch };
        /// Native true/false both consume the owner, neither means save success.
        /// Unavailable interface retains it for an explicit later attempt.
        /// Even repeated end requires the original live owner-thread session.
        pub fn end(self: *WriteBatch) EndError!EndOutcome {
            return self.endWith(c);
        }
        fn endWith(self: *WriteBatch, comptime native: type) EndError!EndOutcome {
            self.lease.check();
            if (self.token == 0) return .already_closed;
            const context = self.lease.context;
            if (context.cloud_batch_active != self.token) return error.StaleBatch;
            const result = native.sw_cloud_end_write_batch();
            if (result == -1) return error.InterfaceUnavailable;
            context.cloud_batch_active = 0;
            self.token = 0;
            return if (result == 0) .no_native_batch else .ended;
        }
    };
    /// ISteamRemoteStorage::IsCloudEnabledForAccount; app enablement is separate.
    pub fn enabledForAccount(self: Cloud) bool {
        self.lease.check();
        return c.sw_cloud_account_enabled() != 0;
    }
    /// ISteamRemoteStorage::IsCloudEnabledForApp; account enablement is separate.
    pub fn enabledForApp(self: Cloud) bool {
        self.lease.check();
        return c.sw_cloud_app_enabled() != 0;
    }
    pub fn exists(self: Cloud, path: [:0]const u8) !bool {
        try name(path);
        self.lease.check();
        return c.sw_cloud_exists(path.ptr) != 0;
    }
    /// ISteamRemoteStorage::GetFileSize after FileExists. Returns bytes or
    /// FileNotFound; a later read can observe a changed file.
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
    /// ISteamRemoteStorage::FileWrite synchronously replaces this named file.
    /// Borrows input for this call only. OperationFailed preserves native false;
    /// success is not a remote-cloud synchronization acknowledgement.
    pub fn write(self: Cloud, path: [:0]const u8, bytes: []const u8) !void {
        try name(path);
        const size = try types.count(bytes.len);
        self.lease.check();
        try accepted(c.sw_cloud_write(path.ptr, bytes.ptr, size));
    }
    /// ISteamRemoteStorage::FileWriteAsync copies input during this call.
    /// Take RemoteStorageFileWriteAsyncComplete_t (cloud_written) and inspect its
    /// result. Returning a Request means accepted, not successful file persistence.
    pub fn writeAsync(self: Cloud, path: [:0]const u8, bytes: []const u8) !Request(.cloud_written) {
        try name(path);
        const size = std.math.cast(u32, bytes.len) orelse return error.TooLarge;
        self.lease.check();
        return Request(.cloud_written).init(@fromBackingInt(@intCast(c.sw_cloud_write_async(path.ptr, bytes.ptr, size))));
    }
    /// Deletes this one named cloud file. Call only on explicit application intent.
    pub fn delete(self: Cloud, path: [:0]const u8) !void {
        try name(path);
        self.lease.check();
        try accepted(c.sw_cloud_delete(path.ptr));
    }
    /// ISteamRemoteStorage::GetQuota; total and available are bytes, not file counts.
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
    /// ISteamRemoteStorage::GetFileNameAndSize; zero-based index below fileCount.
    /// size is bytes; name borrows SDK storage until another Steam call/pump/close.
    /// Copy name before further enumeration or file operations.
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
    try std.testing.expectError(error.InvalidImage, friends.imageSize(@fromBackingInt(@intCast(-1))));
}

test "Friends rejects oversized presence and invalid overlay targets before Steam" {
    var context: Context = undefined;
    const friends: Friends = .{ .lease = .{ .context = &context, .generation = 0 } };
    try std.testing.expectError(error.TooLarge, friends.setPresence(&@as([64:0]u8, @splat('k')), null));
    try std.testing.expectError(error.TooLarge, friends.setPresence("key", &@as([256:0]u8, @splat('v'))));
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

test "Cloud local changes preserve signed failure, bounds, copied paths and future enums" {
    const Native = struct {
        var value: i32 = 0;
        var available: bool = true;
        var status: u8 = c.SW_CLOUD_CHANGE_OK;
        var copies: usize = 0;
        fn sw_cloud_local_change_count(out: *i32) u8 {
            out.* = value;
            return @intFromBool(available);
        }
        fn sw_cloud_local_change_copy(index: i32, buffer: [*]u8, capacity: usize, out: *c.sw_cloud_local_change) u8 {
            std.debug.assert(index == 0);
            copies += 1;
            if (status != c.SW_CLOUD_CHANGE_OK) return status;
            out.* = .{ .path_length = 3, .change = 123456, .path_type = -7654 };
            if (capacity < 3) return c.SW_CLOUD_CHANGE_SHORT_BUFFER;
            @memcpy(buffer[0..3], "abc");
            return c.SW_CLOUD_CHANGE_OK;
        }
    };
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    const cloud: Cloud = .{ .lease = context.lease() };
    try std.testing.expectEqual(@as(usize, 0), try cloud.localChangeCountWith(Native));
    Native.value = -7;
    try std.testing.expectError(error.NativeCountFailed, cloud.localChangeCountWith(Native));
    Native.value = 3;
    try std.testing.expectEqual(@as(usize, 3), try cloud.localChangeCountWith(Native));
    Native.available = false;
    try std.testing.expectError(error.InterfaceUnavailable, cloud.localChangeCountWith(Native));
    var buffer: [4]u8 = @splat(0xa5);
    try std.testing.expectError(error.InvalidIndex, cloud.localChangeAtWith(Native, @as(usize, std.math.maxInt(i32)) + 1, &buffer));
    try std.testing.expectEqual(@as(usize, 0), Native.copies);
    const result = try cloud.localChangeAtWith(Native, 0, &buffer);
    try std.testing.expectEqualStrings("abc", result.path);
    try std.testing.expectEqual(buffer[0..].ptr, result.path.ptr);
    try std.testing.expectEqual(@as(i32, 123456), @backingInt(result.change));
    try std.testing.expectEqual(@as(i32, -7654), @backingInt(result.path_type));
    try std.testing.expectEqual(@as(u8, 0xa5), buffer[3]);
    try std.testing.expectError(error.BufferTooSmall, cloud.localChangeAtWith(Native, 0, buffer[0..2]));
    const cases = .{
        .{ c.SW_CLOUD_CHANGE_UNAVAILABLE, error.InterfaceUnavailable },
        .{ c.SW_CLOUD_CHANGE_COUNT_FAILED, error.NativeCountFailed },
        .{ c.SW_CLOUD_CHANGE_INVALID_INDEX, error.InvalidIndex },
        .{ c.SW_CLOUD_CHANGE_NULL_PATH, error.NullPath },
    };
    inline for (cases) |case| {
        Native.status = case[0];
        try std.testing.expectError(case[1], cloud.localChangeAtWith(Native, 0, &buffer));
    }
}

test "Cloud WriteBatch owns only acquired hints and protects later batches" {
    const Native = struct {
        var begin_result: i32 = 0;
        var end_result: i32 = 1;
        var begins: usize = 0;
        var ends: usize = 0;
        fn sw_cloud_begin_write_batch() i32 {
            begins += 1;
            return begin_result;
        }
        fn sw_cloud_end_write_batch() i32 {
            ends += 1;
            return end_result;
        }
        fn cleanup(owner: *Cloud.WriteBatch) void {
            end_result = 1;
            _ = owner.endWith(@This()) catch unreachable;
        }
        fn expectBeginError(cloud: Cloud, expected: Cloud.BeginWriteBatchError) !void {
            if (cloud.beginWriteBatchWith(@This())) |acquired| {
                var owner = acquired;
                defer cleanup(&owner);
                return error.TestUnexpectedResult;
            } else |err| try std.testing.expectEqual(expected, err);
        }
    };
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    const cloud: Cloud = .{ .lease = context.lease() };
    try Native.expectBeginError(cloud, error.NativeBatchAlreadyActive);
    try std.testing.expectEqual(@as(usize, 0), Native.ends);
    try std.testing.expectEqual(@as(u64, 0), context.cloud_batch_active);
    Native.begin_result = -1;
    try Native.expectBeginError(cloud, error.InterfaceUnavailable);
    try std.testing.expectEqual(@as(u64, 0), context.cloud_batch_active);
    Native.begin_result = 1;
    var first = try cloud.beginWriteBatchWith(Native);
    defer Native.cleanup(&first);
    var stale = first;
    const begins = Native.begins;
    try Native.expectBeginError(cloud, error.BatchAlreadyActive);
    try std.testing.expectEqual(begins, Native.begins);
    Native.end_result = -1;
    try std.testing.expectError(error.InterfaceUnavailable, first.endWith(Native));
    try std.testing.expectEqual(first.token, context.cloud_batch_active);
    Native.end_result = 0;
    try std.testing.expectEqual(.no_native_batch, try first.endWith(Native));
    const ends = Native.ends;
    try std.testing.expectEqual(.already_closed, try first.endWith(Native));
    try std.testing.expectEqual(ends, Native.ends);
    var second = try cloud.beginWriteBatchWith(Native);
    defer Native.cleanup(&second);
    try std.testing.expectError(error.StaleBatch, stale.endWith(Native));
    try std.testing.expectEqual(ends, Native.ends);
    try std.testing.expectEqual(second.token, context.cloud_batch_active);
    Native.end_result = 1;
    try std.testing.expectEqual(.ended, try second.endWith(Native));
    context.cloud_batch_serial = std.math.maxInt(u64);
    const before_exhaustion = Native.begins;
    try Native.expectBeginError(cloud, error.TokenExhausted);
    try std.testing.expectEqual(before_exhaustion, Native.begins);
    try std.testing.expectEqual(@as(u64, 0), context.cloud_batch_active);
}

test "Stats progression bounds, forwarding and independent session request slots" {
    const Native = struct {
        fn require(condition: bool) void {
            std.testing.expect(condition) catch @panic("progression argument forwarding mismatch");
        }
        var calls: usize = 0;
        var availability: u8 = 1;
        var call_id: u64 = 0;
        var image: i32 = 0;
        var around: u8 = 0;
        var first: i32 = 1;
        var last: i32 = 100;
        var users: []const SteamId = &.{};
        var upload: Stats.UploadOptions = .{ .score = 0 };
        fn call(out: *u64) u8 {
            calls += 1;
            out.* = call_id;
            return availability;
        }
        fn sw_stats_achievement_icon(key: [*:0]const u8, out: *i32) u8 {
            require(std.mem.eql(u8, std.mem.span(key), "name"));
            calls += 1;
            out.* = image;
            return availability;
        }
        fn sw_stats_find_leaderboard(key: [*:0]const u8, out: *u64) u8 {
            require(std.mem.eql(u8, std.mem.span(key), "name"));
            return call(out);
        }
        fn sw_stats_request_global_percentages(out: *u64) u8 {
            return call(out);
        }
        fn sw_stats_download(board: u64, a: u8, f: i32, l: i32, out: *u64) u8 {
            require(board == 0xf123456789abcdef and a == around and f == first and l == last);
            return call(out);
        }
        fn sw_stats_download_users(board: u64, ids: [*]const u64, n: i32, out: *u64) u8 {
            require(board == 0xf123456789abcdef and n == users.len);
            for (users, 0..) |id, i| require(ids[i] == @backingInt(id));
            return call(out);
        }
        fn sw_stats_upload(board: u64, force: u8, score: i32, details: [*]const i32, n: i32, out: *u64) u8 {
            require(board == 0xf123456789abcdef and (force != 0) == (upload.method == .force_update) and score == upload.score and n == upload.details.len);
            require(std.mem.eql(i32, details[0..@intCast(n)], upload.details));
            return call(out);
        }
    };
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    const stats: Stats = .{ .lease = context.lease() };
    const board: Stats.Leaderboard = @fromBackingInt(@intCast(0xf123456789abcdef));
    const window: Stats.DownloadWindow = .{ .global = .{ .first_rank = 1, .last_rank = 100 } };
    try std.testing.expectEqual(types.ImageHandle.invalid, try stats.achievementIconWith(Native, "name"));
    Native.image = -123;
    try std.testing.expectEqual(@as(i32, -123), @backingInt(try stats.achievementIconWith(Native, "name")));
    const before_invalid = Native.calls;
    try std.testing.expectError(error.EmptyName, stats.findLeaderboardWith(Native, ""));
    try std.testing.expectError(error.InteriorNul, stats.findLeaderboardWith(Native, "n\x00ame"));
    try std.testing.expectError(error.InvalidUtf8, stats.findLeaderboardWith(Native, "\xff"));
    try std.testing.expectError(error.TooLarge, stats.findLeaderboardWith(Native, &@as([128:0]u8, @splat('n'))));
    try Stats.leaderboardName(&@as([127:0]u8, @splat('n')));
    try Stats.leaderboardName("日本語");
    try std.testing.expectError(error.TooLarge, stats.achievementIconWith(Native, &@as([128:0]u8, @splat('n'))));
    try std.testing.expectError(error.InteriorNul, stats.achievementIconWith(Native, "n\x00"));
    try std.testing.expectError(error.InvalidLeaderboard, stats.downloadLeaderboardWith(Native, .invalid, window));
    const invalid_windows = [_]Stats.DownloadWindow{
        .{ .global = .{ .first_rank = 0, .last_rank = 1 } },
        .{ .global = .{ .first_rank = 2, .last_rank = 1 } },
        .{ .global = .{ .first_rank = 1, .last_rank = std.math.maxInt(u32) } },
    };
    for (invalid_windows) |invalid| try std.testing.expectError(error.InvalidRange, stats.downloadLeaderboardWith(Native, board, invalid));
    try std.testing.expectError(error.TooLarge, stats.downloadLeaderboardWith(Native, board, .{ .global = .{ .first_rank = 1, .last_rank = 101 } }));
    for ([_]u32{ 100, std.math.maxInt(u32) }) |n| {
        try std.testing.expectError(error.TooLarge, stats.downloadLeaderboardWith(Native, board, .{ .around_user = .{ .before = n, .after = 0 } }));
        try std.testing.expectError(error.TooLarge, stats.downloadLeaderboardWith(Native, board, .{ .around_user = .{ .before = 0, .after = n } }));
    }
    try std.testing.expectError(error.TooLarge, stats.downloadLeaderboardWith(Native, board, .{ .around_user = .{ .before = 50, .after = 50 } }));
    try std.testing.expectError(error.InvalidUserCount, stats.downloadLeaderboardUsersWith(Native, board, &.{}));
    const too_many_users: [101]SteamId = @splat(.invalid);
    try std.testing.expectError(error.InvalidUserCount, stats.downloadLeaderboardUsersWith(Native, board, &too_many_users));
    const too_many_details: [65]i32 = @splat(0);
    try std.testing.expectError(error.TooLarge, stats.uploadLeaderboardWith(Native, board, .{ .score = 0, .details = &too_many_details }));
    try std.testing.expectEqual(before_invalid, Native.calls);
    const users = [_]SteamId{ .invalid, @fromBackingInt(@intCast(0xfedcba9876543210)), @fromBackingInt(@intCast(0xfedcba9876543210)) };
    Native.users = &users;
    for ([_]u8{ 0, 1 }) |availability| {
        Native.availability = availability;
        const err = if (availability == 0) error.InterfaceUnavailable else error.RequestRejected;
        try std.testing.expectError(err, stats.findLeaderboardWith(Native, "name"));
        try std.testing.expectError(err, stats.requestGlobalPercentagesWith(Native));
        try std.testing.expectError(err, stats.downloadLeaderboardWith(Native, board, window));
        try std.testing.expectError(err, stats.downloadLeaderboardUsersWith(Native, board, &users));
        try std.testing.expectError(err, stats.uploadLeaderboardWith(Native, board, .{ .score = 0 }));
        try std.testing.expectEqual(@as(u64, 0), context.leaderboard_download_call);
        try std.testing.expectEqual(@as(u64, 0), context.leaderboard_upload_call);
    }
    Native.availability = 0;
    try std.testing.expectError(error.InterfaceUnavailable, stats.achievementIconWith(Native, "name"));
    Native.availability = 1;
    Native.call_id = 0xe123456789abcdef;
    try std.testing.expectEqual(Native.call_id, @backingInt((try stats.findLeaderboardWith(Native, "name")).call));
    try std.testing.expectEqual(Native.call_id, @backingInt((try stats.requestGlobalPercentagesWith(Native)).call));
    _ = try stats.downloadLeaderboardWith(Native, board, window);
    try std.testing.expectEqual(Native.call_id, context.leaderboard_download_call);
    const pending_calls = Native.calls;
    try std.testing.expectError(error.DownloadPending, stats.downloadLeaderboardWith(Native, .invalid, window));
    try std.testing.expectError(error.DownloadPending, stats.downloadLeaderboardUsersWith(Native, board, &.{}));
    try std.testing.expectEqual(pending_calls, Native.calls);
    Native.call_id = 42;
    _ = try stats.uploadLeaderboardWith(Native, board, .{ .score = 0 });
    try std.testing.expectEqual(@as(u64, 42), context.leaderboard_upload_call);
    try std.testing.expectEqual(@as(u64, 0xe123456789abcdef), context.leaderboard_download_call);
    const upload_calls = Native.calls;
    try std.testing.expectError(error.UploadPending, stats.uploadLeaderboardWith(Native, .invalid, .{ .score = 0 }));
    try std.testing.expectEqual(upload_calls, Native.calls);
    // Simulated parent completion bookkeeping, not an integration test.
    context.leaderboard_download_call = 0;
    _ = try stats.downloadLeaderboardUsersWith(Native, board, &users);
    try std.testing.expectEqual(@as(u64, 42), context.leaderboard_download_call);
    context.leaderboard_download_call = 0;
    context.leaderboard_download_blocked = true;
    const blocked_calls = Native.calls;
    try std.testing.expectError(error.DownloadBlocked, stats.downloadLeaderboardUsersWith(Native, board, &users));
    try std.testing.expectError(error.DownloadBlocked, stats.downloadLeaderboardWith(Native, board, window));
    try std.testing.expectEqual(blocked_calls, Native.calls);
    context.leaderboard_upload_call = 0;
    _ = try stats.uploadLeaderboardWith(Native, board, .{ .score = 0 });
    context.leaderboard_download_blocked = false;
    context.leaderboard_upload_call = 0;
    const details: [64]i32 = @splat(std.math.minInt(i32));
    Native.upload = .{ .score = std.math.minInt(i32), .method = .force_update, .details = &details };
    _ = try stats.uploadLeaderboardWith(Native, board, Native.upload);
    Native.around = 1;
    for (0..100) |before| {
        context.leaderboard_download_call = 0;
        Native.first = -@as(i32, @intCast(before));
        Native.last = @intCast(99 - before);
        _ = try stats.downloadLeaderboardWith(Native, board, .{ .around_user = .{ .before = @intCast(before), .after = @intCast(99 - before) } });
    }
    context.leaderboard_download_call = 0;
    Native.first = 0;
    Native.last = 0;
    _ = try stats.downloadLeaderboardWith(Native, board, .{ .around_user = .{ .before = 0, .after = 0 } });
    context.leaderboard_download_call = 0;
    Native.around = 0;
    Native.first = std.math.maxInt(i32);
    Native.last = Native.first;
    _ = try stats.downloadLeaderboardWith(Native, board, .{ .global = .{ .first_rank = std.math.maxInt(i32), .last_rank = std.math.maxInt(i32) } });
    const full_users: [100]SteamId = @splat(.invalid);
    for ([_][]const SteamId{ users[0..1], &full_users }) |ids| {
        context.leaderboard_download_call = 0;
        Native.users = ids;
        _ = try stats.downloadLeaderboardUsersWith(Native, board, ids);
    }
}

test "Stats progression metadata and global percentage owned outcomes preserve unknown values and float bits" {
    const Native = struct {
        fn require(condition: bool) void {
            std.testing.expect(condition) catch @panic("progression argument forwarding mismatch");
        }
        var status: u8 = c.SW_STATS_TEXT_OK;
        var step_status: u8 = c.SW_STATS_PERCENTAGE_ITEM;
        var getter_status: i32 = 1;
        var length: u32 = 3;
        var iterator: i32 = 123456789;
        var percent_bits: u32 = 0x7fc12345;
        var achieved: u8 = 1;
        var calls: usize = 0;
        var previous: ?Stats.PercentageIterator = null;
        fn sw_stats_leaderboard_metadata_copy(board: u64, buffer: [*]u8, capacity: usize, out: *c.sw_stats_leaderboard_metadata) u8 {
            require(board == 42);
            calls += 1;
            out.* = .{ .name_length = length, .entry_count = -77, .sort = -123456, .display = 123456 };
            if (length <= capacity) @memset(buffer[0..length], 'a');
            return status;
        }
        fn sw_stats_percentage_step(first: u8, prev: i32, out: *c.sw_stats_percentage) u8 {
            require((first != 0) == (previous == null));
            if (previous) |cursor| require(prev == @backingInt(cursor));
            calls += 1;
            out.* = .{ .iterator = iterator, .name_length = length, .percent_bits = percent_bits, .achieved = achieved, .name = @splat('a') };
            return step_status;
        }
        fn sw_stats_achievement_percentage(key: [*:0]const u8, bits: *u32) i32 {
            require(std.mem.eql(u8, std.mem.span(key), "name"));
            calls += 1;
            bits.* = percent_bits;
            return getter_status;
        }
    };
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    const stats: Stats = .{ .lease = context.lease() };
    var buffer: [3]u8 = undefined;
    const metadata = try stats.leaderboardMetadataWith(Native, @fromBackingInt(@intCast(42)), &buffer);
    try std.testing.expectEqualStrings("aaa", metadata.name.?);
    try std.testing.expectEqual(buffer[0..].ptr, metadata.name.?.ptr);
    try std.testing.expectEqual(@as(i32, -77), metadata.entry_count);
    try std.testing.expectEqual(@as(i32, -123456), @backingInt(metadata.sort));
    try std.testing.expectEqual(@as(i32, 123456), @backingInt(metadata.display));
    Native.length = 0;
    try std.testing.expectEqualStrings("", (try stats.leaderboardMetadataWith(Native, @fromBackingInt(@intCast(42)), &.{})).name.?);
    Native.status = c.SW_STATS_TEXT_NULL;
    try std.testing.expect((try stats.leaderboardMetadataWith(Native, @fromBackingInt(@intCast(42)), &.{})).name == null);
    inline for (.{ .{ c.SW_STATS_TEXT_UNAVAILABLE, error.InterfaceUnavailable }, .{ c.SW_STATS_TEXT_SHORT, error.BufferTooSmall }, .{ 255, error.InvalidNativeResult } }) |case| {
        Native.status = case[0];
        try std.testing.expectError(case[1], stats.leaderboardMetadataWith(Native, @fromBackingInt(@intCast(42)), &buffer));
    }
    Native.status = c.SW_STATS_TEXT_OK;
    Native.length = 4;
    try std.testing.expectError(error.InvalidNativeResult, stats.leaderboardMetadataWith(Native, @fromBackingInt(@intCast(42)), &buffer));
    const before_invalid = Native.calls;
    try std.testing.expectError(error.InvalidLeaderboard, stats.leaderboardMetadataWith(Native, .invalid, &buffer));
    try std.testing.expectError(error.InvalidIterator, stats.percentageStepWith(Native, .invalid));
    try std.testing.expectError(error.InvalidIterator, stats.percentageStepWith(Native, @fromBackingInt(@intCast(std.math.minInt(i32)))));
    try std.testing.expectError(error.InteriorNul, stats.globalPercentageWith(Native, "n\x00ame"));
    try std.testing.expectError(error.TooLarge, stats.globalPercentageWith(Native, &@as([128:0]u8, @splat('n'))));
    try std.testing.expectEqual(before_invalid, Native.calls);
    for ([_]u32{ 0, 0x80000000, 0x7fc12345, 0x7f800000, 0xff800000, 0xc1234567 }) |bits| {
        Native.percent_bits = bits;
        try std.testing.expectEqual(bits, @as(u32, @bitCast((try stats.globalPercentageWith(Native, "name")).?)));
        for ([_]u32{ 0, 127 }) |length| {
            Native.length = length;
            Native.previous = null;
            const item = (try stats.percentageStepWith(Native, null)).item;
            try std.testing.expectEqual(bits, @as(u32, @bitCast(item.percent)));
            try std.testing.expectEqual(@as(usize, length), item.nameBytes().len);
            try std.testing.expect(item.achieved);
            Native.previous = item.iterator;
            Native.achieved = 0;
            const next = (try stats.percentageStepWith(Native, item.iterator)).item;
            try std.testing.expect(!next.achieved);
            Native.achieved = 1;
        }
    }
    Native.previous = null;
    Native.length = 128;
    try std.testing.expectError(error.InvalidNativeResult, stats.percentageStepWith(Native, null));
    Native.length = 0;
    Native.iterator = -2;
    Native.step_status = c.SW_STATS_PERCENTAGE_NEGATIVE;
    try std.testing.expectEqual(@as(i32, -2), (try stats.percentageStepWith(Native, null)).unexpected_iterator);
    Native.step_status = c.SW_STATS_PERCENTAGE_END;
    try std.testing.expectEqual(.no_data_or_end, try stats.percentageStepWith(Native, null));
    inline for (.{ .{ c.SW_STATS_PERCENTAGE_UNAVAILABLE, error.InterfaceUnavailable }, .{ c.SW_STATS_PERCENTAGE_UNTERMINATED, error.UnterminatedName }, .{ 255, error.InvalidNativeResult } }) |case| {
        Native.step_status = case[0];
        try std.testing.expectError(case[1], stats.percentageStepWith(Native, null));
    }
    Native.getter_status = 0;
    try std.testing.expect(try stats.globalPercentageWith(Native, "name") == null);
    Native.getter_status = -1;
    try std.testing.expectError(error.InterfaceUnavailable, stats.globalPercentageWith(Native, "name"));
}
