const std = @import("std");
const Context = @import("Context.zig");
const types = @import("types.zig");
const c = @cImport({
    @cInclude("networking.h");
});
const Networking = @This();

lease: Context.Lease,

/// Handles belong to the creating client session; never reuse them in a new one.
pub const Connection = enum(u32) { invalid = 0, _ };
pub const ListenSocket = enum(u32) { invalid = 0, _ };
pub const PollGroup = enum(u32) { invalid = 0, _ };
pub const State = enum(i32) {
    none = 0,
    connecting = 1,
    finding_route = 2,
    connected = 3,
    closed_by_peer = 4,
    problem_detected_locally = 5,
    fin_wait = -1,
    linger = -2,
    dead = -3,
    _,
};
pub const Availability = enum(i32) {
    cannot_try = -102,
    failed = -101,
    previously = -100,
    retrying = -10,
    unknown = 0,
    never_tried = 1,
    waiting = 2,
    attempting = 3,
    current = 100,
    _,
};

/// IPv6 bytes in network order; IPv4 uses the IPv4-mapped IPv6 representation.
/// Port is in host order. This is an owned value, not an SDK layout alias.
pub const Address = struct {
    ipv6: [16]u8 = @splat(0),
    port: u16 = 0,

    /// Pure numeric parsing. IPv6 ports require brackets. Names and scope IDs
    /// are not supported. The native parseAddress method retains SDK syntax.
    pub fn parse(text: []const u8) error{InvalidAddress}!Address {
        // The longest numeric literal uses six IPv6 groups, a dotted IPv4
        // suffix, brackets, and a five-digit port (53 bytes).
        if (text.len == 0 or text.len > 53 or
            std.mem.indexOfAny(u8, text, "\x00%") != null) return error.InvalidAddress;
        if (text[0] == '[') {
            const end = std.mem.indexOfScalar(u8, text, ']') orelse return error.InvalidAddress;
            const port: u16 = if (end + 1 == text.len) 0 else blk: {
                if (text[end + 1] != ':') return error.InvalidAddress;
                break :blk try parsePort(text[end + 2 ..]);
            };
            return parseIp6(text[1..end], port);
        }
        const colons = std.mem.count(u8, text, ":");
        if (colons > 1) return parseIp6(text, 0);
        const end = std.mem.indexOfScalar(u8, text, ':') orelse text.len;
        const port = if (end == text.len) 0 else try parsePort(text[end + 1 ..]);
        const ip4 = std.Io.net.Ip4Address.parse(text[0..end], port) catch return error.InvalidAddress;
        const ip6 = std.Io.net.Ip6Address.fromIp4(ip4);
        return .{ .ipv6 = ip6.bytes, .port = ip6.port };
    }

    /// Standard Zig {f} formatting, including the port. No Steam call or allocation.
    pub fn format(self: Address, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const ip = std.Io.net.IpAddress.fromIp6(.{ .bytes = self.ipv6, .port = self.port });
        try ip.format(writer);
    }

    fn parsePort(text: []const u8) error{InvalidAddress}!u16 {
        if (text.len == 0) return error.InvalidAddress;
        for (text) |byte| if (!std.ascii.isDigit(byte)) return error.InvalidAddress;
        return std.fmt.parseInt(u16, text, 10) catch error.InvalidAddress;
    }

    fn parseIp6(text: []const u8, port: u16) error{InvalidAddress}!Address {
        var expanded: [address_text_size]u8 = undefined;
        var numeric = text;
        // Zig 0.16 only accepts dotted suffixes in its special ::ffff: path.
        // Normalize other dotted suffixes to two groups before using its parser.
        if (std.mem.indexOfScalar(u8, text, '.') != null) {
            const end = std.mem.lastIndexOfScalar(u8, text, ':') orelse return error.InvalidAddress;
            const ip4 = std.Io.net.Ip4Address.parse(text[end + 1 ..], 0) catch return error.InvalidAddress;
            numeric = std.fmt.bufPrint(&expanded, "{s}{x}:{x}", .{
                text[0 .. end + 1], std.mem.readInt(u16, ip4.bytes[0..2], .big), std.mem.readInt(u16, ip4.bytes[2..4], .big),
            }) catch return error.InvalidAddress;
        }
        var groups: usize = 0;
        var parts = std.mem.splitScalar(u8, numeric, ':');
        while (parts.next()) |part| if (part.len != 0) {
            groups += 1;
        };
        // Check compression before rewriting the mapped prefix. That rewrite
        // must not conceal a second :: or permit compression of zero groups.
        const compressions = std.mem.count(u8, numeric, "::");
        if (compressions > 1 or (compressions == 1 and groups >= 8)) return error.InvalidAddress;
        var prefixed: [address_text_size]u8 = undefined;
        // An explicit leading zero avoids the std parser's dotted-only special
        // case. With seven groups, it replaces :: rather than adding to it.
        if (std.ascii.startsWithIgnoreCase(numeric, "::ffff:")) {
            numeric = if (groups == 7)
                std.fmt.bufPrint(&prefixed, "0:{s}", .{numeric[2..]}) catch return error.InvalidAddress
            else
                std.fmt.bufPrint(&prefixed, "0{s}", .{numeric}) catch return error.InvalidAddress;
        }
        const ip6 = std.Io.net.Ip6Address.parse(numeric, port) catch return error.InvalidAddress;
        return .{ .ipv6 = ip6.bytes, .port = ip6.port };
    }

    fn native(self: Address) c.SwAddress {
        return .{ .ipv6 = self.ipv6, .port = self.port };
    }
    fn fromNative(value: c.SwAddress) Address {
        return .{ .ipv6 = value.ipv6, .port = value.port };
    }
};
pub const address_text_size = c.SW_ADDRESS_TEXT_SIZE;
pub const max_receive = c.SW_NETWORKING_MAX_RECEIVE;

