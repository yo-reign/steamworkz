const std = @import("std");
const c = @import("native.zig").c;
const types = @import("types.zig");
const Networking = @import("Networking.zig");
const Lobbies = @import("Lobbies.zig");
const Utils = @import("Utils.zig");
const Input = @import("Input.zig");
const SteamId = types.SteamId;
const AppId = types.AppId;
const Result = types.Result;

pub const LobbyEnterResponse = enum(u32) { success = 1, does_not_exist = 2, not_allowed = 3, full = 4, failed = 5, banned = 6, _ };
pub const AuthResponse = enum(i32) { ok = 0, user_offline = 1, no_license = 2, vac_banned = 3, logged_in_elsewhere = 4, vac_timeout = 5, cancelled = 6, already_used = 7, invalid = 8, publisher_banned = 9, network_identity_failure = 10, _ };
/// All payload data belongs to this value, not to Steam's callback storage.
/// `call == .invalid` means an ordinary broadcast, not an API-call result.
/// A lobby operation can produce both a correlated result and a broadcast.
pub const Event = struct {
    call: types.ApiCall,
    callback_id: i32,
    payload: union(enum) {
        unhandled,
        malformed,
        call_failed: enum { result_unavailable, io_failure },
        connected,
        disconnected: Result,
        connect_failure: struct { result: Result, retrying: bool },
        shutdown,
        overlay: struct { active: bool, user_initiated: bool, app: AppId },
        dlc_installed: AppId,
        persona_changed: struct { user: SteamId, flags: u32 },
        avatar_loaded: struct { user: SteamId, image: types.ImageHandle, width: u32, height: u32 },
        presence_changed: struct { user: SteamId, app: AppId },
        game_join_requested: struct {
            user: SteamId,
            connect: [256]u8,
            /// Borrows this event payload. Treat join text as untrusted input.
            pub fn connectText(self: *const @This()) []const u8 {
                return types.text(&self.connect);
            }
        },
        lobby_join_requested: struct { lobby: SteamId, user: SteamId },
        lobby_invite: struct { lobby: SteamId, user: SteamId, game: u64 },
        lobby_created: struct { lobby: SteamId, result: Result },
        lobby_entered: struct { lobby: SteamId, response: LobbyEnterResponse, locked: bool },
        lobby_list: u32,
        lobby_data: struct { lobby: SteamId, member: SteamId, success: bool },
        lobby_members: struct { lobby: SteamId, member: SteamId, actor: SteamId, changes: u32 },
        lobby_chat: struct { lobby: SteamId, user: SteamId, chat_id: u32, entry_type: u8 },
        lobby_kicked: struct { lobby: SteamId, actor: SteamId, disconnected: bool },
        lobby_game_created: struct { lobby: SteamId, server: Lobbies.GameServer },
        connection_changed: struct { info: Networking.Info, old_state: Networking.State },
        relay_status: struct {
            availability: Networking.Availability,
            measuring: bool,
            debug: [256]u8,
            /// Borrows this event payload, not native callback storage.
            pub fn debugText(self: *const @This()) []const u8 {
                return types.text(&self.debug);
            }
        },
        auth_ticket: struct { ticket: types.AuthTicket, result: Result },
        web_ticket: struct { ticket: types.AuthTicket, result: Result, size: u32, bytes: [2560]u8 },
        auth_validated: struct { user: SteamId, owner: SteamId, response: AuthResponse },
        stats_received: struct { game: u64, user: SteamId, result: Result },
        stats_stored: struct { game: u64, result: Result },
        achievement_stored: struct {
            game: u64,
            name: [128]u8,
            current: u32,
            maximum: u32,
            group: bool,
            /// Borrows this event payload, not native callback storage.
            pub fn nameText(self: *const @This()) []const u8 {
                return types.text(&self.name);
            }
        },
        cloud_written: Result,
        /// Steam evicted this user's stats; request them again before reading.
        stats_unloaded: SteamId,
        achievement_icon: struct {
            game: u64,
            name: [128]u8,
            achieved: bool,
            image: types.ImageHandle,
            /// Borrows bounded owned bytes. Initial icon zero does not prove readiness.
            pub fn nameText(self: *const @This()) []const u8 {
                return types.text(&self.name);
            }
        },
        leaderboard_found: struct { leaderboard: types.Leaderboard, found: bool },
        leaderboard_entries: types.LeaderboardEntries,
        leaderboard_uploaded: struct { leaderboard: types.Leaderboard, success: bool, score: i32, changed: bool, rank_new: i32, rank_previous: i32 },
        global_percentages_ready: struct { game: u64, result: Result },
        gamepad_dismissed: struct { app: AppId, submitted: bool, matched: bool, capture: Utils.GamepadText },
        floating_dismissed,
        resumed,
        /// Notification only. Copy the current cloud change list before another pump.
        cloud_changed,
        input_connected: Input.Controller,
        input_disconnected: Input.Controller,
    },
};

