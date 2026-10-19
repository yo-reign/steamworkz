//! Matchmaking uses Steam's shared search and metadata caches, not per-handle
//! snapshots. Serialize searches across all Lobbies copies and other SDK callers;
//! consume/copy the completed list before starting another search. There is no
//! native lobby-search cancellation exposed here. Correlate create/join/list
//! results using the returned typed Request, not ordinary broadcast events. Creating also emits a LobbyEnter event. The parent Client
//! owns dispatch, completion decoding, and this borrowed lease.
const std = @import("std");
const Context = @import("Context.zig");
const types = @import("types.zig");
const Request = @import("requests.zig").Request;
const c = @cImport({
    @cInclude("lobbies.h");
});
const Lobbies = @This();

lease: Context.Lease,

pub const SteamId = types.SteamId;
pub const ApiCall = types.ApiCall;
pub const Error = error{
    OperationFailed,
    RequestRejected,
    InvalidNativeResult,
    InvalidId,
    InvalidEnum,
    InvalidLimit,
    InvalidIndex,
    EmptyKey,
    InteriorNul,
    TooLarge,
    BufferTooSmall,
};

pub const LobbyType = enum(i32) {
    private = 0,
    friends_only = 1,
    public = 2,
    invisible = 3,
    /// Web API only; rejected by create and setType.
    private_unique = 4,
    _,
};
pub const Comparison = enum(i32) {
    less_or_equal = -2,
    less = -1,
    equal = 0,
    greater = 1,
    greater_or_equal = 2,
    not_equal = 3,
    _,
};
pub const Distance = enum(i32) {
    close = 0,
    default = 1,
    far = 2,
    worldwide = 3,
    _,
};
pub const ChatEntryType = enum(i32) {
    invalid = 0,
    chat_message = 1,
    typing = 2,
    invite_game = 3,
    emote = 4,
    left_conversation = 6,
    entered = 7,
    kicked = 8,
    banned = 9,
    disconnected = 10,
    historical_chat = 11,
    link_blocked = 14,
    _,
};

pub const max_key_bytes = 255;
pub const metadata_value_capacity = 8192; // includes trailing NUL
pub const max_chat_bytes = 4096;
pub const max_members = 250;

pub const Filter = union(enum) {
    string: struct { key: [:0]const u8, value: [:0]const u8, comparison: Comparison = .equal },
    numerical: struct { key: [:0]const u8, value: i32, comparison: Comparison = .equal },
    /// Earlier near-value filters take precedence; order is preserved.
    near: struct { key: [:0]const u8, value: i32 },
    slots_available: u32,
    distance: Distance,
    result_count: u32,
    compatible_members: SteamId,
};

pub const CreateOptions = struct {
    visibility: LobbyType = .private,
    member_limit: u32,
};

/// Acceptance starts a request. Check the matching completion's Steam result.
pub fn create(self: Lobbies, options: CreateOptions) Error!Request(.lobby_created) {
    try validateType(options.visibility);
    try validateLimit(options.member_limit);
    self.lease.check();
    return Request(.lobby_created).init(@enumFromInt(c.sw_lobbies_create(@intFromEnum(options.visibility), @intCast(options.member_limit))));
}

pub fn join(self: Lobbies, lobby: SteamId) Error!Request(.lobby_entered) {
    try validateId(lobby);
    self.lease.check();
    return Request(.lobby_entered).init(@enumFromInt(c.sw_lobbies_join(@intFromEnum(lobby))));
}

/// SDK void operation: success means submitted, not server acknowledgement.
pub fn leave(self: Lobbies, lobby: SteamId) Error!void {
    try validateId(lobby);
    self.lease.check();
    try succeeded(c.sw_lobbies_leave(@intFromEnum(lobby)));
}