/// Owned snapshot. Text accessors borrow this snapshot, not SDK storage.
pub const Info = struct {
    peer_steam_id: types.SteamId,
    connection: Connection,
    listen_socket: ListenSocket,
    state: State,
    end_reason: i32,
    peer_identity: [128]u8,
    end_debug: [128]u8,

    pub fn peerIdentity(self: *const Info) []const u8 {
        return types.text(&self.peer_identity);
    }
    pub fn endDebug(self: *const Info) []const u8 {
        return types.text(&self.end_debug);
    }
    fn fromNative(value: c.SwConnectionInfo) Info {
        return .{
            .peer_steam_id = @enumFromInt(value.peer_steam_id),
            .connection = @enumFromInt(value.connection),
            .listen_socket = @enumFromInt(value.listen_socket),
            .state = @enumFromInt(value.state),
            .end_reason = value.end_reason,
            .peer_identity = value.peer_identity,
            .end_debug = value.end_debug,
        };
    }
};
pub const RelayStatus = struct {
    availability: Availability,
    ping_measurement_in_progress: bool,
    network_config: Availability,
    any_relay: Availability,
    debug: [256]u8,

    pub fn debugText(self: *const RelayStatus) []const u8 {
        return types.text(&self.debug);
    }
};

/// Raw SDK bits for sendRaw. The C++ bridge checks these against SDK headers.
pub const SendFlags = struct {
    pub const unreliable: i32 = c.SW_SEND_UNRELIABLE;
    pub const no_nagle: i32 = c.SW_SEND_NO_NAGLE;
    pub const no_delay: i32 = c.SW_SEND_NO_DELAY;
    pub const reliable: i32 = c.SW_SEND_RELIABLE;
    pub const use_current_thread: i32 = c.SW_SEND_USE_CURRENT_THREAD;
};
pub const SendOptions = struct {
    reliability: enum { unreliable, reliable } = .unreliable,
    no_nagle: bool = false,
    /// Drop an unreliable message if Steam cannot send it soon. This does not
    /// imply no_nagle. Reliable sends cannot use this option.
    no_delay: bool = false,
    use_current_thread: bool = false,

    fn flags(self: SendOptions) error{InvalidSendOptions}!i32 {
        if (self.reliability == .reliable and self.no_delay) return error.InvalidSendOptions;
        var value: i32 = if (self.reliability == .reliable) SendFlags.reliable else SendFlags.unreliable;
        if (self.no_nagle) value |= SendFlags.no_nagle;
        if (self.no_delay) value |= SendFlags.no_delay;
        if (self.use_current_thread) value |= SendFlags.use_current_thread;
        return value;
    }
};
pub const CloseOptions = struct {
    /// Application reason code from the SDK's permitted range, or zero.
    reason: i32 = 0,
    debug: ?[:0]const u8 = null,
    linger: bool = false,
};
pub const SocketPairOptions = struct { network_loopback: bool = false };
pub const SendOutcome = union(enum) {
    /// Local acceptance and the assigned message number, not remote delivery.
    accepted: i64,
    /// Steam's exact result, including unknown future values.
    rejected: types.Result,

    fn fromNative(result: i32, number: i64) SendOutcome {
        const value: types.Result = @enumFromInt(result);
        return if (value == .ok) .{ .accepted = number } else .{ .rejected = value };
    }
};
pub const Metadata = struct {
    connection: Connection,
    peer_steam_id: types.SteamId,
    number: i64,
    received_at: i64,
    channel: i32,
};