pub fn decode(native: *const c.SwEvent) Event {
    const d = &native.data;
    return .{
        .call = @enumFromInt(native.call),
        .callback_id = native.callback_id,
        .payload = switch (native.kind) {
            c.SW_MALFORMED => .malformed,
            c.SW_CALL_FAILED => .{ .call_failed = if (d.call_failure.reason == c.SW_IO_FAILURE) .io_failure else .result_unavailable },
            c.SW_CONNECTED => .connected,
            c.SW_DISCONNECTED => .{ .disconnected = @enumFromInt(d.connection.result) },
            c.SW_CONNECT_FAILURE => .{ .connect_failure = .{ .result = @enumFromInt(d.connection.result), .retrying = d.connection.retrying != 0 } },
            c.SW_SHUTDOWN => .shutdown,
            c.SW_OVERLAY => .{ .overlay = .{ .active = d.overlay.active != 0, .user_initiated = d.overlay.user_initiated != 0, .app = @enumFromInt(d.overlay.app) } },
            c.SW_DLC_INSTALLED => .{ .dlc_installed = @enumFromInt(d.dlc.app) },
            c.SW_PERSONA_CHANGED => .{ .persona_changed = .{ .user = @enumFromInt(d.persona.user), .flags = d.persona.flags } },
            c.SW_AVATAR_LOADED => .{ .avatar_loaded = .{ .user = @enumFromInt(d.avatar.user), .image = @enumFromInt(d.avatar.image), .width = d.avatar.width, .height = d.avatar.height } },
            c.SW_PRESENCE_CHANGED => .{ .presence_changed = .{ .user = @enumFromInt(d.presence.user), .app = @enumFromInt(d.presence.app) } },
            c.SW_GAME_JOIN_REQUESTED => .{ .game_join_requested = .{ .user = @enumFromInt(d.game_join.user), .connect = d.game_join.connect } },
            c.SW_LOBBY_JOIN_REQUESTED => .{ .lobby_join_requested = .{ .lobby = @enumFromInt(d.lobby_invite.lobby), .user = @enumFromInt(d.lobby_invite.user) } },
            c.SW_LOBBY_INVITE => .{ .lobby_invite = .{ .lobby = @enumFromInt(d.lobby_invite.lobby), .user = @enumFromInt(d.lobby_invite.user), .game = d.lobby_invite.game } },
            c.SW_LOBBY_CREATED => .{ .lobby_created = .{ .lobby = @enumFromInt(d.lobby_created.lobby), .result = @enumFromInt(d.lobby_created.result) } },
            c.SW_LOBBY_ENTERED => .{ .lobby_entered = .{ .lobby = @enumFromInt(d.lobby_entered.lobby), .response = @enumFromInt(d.lobby_entered.response), .locked = d.lobby_entered.locked != 0 } },
            c.SW_LOBBY_LIST => .{ .lobby_list = d.lobby_list.count },
            c.SW_LOBBY_DATA => .{ .lobby_data = .{ .lobby = @enumFromInt(d.lobby_data.lobby), .member = @enumFromInt(d.lobby_data.member), .success = d.lobby_data.success != 0 } },
            c.SW_LOBBY_MEMBERS => .{ .lobby_members = .{ .lobby = @enumFromInt(d.lobby_members.lobby), .member = @enumFromInt(d.lobby_members.member), .actor = @enumFromInt(d.lobby_members.actor), .changes = d.lobby_members.changes } },
            c.SW_LOBBY_CHAT => .{ .lobby_chat = .{ .lobby = @enumFromInt(d.lobby_chat.lobby), .user = @enumFromInt(d.lobby_chat.user), .chat_id = d.lobby_chat.chat_id, .entry_type = d.lobby_chat.entry_type } },
            c.SW_LOBBY_KICKED => .{ .lobby_kicked = .{ .lobby = @enumFromInt(d.lobby_kicked.lobby), .actor = @enumFromInt(d.lobby_kicked.actor), .disconnected = d.lobby_kicked.disconnected != 0 } },
            c.SW_LOBBY_GAME_CREATED => .{ .lobby_game_created = .{ .lobby = @enumFromInt(d.lobby_game.lobby), .server = .{ .steam_id = @enumFromInt(d.lobby_game.server), .ipv4 = d.lobby_game.ipv4, .port = d.lobby_game.port } } },
            c.SW_CONNECTION_CHANGED => .{ .connection_changed = .{
                .info = .{
                    .connection = @enumFromInt(d.network.info.connection),
                    .listen_socket = @enumFromInt(d.network.info.listen_socket),
                    .peer_steam_id = @enumFromInt(d.network.info.peer_steam_id),
                    .state = @enumFromInt(d.network.info.state),
                    .end_reason = d.network.info.end_reason,
                    .peer_identity = d.network.info.peer_identity,
                    .end_debug = d.network.info.end_debug,
                },
                .old_state = @enumFromInt(d.network.old_state),
            } },
            c.SW_RELAY_STATUS => .{ .relay_status = .{ .availability = @enumFromInt(d.relay.availability), .measuring = d.relay.measuring != 0, .debug = d.relay.debug } },
            c.SW_AUTH_TICKET => .{ .auth_ticket = .{ .ticket = @enumFromInt(d.auth_ticket.ticket), .result = @enumFromInt(d.auth_ticket.result) } },
            c.SW_WEB_TICKET => if (d.web_ticket.size <= d.web_ticket.bytes.len) .{ .web_ticket = .{ .ticket = @enumFromInt(d.web_ticket.ticket), .result = @enumFromInt(d.web_ticket.result), .size = d.web_ticket.size, .bytes = d.web_ticket.bytes } } else .malformed,
            c.SW_AUTH_VALIDATED => .{ .auth_validated = .{ .user = @enumFromInt(d.auth_validated.user), .owner = @enumFromInt(d.auth_validated.owner), .response = @enumFromInt(d.auth_validated.response) } },
            c.SW_STATS_RECEIVED => .{ .stats_received = .{ .game = d.stats.game, .user = @enumFromInt(d.stats.user), .result = @enumFromInt(d.stats.result) } },
            c.SW_STATS_STORED => .{ .stats_stored = .{ .game = d.stats.game, .result = @enumFromInt(d.stats.result) } },
            c.SW_STATS_UNLOADED => .{ .stats_unloaded = @enumFromInt(d.stats.user) },
            c.SW_ACHIEVEMENT_STORED => .{ .achievement_stored = .{ .game = d.achievement.game, .name = d.achievement.name, .current = d.achievement.current, .maximum = d.achievement.maximum, .group = d.achievement.group != 0 } },
            c.SW_CLOUD_WRITTEN => .{ .cloud_written = @enumFromInt(d.cloud.result) },
            c.SW_ACHIEVEMENT_ICON => .{ .achievement_icon = .{ .game = d.achievement_icon.game, .name = d.achievement_icon.name, .achieved = d.achievement_icon.achieved != 0, .image = @enumFromInt(d.achievement_icon.image) } },
            c.SW_LEADERBOARD_FOUND => .{ .leaderboard_found = .{ .leaderboard = @enumFromInt(d.leaderboard_found.leaderboard), .found = d.leaderboard_found.found != 0 } },
            c.SW_LEADERBOARD_ENTRIES => blk: {
                const snapshot = leaderboardEntries(d.leaderboard_download.leaderboard, &d.leaderboard_download.capture) orelse break :blk .malformed;
                break :blk .{ .leaderboard_entries = snapshot };
            },
            c.SW_LEADERBOARD_UPLOADED => .{ .leaderboard_uploaded = .{ .leaderboard = @enumFromInt(d.leaderboard_upload.leaderboard), .success = d.leaderboard_upload.success != 0, .score = d.leaderboard_upload.score, .changed = d.leaderboard_upload.changed != 0, .rank_new = d.leaderboard_upload.rank_new, .rank_previous = d.leaderboard_upload.rank_previous } },
            c.SW_GLOBAL_PERCENTAGES_READY => .{ .global_percentages_ready = .{ .game = d.global_percentages.game, .result = @enumFromInt(d.global_percentages.result) } },
            c.SW_GAMEPAD_DISMISSED => blk: {
                const capture = gamepadText(&d.gamepad.capture) orelse break :blk .malformed;
                break :blk .{ .gamepad_dismissed = .{ .app = @enumFromInt(d.gamepad.app), .submitted = d.gamepad.submitted != 0, .matched = d.gamepad.matched != 0, .capture = capture } };
            },
            c.SW_FLOATING_DISMISSED => .floating_dismissed,
            c.SW_RESUMED => .resumed,
            c.SW_CLOUD_CHANGED => .cloud_changed,
            c.SW_INPUT_CONNECTED => .{ .input_connected = @enumFromInt(d.input_device.controller) },
            c.SW_INPUT_DISCONNECTED => .{ .input_disconnected = @enumFromInt(d.input_device.controller) },
            else => .unhandled,
        },
    };
}