/// Allocation and ALL validation precede any native filter mutation. The bridge
/// adds the complete filter sequence and immediately requests the list, which
/// clears the native filters. An invalid call handle cannot be cancelled/retried
/// as a continuation. Strings are borrowed only during this call.
pub fn requestList(self: Lobbies, allocator: std.mem.Allocator, filters: []const Filter) (Error || std.mem.Allocator.Error)!Request(.lobby_list) {
    const native = try allocator.alloc(c.SwLobbyFilter, filters.len);
    defer allocator.free(native);
    try marshalFilters(filters, native);
    self.lease.check();
    return Request(.lobby_list).init(@enumFromInt(c.sw_lobbies_request_list(native.ptr, native.len)));
}

/// matching_count must come from the successful LobbyMatchList completion of
/// the latest search. It is a bound, NOT a snapshot/token: starting another
/// search invalidates this association, even on another Lobbies copy.
pub fn lobbyAt(self: Lobbies, index: usize, matching_count: u32) Error!SteamId {
    const native_index = try checkedIndex(index, matching_count);
    self.lease.check();
    return steamId(c.sw_lobbies_at(native_index));
}

/// Requires membership. Zero does not prove that the lobby exists.
pub fn memberCount(self: Lobbies, lobby: SteamId) Error!u32 {
    try validateId(lobby);
    self.lease.check();
    return nativeCount(c.sw_lobbies_member_count(@intFromEnum(lobby)));
}

pub fn memberAt(self: Lobbies, lobby: SteamId, index: usize) Error!SteamId {
    const native_index = try checkedIndex(index, try self.memberCount(lobby));
    self.lease.check();
    return steamId(c.sw_lobbies_member_at(@intFromEnum(lobby), native_index));
}

/// Requires membership.
pub fn owner(self: Lobbies, lobby: SteamId) Error!SteamId {
    try validateId(lobby);
    self.lease.check();
    return steamId(c.sw_lobbies_owner(@intFromEnum(lobby)));
}

/// Requires local ownership and a new owner who is already a member.
pub fn setOwner(self: Lobbies, lobby: SteamId, new_owner: SteamId) Error!void {
    try validateId(lobby);
    try validateId(new_owner);
    self.lease.check();
    try succeeded(c.sw_lobbies_set_owner(@intFromEnum(lobby), @intFromEnum(new_owner)));
}

/// Borrowed SDK text: copy before any further Steam call, callback pump or client
/// close. Empty is the native ambiguous empty value (unset, explicitly empty, or
/// invalid/uncached lobby), NOT a proven missing key. Use dataCount/dataAt to
/// inspect keys in a known-valid, populated cache; no network existence proof is
/// implied. Never convert this result to null merely because it is empty.
pub fn data(self: Lobbies, lobby: SteamId, key: [:0]const u8) Error![]const u8 {
    try validateId(lobby);
    try validateKey(key);
    self.lease.check();
    return borrowedText(c.sw_lobbies_data(@intFromEnum(lobby), key.ptr));
}

/// Copies the full value into caller storage. Empty retains data()'s ambiguity.
pub fn dataCopy(self: Lobbies, lobby: SteamId, key: [:0]const u8, buffer: []u8) Error![]u8 {
    return types.copyText(buffer, try self.data(lobby, key));
}

/// Caller owns the returned bytes and must release them with allocator.free.
pub fn dataAlloc(self: Lobbies, allocator: std.mem.Allocator, lobby: SteamId, key: [:0]const u8) (Error || std.mem.Allocator.Error)![]u8 {
    return allocator.dupe(u8, try self.data(lobby, key));
}

/// Same borrowed lifetime and ambiguous empty semantics as data(). Steam has no
/// member-metadata key enumeration, so an empty result cannot prove absence.
pub fn memberData(self: Lobbies, lobby: SteamId, member: SteamId, key: [:0]const u8) Error![]const u8 {
    try validateId(lobby);
    try validateId(member);
    try validateKey(key);
    self.lease.check();
    return borrowedText(c.sw_lobbies_member_data(@intFromEnum(lobby), @intFromEnum(member), key.ptr));
}

/// Copies the full value into caller storage without a terminator or truncation.
pub fn memberDataCopy(self: Lobbies, lobby: SteamId, member: SteamId, key: [:0]const u8, buffer: []u8) Error![]u8 {
    return types.copyText(buffer, try self.memberData(lobby, member, key));
}

