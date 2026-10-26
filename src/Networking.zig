//! Owner-thread, session-borrowed sockets and relay access. Handles need explicit
//! close/destroy; copied status values do not. Receive calls transfer SDK message
//! ownership into caller slots: release every batch before Client.deinit.
//! Connection callbacks arrive through Client pumping/polling, not receive calls.
//! Valve: https://partner.steamgames.com/doc/api/ISteamNetworkingSockets
//! and https://partner.steamgames.com/doc/api/ISteamNetworkingUtils
const std = @import("std");
const Context = @import("Context.zig");
const types = @import("types.zig");
const c = @import("steamworkz_c");
const Networking = @This();

lease: Context.Lease,

/// Handles belong to the creating client session; never reuse them in a new one.
pub const Connection = enum(u32) { invalid = 0, _ };
/// Session handle; closeListen releases it and closes its incoming connections.
pub const ListenSocket = enum(u32) { invalid = 0, _ };
/// Session receive grouping; destroyPollGroup does not close member connections.
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
            .peer_steam_id = @fromBackingInt(@intCast(value.peer_steam_id)),
            .connection = @fromBackingInt(@intCast(value.connection)),
            .listen_socket = @fromBackingInt(@intCast(value.listen_socket)),
            .state = @fromBackingInt(@intCast(value.state)),
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

/// Steam's maximum configured lane count, not a count discovery mechanism.
pub const max_lanes = c.SW_NETWORKING_MAX_LANES;

/// Owned snapshot, with signed readings and native floating-point values intact.
/// No teardown is needed for this value or LaneRealTimeStatus.
pub const RealTimeStatus = struct {
    state: State,
    ping_ms: i32,
    connection_quality_local: f32,
    connection_quality_remote: f32,
    out_packets_per_second: f32,
    out_bytes_per_second: f32,
    in_packets_per_second: f32,
    in_bytes_per_second: f32,
    send_rate_bytes_per_second: i32,
    /// Bytes queued for sending, including data waiting for Nagle.
    pending_unreliable: i32,
    /// Also includes previously sent bytes scheduled for retransmission.
    pending_reliable: i32,
    /// Bytes sent reliably but not yet acknowledged.
    sent_unacked_reliable: i32,
    /// Estimate ignoring Nagle delay. Valid only when multiple lanes are NOT used;
    /// use each lane's queue_time_us when multiple lanes are configured.
    queue_time_us: i64,
    /// High-water jitter since the last fetch; negative means unavailable.
    /// Fetching real-time status clears this native high-water mark.
    max_jitter_us: i32,

    fn fromNative(value: c.SwConnectionRealTimeStatus) RealTimeStatus {
        return .{
            .state = @fromBackingInt(@intCast(value.state)),
            .ping_ms = value.ping_ms,
            .connection_quality_local = value.connection_quality_local,
            .connection_quality_remote = value.connection_quality_remote,
            .out_packets_per_second = value.out_packets_per_second,
            .out_bytes_per_second = value.out_bytes_per_second,
            .in_packets_per_second = value.in_packets_per_second,
            .in_bytes_per_second = value.in_bytes_per_second,
            .send_rate_bytes_per_second = value.send_rate_bytes_per_second,
            .pending_unreliable = value.pending_unreliable,
            .pending_reliable = value.pending_reliable,
            .sent_unacked_reliable = value.sent_unacked_reliable,
            .queue_time_us = value.queue_time_us,
            .max_jitter_us = value.max_jitter_us,
        };
    }
};
/// Owned per-lane byte counters with the same meaning as RealTimeStatus.
pub const LaneRealTimeStatus = struct {
    pending_unreliable: i32,
    pending_reliable: i32,
    sent_unacked_reliable: i32,
    /// Lane estimate accounts for priorities, weights and queued data in all lanes.
    queue_time_us: i64,

    fn fromNative(value: c.SwLaneRealTimeStatus) LaneRealTimeStatus {
        return .{
            .pending_unreliable = value.pending_unreliable,
            .pending_reliable = value.pending_reliable,
            .sent_unacked_reliable = value.sent_unacked_reliable,
            .queue_time_us = value.queue_time_us,
        };
    }
};
pub const RealTimeStatusOutcome = union(enum) {
    status: RealTimeStatus,
    rejected: types.Result,
};
pub const DetailedStatusOutcome = union(enum) {
    /// Borrows caller storage, excluding the terminator. No teardown required.
    complete: []const u8,
    /// Required byte capacity, including space for the terminator.
    required_capacity: usize,
    failed,
    unexpected_result: i32,
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
        const value: types.Result = @fromBackingInt(@intCast(result));
        return if (value == .ok) .{ .accepted = number } else .{ .rejected = value };
    }
};
/// Lower priorities strictly precede higher ones. Weights share bandwidth only
/// among equal priorities; zero weight is invalid.
pub const LaneConfig = struct { priority: i32, weight: u16 };
/// Wrapper bound, not an SDK limit or the receive limit.
pub const max_send_batch = c.SW_NETWORKING_MAX_SEND_BATCH;
pub const max_send_size = c.SW_NETWORKING_MAX_SEND_SIZE;
/// Payload is borrowed only during sendBatch. No buffer or callback is retained.
pub const BatchSend = struct {
    connection: Connection,
    payload: []const u8,
    lane: u16 = 0,
    options: SendOptions = .{},
};
pub const BatchSendOutcome = union(enum) {
    /// Local acceptance only; numbers are scoped to connection AND lane.
    accepted: i64,
    rejected: types.Result,
    /// An earlier entry on the same connection failed. No retry is performed.
    not_attempted,
    unexpected_result: i64,

    fn fromNative(raw: i64) BatchSendOutcome {
        if (raw > 0) return .{ .accepted = raw };
        if (raw == 0) return .not_attempted;
        // Compare before negation, including INT64_MIN.
        if (raw >= -@as(i64, std.math.maxInt(i32))) return .{ .rejected = @fromBackingInt(@intCast(@as(i32, @intCast(-raw)))) };
        return .{ .unexpected_result = raw };
    }
};
pub const BatchSendError = error{ TooManyMessages, InsufficientOutcomes, TooLarge, InvalidLane, InvalidSendOptions, Unavailable, AllocationFailed, BridgeFailed };