fn gamepadText(raw: *const c.SwUtilsTextCapture) ?Utils.GamepadText {
    if (raw.copied_length >= Utils.GamepadText.capacity) return null;
    if (raw.status == c.SW_UTILS_TEXT_COMPLETE and (raw.queried_length == 0 or raw.queried_length > Utils.GamepadText.capacity or raw.queried_length != raw.reported_length or raw.copied_length >= raw.queried_length or raw.bytes[raw.copied_length] != 0)) return null;
    return .{ .status = @enumFromInt(raw.status), .reported_length = raw.reported_length, .queried_length = raw.queried_length, .copied_length = raw.copied_length, .bytes = raw.bytes };
}

test "platform events own keyboard bytes and preserve unmatched metadata" {
    var raw = std.mem.zeroes(c.SwEvent);
    raw.kind = c.SW_GAMEPAD_DISMISSED;
    raw.data.gamepad.app = 73;
    raw.data.gamepad.submitted = 1;
    raw.data.gamepad.matched = 1;
    const capture = &raw.data.gamepad.capture;
    capture.status = c.SW_UTILS_TEXT_COMPLETE;
    capture.reported_length = 4;
    capture.queried_length = 4;
    capture.copied_length = 3;
    @memcpy(capture.bytes[0..4], "own\x00");
    const event = decode(&raw);
    @memset(&capture.bytes, 0);
    try std.testing.expectEqualStrings("own", event.payload.gamepad_dismissed.capture.text().?);
    try std.testing.expect(event.payload.gamepad_dismissed.matched and event.payload.gamepad_dismissed.submitted);
    try std.testing.expectEqual(@as(u32, 73), @intFromEnum(event.payload.gamepad_dismissed.app));
    capture.status = c.SW_UTILS_TEXT_UNTRACKED;
    capture.reported_length = std.math.maxInt(u32);
    capture.queried_length = 0;
    capture.copied_length = 0;
    raw.data.gamepad.matched = 0;
    const untracked = decode(&raw).payload.gamepad_dismissed;
    try std.testing.expect(untracked.capture.status == .untracked and untracked.capture.text() == null and !untracked.matched);
    try std.testing.expectEqual(std.math.maxInt(u32), untracked.capture.reported_length);
    capture.status = 123456;
    try std.testing.expectEqual(@as(i32, 123456), @intFromEnum(decode(&raw).payload.gamepad_dismissed.capture.status));
    capture.copied_length = Utils.GamepadText.capacity;
    try std.testing.expect(decode(&raw).payload == .malformed);
    capture.copied_length = 0;
    capture.status = c.SW_UTILS_TEXT_COMPLETE;
    try std.testing.expect(decode(&raw).payload == .malformed);
    raw.kind = c.SW_INPUT_CONNECTED;
    raw.data.input_device.controller = std.math.maxInt(u64);
    try std.testing.expectEqual(std.math.maxInt(u64), @intFromEnum(decode(&raw).payload.input_connected));
    raw.kind = c.SW_INPUT_DISCONNECTED;
    try std.testing.expectEqual(std.math.maxInt(u64), @intFromEnum(decode(&raw).payload.input_disconnected));
    inline for (.{ .{ c.SW_FLOATING_DISMISSED, .floating_dismissed }, .{ c.SW_RESUMED, .resumed }, .{ c.SW_CLOUD_CHANGED, .cloud_changed } }) |pair| {
        raw.kind = pair[0];
        try std.testing.expectEqual(pair[1], std.meta.activeTag(decode(&raw).payload));
    }
}