/// Caller owns the returned bytes and must release them with allocator.free.
pub fn memberDataAlloc(self: Lobbies, allocator: std.mem.Allocator, lobby: SteamId, member: SteamId, key: [:0]const u8) (Error || std.mem.Allocator.Error)![]u8 {
    return allocator.dupe(u8, try self.memberData(lobby, member, key));
}

/// Requires ownership. Changes are announced via LobbyDataUpdate events.
pub fn setData(self: Lobbies, lobby: SteamId, key: [:0]const u8, value: [:0]const u8) Error!void {
    try validateId(lobby);
    try validateKey(key);
    try validateValue(value);
    self.lease.check();
    try succeeded(c.sw_lobbies_set_data(@intFromEnum(lobby), key.ptr, value.ptr));
}

/// Sets only the local member's metadata. SDK void operation: submission only.
pub fn setMemberData(self: Lobbies, lobby: SteamId, key: [:0]const u8, value: [:0]const u8) Error!void {
    try validateId(lobby);
    try validateKey(key);
    try validateValue(value);
    self.lease.check();
    try succeeded(c.sw_lobbies_set_member_data(@intFromEnum(lobby), key.ptr, value.ptr));
}

/// Native false is a failure, not evidence that the key was missing.
pub fn deleteData(self: Lobbies, lobby: SteamId, key: [:0]const u8) Error!void {
    try validateId(lobby);
    try validateKey(key);
    self.lease.check();
    try succeeded(c.sw_lobbies_delete_data(@intFromEnum(lobby), key.ptr));
}

/// Cached key count; zero also occurs for unavailable/invalid lobby data.
pub fn dataCount(self: Lobbies, lobby: SteamId) Error!u32 {
    try validateId(lobby);
    self.lease.check();
    return nativeCount(c.sw_lobbies_data_count(@intFromEnum(lobby)));
}

pub const MetadataBuffers = struct {
    key: [max_key_bytes + 1]u8 = undefined,
    value: [metadata_value_capacity]u8 = undefined,
};
pub const Metadata = struct { key: []const u8, value: []const u8 };

/// Copies one cached key/value into caller storage. Full-sized arrays avoid SDK
/// truncation ambiguity. Returned slices borrow buffers, not the SDK cache.
pub fn dataAt(self: Lobbies, lobby: SteamId, index: usize, buffers: *MetadataBuffers) Error!Metadata {
    const native_index = try checkedIndex(index, try self.dataCount(lobby));
    @memset(&buffers.key, 0xff);
    @memset(&buffers.value, 0xff);
    self.lease.check();
    try succeeded(c.sw_lobbies_data_at(@intFromEnum(lobby), native_index, &buffers.key, buffers.key.len, &buffers.value, buffers.value.len));
    return .{ .key = try terminatedText(&buffers.key), .value = try terminatedText(&buffers.value) };
}

/// Refreshes a non-member lobby's metadata. Correlate the ordinary
/// LobbyDataUpdate event by lobby ID; no ApiCall handle exists for this operation.
pub fn requestData(self: Lobbies, lobby: SteamId) Error!void {
    try validateId(lobby);
    self.lease.check();
    try succeeded(c.sw_lobbies_request_data(@intFromEnum(lobby)));
}

/// Success means sent, not accepted by the invitee.
pub fn invite(self: Lobbies, lobby: SteamId, invitee: SteamId) Error!void {
    try validateId(lobby);
    try validateId(invitee);
    self.lease.check();
    try succeeded(c.sw_lobbies_invite(@intFromEnum(lobby), @intFromEnum(invitee)));
}

pub fn setJoinable(self: Lobbies, lobby: SteamId, joinable: bool) Error!void {
    try validateId(lobby);
    self.lease.check();
    try succeeded(c.sw_lobbies_set_joinable(@intFromEnum(lobby), @intFromBool(joinable)));
}

pub fn setType(self: Lobbies, lobby: SteamId, lobby_type: LobbyType) Error!void {
    try validateId(lobby);
    try validateType(lobby_type);
    self.lease.check();
    try succeeded(c.sw_lobbies_set_type(@intFromEnum(lobby), @intFromEnum(lobby_type)));
}