/// Unique owner: do not copy a live Message or move it out of a received batch.
/// No ownership-transfer API currently exists. Release on the client owner thread
/// before Client.deinit. The borrowed payload expires at deinit; metadata is an
/// independent copied value.
pub const Message = struct {
    lease: Context.Lease,
    handle: ?*c.SwMessage,
    data: []const u8,
    metadata: Metadata,

    pub fn bytes(self: *const Message) []const u8 {
        self.lease.check();
        if (self.handle == null) @panic("Steamworks message has been released");
        return self.data;
    }
    /// Repeated deinit on this value is harmless while the client remains open.
    pub fn deinit(self: *Message) void {
        self.releaseWith(c.sw_networking_release_message);
    }
    fn releaseWith(self: *Message, comptime release: @TypeOf(c.sw_networking_release_message)) void {
        self.lease.check();
        if (self.handle == null) return;
        release(&self.handle);
        self.data = &.{};
        self.lease.releaseMessage();
    }
    fn validate(view: c.SwMessageView) error{InvalidMessage}!void {
        if (view.handle == null or view.size < 0 or (view.size != 0 and view.data == null))
            return error.InvalidMessage;
    }
    fn adopt(lease: Context.Lease, view: c.SwMessageView) Message {
        lease.acquireMessage();
        return .{
            .lease = lease,
            .handle = view.handle,
            .data = if (view.size == 0) &.{} else view.data[0..@intCast(view.size)],
            .metadata = .{
                .connection = @enumFromInt(view.connection),
                .peer_steam_id = @enumFromInt(view.peer_steam_id),
                .number = view.number,
                .received_at = view.received_at,
                .channel = view.channel,
            },
        };
    }
};

/// Owns the initialized messages in caller-provided storage, not the storage
/// allocation. Do not copy a live batch, move out its messages, or reuse its slots.
/// Individual messages may be released early. Batch cleanup releases the rest.
/// Deinitialize the batch before closing its client.
pub const MessageBatch = struct {
    messages: []Message,

    pub fn deinit(self: *MessageBatch) void {
        self.releaseWith(c.sw_networking_release_message);
    }
    fn releaseWith(self: *MessageBatch, comptime release: @TypeOf(c.sw_networking_release_message)) void {
        for (self.messages) |*message| message.releaseWith(release);
        self.messages = self.messages[0..0];
    }
};