fn leaderboardEntries(board: u64, raw: *const c.SwLeaderboardEntries) ?types.LeaderboardEntries {
    if (raw.copied_count > types.LeaderboardEntries.max_entries) return null;
    if (raw.copied_count != 0 and (raw.reported_count < 0 or raw.copied_count > raw.reported_count)) return null;
    var result: types.LeaderboardEntries = .{
        .leaderboard = @enumFromInt(board),
        .status = @enumFromInt(raw.status),
        .reported_count = raw.reported_count,
        .copied_count = raw.copied_count,
        .failure_index = raw.failure_index,
        .reported_details = raw.reported_details,
        .all_rows_accessed = raw.all_rows_accessed != 0,
    };
    for (raw.entries[0..raw.copied_count], result.entry_values[0..raw.copied_count]) |*source, *entry| {
        if (source.detail_count > types.LeaderboardEntry.max_details) return null;
        entry.* = .{ .user = @enumFromInt(source.user), .global_rank = source.global_rank, .score = source.score, .ugc = source.ugc, .detail_count = source.detail_count };
        @memcpy(entry.detail_values[0..source.detail_count], source.details[0..source.detail_count]);
    }
    return result;
}

test "leaderboard events own bounded rows and details independently of native storage" {
    var native = std.mem.zeroes(c.SwEvent);
    native.kind = c.SW_LEADERBOARD_ENTRIES;
    native.call = 71;
    native.callback_id = 1105;
    native.data.leaderboard_download.leaderboard = 83;
    const capture = &native.data.leaderboard_download.capture;
    capture.status = c.SW_LEADERBOARD_CAPTURE_COMPLETE;
    capture.reported_count = 1;
    capture.copied_count = 1;
    capture.failure_index = -1;
    capture.all_rows_accessed = 1;
    capture.entries[0].user = 97;
    capture.entries[0].global_rank = -5;
    capture.entries[0].score = std.math.minInt(i32);
    capture.entries[0].ugc = std.math.maxInt(u64);
    capture.entries[0].detail_count = types.LeaderboardEntry.max_details;
    for (&capture.entries[0].details, 0..) |*value, index| value.* = @as(i32, @intCast(index)) - 31;
    const event = decode(&native);
    @memset(std.mem.asBytes(&native), 0);
    try std.testing.expectEqual(@as(u64, 71), @intFromEnum(event.call));
    try std.testing.expectEqual(@as(i32, 1105), event.callback_id);
    const result = &event.payload.leaderboard_entries;
    try std.testing.expectEqual(@as(u64, 83), @intFromEnum(result.leaderboard));
    try std.testing.expect(result.all_rows_accessed);
    try std.testing.expectEqual(@as(usize, 1), result.entries().len);
    const row = &result.entries()[0];
    try std.testing.expectEqual(@as(u64, 97), @intFromEnum(row.user));
    try std.testing.expectEqual(@as(i32, -5), row.global_rank);
    try std.testing.expectEqual(std.math.minInt(i32), row.score);
    try std.testing.expectEqual(std.math.maxInt(u64), row.ugc);
    for (row.details(), 0..) |value, index| try std.testing.expectEqual(@as(i32, @intCast(index)) - 31, value);
}