pub fn setMemberLimit(self: Lobbies, lobby: SteamId, member_limit: u32) Error!void {
    try validateId(lobby);
    try validateLimit(member_limit);
    self.lease.check();
    try succeeded(c.sw_lobbies_set_limit(@intFromEnum(lobby), @intCast(member_limit)));
}

/// Native zero means no defined limit (and does not establish lobby validity).
pub fn memberLimit(self: Lobbies, lobby: SteamId) Error!u32 {
    try validateId(lobby);
    self.lease.check();
    return nativeCount(c.sw_lobbies_limit(@intFromEnum(lobby)));
}

/// Binary payload: no NUL appended. For text include a NUL yourself if desired.
/// Empty messages are rejected because the native reader cannot distinguish an
/// empty entry from failure (both return zero).
pub fn sendChat(self: Lobbies, lobby: SteamId, bytes: []const u8) Error!void {
    try validateId(lobby);
    try validateChatSize(bytes.len);
    self.lease.check();
    try succeeded(c.sw_lobbies_send_chat(@intFromEnum(lobby), bytes.ptr, @intCast(bytes.len)));
}

pub const Chat = struct { sender: SteamId, entry_type: ChatEntryType, bytes: []const u8 };

/// chat_id comes from LobbyChatMsg. A full 4 KiB buffer is required to avoid
/// silent truncation; only the returned prefix is initialized. Bytes borrow the
/// caller's buffer. Unknown native entry types are preserved.
pub fn readChat(self: Lobbies, lobby: SteamId, chat_id: u32, buffer: []u8) Error!Chat {
    try validateId(lobby);
    const native_id = try types.count(chat_id);
    if (buffer.len < max_chat_bytes) return error.BufferTooSmall;
    var out: c.SwLobbyChat = undefined;
    self.lease.check();
    try succeeded(c.sw_lobbies_read_chat(@intFromEnum(lobby), native_id, buffer.ptr, max_chat_bytes, &out));
    const size = try chatSize(out.size, max_chat_bytes);
    return .{ .sender = try steamId(out.sender), .entry_type = @enumFromInt(out.entry_type), .bytes = buffer[0..size] };
}

pub const GameServer = struct {
    steam_id: SteamId = .invalid,
    /// Host byte order, e.g. 0x7f000001 for 127.0.0.1.
    ipv4: u32 = 0,
    port: u16 = 0,
};

/// Requires either a Steam server ID or a nonzero IPv4/port pair. SDK void
/// operation: success means submitted; observe LobbyGameCreated events.
pub fn setGameServer(self: Lobbies, lobby: SteamId, server: GameServer) Error!void {
    try validateId(lobby);
    const native = try marshalServer(server);
    self.lease.check();
    try succeeded(c.sw_lobbies_set_game_server(@intFromEnum(lobby), &native));
}

/// null means the SDK reported no association OR an invalid/uncached lobby.
pub fn gameServer(self: Lobbies, lobby: SteamId) Error!?GameServer {
    try validateId(lobby);
    var out: c.SwLobbyGameServer = undefined;
    self.lease.check();
    const result = c.sw_lobbies_game_server(@intFromEnum(lobby), &out);
    if (result < 0) return error.OperationFailed;
    if (result == 0) return null;
    return .{ .steam_id = @enumFromInt(out.steam_id), .ipv4 = out.ipv4, .port = out.port };
}