/// Uses SDK helpers and requires an initialized client. Prefer Address.parse
/// for pure numeric parsing without a client.
pub fn parseAddress(self: Networking, text: [:0]const u8) error{ InvalidAddress, Unavailable }!Address {
    self.lease.check();
    if (std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidAddress;
    var value: c.SwAddress = undefined;
    const result = c.sw_networking_parse_address(text, &value);
    if (result < 0) return error.Unavailable;
    if (result == 0) return error.InvalidAddress;
    return Address.fromNative(value);
}
/// Returns text borrowing the caller's fixed-size buffer, without its terminator.
pub fn formatAddress(self: Networking, address: Address, buffer: *[address_text_size]u8, with_port: bool) error{Unavailable}![]const u8 {
    self.lease.check();
    const value = address.native();
    if (c.sw_networking_format_address(&value, buffer, buffer.len, @intFromBool(with_port)) == 0) return error.Unavailable;
    return types.text(buffer);
}
pub fn listenIP(self: Networking, address: Address) error{ListenFailed}!ListenSocket {
    self.lease.check();
    const value = address.native();
    const handle = c.sw_networking_listen_ip(&value);
    if (handle == 0) return error.ListenFailed;
    return @enumFromInt(handle);
}
pub fn connectIP(self: Networking, address: Address) error{ConnectFailed}!Connection {
    self.lease.check();
    const value = address.native();
    const handle = c.sw_networking_connect_ip(&value);
    if (handle == 0) return error.ConnectFailed;
    return @enumFromInt(handle);
}
pub fn listenP2P(self: Networking, virtual_port: u16) error{ListenFailed}!ListenSocket {
    self.lease.check();
    const handle = c.sw_networking_listen_p2p(virtual_port);
    if (handle == 0) return error.ListenFailed;
    return @enumFromInt(handle);
}
pub fn connectP2P(self: Networking, peer: types.SteamId, virtual_port: u16) error{ InvalidSteamId, ConnectFailed }!Connection {
    self.lease.check();
    if (peer == .invalid) return error.InvalidSteamId;
    const handle = c.sw_networking_connect_p2p(@intFromEnum(peer), virtual_port);
    if (handle == 0) return error.ConnectFailed;
    return @enumFromInt(handle);
}
pub fn accept(self: Networking, connection: Connection) types.Result {
    self.lease.check();
    return @enumFromInt(c.sw_networking_accept(@intFromEnum(connection)));
}
/// Terminal connection callbacks do not release a connection: explicitly close
/// it even after closed_by_peer or problem_detected_locally. Debug text is
/// borrowed only for this call. Linger permits queued reliable sends to drain.
pub fn close(self: Networking, connection: Connection, options: CloseOptions) error{ InvalidDebugText, OperationFailed }!void {
    self.lease.check();
    if (options.debug) |text| {
        if (text.len >= 128 or std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidDebugText;
    }
    if (c.sw_networking_close(@intFromEnum(connection), options.reason, if (options.debug) |text| text.ptr else null, @intFromBool(options.linger)) == 0)
        return error.OperationFailed;
}
/// The SDK closes associated incoming connections ungracefully when destroying
/// the listener. Plan graceful connection shutdown separately before this call.
pub fn closeListen(self: Networking, socket: ListenSocket) error{OperationFailed}!void {
    self.lease.check();
    if (c.sw_networking_close_listen(@intFromEnum(socket)) == 0) return error.OperationFailed;
}
/// Both returned connections require explicit close. With network_loopback=false
/// the SDK uses an in-process pair; this still requires an initialized client.
pub fn socketPair(self: Networking, options: SocketPairOptions) error{OperationFailed}![2]Connection {
    self.lease.check();
    var first: u32 = 0;
    var second: u32 = 0;
    if (c.sw_networking_socket_pair(&first, &second, @intFromBool(options.network_loopback)) == 0) return error.OperationFailed;
    return .{ @enumFromInt(first), @enumFromInt(second) };
}
/// Local errors use Zig errors. Steam rejection retains its Result in the outcome.
pub fn send(self: Networking, connection: Connection, data: []const u8, options: SendOptions) error{ TooLarge, InvalidSendOptions }!SendOutcome {
    self.lease.check();
    return sendMessage(connection, data, try options.flags());
}
/// Explicit escape hatch for advanced/future SDK bits. Steam validates raw flags.
pub fn sendRaw(self: Networking, connection: Connection, data: []const u8, flags: i32) error{TooLarge}!SendOutcome {
    self.lease.check();
    return sendMessage(connection, data, flags);
}
fn sendMessage(connection: Connection, data: []const u8, flags: i32) error{TooLarge}!SendOutcome {
    const size = std.math.cast(u32, data.len) orelse return error.TooLarge;
    var number: i64 = -1;
    const result = c.sw_networking_send(@intFromEnum(connection), data.ptr, size, flags, &number);
    return SendOutcome.fromNative(result, number);
}
pub fn flush(self: Networking, connection: Connection) types.Result {
    self.lease.check();
    return @enumFromInt(c.sw_networking_flush(@intFromEnum(connection)));
}

pub const ReceiveError = error{ TooManyMessages, ReceiveFailed, InvalidMessage };
/// Writes at most max_receive messages into unowned/undefined output slots.
/// The batch contains only initialized slots. Use defer batch.deinit() immediately.
pub fn receive(self: Networking, connection: Connection, out: []Message) ReceiveError!MessageBatch {
    return self.receiveBatch(@intFromEnum(connection), false, out);
}
pub fn receivePollGroup(self: Networking, group: PollGroup, out: []Message) ReceiveError!MessageBatch {
    return self.receiveBatch(@intFromEnum(group), true, out);
}
fn receiveBatch(self: Networking, handle: u32, poll_group: bool, out: []Message) ReceiveError!MessageBatch {
    self.lease.check();
    if (out.len > max_receive) return error.TooManyMessages;
    if (out.len == 0) return .{ .messages = out };
    var views: [max_receive]c.SwMessageView = @splat(std.mem.zeroes(c.SwMessageView));
    const count = c.sw_networking_receive(handle, @intFromBool(poll_group), &views, @intCast(out.len));
    // Clear all acquired native handles on any error, even an invalid count.
    errdefer for (views[0..out.len]) |*view| {
        if (view.handle != null) {
            self.lease.check();
            c.sw_networking_release_message(&view.handle);
        }
    };
    if (count < 0 or count > out.len) return error.ReceiveFailed;
    const length: usize = @intCast(count);
    for (views[0..length]) |view| try Message.validate(view);
    for (views[0..length], out[0..length]) |view, *message| message.* = Message.adopt(self.lease, view);
    return .{ .messages = out[0..length] };
}
pub fn connectionInfo(self: Networking, connection: Connection) error{InfoUnavailable}!Info {
    self.lease.check();
    var value: c.SwConnectionInfo = undefined;
    if (c.sw_networking_connection_info(@intFromEnum(connection), &value) == 0) return error.InfoUnavailable;
    return Info.fromNative(value);
}
pub fn listenAddress(self: Networking, socket: ListenSocket) error{AddressUnavailable}!Address {
    self.lease.check();
    var value: c.SwAddress = undefined;
    if (c.sw_networking_listen_address(@intFromEnum(socket), &value) == 0) return error.AddressUnavailable;
    return Address.fromNative(value);
}
pub fn createPollGroup(self: Networking) error{PollGroupFailed}!PollGroup {
    self.lease.check();
    const group = c.sw_networking_create_poll_group();
    if (group == 0) return error.PollGroupFailed;
    return @enumFromInt(group);
}
pub fn destroyPollGroup(self: Networking, group: PollGroup) error{OperationFailed}!void {
    self.lease.check();
    if (c.sw_networking_destroy_poll_group(@intFromEnum(group)) == 0) return error.OperationFailed;
}
/// Use .invalid to detach a connection. Destroying a group does not close its connections.
pub fn setPollGroup(self: Networking, connection: Connection, group: PollGroup) error{OperationFailed}!void {
    self.lease.check();
    if (c.sw_networking_set_poll_group(@intFromEnum(connection), @intFromEnum(group)) == 0) return error.OperationFailed;
}
pub fn initRelay(self: Networking) error{Unavailable}!void {
    self.lease.check();
    if (c.sw_networking_init_relay() == 0) return error.Unavailable;
}
pub fn relayStatus(self: Networking) error{Unavailable}!RelayStatus {
    self.lease.check();
    var value: c.SwRelayStatus = undefined;
    if (c.sw_networking_relay_status(&value) == 0) return error.Unavailable;
    return .{
        .availability = @enumFromInt(value.availability),
        .ping_measurement_in_progress = value.ping_measurement_in_progress != 0,
        .network_config = @enumFromInt(value.network_config),
        .any_relay = @enumFromInt(value.any_relay),
        .debug = value.debug,
    };
}

fn analyzeDeclarations(comptime T: type) void {
    inline for (comptime std.meta.declarations(T)) |decl| {
        const value = @field(T, decl.name);
        if (@TypeOf(value) == type) {
            switch (@typeInfo(value)) {
                .@"struct", .@"enum", .@"union", .@"opaque" => analyzeDeclarations(value),
                else => {},
            }
        } else {
            _ = &@field(T, decl.name);
        }
    }
}
test "public Networking declarations analyze" {
    analyzeDeclarations(@This());
}
test "Info owns copied values and preserves unknown states and unterminated text" {
    var native = std.mem.zeroes(c.SwConnectionInfo);
    native.connection = 123;
    native.listen_socket = 456;
    native.peer_steam_id = 76561198000000000;
    native.state = 12345;
    native.end_reason = 4321;
    native.peer_identity = @splat('i');
    native.end_debug = @splat('d');
    const info = Info.fromNative(native);
    native.end_debug[0] = 0;
    try std.testing.expectEqual(@as(u32, 123), @intFromEnum(info.connection));
    try std.testing.expectEqual(@as(u32, 456), @intFromEnum(info.listen_socket));
    try std.testing.expectEqual(@as(u64, 76561198000000000), @intFromEnum(info.peer_steam_id));
    try std.testing.expectEqual(@as(i32, 12345), @intFromEnum(info.state));
    try std.testing.expectEqual(@as(i32, 4321), info.end_reason);
    try std.testing.expectEqual(@as(usize, 128), info.peerIdentity().len);
    try std.testing.expectEqual(@as(usize, 128), info.endDebug().len);
}
test "Address copies bytes and host-order port without SDK layout aliases" {
    var address = Address{ .port = 27015 };
    address.ipv6[15] = 1;
    const roundtrip = Address.fromNative(address.native());
    try std.testing.expectEqualDeep(address, roundtrip);
}
test "pure addresses preserve bytes and ports through Zig formatting without Steam" {
    const cases = [_]struct { input: []const u8, formatted: []const u8 }{
        .{ .input = "127.0.0.1:27015", .formatted = "127.0.0.1:27015" },
        .{ .input = "0.0.0.0", .formatted = "0.0.0.0:0" },
        .{ .input = "[::1]:65535", .formatted = "[::1]:65535" },
        .{ .input = "::", .formatted = "[::]:0" },
        .{ .input = "[2001:db8::1]", .formatted = "[2001:db8::1]:0" },
        .{ .input = "::ffff:192.0.2.1", .formatted = "192.0.2.1:0" },
        .{ .input = "[::ffff:c000:201]:7", .formatted = "192.0.2.1:7" },
        .{ .input = "2001:db8::192.0.2.1", .formatted = "[2001:db8::c000:201]:0" },
        .{ .input = "[ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff]:65535", .formatted = "[ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff]:65535" },
        .{ .input = "[ffff:ffff:ffff:ffff:ffff:ffff:255.255.255.255]:65535", .formatted = "[ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff]:65535" },
        .{ .input = "::ffff:1:2:3:4:5:6", .formatted = "[0:ffff:1:2:3:4:5:6]:0" },
    };
    for (cases) |case| {
        const address = try Address.parse(case.input);
        var buffer: [address_text_size]u8 = undefined;
        const formatted = try std.fmt.bufPrint(&buffer, "{f}", .{address});
        try std.testing.expectEqualStrings(case.formatted, formatted);
        try std.testing.expectEqualDeep(address, try Address.parse(formatted));
        var short: [1]u8 = undefined;
        try std.testing.expectError(error.NoSpaceLeft, std.fmt.bufPrint(&short, "{f}", .{address}));
    }
    for ([_][]const u8{ "", ":", "localhost:80", "127.0.0.1:65536", "127.0.0.1:", "127.0.0.1:+1", "[::1]:8_0", "[::1]extra", "[127.0.0.1]:8", "::1\x00suffix", "fe80::1%en0", "1:2:3:4:5:6:7::8", "::1::2", "[::1]:-1" }) |text|
        try std.testing.expectError(error.InvalidAddress, Address.parse(text));
}

test "address parsing rejects repeated compression before mapped address normalization" {
    try std.testing.expectError(error.InvalidAddress, Address.parse("::ffff:1::2:3:4:5:6"));
    try std.testing.expectError(error.InvalidAddress, Address.parse("[::ffff:1::2:3:4:5:6]:8"));
}

test "send options preserve independent flags and reject invalid reliability combinations" {
    try std.testing.expectEqual(SendFlags.reliable | SendFlags.no_nagle, try (SendOptions{ .reliability = .reliable, .no_nagle = true }).flags());
    try std.testing.expectEqual(SendFlags.no_delay | SendFlags.use_current_thread, try (SendOptions{ .no_delay = true, .use_current_thread = true }).flags());
    try std.testing.expectEqual(SendFlags.no_delay | SendFlags.no_nagle, try (SendOptions{ .no_delay = true, .no_nagle = true }).flags());
    try std.testing.expectError(error.InvalidSendOptions, (SendOptions{ .reliability = .reliable, .no_delay = true }).flags());
}

test "send outcomes expose a number only on acceptance and preserve unknown rejections" {
    try std.testing.expectEqual(@as(i64, 71), SendOutcome.fromNative(@intFromEnum(types.Result.ok), 71).accepted);
    try std.testing.expectEqual(types.Result.limit_exceeded, SendOutcome.fromNative(@intFromEnum(types.Result.limit_exceeded), -1).rejected);
    try std.testing.expectEqual(@as(i32, 123456), @intFromEnum(SendOutcome.fromNative(123456, -1).rejected));
}

test "batch cleanup releases unread messages after an early error without double release" {
    const Fixture = struct {
        fn release(handle: [*c]?*c.SwMessage) callconv(.c) void {
            const counter: *u8 = @ptrCast(handle[0].?);
            counter.* += 1;
            handle[0] = null;
        }
        fn process(batch: *MessageBatch) error{ProcessingFailed}!void {
            defer batch.releaseWith(release);
            _ = batch.messages[0].bytes();
            batch.messages[0].releaseWith(release);
            return error.ProcessingFailed;
        }
    };
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    var released = [_]u8{ 0, 0, 0 };
    var storage: [3]Message = undefined;
    for (&released, &storage) |*counter, *message| {
        var view = std.mem.zeroes(c.SwMessageView);
        view.handle = @ptrCast(counter);
        message.* = Message.adopt(context.lease(), view);
    }
    var batch: MessageBatch = .{ .messages = &storage };
    try std.testing.expectEqual(@as(usize, 3), context.messages);
    try std.testing.expectError(error.ProcessingFailed, Fixture.process(&batch));
    try std.testing.expectEqualSlices(u8, &.{ 1, 1, 1 }, &released);
    try std.testing.expectEqual(@as(usize, 0), context.messages);
    try std.testing.expectEqual(@as(usize, 0), batch.messages.len);
    batch.releaseWith(Fixture.release);
    try std.testing.expectEqualSlices(u8, &.{ 1, 1, 1 }, &released);
}

test "receive limits and message validation reject invalid ownership without native calls" {
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    const networking = Networking{ .lease = context.lease() };
    try std.testing.expectError(error.InvalidAddress, networking.parseAddress("::1\x00suffix"));
    try std.testing.expectError(error.InvalidDebugText, networking.close(.invalid, .{ .debug = "a\x00b" }));
    try std.testing.expectError(error.InvalidSendOptions, networking.send(.invalid, "", .{ .reliability = .reliable, .no_delay = true }));
    try std.testing.expectError(error.InvalidSteamId, networking.connectP2P(.invalid, 0));
    var slots: [max_receive + 1]Message = undefined;
    try std.testing.expectError(error.TooManyMessages, networking.receive(.invalid, &slots));
    var empty = try networking.receive(.invalid, slots[0..0]);
    defer empty.deinit();
    try std.testing.expectEqual(@as(usize, 0), empty.messages.len);
    var view = std.mem.zeroes(c.SwMessageView);
    try std.testing.expectError(error.InvalidMessage, Message.validate(view));
    // Validation never dereferences opaque handles.
    var token: u8 = 0;
    view.handle = @ptrCast(&token);
    try Message.validate(view); // A zero-byte native message may have a null payload.
    view.size = -1;
    try std.testing.expectError(error.InvalidMessage, Message.validate(view));
    view.size = 1;
    try std.testing.expectError(error.InvalidMessage, Message.validate(view));
    view.data = &token;
    try Message.validate(view);
    try std.testing.expectEqual(@as(usize, 0), context.messages);
}