test "leaderboard conversion rejects invalid published bounds but retains capture failures" {
    var raw = std.mem.zeroes(c.SwLeaderboardEntries);
    raw.status = c.SW_LEADERBOARD_CAPTURE_INVALID_COUNT;
    raw.reported_count = -9;
    raw.failure_index = -1;
    const failed = leaderboardEntries(7, &raw).?;
    try std.testing.expectEqual(@as(i32, -9), failed.reported_count);
    try std.testing.expect(failed.status == .invalid_count);
    try std.testing.expectEqual(@as(usize, 0), failed.entries().len);
    raw.status = 123456;
    try std.testing.expectEqual(@as(i32, 123456), @intFromEnum(leaderboardEntries(7, &raw).?.status));
    raw.copied_count = 1;
    try std.testing.expect(leaderboardEntries(7, &raw) == null);
    raw.reported_count = 1;
    raw.entries[0].detail_count = types.LeaderboardEntry.max_details + 1;
    try std.testing.expect(leaderboardEntries(7, &raw) == null);
    raw.entries[0].detail_count = 0;
    try std.testing.expect(leaderboardEntries(7, &raw) != null);
    raw.copied_count = types.LeaderboardEntries.max_entries + 1;
    try std.testing.expect(leaderboardEntries(7, &raw) == null);
}