fn validateId(id: SteamId) Error!void {
    if (id == .invalid) return error.InvalidId;
}
fn steamId(id: u64) Error!SteamId {
    if (id == 0) return error.OperationFailed;
    return @enumFromInt(id);
}
fn succeeded(result: c_int) Error!void {
    if (result == 0) return error.OperationFailed;
}
fn nativeCount(result: i32) Error!u32 {
    if (result < 0) return error.InvalidNativeResult;
    return @intCast(result);
}
fn checkedIndex(index: usize, count: u32) Error!c_int {
    if (index >= count) return error.InvalidIndex;
    return types.count(index);
}
fn validateType(value: LobbyType) Error!void {
    switch (value) {
        .private, .friends_only, .public, .invisible => {},
        else => return error.InvalidEnum,
    }
}
fn validateLimit(value: u32) Error!void {
    if (value == 0 or value > max_members) return error.InvalidLimit;
}
fn validateText(value: [:0]const u8, max_bytes: usize) Error!void {
    if (value.len > max_bytes) return error.TooLarge;
    if (std.mem.indexOfScalar(u8, value, 0) != null) return error.InteriorNul;
}
fn validateKey(key: [:0]const u8) Error!void {
    if (key.len == 0) return error.EmptyKey;
    try validateText(key, max_key_bytes);
}
fn validateValue(value: [:0]const u8) Error!void {
    try validateText(value, metadata_value_capacity - 1);
}
fn validateComparison(value: Comparison) Error!void {
    if (@intFromEnum(value) < -2 or @intFromEnum(value) > 3) return error.InvalidEnum;
}
fn marshalFilters(filters: []const Filter, out: []c.SwLobbyFilter) Error!void {
    std.debug.assert(filters.len == out.len);
    for (filters, out) |filter, *native| {
        native.* = std.mem.zeroes(c.SwLobbyFilter);
        switch (filter) {
            .string => |f| {
                try validateKey(f.key);
                try validateValue(f.value);
                try validateComparison(f.comparison);
                native.kind = 0;
                native.key = f.key.ptr;
                native.text = f.value.ptr;
                native.comparison = @intFromEnum(f.comparison);
            },
            .numerical => |f| {
                try validateKey(f.key);
                try validateComparison(f.comparison);
                native.kind = 1;
                native.key = f.key.ptr;
                native.value = f.value;
                native.comparison = @intFromEnum(f.comparison);
            },
            .near => |f| {
                try validateKey(f.key);
                native.kind = 2;
                native.key = f.key.ptr;
                native.value = f.value;
            },
            .slots_available => |value| {
                try validateLimit(value);
                native.kind = 3;
                native.value = @intCast(value);
            },
            .distance => |value| {
                if (@intFromEnum(value) < 0 or @intFromEnum(value) > 3) return error.InvalidEnum;
                native.kind = 4;
                native.value = @intFromEnum(value);
            },
            .result_count => |value| {
                if (value == 0) return error.InvalidLimit;
                native.kind = 5;
                native.value = try types.count(value);
            },
            .compatible_members => |value| {
                try validateId(value);
                native.kind = 6;
                native.lobby = @intFromEnum(value);
            },
        }
    }
}
fn terminatedText(bytes: []const u8) Error![]const u8 {
    const end = std.mem.indexOfScalar(u8, bytes, 0) orelse return error.InvalidNativeResult;
    return bytes[0..end];
}
fn borrowedText(ptr: [*c]const u8) Error![]const u8 {
    if (ptr == null) return error.OperationFailed;
    for (0..metadata_value_capacity) |i| {
        if (ptr[i] == 0) return ptr[0..i];
    }
    return error.InvalidNativeResult;
}
fn validateChatSize(size: usize) Error!void {
    if (size == 0) return error.InvalidLimit;
    if (size > max_chat_bytes) return error.TooLarge;
}
fn chatSize(size: i32, capacity: usize) Error!usize {
    if (size <= 0) return error.InvalidNativeResult;
    const length: usize = @intCast(size);
    if (length > capacity) return error.InvalidNativeResult;
    return length;
}
fn marshalServer(server: GameServer) Error!c.SwLobbyGameServer {
    if (server.steam_id == .invalid and (server.ipv4 == 0 or server.port == 0)) return error.InvalidId;
    return .{ .steam_id = @intFromEnum(server.steam_id), .ipv4 = server.ipv4, .port = server.port };
}

fn refPublicDeclsRecursive(comptime T: type) void {
    std.testing.refAllDecls(T);
    inline for (comptime std.meta.declarations(T)) |decl| {
        const value = @field(T, decl.name);
        if (@TypeOf(value) == type) {
            switch (@typeInfo(value)) {
                .@"struct", .@"enum", .@"union", .@"opaque" => refPublicDeclsRecursive(value),
                else => {},
            }
        }
    }
}