pub const Metadata = struct {
    connection: Connection,
    peer_steam_id: types.SteamId,
    /// Message numbers are per lane. Only reliable messages within one lane
    /// have an ordering guarantee; numbers are not globally unique.
    number: i64,
    /// SDK local monotonic timestamp in microseconds, not Unix time.
    received_at: i64,
    channel: i32,
    /// Raw incoming lane, independent of channel and outgoing wrapper bounds.
    lane: u16 = 0,
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

    /// Borrows SDK payload until this message/batch is deinitialized. Copy bytes
    /// before retaining beyond that point; access after release is a runtime panic.
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
                .connection = @fromBackingInt(@intCast(view.connection)),
                .peer_steam_id = @fromBackingInt(@intCast(view.peer_steam_id)),
                .number = view.number,
                .received_at = view.received_at,
                .channel = view.channel,
                .lane = view.lane,
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

    /// Releases remaining SteamNetworkingMessage_t owners, not the caller's slots.
    /// Call on the client owner thread while the original session is still live.
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
/// ISteamNetworkingSockets::CreateListenSocketIP. Owns a listener until closeListen.
/// Incoming connection_changed (SteamNetConnectionStatusChangedCallback_t) events
/// require an explicit accept or close; creation alone does not accept peers.
pub fn listenIP(self: Networking, address: Address) error{ListenFailed}!ListenSocket {
    self.lease.check();
    const value = address.native();
    const handle = c.sw_networking_listen_ip(&value);
    if (handle == 0) return error.ListenFailed;
    return @fromBackingInt(@intCast(handle));
}
/// ISteamNetworkingSockets::ConnectByIPAddress starts connecting, not a ready link.
/// Observe connection_changed.info.state; close the handle even after terminal failure.
pub fn connectIP(self: Networking, address: Address) error{ConnectFailed}!Connection {
    self.lease.check();
    const value = address.native();
    const handle = c.sw_networking_connect_ip(&value);
    if (handle == 0) return error.ConnectFailed;
    return @fromBackingInt(@intCast(handle));
}
/// ISteamNetworkingSockets::CreateListenSocketP2P; virtual_port is a logical
/// endpoint, not a UDP port. Accept/close incoming connections; closeListen when done.
pub fn listenP2P(self: Networking, virtual_port: u16) error{ListenFailed}!ListenSocket {
    self.lease.check();
    const handle = c.sw_networking_listen_p2p(virtual_port);
    if (handle == 0) return error.ListenFailed;
    return @fromBackingInt(@intCast(handle));
}
/// ISteamNetworkingSockets::ConnectP2P targets the peer's logical virtual_port.
/// Returning a handle is not connection success; observe connection_changed and
/// eventually close, including after failure. No application handshake is supplied.
pub fn connectP2P(self: Networking, peer: types.SteamId, virtual_port: u16) error{ InvalidSteamId, ConnectFailed }!Connection {
    self.lease.check();
    if (peer == .invalid) return error.InvalidSteamId;
    const handle = c.sw_networking_connect_p2p(@backingInt(peer), virtual_port);
    if (handle == 0) return error.ConnectFailed;
    return @fromBackingInt(@intCast(handle));
}
/// ISteamNetworkingSockets::AcceptConnection for an incoming connecting event.
/// Preserves the native Result; .ok accepts the attempt, not a completed handshake.
pub fn accept(self: Networking, connection: Connection) types.Result {
    self.lease.check();
    return @fromBackingInt(@intCast(c.sw_networking_accept(@backingInt(connection))));
}
/// ISteamNetworkingSockets::CloseConnection. Terminal callbacks do not release it: close
/// it even after closed_by_peer or problem_detected_locally. Debug text is
/// borrowed only for this call. Linger permits queued reliable sends to drain.
pub fn close(self: Networking, connection: Connection, options: CloseOptions) error{ InvalidDebugText, OperationFailed }!void {
    self.lease.check();
    if (options.debug) |text| {
        if (text.len >= 128 or std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidDebugText;
    }
    if (c.sw_networking_close(@backingInt(connection), options.reason, if (options.debug) |text| text.ptr else null, @intFromBool(options.linger)) == 0)
        return error.OperationFailed;
}
/// ISteamNetworkingSockets::CloseListenSocket destroys the listener and closes
/// associated incoming connections ungracefully. Plan graceful connection shutdown
/// separately before this call.
pub fn closeListen(self: Networking, socket: ListenSocket) error{OperationFailed}!void {
    self.lease.check();
    if (c.sw_networking_close_listen(@backingInt(socket)) == 0) return error.OperationFailed;
}
/// Both returned connections require explicit close. With network_loopback=false
/// the SDK uses an in-process pair; this still requires an initialized client.
pub fn socketPair(self: Networking, options: SocketPairOptions) error{OperationFailed}![2]Connection {
    self.lease.check();
    var first: u32 = 0;
    var second: u32 = 0;
    if (c.sw_networking_socket_pair(&first, &second, @intFromBool(options.network_loopback)) == 0) return error.OperationFailed;
    return .{ @fromBackingInt(@intCast(first)), @fromBackingInt(@intCast(second)) };
}
/// ISteamNetworkingSockets::SendMessageToConnection copies data during the call;
/// no borrowed payload survives return. Sends on lane zero; acceptance is not delivery.
/// Local errors use Zig errors; native rejection retains its Result in the outcome.
/// Use sendBatch (including one entry) for other lanes.
pub fn send(self: Networking, connection: Connection, data: []const u8, options: SendOptions) error{ TooLarge, InvalidSendOptions }!SendOutcome {
    self.lease.check();
    return sendMessage(connection, data, try options.flags());
}
/// Lane-zero escape hatch for advanced/future SDK bits. Steam validates raw flags.
pub fn sendRaw(self: Networking, connection: Connection, data: []const u8, flags: i32) error{TooLarge}!SendOutcome {
    self.lease.check();
    return sendMessage(connection, data, flags);
}
fn sendMessage(connection: Connection, data: []const u8, flags: i32) error{TooLarge}!SendOutcome {
    const size = std.math.cast(u32, data.len) orelse return error.TooLarge;
    var number: i64 = -1;
    const result = c.sw_networking_send(@backingInt(connection), data.ptr, size, flags, &number);
    return SendOutcome.fromNative(result, number);
}
/// Configure 1..max_lanes outbound lanes. Native rejects reducing the count and
/// may reset bandwidth balancing on reconfiguration. No count is cached and
/// sends never configure lanes automatically.
pub fn configureLanes(self: Networking, connection: Connection, lanes: []const LaneConfig) error{ InvalidLaneCount, InvalidLaneWeight, Unavailable, BridgeFailed }!types.Result {
    return self.configureLanesWith(connection, lanes, c.sw_networking_configure_lanes);
}
fn configureLanesWith(self: Networking, connection: Connection, lanes: []const LaneConfig, comptime configure: @TypeOf(c.sw_networking_configure_lanes)) error{ InvalidLaneCount, InvalidLaneWeight, Unavailable, BridgeFailed }!types.Result {
    self.lease.check();
    if (lanes.len == 0 or lanes.len > max_lanes) return error.InvalidLaneCount;
    var native: [max_lanes]c.SwLaneConfig = undefined;
    for (lanes, native[0..lanes.len]) |lane, *out| {
        if (lane.weight == 0) return error.InvalidLaneWeight;
        out.* = .{ .priority = lane.priority, .weight = lane.weight };
    }
    var result: i32 = undefined;
    try checkStatusBridge(configure(@backingInt(connection), &native, @intCast(lanes.len), &result));
    return @fromBackingInt(@intCast(result));
}
/// Validate all descriptors before any native access, then copy payloads into
/// SDK-allocated messages and transfer all with one call. Empty payloads use a
/// one-byte SDK allocation with logical size zero. Pre-transfer errors send
/// nothing and leave outcomes untouched. No outbound owner escapes this call.
/// Returns the initialized prefix borrowing caller storage; no teardown needed.
/// An empty batch is a no-op after checking the lease.
pub fn sendBatch(self: Networking, messages: []const BatchSend, outcomes: []BatchSendOutcome) BatchSendError![]BatchSendOutcome {
    return self.sendBatchWith(messages, outcomes, c.sw_networking_send_batch);
}
fn sendBatchWith(self: Networking, messages: []const BatchSend, outcomes: []BatchSendOutcome, comptime transfer: @TypeOf(c.sw_networking_send_batch)) BatchSendError![]BatchSendOutcome {
    self.lease.check();
    if (messages.len > max_send_batch) return error.TooManyMessages;
    if (outcomes.len < messages.len) return error.InsufficientOutcomes;
    if (messages.len == 0) return outcomes[0..0];
    var native: [max_send_batch]c.SwBatchSend = undefined;
    for (messages, native[0..messages.len]) |message, *out| {
        if (message.payload.len > max_send_size) return error.TooLarge;
        if (message.lane >= max_lanes) return error.InvalidLane;
        out.* = .{
            .connection = @backingInt(message.connection),
            .data = message.payload.ptr,
            .size = @intCast(message.payload.len),
            .lane = message.lane,
            .flags = try message.options.flags(),
        };
    }
    var results: [max_send_batch]i64 = undefined;
    const result = transfer(&native, @intCast(messages.len), &results);
    if (result == -2) return error.AllocationFailed;
    try checkStatusBridge(result);
    for (outcomes[0..messages.len], results[0..messages.len]) |*out, raw| out.* = BatchSendOutcome.fromNative(raw);
    return outcomes[0..messages.len];
}
/// ISteamNetworkingSockets::FlushMessagesOnConnection bypasses the Nagle wait.
/// Preserves the native Result; .ok is not a delivery acknowledgement.
pub fn flush(self: Networking, connection: Connection) types.Result {
    self.lease.check();
    return @fromBackingInt(@intCast(c.sw_networking_flush(@backingInt(connection))));
}

pub const ReceiveError = error{ TooManyMessages, ReceiveFailed, InvalidMessage };
/// ISteamNetworkingSockets::ReceiveMessagesOnConnection. out.len must not exceed
/// max_receive; slots must be unowned/undefined. Returns only initialized messages,
/// possibly none; it does not pump connection callbacks. Install defer batch.deinit()
/// immediately and release before client close or slot reuse. Errors release any
/// native messages acquired by this call; no partial batch escapes.
pub fn receive(self: Networking, connection: Connection, out: []Message) ReceiveError!MessageBatch {
    return self.receiveBatch(@backingInt(connection), false, out);
}
/// ISteamNetworkingSockets::ReceiveMessagesOnPollGroup. Same slot/cleanup contract
/// as receive: defer batch.deinit(), before client close or reusing storage.
/// Each message's metadata.connection identifies its source; destroying the group
/// does not release already received messages or close its connections.
pub fn receivePollGroup(self: Networking, group: PollGroup, out: []Message) ReceiveError!MessageBatch {
    return self.receiveBatch(@backingInt(group), true, out);
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
/// ISteamNetworkingSockets::GetConnectionInfo returns an owned snapshot, not
/// a live reference. InfoUnavailable includes invalid/closed handles.
pub fn connectionInfo(self: Networking, connection: Connection) error{InfoUnavailable}!Info {
    self.lease.check();
    var value: c.SwConnectionInfo = undefined;
    if (c.sw_networking_connection_info(@backingInt(connection), &value) == 0) return error.InfoUnavailable;
    return Info.fromNative(value);
}
/// ISteamNetworkingSockets::GetConnectionRealTimeStatus.
/// Requests exactly lanes.len entries (lane zero onward), including zero or a
/// prefix. The caller tracks the configured count: requesting more configured
/// lanes than exist is left to native validation. Outputs are unchanged unless
/// native returns OK. Fetching this status clears the jitter high-water mark.
pub fn realTimeStatus(self: Networking, connection: Connection, lanes: []LaneRealTimeStatus) error{ TooManyLanes, Unavailable, BridgeFailed }!RealTimeStatusOutcome {
    return self.realTimeStatusWith(connection, lanes, c.sw_networking_real_time_status);
}
fn realTimeStatusWith(self: Networking, connection: Connection, lanes: []LaneRealTimeStatus, comptime query: @TypeOf(c.sw_networking_real_time_status)) error{ TooManyLanes, Unavailable, BridgeFailed }!RealTimeStatusOutcome {
    self.lease.check();
    if (lanes.len > max_lanes) return error.TooManyLanes;
    var value: c.SwConnectionRealTimeStatus = undefined;
    var native_lanes: [max_lanes]c.SwLaneRealTimeStatus = undefined;
    var result: i32 = undefined;
    try checkStatusBridge(query(@backingInt(connection), &value, if (lanes.len == 0) null else &native_lanes, @intCast(lanes.len), &result));
    const native_result: types.Result = @fromBackingInt(@intCast(result));
    if (native_result != .ok) return .{ .rejected = native_result };
    for (lanes, native_lanes[0..lanes.len]) |*lane, native_lane| lane.* = LaneRealTimeStatus.fromNative(native_lane);
    return .{ .status = RealTimeStatus.fromNative(value) };
}
/// ISteamNetworkingSockets::GetDetailedConnectionStatus. Caller-storage-only text.
/// Empty storage queries with null/zero. The SDK may modify/truncate a short
/// buffer: no untouched-buffer guarantee is made.
/// Retry with the reported capacity; status can change between calls.
pub fn detailedStatus(self: Networking, connection: Connection, buffer: []u8) error{ BufferTooLarge, Unavailable, BridgeFailed, UnterminatedStatus }!DetailedStatusOutcome {
    return self.detailedStatusWith(connection, buffer, c.sw_networking_detailed_status);
}
fn detailedStatusWith(self: Networking, connection: Connection, buffer: []u8, comptime query: @TypeOf(c.sw_networking_detailed_status)) error{ BufferTooLarge, Unavailable, BridgeFailed, UnterminatedStatus }!DetailedStatusOutcome {
    self.lease.check();
    const capacity = try detailedStatusCapacity(buffer.len);
    var result: i32 = undefined;
    try checkStatusBridge(query(@backingInt(connection), if (buffer.len == 0) null else buffer.ptr, capacity, &result));
    if (result == -1) return .failed;
    if (result < -1) return .{ .unexpected_result = result };
    if (result > 0) return .{ .required_capacity = @intCast(result) };
    const end = std.mem.indexOfScalar(u8, buffer, 0) orelse return error.UnterminatedStatus;
    return .{ .complete = buffer[0..end] };
}
fn detailedStatusCapacity(length: usize) error{BufferTooLarge}!c_int {
    return std.math.cast(c_int, length) orelse error.BufferTooLarge;
}
fn checkStatusBridge(result: c_int) error{ Unavailable, BridgeFailed }!void {
    switch (result) {
        1 => {},
        0 => return error.Unavailable,
        else => return error.BridgeFailed,
    }
}
/// ISteamNetworkingSockets::GetListenSocketAddress; owned IP endpoint, including
/// the actual bound port when listenIP requested port zero.
pub fn listenAddress(self: Networking, socket: ListenSocket) error{AddressUnavailable}!Address {
    self.lease.check();
    var value: c.SwAddress = undefined;
    if (c.sw_networking_listen_address(@backingInt(socket), &value) == 0) return error.AddressUnavailable;
    return Address.fromNative(value);
}
/// ISteamNetworkingSockets::CreatePollGroup creates an empty receive group.
/// Attach with setPollGroup; explicitly destroyPollGroup before Client.deinit.
pub fn createPollGroup(self: Networking) error{PollGroupFailed}!PollGroup {
    self.lease.check();
    const group = c.sw_networking_create_poll_group();
    if (group == 0) return error.PollGroupFailed;
    return @fromBackingInt(@intCast(group));
}
/// ISteamNetworkingSockets::DestroyPollGroup detaches, but does not close, its
/// connections. Already received batches still need their own deinit.
pub fn destroyPollGroup(self: Networking, group: PollGroup) error{OperationFailed}!void {
    self.lease.check();
    if (c.sw_networking_destroy_poll_group(@backingInt(group)) == 0) return error.OperationFailed;
}
/// ISteamNetworkingSockets::SetConnectionPollGroup assigns one group per connection.
/// Use .invalid to detach. Destroying a group does not close its connections.
pub fn setPollGroup(self: Networking, connection: Connection, group: PollGroup) error{OperationFailed}!void {
    self.lease.check();
    if (c.sw_networking_set_poll_group(@backingInt(connection), @backingInt(group)) == 0) return error.OperationFailed;
}
/// ISteamNetworkingUtils::InitRelayNetworkAccess begins relay preparation explicitly.
/// Success means invocation only; inspect relayStatus or relay_status events
/// (SteamRelayNetworkStatus_t) for availability. May start network work.
pub fn initRelay(self: Networking) error{Unavailable}!void {
    self.lease.check();
    if (c.sw_networking_init_relay() == 0) return error.Unavailable;
}
/// ISteamNetworkingUtils::GetRelayNetworkStatus returns an owned current snapshot.
/// Unknown availability values survive; no relay initialization is implied.
pub fn relayStatus(self: Networking) error{Unavailable}!RelayStatus {
    self.lease.check();
    var value: c.SwRelayStatus = undefined;
    if (c.sw_networking_relay_status(&value) == 0) return error.Unavailable;
    return .{
        .availability = @fromBackingInt(@intCast(value.availability)),
        .ping_measurement_in_progress = value.ping_measurement_in_progress != 0,
        .network_config = @fromBackingInt(@intCast(value.network_config)),
        .any_relay = @fromBackingInt(@intCast(value.any_relay)),
        .debug = value.debug,
    };
}

fn analyzeDeclarations(comptime T: type) void {
    inline for (comptime std.meta.declarations(T)) |decl_name| {
        const value = @field(T, decl_name);
        if (@TypeOf(value) == type) {
            switch (@typeInfo(value)) {
                .@"struct", .@"enum", .@"union", .@"opaque" => analyzeDeclarations(value),
                else => {},
            }
        } else {
            _ = &@field(T, decl_name);
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
    try std.testing.expectEqual(@as(u32, 123), @backingInt(info.connection));
    try std.testing.expectEqual(@as(u32, 456), @backingInt(info.listen_socket));
    try std.testing.expectEqual(@as(u64, 76561198000000000), @backingInt(info.peer_steam_id));
    try std.testing.expectEqual(@as(i32, 12345), @backingInt(info.state));
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
    try std.testing.expectEqual(@as(i64, 71), SendOutcome.fromNative(@backingInt(types.Result.ok), 71).accepted);
    try std.testing.expectEqual(types.Result.limit_exceeded, SendOutcome.fromNative(@backingInt(types.Result.limit_exceeded), -1).rejected);
    try std.testing.expectEqual(@as(i32, 123456), @backingInt(SendOutcome.fromNative(123456, -1).rejected));
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

test "lifecycle fatal released-message" {
    if (!@import("steamworkz_test_options").fatal_lifecycle) return error.SkipZigTest;
    const Fixture = struct {
        fn release(handle: [*c]?*c.SwMessage) callconv(.c) void {
            handle[0] = null;
        }
    };
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    var token: u8 = 0;
    const payload = "owned fixture bytes";
    var view = std.mem.zeroes(c.SwMessageView);
    view.handle = @ptrCast(&token);
    view.data = payload.ptr;
    view.size = payload.len;
    var message = Message.adopt(context.lease(), view);
    try std.testing.expectEqualStrings(payload, message.bytes());
    message.releaseWith(Fixture.release);
    try std.testing.expectEqual(@as(usize, 0), context.messages);
    try std.Io.File.stderr().writeStreamingAll(std.testing.io, "STEAMWORKZ_FATAL_READY:released-message\n");
    _ = message.bytes();
}

test "property Address deterministic bytes and ports round trip" {
    var prng = std.Random.DefaultPrng.init(0x535741444452);
    const random = prng.random();
    for (0..256) |index| {
        errdefer std.debug.print("Address seed=0x535741444452 case={d}\n", .{index});
        var address: Address = .{ .port = switch ((index / 4) % 4) {
            0 => 0,
            1 => 65535,
            else => random.int(u16),
        } };
        random.bytes(&address.ipv6);
        switch (index % 4) {
            0 => { // IPv4-mapped bytes.
                @memset(address.ipv6[0..10], 0);
                address.ipv6[10] = 0xff;
                address.ipv6[11] = 0xff;
            },
            1 => @memset(address.ipv6[0 .. index % 17], 0),
            2 => @memset(address.ipv6[index % 17 ..], 0),
            else => {},
        }
        var buffer: [address_text_size]u8 = undefined;
        const formatted = try std.fmt.bufPrint(&buffer, "{f}", .{address});
        try std.testing.expectEqualDeep(address, try Address.parse(formatted));
        var mutation: [address_text_size + 16]u8 = undefined;
        for ([_][]const u8{ "%scope", "\x00", "]", ":65536" }) |suffix| {
            const malformed = try std.fmt.bufPrint(&mutation, "{s}{s}", .{ formatted, suffix });
            try std.testing.expectError(error.InvalidAddress, Address.parse(malformed));
        }
    }
}

test "property Address bounded arbitrary strings and malformed numeric mutations" {
    var prng = std.Random.DefaultPrng.init(0x53575041525345);
    const random = prng.random();
    var input: [64]u8 = undefined;
    for (0..512) |index| {
        errdefer std.debug.print("Address seed=0x53575041525345 case={d}\n", .{index});
        const length = index % (input.len + 1);
        random.bytes(input[0..length]);
        if (index % 2 == 0) {
            const alphabet = "0123456789abcdef:.[]%";
            for (input[0..length]) |*byte| byte.* = alphabet[byte.* % alphabet.len];
        }
        if (Address.parse(input[0..length])) |address| {
            var buffer: [address_text_size]u8 = undefined;
            try std.testing.expectEqualDeep(address, try Address.parse(try std.fmt.bufPrint(&buffer, "{f}", .{address})));
        } else |err| try std.testing.expectEqual(error.InvalidAddress, err);
    }
    for (0..32) |index| {
        var buffer: [128]u8 = undefined;
        inline for (.{ "[::1]:+{d}", "[::1]:{d}_0", "[::1:{d}", "::ffff:{d}::1", "[fe80::{d}%1]:80", "127.0.0.1:{d}\x00" }) |pattern| {
            try std.testing.expectError(error.InvalidAddress, Address.parse(try std.fmt.bufPrint(&buffer, pattern, .{index})));
        }
    }
}

test "realTimeStatus copies all fields preserving signed readings and float bits" {
    const native: c.SwConnectionRealTimeStatus = .{
        .state = 12345,
        .ping_ms = -11,
        .connection_quality_local = @bitCast(@as(u32, 0x80000000)),
        .connection_quality_remote = @bitCast(@as(u32, 0x7fc12345)),
        .out_packets_per_second = @bitCast(@as(u32, 0x7f800000)),
        .out_bytes_per_second = @bitCast(@as(u32, 0xff800000)),
        .in_packets_per_second = @bitCast(@as(u32, 1)),
        .in_bytes_per_second = -29.5,
        .send_rate_bytes_per_second = -31,
        .pending_unreliable = -41,
        .pending_reliable = 43,
        .sent_unacked_reliable = -47,
        .queue_time_us = std.math.minInt(i64) + 53,
        .max_jitter_us = -59,
    };
    const status = RealTimeStatus.fromNative(native);
    try std.testing.expectEqual(@as(i32, 12345), @backingInt(status.state));
    const info = @typeInfo(RealTimeStatus).@"struct";
    inline for (info.field_names, info.field_types) |field_name, Field| {
        if (Field == f32) {
            try std.testing.expectEqual(@as(u32, @bitCast(@field(native, field_name))), @as(u32, @bitCast(@field(status, field_name))));
        } else if (Field != State) {
            try std.testing.expectEqual(@field(native, field_name), @field(status, field_name));
        }
    }
    const lane = LaneRealTimeStatus.fromNative(.{
        .pending_unreliable = -61,
        .pending_reliable = 67,
        .sent_unacked_reliable = -71,
        .queue_time_us = std.math.maxInt(i64) - 73,
    });
    try std.testing.expectEqualDeep(LaneRealTimeStatus{
        .pending_unreliable = -61,
        .pending_reliable = 67,
        .sent_unacked_reliable = -71,
        .queue_time_us = std.math.maxInt(i64) - 73,
    }, lane);
}

test "realTimeStatus zero prefix maximum and rejections commit only native success" {
    const Fixture = struct {
        var calls: usize = 0;
        var count: c_int = 0;
        var bridge: c_int = 1;
        var result: i32 = 1;
        fn query(connection: u32, status: [*c]c.SwConnectionRealTimeStatus, lanes: [*c]c.SwLaneRealTimeStatus, lane_count: c_int, native_result: [*c]i32) callconv(.c) c_int {
            std.testing.expect(connection == 79 and lane_count == count) catch @panic("telemetry arguments");
            std.testing.expect(if (count == 0) lanes == null else lanes != null) catch @panic("telemetry lane pointer");
            calls += 1;
            // Even a badly behaved bridge must not leak failed outputs to callers.
            status.* = std.mem.zeroes(c.SwConnectionRealTimeStatus);
            status.*.state = 12345;
            for (0..@intCast(lane_count)) |i| lanes[i] = .{
                .pending_unreliable = -100 - @as(i32, @intCast(i)),
                .pending_reliable = 200 + @as(i32, @intCast(i)),
                .sent_unacked_reliable = -300 - @as(i32, @intCast(i)),
                .queue_time_us = std.math.maxInt(i64) - @as(i64, @intCast(i)),
            };
            native_result.* = result;
            return bridge;
        }
    };
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    const networking: Networking = .{ .lease = context.lease() };
    const sentinel: LaneRealTimeStatus = .{ .pending_unreliable = 1, .pending_reliable = 2, .sent_unacked_reliable = 3, .queue_time_us = 4 };
    var lanes: [max_lanes + 1]LaneRealTimeStatus = @splat(sentinel);
    for ([_]usize{ 0, 1, 3, max_lanes }) |count| {
        @memset(&lanes, sentinel);
        Fixture.count = @intCast(count);
        const result = try networking.realTimeStatusWith(@fromBackingInt(@intCast(79)), lanes[0..count], Fixture.query);
        try std.testing.expectEqual(@as(i32, 12345), @backingInt(result.status.state));
        for (lanes[0..count], 0..) |lane, i| {
            try std.testing.expectEqualDeep(LaneRealTimeStatus{
                .pending_unreliable = -100 - @as(i32, @intCast(i)),
                .pending_reliable = 200 + @as(i32, @intCast(i)),
                .sent_unacked_reliable = -300 - @as(i32, @intCast(i)),
                .queue_time_us = std.math.maxInt(i64) - @as(i64, @intCast(i)),
            }, lane);
        }
        for (lanes[count..]) |lane| try std.testing.expectEqualDeep(sentinel, lane);
    }
    const saved = lanes;
    Fixture.count = 3;
    for ([_]i32{ @backingInt(types.Result.no_connection), @backingInt(types.Result.invalid_parameter), 123456, -123456 }) |result| {
        Fixture.result = result;
        try std.testing.expectEqual(result, @backingInt((try networking.realTimeStatusWith(@fromBackingInt(@intCast(79)), lanes[0..3], Fixture.query)).rejected));
        try std.testing.expectEqualDeep(saved, lanes);
    }
    Fixture.bridge = 0;
    try std.testing.expectError(error.Unavailable, networking.realTimeStatusWith(@fromBackingInt(@intCast(79)), lanes[0..3], Fixture.query));
    Fixture.bridge = -1;
    try std.testing.expectError(error.BridgeFailed, networking.realTimeStatusWith(@fromBackingInt(@intCast(79)), lanes[0..3], Fixture.query));
    try std.testing.expectEqualDeep(saved, lanes);
    const calls = Fixture.calls;
    try std.testing.expectError(error.TooManyLanes, networking.realTimeStatusWith(@fromBackingInt(@intCast(79)), &lanes, Fixture.query));
    // The actual public entry point must also reject before resolving Steam.
    try std.testing.expectError(error.TooManyLanes, networking.realTimeStatus(.invalid, &lanes));
    try std.testing.expectEqual(calls, Fixture.calls);
    try std.testing.expectEqualDeep(saved, lanes);
}

test "detailedStatus caller storage query completion truncation and raw failures" {
    const Fixture = struct {
        var bridge: c_int = 1;
        var result: i32 = 4;
        var capacity: c_int = 0;
        var terminate: bool = true;
        fn query(connection: u32, buffer: [*c]u8, length: c_int, native_result: [*c]i32) callconv(.c) c_int {
            std.testing.expect(connection == 79 and length == capacity) catch @panic("text arguments");
            std.testing.expect(if (length == 0) buffer == null else buffer != null) catch @panic("text buffer pointer");
            if (bridge != 1) return bridge;
            native_result.* = result;
            if (length > 0) {
                const bytes = buffer[0..@intCast(length)];
                @memset(bytes, 'x');
                if (terminate) bytes[bytes.len - 1] = 0;
            }
            return 1;
        }
    };
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    const networking: Networking = .{ .lease = context.lease() };
    var buffer = [_]u8{ 'a', 'b', 'c', 'd', '!' };
    const connection: Connection = @fromBackingInt(@intCast(79));
    try std.testing.expectEqual(@as(usize, 4), (try networking.detailedStatusWith(connection, buffer[0..0], Fixture.query)).required_capacity);
    Fixture.capacity = 4;
    Fixture.result = 0;
    const complete = (try networking.detailedStatusWith(connection, buffer[0..4], Fixture.query)).complete;
    try std.testing.expectEqualStrings("xxx", complete);
    try std.testing.expect(complete.ptr == &buffer);
    try std.testing.expectEqual(@as(u8, '!'), buffer[4]);
    buffer[0] = 'b';
    try std.testing.expectEqual(@as(u8, 'b'), complete[0]); // Borrowed, not copied.
    Fixture.capacity = 2;
    Fixture.result = 4;
    try std.testing.expectEqual(@as(usize, 4), (try networking.detailedStatusWith(connection, buffer[0..2], Fixture.query)).required_capacity);
    try std.testing.expectEqualSlices(u8, "x\x00x\x00!", &buffer);
    Fixture.terminate = false;
    _ = try networking.detailedStatusWith(connection, buffer[0..2], Fixture.query);
    try std.testing.expectEqualStrings("xx", buffer[0..2]); // Short buffers need not terminate.
    Fixture.result = -1;
    try std.testing.expectEqual(DetailedStatusOutcome.failed, try networking.detailedStatusWith(connection, buffer[0..2], Fixture.query));
    for ([_]i32{ -2, -71, std.math.minInt(i32) }) |raw| {
        Fixture.result = raw;
        try std.testing.expectEqual(raw, (try networking.detailedStatusWith(connection, buffer[0..2], Fixture.query)).unexpected_result);
    }
    Fixture.result = std.math.maxInt(i32);
    try std.testing.expectEqual(@as(usize, std.math.maxInt(i32)), (try networking.detailedStatusWith(connection, buffer[0..2], Fixture.query)).required_capacity);
    Fixture.result = 0;
    // A terminator exists just past this slice: it must not be read.
    buffer[2] = 0;
    try std.testing.expectError(error.UnterminatedStatus, networking.detailedStatusWith(connection, buffer[0..2], Fixture.query));
    Fixture.capacity = 0;
    try std.testing.expectError(error.UnterminatedStatus, networking.detailedStatusWith(connection, buffer[0..0], Fixture.query));
    Fixture.capacity = 1;
    Fixture.terminate = true;
    try std.testing.expectEqualStrings("", (try networking.detailedStatusWith(connection, buffer[0..1], Fixture.query)).complete);
    Fixture.bridge = 0;
    try std.testing.expectError(error.Unavailable, networking.detailedStatusWith(connection, buffer[0..1], Fixture.query));
    Fixture.bridge = -1;
    try std.testing.expectError(error.BridgeFailed, networking.detailedStatusWith(connection, buffer[0..1], Fixture.query));
    try std.testing.expectEqual(@as(c_int, std.math.maxInt(c_int)), try detailedStatusCapacity(std.math.maxInt(c_int)));
    try std.testing.expectError(error.BufferTooLarge, detailedStatusCapacity(@as(usize, std.math.maxInt(c_int)) + 1));
    try std.testing.expectError(error.BufferTooLarge, detailedStatusCapacity(std.math.maxInt(usize)));
}

test "configureLanes validates before native and preserves full priorities weights and results" {
    const Fixture = struct {
        var calls: usize = 0;
        var bridge: c_int = 1;
        var result: i32 = 1;
        fn configure(connection: u32, lanes: [*c]const c.SwLaneConfig, count: c_int, out: [*c]i32) callconv(.c) c_int {
            std.testing.expectEqual(@as(u32, 0), connection) catch @panic("connection");
            for (0..@intCast(count)) |i| {
                std.testing.expectEqual(@as(i32, if (i % 2 == 0) std.math.minInt(i32) else std.math.maxInt(i32)), lanes[i].priority) catch @panic("priority");
                std.testing.expectEqual(@as(u16, if (i % 2 == 0) 1 else 65535), lanes[i].weight) catch @panic("weight");
            }
            calls += 1;
            out.* = result;
            return bridge;
        }
    };
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    const networking: Networking = .{ .lease = context.lease() };
    var lanes: [max_lanes + 1]LaneConfig = undefined;
    for (&lanes, 0..) |*lane, i| lane.* = .{ .priority = if (i % 2 == 0) std.math.minInt(i32) else std.math.maxInt(i32), .weight = if (i % 2 == 0) 1 else 65535 };
    for ([_]usize{ 1, max_lanes }) |count| {
        try std.testing.expectEqual(types.Result.ok, try networking.configureLanesWith(.invalid, lanes[0..count], Fixture.configure));
    }
    for ([_]i32{ 8, 3, 255, std.math.maxInt(i32), std.math.minInt(i32) }) |result| {
        Fixture.result = result;
        try std.testing.expectEqual(result, @backingInt(try networking.configureLanesWith(.invalid, lanes[0..1], Fixture.configure)));
    }
    Fixture.bridge = 0;
    try std.testing.expectError(error.Unavailable, networking.configureLanesWith(.invalid, lanes[0..1], Fixture.configure));
    Fixture.bridge = -1;
    try std.testing.expectError(error.BridgeFailed, networking.configureLanesWith(.invalid, lanes[0..1], Fixture.configure));
    const calls = Fixture.calls;
    try std.testing.expectError(error.InvalidLaneCount, networking.configureLanes(.invalid, &.{}));
    try std.testing.expectError(error.InvalidLaneCount, networking.configureLanes(.invalid, &lanes));
    lanes[max_lanes - 1].weight = 0;
    try std.testing.expectError(error.InvalidLaneWeight, networking.configureLanesWith(.invalid, lanes[0..max_lanes], Fixture.configure));
    try std.testing.expectEqual(calls, Fixture.calls);
}

test "sendBatch validates the whole batch and publishes only transferred outcomes" {
    const Fixture = struct {
        var calls: usize = 0;
        var bridge: c_int = 1;
        const raw = [_]i64{ 71, -8, 0, 73, -255, std.math.maxInt(i64), std.math.minInt(i64), -2147483648, -2147483647 };
        fn transfer(messages: [*c]const c.SwBatchSend, count: c_int, results: [*c]i64) callconv(.c) c_int {
            calls += 1;
            for (0..@intCast(count)) |i| {
                std.testing.expectEqual(@as(u32, @intCast(if (i % 9 == 1 or i % 9 == 2) 0 else i + 1)), messages[i].connection) catch @panic("connection");
                std.testing.expectEqual(@as(u16, if (i % 2 == 0) 254 else 0), messages[i].lane) catch @panic("lane");
                std.testing.expectEqual(@as(i32, if (i % 2 == 0) SendFlags.reliable | SendFlags.no_nagle else SendFlags.no_delay | SendFlags.use_current_thread), messages[i].flags) catch @panic("flags");
                const payload: []const u8 = if (i % 2 == 0) "copy me" else "";
                std.testing.expectEqualStrings(payload, messages[i].data[0..messages[i].size]) catch @panic("payload");
                results[i] = raw[i % raw.len]; // Even failed bridge output must stay private.
            }
            return bridge;
        }
    };
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    const networking: Networking = .{ .lease = context.lease() };
    var messages: [max_send_batch + 1]BatchSend = undefined;
    for (&messages, 0..) |*message, i| message.* = .{
        .connection = @fromBackingInt(@intCast(if (i % 9 == 1 or i % 9 == 2) 0 else i + 1)),
        .payload = if (i % 2 == 0) "copy me" else "",
        .lane = if (i % 2 == 0) 254 else 0,
        .options = if (i % 2 == 0) .{ .reliability = .reliable, .no_nagle = true } else .{ .no_delay = true, .use_current_thread = true },
    };
    const sentinel: BatchSendOutcome = .{ .unexpected_result = -987 };
    var outcomes: [max_send_batch + 1]BatchSendOutcome = @splat(sentinel);
    const empty = try networking.sendBatch(&.{}, &outcomes);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
    try std.testing.expect(empty.ptr == &outcomes);
    try std.testing.expectEqual(@as(usize, 0), Fixture.calls);
    for ([_]usize{ 1, max_send_batch }) |count| {
        const initialized = try networking.sendBatchWith(messages[0..count], &outcomes, Fixture.transfer);
        try std.testing.expect(initialized.ptr == &outcomes and initialized.len == count);
        for (initialized, 0..) |outcome, i| try std.testing.expectEqualDeep(BatchSendOutcome.fromNative(Fixture.raw[i % Fixture.raw.len]), outcome);
        try std.testing.expectEqualDeep(sentinel, outcomes[count]);
    }
    try std.testing.expectEqual(@as(i64, 71), outcomes[0].accepted);
    try std.testing.expectEqual(@as(i32, 8), @backingInt(outcomes[1].rejected));
    try std.testing.expectEqual(BatchSendOutcome.not_attempted, outcomes[2]);
    try std.testing.expectEqual(@as(i64, 73), outcomes[3].accepted);
    try std.testing.expectEqual(@as(i32, 255), @backingInt(outcomes[4].rejected));
    try std.testing.expectEqual(std.math.maxInt(i64), outcomes[5].accepted);
    try std.testing.expectEqual(std.math.minInt(i64), outcomes[6].unexpected_result);
    try std.testing.expectEqual(@as(i64, -2147483648), outcomes[7].unexpected_result);
    try std.testing.expectEqual(std.math.maxInt(i32), @backingInt(outcomes[8].rejected));
    const saved = outcomes;
    for ([_]c_int{ -2, 0, -1 }) |bridge| {
        Fixture.bridge = bridge;
        const expected = switch (bridge) {
            -2 => error.AllocationFailed,
            0 => error.Unavailable,
            else => error.BridgeFailed,
        };
        try std.testing.expectError(expected, networking.sendBatchWith(messages[0..max_send_batch], &outcomes, Fixture.transfer));
        try std.testing.expectEqualDeep(saved, outcomes);
    }
    const calls = Fixture.calls;
    try std.testing.expectError(error.TooManyMessages, networking.sendBatch(&messages, &outcomes));
    try std.testing.expectError(error.InsufficientOutcomes, networking.sendBatch(messages[0..max_send_batch], outcomes[0 .. max_send_batch - 1]));
    const last = &messages[max_send_batch - 1];
    const valid = last.*;
    last.lane = 255;
    try std.testing.expectError(error.InvalidLane, networking.sendBatchWith(messages[0..max_send_batch], &outcomes, Fixture.transfer));
    last.lane = 65535;
    try std.testing.expectError(error.InvalidLane, networking.sendBatch(messages[0..max_send_batch], &outcomes));
    last.* = valid;
    var large: [max_send_size + 1]u8 = undefined;
    last.payload = &large;
    try std.testing.expectError(error.TooLarge, networking.sendBatchWith(messages[0..max_send_batch], &outcomes, Fixture.transfer));
    last.* = valid;
    last.options = .{ .reliability = .reliable, .no_delay = true };
    try std.testing.expectError(error.InvalidSendOptions, networking.sendBatchWith(messages[0..max_send_batch], &outcomes, Fixture.transfer));
    try std.testing.expectEqual(calls, Fixture.calls);
    try std.testing.expectEqualDeep(saved, outcomes);
    try std.testing.expectEqual(@as(usize, 0), context.messages);
}

test "Metadata copies raw incoming lanes without changing received ownership" {
    const Fixture = struct {
        var releases: usize = 0;
        fn release(handle: [*c]?*c.SwMessage) callconv(.c) void {
            releases += 1;
            handle.* = null;
        }
    };
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    var token: u8 = 0;
    for ([_]u16{ 1, 254, 65535 }) |lane| {
        var view = std.mem.zeroes(c.SwMessageView);
        view.handle = @ptrCast(&token);
        view.lane = lane;
        view.channel = 17;
        view.number = 23;
        try Message.validate(view);
        var message = Message.adopt(context.lease(), view);
        defer message.releaseWith(Fixture.release);
        view.lane = 0;
        try std.testing.expectEqual(lane, message.metadata.lane);
        try std.testing.expectEqual(@as(i32, 17), message.metadata.channel);
        try std.testing.expectEqual(@as(i64, 23), message.metadata.number);
        try std.testing.expectEqual(@as(usize, 1), context.messages);
        message.releaseWith(Fixture.release);
        message.releaseWith(Fixture.release);
        try std.testing.expectEqual(@as(usize, 0), context.messages);
    }
    try std.testing.expectEqual(@as(usize, 3), Fixture.releases);
}