test "progression event fields preserve operation failure, signed values and bounded icon names" {
    var native = std.mem.zeroes(c.SwEvent);
    native.kind = c.SW_ACHIEVEMENT_ICON;
    native.data.achievement_icon.game = std.math.maxInt(u64);
    @memset(&native.data.achievement_icon.name, 'x');
    native.data.achievement_icon.image = 17;
    native.data.achievement_icon.achieved = 1;
    const icon = decode(&native).payload.achievement_icon;
    try std.testing.expectEqual(native.data.achievement_icon.name.len, icon.nameText().len);
    try std.testing.expectEqual(std.math.maxInt(u64), icon.game);
    try std.testing.expect(icon.achieved);
    try std.testing.expectEqual(@as(i32, 17), @intFromEnum(icon.image));
    native.kind = c.SW_LEADERBOARD_FOUND;
    native.data.leaderboard_found = .{ .leaderboard = 19, .found = 0 };
    const found = decode(&native).payload.leaderboard_found;
    try std.testing.expect(!found.found);
    try std.testing.expectEqual(@as(u64, 19), @intFromEnum(found.leaderboard));
    native.kind = c.SW_LEADERBOARD_UPLOADED;
    native.data.leaderboard_upload = .{ .leaderboard = 23, .success = 0, .score = -31, .changed = 1, .rank_new = -2, .rank_previous = 0 };
    const upload = decode(&native).payload.leaderboard_uploaded;
    try std.testing.expect(!upload.success and upload.changed);
    try std.testing.expectEqual(@as(i32, -31), upload.score);
    try std.testing.expectEqual(@as(i32, -2), upload.rank_new);
    try std.testing.expectEqual(@as(i32, 0), upload.rank_previous);
    native.kind = c.SW_GLOBAL_PERCENTAGES_READY;
    native.data.global_percentages = .{ .game = 29, .result = 123456 };
    const percentages = decode(&native).payload.global_percentages_ready;
    try std.testing.expectEqual(@as(u64, 29), percentages.game);
    try std.testing.expectEqual(@as(i32, 123456), @intFromEnum(percentages.result));
}