test "Lobbies public declarations analyze" {
    refPublicDeclsRecursive(@This());
}

test "Lobbies validates strings, supported enums and native integer bounds" {
    try validateKey("mode");
    try validateValue("");
    try std.testing.expectError(error.EmptyKey, validateKey(""));
    try std.testing.expectError(error.InteriorNul, validateKey("a\x00b"));
    try std.testing.expectError(error.InteriorNul, validateValue("a\x00b"));
    const long_key = "k" ** (max_key_bytes + 1);
    try std.testing.expectError(error.TooLarge, validateKey(long_key));
    const long_value = "v" ** metadata_value_capacity;
    try std.testing.expectError(error.TooLarge, validateValue(long_value));
    try validateLimit(1);
    try validateLimit(max_members);
    try std.testing.expectError(error.InvalidLimit, validateLimit(0));
    try std.testing.expectError(error.InvalidLimit, validateLimit(max_members + 1));
    try std.testing.expectError(error.InvalidEnum, validateType(.private_unique));
    try std.testing.expectError(error.InvalidEnum, validateType(@enumFromInt(500)));
    try std.testing.expectError(error.InvalidEnum, validateComparison(@enumFromInt(-3)));
    try std.testing.expectError(error.InvalidIndex, checkedIndex(3, 3));
    try std.testing.expectError(error.TooLarge, checkedIndex(@as(usize, std.math.maxInt(i32)) + 1, std.math.maxInt(u32)));
    try std.testing.expectEqual(@as(c_int, 2), try checkedIndex(2, 3));
}

test "lobby creation options validate before calling Steam" {
    var context: Context = undefined;
    const lobbies: Lobbies = .{ .lease = .{ .context = &context, .generation = 0 } };
    try std.testing.expectError(error.InvalidLimit, lobbies.create(.{ .visibility = .private, .member_limit = 0 }));
    try std.testing.expectError(error.InvalidEnum, lobbies.create(.{ .visibility = .private_unique, .member_limit = 2 }));
}

test "Lobbies filter marshalling preserves order, signed comparisons and IDs" {
    const id: SteamId = @enumFromInt(0x0110000101020304);
    const filters = [_]Filter{
        .{ .string = .{ .key = "mode", .value = "coop", .comparison = .not_equal } },
        .{ .numerical = .{ .key = "rank", .value = -7, .comparison = .less_or_equal } },
        .{ .near = .{ .key = "ping", .value = 90 } },
        .{ .slots_available = 2 },
        .{ .distance = .worldwide },
        .{ .result_count = 17 },
        .{ .compatible_members = id },
    };
    var out: [filters.len]c.SwLobbyFilter = undefined;
    try marshalFilters(&filters, &out);
    for (out, 0..) |f, i| try std.testing.expectEqual(@as(i32, @intCast(i)), f.kind);
    try std.testing.expectEqualStrings("coop", std.mem.span(out[0].text));
    try std.testing.expectEqual(@intFromEnum(Comparison.not_equal), out[0].comparison);
    try std.testing.expectEqual(@as(i32, -7), out[1].value);
    try std.testing.expectEqual(@intFromEnum(Comparison.less_or_equal), out[1].comparison);
    try std.testing.expectEqual(@as(i32, 90), out[2].value);
    try std.testing.expectEqual(@as(i32, 2), out[3].value);
    try std.testing.expectEqual(@intFromEnum(Distance.worldwide), out[4].value);
    try std.testing.expectEqual(@as(i32, 17), out[5].value);
    try std.testing.expectEqual(@intFromEnum(id), out[6].lobby);
}

test "Lobbies rejects later invalid filters without entering native code" {
    // An unusable lease makes an accidental native call fail loudly. Validation
    // must finish before lease.check and before the bridge mutates shared filters.
    var context: Context = undefined;
    const lobbies: Lobbies = .{ .lease = .{ .context = &context, .generation = 0 } };
    const good: Filter = .{ .near = .{ .key = "rank", .value = 12 } };
    const bad = [_]Filter{
        .{ .string = .{ .key = "bad\x00key", .value = "v" } },
        .{ .numerical = .{ .key = "rank", .value = 2, .comparison = @enumFromInt(19) } },
        .{ .slots_available = max_members + 1 },
        .{ .distance = @enumFromInt(7) },
        .{ .result_count = std.math.maxInt(u32) },
        .{ .compatible_members = .invalid },
    };
    const errors = [_]Error{ error.InteriorNul, error.InvalidEnum, error.InvalidLimit, error.InvalidEnum, error.TooLarge, error.InvalidId };
    for (bad, errors) |filter, expected| {
        try std.testing.expectError(expected, lobbies.requestList(std.testing.allocator, &.{ good, filter }));
    }
    try std.testing.expectError(error.OutOfMemory, lobbies.requestList(std.testing.failing_allocator, &.{good}));
}

test "Lobbies metadata keeps native empty distinct from absence and checks termination" {
    try std.testing.expectEqualStrings("", try borrowedText(""));
    try std.testing.expectEqualStrings("value", try borrowedText("value"));
    try std.testing.expectError(error.OperationFailed, borrowedText(null));
    try std.testing.expectEqualStrings("key", try terminatedText("key\x00tail"));
    try std.testing.expectError(error.InvalidNativeResult, terminatedText("unterminated"));
    const unterminated = [_]u8{'v'} ** metadata_value_capacity;
    try std.testing.expectError(error.InvalidNativeResult, borrowedText(&unterminated));
}

test "Lobbies binary chat checks bounds without treating NUL as termination" {
    const bytes = [_]u8{ 0, 255, 0, 12 };
    try validateChatSize(bytes.len);
    const length = try chatSize(@intCast(bytes.len), bytes.len);
    try std.testing.expectEqualSlices(u8, &bytes, bytes[0..length]);
    try std.testing.expectError(error.InvalidLimit, validateChatSize(0));
    try std.testing.expectError(error.TooLarge, validateChatSize(max_chat_bytes + 1));
    try std.testing.expectError(error.InvalidNativeResult, chatSize(-1, 4));
    try std.testing.expectError(error.InvalidNativeResult, chatSize(0, 4));
    try std.testing.expectError(error.InvalidNativeResult, chatSize(5, 4));
    const unknown: ChatEntryType = @enumFromInt(123);
    try std.testing.expectEqual(@as(i32, 123), @intFromEnum(unknown));

    var context: Context = undefined;
    const lobbies: Lobbies = .{ .lease = .{ .context = &context, .generation = 0 } };
    const lobby: SteamId = @enumFromInt(1);
    var buffer: [max_chat_bytes]u8 = undefined;
    try std.testing.expectError(error.BufferTooSmall, lobbies.readChat(lobby, 0, buffer[0..1]));
    try std.testing.expectError(error.TooLarge, lobbies.readChat(lobby, std.math.maxInt(u32), &buffer));
    try std.testing.expectError(error.InvalidLimit, lobbies.sendChat(lobby, ""));
}

test "Lobbies game server marshalling accepts either transport and preserves scalar fields" {
    try std.testing.expectError(error.InvalidId, marshalServer(.{}));
    try std.testing.expectError(error.InvalidId, marshalServer(.{ .ipv4 = 0x7f000001 }));
    const ip = try marshalServer(.{ .ipv4 = 0x7f000001, .port = 27015 });
    try std.testing.expectEqual(@as(u32, 0x7f000001), ip.ipv4);
    try std.testing.expectEqual(@as(u16, 27015), ip.port);
    try std.testing.expectEqual(@as(u64, 0), ip.steam_id);
    const id: SteamId = @enumFromInt(0x0110000101020304);
    const server = try marshalServer(.{ .steam_id = id });
    try std.testing.expectEqual(@intFromEnum(id), server.steam_id);
    try std.testing.expectError(error.OperationFailed, succeeded(0));
    try std.testing.expectError(error.InvalidNativeResult, nativeCount(-1));
}