test "events own strings and retain call correlation and unknown result codes" {
    var native = std.mem.zeroes(c.SwEvent);
    native.kind = c.SW_GAME_JOIN_REQUESTED;
    native.call = 123;
    native.callback_id = 456;
    @memcpy(native.data.game_join.connect[0..5], "hello");
    const event = decode(&native);
    native.data.game_join.connect[0] = 'x';
    try std.testing.expectEqualStrings("hello", event.payload.game_join_requested.connectText());
    try std.testing.expectEqual(@as(types.ApiCall, @enumFromInt(123)), event.call);
    try std.testing.expectEqual(@as(i32, 456), event.callback_id);
    native.kind = c.SW_LOBBY_CREATED;
    native.data.lobby_created.result = 123456;
    try std.testing.expectEqual(@as(i32, 123456), @intFromEnum(decode(&native).payload.lobby_created.result));
}

test "stats_unloaded owns the affected user identity without call correlation" {
    var native = std.mem.zeroes(c.SwEvent);
    native.kind = c.SW_STATS_UNLOADED;
    native.callback_id = 456;
    native.data.stats.user = 0x123456789abcdef0;
    const event = decode(&native);
    native.data.stats.user = 99;
    try std.testing.expectEqual(@as(SteamId, @enumFromInt(0x123456789abcdef0)), event.payload.stats_unloaded);
    try std.testing.expectEqual(types.ApiCall.invalid, event.call);
    try std.testing.expectEqual(@as(i32, 456), event.callback_id);
}

test "auth_validated names network identity failure and preserves unknown responses" {
    var native = std.mem.zeroes(c.SwEvent);
    native.kind = c.SW_AUTH_VALIDATED;
    native.data.auth_validated = .{ .user = 23, .owner = 99, .response = 10 };
    const event = decode(&native);
    native.data.auth_validated.user = 42;
    native.data.auth_validated.owner = 43;
    try std.testing.expectEqual(AuthResponse.network_identity_failure, event.payload.auth_validated.response);
    try std.testing.expectEqual(@as(SteamId, @enumFromInt(23)), event.payload.auth_validated.user);
    try std.testing.expectEqual(@as(SteamId, @enumFromInt(99)), event.payload.auth_validated.owner);
    native.data.auth_validated.response = 123456;
    try std.testing.expectEqual(@as(i32, 123456), @intFromEnum(decode(&native).payload.auth_validated.response));
}

test "connection events use the networking handle and state types" {
    var native = std.mem.zeroes(c.SwEvent);
    native.kind = c.SW_CONNECTION_CHANGED;
    native.data.network.info.connection = 23;
    native.data.network.info.listen_socket = 42;
    native.data.network.info.state = @intFromEnum(Networking.State.connected);
    native.data.network.old_state = 123456;
    const changed = decode(&native).payload.connection_changed;
    const connection: Networking.Connection = changed.info.connection;
    const socket: Networking.ListenSocket = changed.info.listen_socket;
    try std.testing.expectEqual(@as(u32, 23), @intFromEnum(connection));
    try std.testing.expectEqual(@as(u32, 42), @intFromEnum(socket));
    try std.testing.expectEqual(Networking.State.connected, changed.info.state);
    try std.testing.expectEqual(@as(i32, 123456), @intFromEnum(changed.old_state));
}

test "lobby game association and avatar readiness preserve supplied data" {
    var native = std.mem.zeroes(c.SwEvent);
    native.kind = c.SW_LOBBY_GAME_CREATED;
    native.data.lobby_game = .{ .lobby = 23, .server = 99, .ipv4 = 0x7f000001, .port = 27015 };
    const game = decode(&native).payload.lobby_game_created;
    try std.testing.expectEqual(@as(u64, 23), @intFromEnum(game.lobby));
    try std.testing.expectEqual(@as(u64, 99), @intFromEnum(game.server.steam_id));
    try std.testing.expectEqual(@as(u32, 0x7f000001), game.server.ipv4);
    try std.testing.expectEqual(@as(u16, 27015), game.server.port);
    native.kind = c.SW_AVATAR_LOADED;
    native.data.avatar = .{ .user = 99, .image = 17, .width = 10, .height = 20 };
    const avatar = decode(&native).payload.avatar_loaded;
    try std.testing.expectEqual(@as(u64, 99), @intFromEnum(avatar.user));
    try std.testing.expectEqual(@as(types.ImageHandle, @enumFromInt(17)), avatar.image);
    try std.testing.expectEqual(@as(u32, 10), avatar.width);
    try std.testing.expectEqual(@as(u32, 20), avatar.height);
}

test "event text accessors stay bounded and relay availability retains unknown values" {
    var native = std.mem.zeroes(c.SwEvent);
    native.kind = c.SW_RELAY_STATUS;
    native.data.relay.availability = 123456;
    native.data.relay.debug = @splat('x');
    const relay = decode(&native).payload.relay_status;
    native.data.relay.debug[0] = 0;
    try std.testing.expectEqual(@as(i32, 123456), @intFromEnum(relay.availability));
    try std.testing.expectEqualStrings(&([_]u8{'x'} ** 256), relay.debugText());
    native.kind = c.SW_ACHIEVEMENT_STORED;
    native.data.achievement.name = @splat(0);
    @memcpy(native.data.achievement.name[0..5], "award");
    const achievement = decode(&native).payload.achievement_stored;
    try std.testing.expectEqualStrings("award", achievement.nameText());
}

test "web ticket length is checked before exposing its bytes" {
    var native = std.mem.zeroes(c.SwEvent);
    native.kind = c.SW_WEB_TICKET;
    native.data.web_ticket.size = native.data.web_ticket.bytes.len + 1;
    try std.testing.expect(decode(&native).payload == .malformed);
}

test "property web ticket boundary lengths copy binary payload and correlation" {
    for ([_]u32{ 0, 1, 2559, 2560, 2561, std.math.maxInt(u32) }) |size| {
        var native = std.mem.zeroes(c.SwEvent);
        native.kind = c.SW_WEB_TICKET;
        native.call = 0xfedcba9876543210;
        native.callback_id = 168;
        native.data.web_ticket.size = size;
        native.data.web_ticket.result = -123456;
        native.data.web_ticket.ticket = 0xfedcba98;
        for (&native.data.web_ticket.bytes, 0..) |*byte, i| byte.* = @truncate(i);
        const event = decode(&native);
        @memset(&native.data.web_ticket.bytes, 0xaa);
        try std.testing.expectEqual(@as(u64, 0xfedcba9876543210), @intFromEnum(event.call));
        try std.testing.expectEqual(@as(i32, 168), event.callback_id);
        if (size > 2560) {
            try std.testing.expect(event.payload == .malformed);
        } else {
            const ticket = event.payload.web_ticket;
            try std.testing.expectEqual(size, ticket.size);
            try std.testing.expectEqual(@as(i32, -123456), @intFromEnum(ticket.result));
            try std.testing.expectEqual(@as(u32, 0xfedcba98), @intFromEnum(ticket.ticket));
            // Only the declared prefix is ticket data; do not constrain unused storage.
            for (ticket.bytes[0..size], 0..) |byte, i| try std.testing.expectEqual(@as(u8, @truncate(i)), byte);
        }
    }
}
