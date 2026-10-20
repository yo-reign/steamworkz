#include "networking.h"
#include "steam/steam_api_flat.h"
#include <string.h>

static_assert(SW_NETWORKING_MAX_SEND_SIZE == k_cbMaxSteamNetworkingSocketsMessageSizeSend, "send size limit");
static_assert(SW_SEND_UNRELIABLE == k_nSteamNetworkingSend_Unreliable, "unreliable send flag");
static_assert(SW_SEND_NO_NAGLE == k_nSteamNetworkingSend_NoNagle, "no Nagle send flag");
static_assert(SW_SEND_NO_DELAY == k_nSteamNetworkingSend_NoDelay, "no delay send flag");
static_assert(SW_SEND_RELIABLE == k_nSteamNetworkingSend_Reliable, "reliable send flag");
static_assert(SW_SEND_USE_CURRENT_THREAD == k_nSteamNetworkingSend_UseCurrentThread, "current thread send flag");
static_assert(SW_ADDRESS_TEXT_SIZE >= SteamNetworkingIPAddr::k_cchMaxString, "address text capacity");
static_assert(sizeof(((SwConnectionInfo *)nullptr)->peer_identity) >= SteamNetworkingIdentity::k_cchMaxString, "identity text capacity");

#ifdef SW_NETWORKING_TEST
static ISteamNetworkingSockets *fixture_sockets();
static EResult fixture_real_time_status(ISteamNetworkingSockets *, HSteamNetConnection,
    SteamNetConnectionRealTimeStatus_t *, int, SteamNetConnectionRealTimeLaneStatus_t *);
static int fixture_detailed_status(ISteamNetworkingSockets *, HSteamNetConnection, char *, int);
static_assert(__is_same(decltype(&fixture_sockets), decltype(&SteamAPI_SteamNetworkingSockets_SteamAPI_v013)), "sockets signature");
static_assert(__is_same(decltype(&fixture_real_time_status), decltype(&SteamAPI_ISteamNetworkingSockets_GetConnectionRealTimeStatus)), "real-time signature");
static_assert(__is_same(decltype(&fixture_detailed_status), decltype(&SteamAPI_ISteamNetworkingSockets_GetDetailedConnectionStatus)), "detailed signature");
static ISteamNetworkingUtils *fixture_utils();
static SteamNetworkingMessage_t *fixture_allocate(ISteamNetworkingUtils *, int);
static void fixture_send_messages(ISteamNetworkingSockets *, int, SteamNetworkingMessage_t **, int64 *, bool);
static EResult fixture_configure_lanes(ISteamNetworkingSockets *, HSteamNetConnection, int, const int *, const uint16 *);
static_assert(__is_same(decltype(&fixture_utils), decltype(&SteamAPI_SteamNetworkingUtils_SteamAPI_v004)), "utils signature");
static_assert(__is_same(decltype(&fixture_allocate), decltype(&SteamAPI_ISteamNetworkingUtils_AllocateMessage)), "allocate signature");
static_assert(__is_same(decltype(&fixture_send_messages), decltype(&SteamAPI_ISteamNetworkingSockets_SendMessages)), "batch signature");
static_assert(__is_same(decltype(&fixture_configure_lanes), decltype(&SteamAPI_ISteamNetworkingSockets_ConfigureConnectionLanes)), "lanes signature");
#define SteamAPI_SteamNetworkingUtils_SteamAPI_v004 fixture_utils
#define SteamAPI_ISteamNetworkingUtils_AllocateMessage fixture_allocate
#define SteamAPI_ISteamNetworkingSockets_SendMessages fixture_send_messages
#define SteamAPI_ISteamNetworkingSockets_ConfigureConnectionLanes fixture_configure_lanes
#define SteamAPI_SteamNetworkingSockets_SteamAPI_v013 fixture_sockets
#define SteamAPI_ISteamNetworkingSockets_GetConnectionRealTimeStatus fixture_real_time_status
#define SteamAPI_ISteamNetworkingSockets_GetDetailedConnectionStatus fixture_detailed_status
#endif

static SteamNetworkingIPAddr native_address(const SwAddress &address) {
    SteamNetworkingIPAddr result;
    result.SetIPv6(address.ipv6, address.port);
    return result;
}
static void copy_address(const SteamNetworkingIPAddr &address, SwAddress *out) {
    memcpy(out->ipv6, address.m_ipv6, sizeof(out->ipv6));
    out->port = address.m_port;
}
static void copy_info(uint32_t connection, const SteamNetConnectionInfo_t &info, SwConnectionInfo *out) {
    memset(out, 0, sizeof(*out));
    out->connection = connection;
    out->listen_socket = info.m_hListenSocket;
    out->peer_steam_id = info.m_identityRemote.GetSteamID64();
    out->state = info.m_eState;
    out->end_reason = info.m_eEndReason;
    static_assert(sizeof(out->end_debug) == sizeof(info.m_szEndDebug), "close reason size");
    memcpy(out->end_debug, info.m_szEndDebug, sizeof(out->end_debug));
}
static bool copy_message(SteamNetworkingMessage_t *message, SwMessageView *out) {
    if (!message || message->m_cbSize < 0 || (message->m_cbSize && !message->m_pData)) return false;
    *out = {};
    out->handle = reinterpret_cast<SwMessage *>(message);
    out->data = static_cast<const uint8_t *>(message->m_pData);
    out->size = message->m_cbSize;
    out->connection = message->m_conn;
    out->peer_steam_id = message->m_identityPeer.GetSteamID64();
    out->number = message->m_nMessageNumber;
    out->received_at = message->m_usecTimeReceived;
    out->channel = message->m_nChannel;
    out->lane = message->m_idxLane;
    return true;
}
/* The fixed array also lets us reclaim everything if the native count or a
 * message is malformed. Only a completely validated batch transfers ownership. */
static int finish_receive(SteamNetworkingMessage_t **messages, int count, int capacity, SwMessageView *out) {
    bool valid = count >= 0 && count <= capacity;
    if (valid) {
        for (int i = 0; i < count; ++i) {
            if (!copy_message(messages[i], &out[i])) { valid = false; break; }
        }
    }
    if (valid) return count;
    for (int i = 0; i < capacity; ++i) {
        if (messages[i]) messages[i]->Release();
        out[i] = {};
    }
    return -1;
}

int sw_networking_parse_address(const char *text, SwAddress *out) {
    auto *utils = SteamAPI_SteamNetworkingUtils_SteamAPI_v004();
    if (!utils) return -1;
    SteamNetworkingIPAddr address;
    if (!SteamAPI_ISteamNetworkingUtils_SteamNetworkingIPAddr_ParseString(utils, &address, text)) return 0;
    copy_address(address, out);
    return 1;
}
int sw_networking_format_address(const SwAddress *address, char *out, int capacity, int with_port) {
    if (capacity < SW_ADDRESS_TEXT_SIZE) return 0;
    auto *utils = SteamAPI_SteamNetworkingUtils_SteamAPI_v004();
    if (!utils) return 0;
    const auto native = native_address(*address);
    SteamAPI_ISteamNetworkingUtils_SteamNetworkingIPAddr_ToString(utils, native, out, static_cast<uint32_t>(capacity), with_port != 0);
    return 1;
}
uint32_t sw_networking_listen_ip(const SwAddress *address) {
    auto *sockets = SteamAPI_SteamNetworkingSockets_SteamAPI_v013();
    if (!sockets) return 0;
    const auto native = native_address(*address);
    return SteamAPI_ISteamNetworkingSockets_CreateListenSocketIP(sockets, native, 0, nullptr);
}
uint32_t sw_networking_connect_ip(const SwAddress *address) {
    auto *sockets = SteamAPI_SteamNetworkingSockets_SteamAPI_v013();
    if (!sockets) return 0;
    const auto native = native_address(*address);
    return SteamAPI_ISteamNetworkingSockets_ConnectByIPAddress(sockets, native, 0, nullptr);
}
uint32_t sw_networking_listen_p2p(int virtual_port) {
    auto *sockets = SteamAPI_SteamNetworkingSockets_SteamAPI_v013();
    return sockets ? SteamAPI_ISteamNetworkingSockets_CreateListenSocketP2P(sockets, virtual_port, 0, nullptr) : 0;
}
uint32_t sw_networking_connect_p2p(uint64_t steam_id, int virtual_port) {
    auto *sockets = SteamAPI_SteamNetworkingSockets_SteamAPI_v013();
    if (!sockets) return 0;
    SteamNetworkingIdentity identity;
    identity.SetSteamID64(steam_id);
    return SteamAPI_ISteamNetworkingSockets_ConnectP2P(sockets, identity, virtual_port, 0, nullptr);
}
int32_t sw_networking_accept(uint32_t connection) {
    auto *sockets = SteamAPI_SteamNetworkingSockets_SteamAPI_v013();
    return sockets ? SteamAPI_ISteamNetworkingSockets_AcceptConnection(sockets, connection) : k_EResultNoConnection;
}
int sw_networking_close(uint32_t connection, int reason, const char *debug, int linger) {
    auto *sockets = SteamAPI_SteamNetworkingSockets_SteamAPI_v013();
    return sockets && SteamAPI_ISteamNetworkingSockets_CloseConnection(sockets, connection, reason, debug, linger != 0);
}
int sw_networking_close_listen(uint32_t socket) {
    auto *sockets = SteamAPI_SteamNetworkingSockets_SteamAPI_v013();
    return sockets && SteamAPI_ISteamNetworkingSockets_CloseListenSocket(sockets, socket);
}
int sw_networking_socket_pair(uint32_t *first, uint32_t *second, int network_loopback) {
    *first = *second = 0;
    auto *sockets = SteamAPI_SteamNetworkingSockets_SteamAPI_v013();
    return sockets && SteamAPI_ISteamNetworkingSockets_CreateSocketPair(sockets, first, second, network_loopback != 0, nullptr, nullptr);
}
int32_t sw_networking_send(uint32_t connection, const uint8_t *data, uint32_t size, int flags, int64_t *number) {
    *number = -1;
    auto *sockets = SteamAPI_SteamNetworkingSockets_SteamAPI_v013();
    if (!sockets) return k_EResultNoConnection;
    int64 native_number = -1;
    const EResult result = SteamAPI_ISteamNetworkingSockets_SendMessageToConnection(sockets, connection, data, size, flags, &native_number);
    *number = static_cast<int64_t>(native_number);
    return result;
}
int sw_networking_configure_lanes(uint32_t connection, const SwLaneConfig *lanes, int count, int32_t *native_result) {
    if (!lanes || !native_result || count < 1 || count > SW_NETWORKING_MAX_LANES) return -1;
    int priorities[SW_NETWORKING_MAX_LANES];
    uint16 weights[SW_NETWORKING_MAX_LANES];
    for (int i = 0; i < count; ++i) {
        if (!lanes[i].weight) return -1;
        priorities[i] = lanes[i].priority;
        weights[i] = lanes[i].weight;
    }
    auto *sockets = SteamAPI_SteamNetworkingSockets_SteamAPI_v013();
    if (!sockets) return 0;
    *native_result = SteamAPI_ISteamNetworkingSockets_ConfigureConnectionLanes(sockets, connection, count, priorities, weights);
    return 1;
}
int sw_networking_send_batch(const SwBatchSend *messages, int count, int64_t *results) {
    if (count < 0 || count > SW_NETWORKING_MAX_SEND_BATCH || (count && (!messages || !results))) return -1;
    if (!count) return 1;
    const int allowed_flags = SW_SEND_NO_NAGLE | SW_SEND_NO_DELAY | SW_SEND_RELIABLE | SW_SEND_USE_CURRENT_THREAD;
    for (int i = 0; i < count; ++i) {
        const auto &entry = messages[i];
        if (entry.size > SW_NETWORKING_MAX_SEND_SIZE || (entry.size && !entry.data) || entry.lane >= SW_NETWORKING_MAX_LANES ||
            (entry.flags & ~allowed_flags) || ((entry.flags & SW_SEND_RELIABLE) && (entry.flags & SW_SEND_NO_DELAY))) return -1;
    }
    auto *sockets = SteamAPI_SteamNetworkingSockets_SteamAPI_v013();
    auto *utils = SteamAPI_SteamNetworkingUtils_SteamAPI_v004();
    if (!sockets || !utils) return 0;
    SteamNetworkingMessage_t *owned[SW_NETWORKING_MAX_SEND_BATCH];
    for (int i = 0; i < count; ++i) {
        const auto &entry = messages[i];
        // Empty messages still use SDK-owned storage/callbacks: allocate one byte,
        // but transmit zero. Never invent a free callback for AllocateMessage(0).
        auto *message = SteamAPI_ISteamNetworkingUtils_AllocateMessage(utils, entry.size ? static_cast<int>(entry.size) : 1);
        if (!message) {
            for (int j = 0; j < i; ++j) owned[j]->Release();
            return -2;
        }
        owned[i] = message;
        if (entry.size) memcpy(message->m_pData, entry.data, entry.size);
        message->m_cbSize = static_cast<int>(entry.size);
        message->m_conn = entry.connection;
        message->m_nFlags = entry.flags;
        message->m_idxLane = entry.lane;
    }
    int64 native_results[SW_NETWORKING_MAX_SEND_BATCH];
    SteamAPI_ISteamNetworkingSockets_SendMessages(sockets, count, owned, native_results, true);
    // All pointers transferred, including rejected/skipped entries. Do not touch them.
    for (int i = 0; i < count; ++i) results[i] = native_results[i];
    return 1;
}
int32_t sw_networking_flush(uint32_t connection) {
    auto *sockets = SteamAPI_SteamNetworkingSockets_SteamAPI_v013();
    return sockets ? SteamAPI_ISteamNetworkingSockets_FlushMessagesOnConnection(sockets, connection) : k_EResultNoConnection;
}
int sw_networking_receive(uint32_t handle, int poll_group, SwMessageView *out, int capacity) {
    if (capacity < 0 || capacity > SW_NETWORKING_MAX_RECEIVE || (capacity && !out)) return -1;
    if (!capacity) return 0;
    memset(out, 0, sizeof(*out) * static_cast<size_t>(capacity));
    auto *sockets = SteamAPI_SteamNetworkingSockets_SteamAPI_v013();
    if (!sockets) return -1;
    SteamNetworkingMessage_t *messages[SW_NETWORKING_MAX_RECEIVE] = {};
    const int count = poll_group
        ? SteamAPI_ISteamNetworkingSockets_ReceiveMessagesOnPollGroup(sockets, handle, messages, capacity)
        : SteamAPI_ISteamNetworkingSockets_ReceiveMessagesOnConnection(sockets, handle, messages, capacity);
    return finish_receive(messages, count, capacity, out);
}
void sw_networking_release_message(SwMessage **handle) {
    if (!*handle) return;
    // SDK inline Release invokes the native message's release callback, not a vtable.
    reinterpret_cast<SteamNetworkingMessage_t *>(*handle)->Release();
    *handle = nullptr;
}
int sw_networking_connection_info(uint32_t connection, SwConnectionInfo *out) {
    auto *sockets = SteamAPI_SteamNetworkingSockets_SteamAPI_v013();
    SteamNetConnectionInfo_t info = {};
    if (!sockets || !SteamAPI_ISteamNetworkingSockets_GetConnectionInfo(sockets, connection, &info)) return 0;
    auto *utils = SteamAPI_SteamNetworkingUtils_SteamAPI_v004();
    if (!utils) return 0;
    copy_info(connection, info, out);
    SteamAPI_ISteamNetworkingUtils_SteamNetworkingIdentity_ToString(utils, info.m_identityRemote, out->peer_identity, sizeof(out->peer_identity));
    return 1;
}
int sw_networking_real_time_status(uint32_t connection, SwConnectionRealTimeStatus *out,
    SwLaneRealTimeStatus *lanes, int lane_count, int32_t *native_result) {
    if (!out || !native_result || lane_count < 0 || lane_count > SW_NETWORKING_MAX_LANES || (lane_count && !lanes)) return -1;
    auto *sockets = SteamAPI_SteamNetworkingSockets_SteamAPI_v013();
    if (!sockets) return 0;
    SteamNetConnectionRealTimeStatus_t status = {};
    SteamNetConnectionRealTimeLaneStatus_t native_lanes[SW_NETWORKING_MAX_LANES] = {};
    const EResult result = SteamAPI_ISteamNetworkingSockets_GetConnectionRealTimeStatus(
        sockets, connection, &status, lane_count, lane_count ? native_lanes : nullptr);
    *native_result = result;
    if (result != k_EResultOK) return 1;
    out->state = status.m_eState;
    out->ping_ms = status.m_nPing;
    out->connection_quality_local = status.m_flConnectionQualityLocal;
    out->connection_quality_remote = status.m_flConnectionQualityRemote;
    out->out_packets_per_second = status.m_flOutPacketsPerSec;
    out->out_bytes_per_second = status.m_flOutBytesPerSec;
    out->in_packets_per_second = status.m_flInPacketsPerSec;
    out->in_bytes_per_second = status.m_flInBytesPerSec;
    out->send_rate_bytes_per_second = status.m_nSendRateBytesPerSecond;
    out->pending_unreliable = status.m_cbPendingUnreliable;
    out->pending_reliable = status.m_cbPendingReliable;
    out->sent_unacked_reliable = status.m_cbSentUnackedReliable;
    out->queue_time_us = status.m_usecQueueTime;
    out->max_jitter_us = status.m_usecMaxJitter;
    for (int i = 0; i < lane_count; ++i) {
        lanes[i].pending_unreliable = native_lanes[i].m_cbPendingUnreliable;
        lanes[i].pending_reliable = native_lanes[i].m_cbPendingReliable;
        lanes[i].sent_unacked_reliable = native_lanes[i].m_cbSentUnackedReliable;
        lanes[i].queue_time_us = native_lanes[i].m_usecQueueTime;
    }
    return 1;
}
int sw_networking_detailed_status(uint32_t connection, char *buffer, int capacity, int32_t *native_result) {
    if (!native_result || capacity < 0 || (capacity && !buffer)) return -1;
    auto *sockets = SteamAPI_SteamNetworkingSockets_SteamAPI_v013();
    if (!sockets) return 0;
    *native_result = SteamAPI_ISteamNetworkingSockets_GetDetailedConnectionStatus(sockets, connection, capacity ? buffer : nullptr, capacity);
    return 1;
}
int sw_networking_listen_address(uint32_t socket, SwAddress *out) {
    auto *sockets = SteamAPI_SteamNetworkingSockets_SteamAPI_v013();
    SteamNetworkingIPAddr address;
    if (!sockets || !SteamAPI_ISteamNetworkingSockets_GetListenSocketAddress(sockets, socket, &address)) return 0;
    copy_address(address, out);
    return 1;
}
uint32_t sw_networking_create_poll_group(void) {
    auto *sockets = SteamAPI_SteamNetworkingSockets_SteamAPI_v013();
    return sockets ? SteamAPI_ISteamNetworkingSockets_CreatePollGroup(sockets) : 0;
}
int sw_networking_destroy_poll_group(uint32_t group) {
    auto *sockets = SteamAPI_SteamNetworkingSockets_SteamAPI_v013();
    return sockets && SteamAPI_ISteamNetworkingSockets_DestroyPollGroup(sockets, group);
}
int sw_networking_set_poll_group(uint32_t connection, uint32_t group) {
    auto *sockets = SteamAPI_SteamNetworkingSockets_SteamAPI_v013();
    return sockets && SteamAPI_ISteamNetworkingSockets_SetConnectionPollGroup(sockets, connection, group);
}
int sw_networking_init_relay(void) {
    auto *utils = SteamAPI_SteamNetworkingUtils_SteamAPI_v004();
    if (!utils) return 0;
    SteamAPI_ISteamNetworkingUtils_InitRelayNetworkAccess(utils);
    return 1;
}
int sw_networking_relay_status(SwRelayStatus *out) {
    auto *utils = SteamAPI_SteamNetworkingUtils_SteamAPI_v004();
    if (!utils) return 0;
    SteamRelayNetworkStatus_t status = {};
    out->availability = SteamAPI_ISteamNetworkingUtils_GetRelayNetworkStatus(utils, &status);
    out->ping_measurement_in_progress = status.m_bPingMeasurementInProgress;
    out->network_config = status.m_eAvailNetworkConfig;
    out->any_relay = status.m_eAvailAnyRelay;
    static_assert(sizeof(out->debug) == sizeof(status.m_debugMsg), "relay debug size");
    memcpy(out->debug, status.m_debugMsg, sizeof(out->debug));
    return 1;
}

#ifdef SW_NETWORKING_TEST
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
struct MessageFixture : SteamNetworkingMessage_t {
    MessageFixture() : SteamNetworkingMessage_t{} {}
};
static int released_messages;
static void release_fixture(SteamNetworkingMessage_t *) { ++released_messages; }

// Opaque interface token is compared only, never dereferenced as an SDK object.
static char sockets_token;
static bool sockets_available = true;
static int status_calls, socket_accessors, expected_lanes, text_capacity;
static EResult status_result = k_EResultOK;
static int text_result;
static bool terminate_text;
static char *text_buffer;
static SteamNetConnectionRealTimeStatus_t status_fixture = {};
static SteamNetConnectionRealTimeLaneStatus_t lane_fixtures[SW_NETWORKING_MAX_LANES] = {};
static ISteamNetworkingSockets *fixture_sockets() {
    ++socket_accessors;
    return sockets_available ? reinterpret_cast<ISteamNetworkingSockets *>(&sockets_token) : nullptr;
}
static EResult fixture_real_time_status(ISteamNetworkingSockets *self, HSteamNetConnection connection,
    SteamNetConnectionRealTimeStatus_t *status, int count, SteamNetConnectionRealTimeLaneStatus_t *lanes) {
    assert(self == reinterpret_cast<ISteamNetworkingSockets *>(&sockets_token) && connection == 79);
    assert(count == expected_lanes && (count == 0 ? lanes == nullptr : lanes != nullptr));
    ++status_calls;
    *status = status_fixture; // Deliberately write even when returning failure.
    for (int i = 0; i < count; ++i) lanes[i] = lane_fixtures[i];
    return status_result;
}
static int fixture_detailed_status(ISteamNetworkingSockets *self, HSteamNetConnection connection, char *buffer, int capacity) {
    assert(self == reinterpret_cast<ISteamNetworkingSockets *>(&sockets_token) && connection == 79);
    assert(buffer == text_buffer && capacity == text_capacity);
    ++status_calls;
    if (capacity) {
        memset(buffer, 'x', static_cast<size_t>(capacity));
        if (terminate_text) buffer[capacity - 1] = 0;
    }
    return text_result;
}
static char utils_token;
static bool utils_available = true;
static int utils_accessors, allocation_calls, transfer_calls, configure_calls;
static int fail_allocation = -1;
static int allocation_sizes[SW_NETWORKING_MAX_SEND_BATCH];
static int outbound_releases[SW_NETWORKING_MAX_SEND_BATCH];
static MessageFixture outbound_messages[SW_NETWORKING_MAX_SEND_BATCH];
static uint8_t outbound_payloads[SW_NETWORKING_MAX_SEND_BATCH][SW_NETWORKING_MAX_SEND_SIZE];
static const SwBatchSend *expected_batch;
static int expected_batch_count;
static const SwLaneConfig *expected_config;
static int expected_config_count;
static EResult configure_result = k_EResultOK;
static int64 batch_results[SW_NETWORKING_MAX_SEND_BATCH];
static ISteamNetworkingUtils *fixture_utils() {
    ++utils_accessors;
    return utils_available ? reinterpret_cast<ISteamNetworkingUtils *>(&utils_token) : nullptr;
}
static void free_outbound_data(SteamNetworkingMessage_t *) {} // Static fixture storage only.
static void release_outbound(SteamNetworkingMessage_t *message) {
    for (int i = 0; i < SW_NETWORKING_MAX_SEND_BATCH; ++i) {
        if (message != &outbound_messages[i]) continue;
        assert(++outbound_releases[i] == 1);
        assert(message->m_pfnFreeData == free_outbound_data);
        message->m_pfnFreeData(message);
        // Poison released fields. Production must never revisit transferred owners.
        message->m_pData = nullptr;
        message->m_cbSize = -1;
        return;
    }
    assert(false);
}
static SteamNetworkingMessage_t *fixture_allocate(ISteamNetworkingUtils *self, int size) {
    assert(self == reinterpret_cast<ISteamNetworkingUtils *>(&utils_token));
    const int index = allocation_calls++;
    assert(index < expected_batch_count && size > 0 && size <= SW_NETWORKING_MAX_SEND_SIZE);
    assert(size == (expected_batch[index].size ? static_cast<int>(expected_batch[index].size) : 1));
    allocation_sizes[index] = size;
    if (index == fail_allocation) return nullptr;
    auto &message = outbound_messages[index];
    message = MessageFixture{};
    message.m_pData = outbound_payloads[index];
    message.m_cbSize = size;
    message.m_pfnFreeData = free_outbound_data;
    message.m_pfnRelease = release_outbound;
    memset(message.m_pData, 0xa5, static_cast<size_t>(size));
    return &message;
}
static void fixture_send_messages(ISteamNetworkingSockets *self, int count, SteamNetworkingMessage_t **messages, int64 *results, bool delete_failed) {
    assert(self == reinterpret_cast<ISteamNetworkingSockets *>(&sockets_token));
    assert(delete_failed && count == expected_batch_count && ++transfer_calls == 1);
    for (int i = 0; i < count; ++i) {
        const auto &entry = expected_batch[i];
        const auto *message = messages[i];
        assert(message == &outbound_messages[i]);
        assert(message->m_pData == outbound_payloads[i] && message->m_pData != entry.data);
        assert(message->m_cbSize == static_cast<int>(entry.size));
        assert(message->m_conn == entry.connection && message->m_idxLane == entry.lane && message->m_nFlags == entry.flags);
        assert(message->m_pfnFreeData == free_outbound_data && message->m_pfnRelease == release_outbound);
        assert(message->m_nChannel == 0 && message->m_nMessageNumber == 0 && message->m_nUserData == 0);
        assert(message->m_nConnUserData == 0 && message->m_usecTimeReceived == 0 && message->m_identityPeer.IsInvalid());
        if (entry.size) assert(memcmp(message->m_pData, entry.data, entry.size) == 0);
        else assert(allocation_sizes[i] == 1 && outbound_payloads[i][0] == 0xa5);
        results[i] = batch_results[i];
        messages[i]->Release(); // Native may release every owner before returning.
    }
}
static EResult fixture_configure_lanes(ISteamNetworkingSockets *self, HSteamNetConnection connection, int count, const int *priorities, const uint16 *weights) {
    assert(self == reinterpret_cast<ISteamNetworkingSockets *>(&sockets_token) && connection == 0);
    assert(count == expected_config_count);
    ++configure_calls;
    for (int i = 0; i < count; ++i) {
        assert(priorities[i] == expected_config[i].priority && weights[i] == expected_config[i].weight);
    }
    return configure_result;
}
static void test_configure_lanes() {
    SwLaneConfig lanes[SW_NETWORKING_MAX_LANES + 1];
    for (int i = 0; i <= SW_NETWORKING_MAX_LANES; ++i) lanes[i] = {i % 2 ? INT32_MIN : INT32_MAX, static_cast<uint16_t>(i % 2 ? 1 : UINT16_MAX)};
    expected_config = lanes;
    int32_t result = -987;
    const int counts[] = {1, SW_NETWORKING_MAX_LANES};
    for (int count : counts) {
        expected_config_count = count;
        assert(sw_networking_configure_lanes(0, lanes, count, &result) == 1 && result == k_EResultOK);
    }
    expected_config_count = 1;
    const EResult rejections[] = {k_EResultInvalidParam, k_EResultNoConnection, static_cast<EResult>(255)};
    for (auto rejection : rejections) {
        configure_result = rejection;
        assert(sw_networking_configure_lanes(0, lanes, 1, &result) == 1 && result == rejection);
    }
    const int accessors = socket_accessors, calls = configure_calls;
    assert(sw_networking_configure_lanes(0, lanes, 0, &result) == -1);
    assert(sw_networking_configure_lanes(0, lanes, SW_NETWORKING_MAX_LANES + 1, &result) == -1);
    lanes[SW_NETWORKING_MAX_LANES - 1].weight = 0;
    assert(sw_networking_configure_lanes(0, lanes, SW_NETWORKING_MAX_LANES, &result) == -1);
    assert(socket_accessors == accessors && configure_calls == calls);
    sockets_available = false;
    result = -987;
    assert(sw_networking_configure_lanes(0, lanes, 1, &result) == 0 && result == -987);
    sockets_available = true;
}
static void reset_batch_fixture(const SwBatchSend *batch, int count) {
    expected_batch = batch;
    expected_batch_count = count;
    allocation_calls = transfer_calls = 0;
    fail_allocation = -1;
    memset(outbound_releases, 0, sizeof(outbound_releases));
}
static void test_send_batch() {
    static uint8_t payload[SW_NETWORKING_MAX_SEND_SIZE];
    for (unsigned i = 0; i < sizeof(payload); ++i) payload[i] = static_cast<uint8_t>(i * 17);
    SwBatchSend batch[SW_NETWORKING_MAX_SEND_BATCH + 1] = {};
    int64_t results[SW_NETWORKING_MAX_SEND_BATCH + 1];
    const int64 mixed[] = {71, -k_EResultInvalidState, 0, 73, -255, INT64_MAX, INT64_MIN, -INT64_C(2147483648), -INT64_C(2147483647)};
    for (int i = 0; i <= SW_NETWORKING_MAX_SEND_BATCH; ++i) {
        batch[i] = {static_cast<uint32_t>(i % 9 == 1 || i % 9 == 2 ? 0 : i + 1), payload, i % 2 ? 0u : static_cast<uint32_t>(sizeof(payload)), static_cast<uint16_t>(i % 2 ? 0 : 254),
            i % 2 ? SW_SEND_NO_DELAY | SW_SEND_USE_CURRENT_THREAD : SW_SEND_RELIABLE | SW_SEND_NO_NAGLE};
        results[i] = -987;
        if (i < SW_NETWORKING_MAX_SEND_BATCH) batch_results[i] = mixed[i % (sizeof(mixed) / sizeof(mixed[0]))];
    }
    reset_batch_fixture(batch, 0);
    const int accessors = socket_accessors, utilities = utils_accessors;
    assert(sw_networking_send_batch(nullptr, 0, nullptr) == 1);
    assert(socket_accessors == accessors && utils_accessors == utilities && allocation_calls == 0 && transfer_calls == 0);
    const int counts[] = {1, SW_NETWORKING_MAX_SEND_BATCH};
    for (int count : counts) {
        reset_batch_fixture(batch, count);
        assert(sw_networking_send_batch(batch, count, results) == 1);
        assert(allocation_calls == count && transfer_calls == 1);
        for (int i = 0; i < count; ++i) assert(results[i] == batch_results[i] && outbound_releases[i] == 1);
    }
    for (auto &result : results) result = -987;
    for (int failure = 0; failure < SW_NETWORKING_MAX_SEND_BATCH; ++failure) {
        reset_batch_fixture(batch, SW_NETWORKING_MAX_SEND_BATCH);
        fail_allocation = failure;
        assert(sw_networking_send_batch(batch, SW_NETWORKING_MAX_SEND_BATCH, results) == -2);
        assert(allocation_calls == failure + 1 && transfer_calls == 0);
        for (int i = 0; i < SW_NETWORKING_MAX_SEND_BATCH; ++i) assert(outbound_releases[i] == (i < failure ? 1 : 0));
        for (auto result : results) assert(result == -987);
    }
    reset_batch_fixture(batch, SW_NETWORKING_MAX_SEND_BATCH);
    const int before_sockets = socket_accessors, before_utils = utils_accessors;
    assert(sw_networking_send_batch(batch, SW_NETWORKING_MAX_SEND_BATCH + 1, results) == -1);
    auto &last = batch[SW_NETWORKING_MAX_SEND_BATCH - 1];
    const auto saved = last;
    last.lane = 255;
    assert(sw_networking_send_batch(batch, SW_NETWORKING_MAX_SEND_BATCH, results) == -1);
    last = saved; last.size = SW_NETWORKING_MAX_SEND_SIZE + 1;
    assert(sw_networking_send_batch(batch, SW_NETWORKING_MAX_SEND_BATCH, results) == -1);
    last = saved; last.flags = SW_SEND_RELIABLE | SW_SEND_NO_DELAY;
    assert(sw_networking_send_batch(batch, SW_NETWORKING_MAX_SEND_BATCH, results) == -1);
    last = saved; last.flags = 2;
    assert(sw_networking_send_batch(batch, SW_NETWORKING_MAX_SEND_BATCH, results) == -1);
    last = saved;
    assert(socket_accessors == before_sockets && utils_accessors == before_utils);
    sockets_available = false;
    assert(sw_networking_send_batch(batch, SW_NETWORKING_MAX_SEND_BATCH, results) == 0);
    sockets_available = true; utils_available = false;
    assert(sw_networking_send_batch(batch, SW_NETWORKING_MAX_SEND_BATCH, results) == 0);
    utils_available = true;
    assert(allocation_calls == 0 && transfer_calls == 0);
    for (auto result : results) assert(result == -987);
}
static float float_from_bits(uint32_t bits) {
    float value;
    static_assert(sizeof(value) == sizeof(bits), "float width");
    memcpy(&value, &bits, sizeof(value));
    return value;
}
static uint32_t float_bits(float value) {
    uint32_t bits;
    memcpy(&bits, &value, sizeof(bits));
    return bits;
}
static void test_real_time_status() {
    status_fixture.m_eState = static_cast<ESteamNetworkingConnectionState>(12345);
    status_fixture.m_nPing = -11;
    status_fixture.m_flConnectionQualityLocal = float_from_bits(0x80000000); // -0
    status_fixture.m_flConnectionQualityRemote = float_from_bits(0x7fc12345); // NaN payload
    status_fixture.m_flOutPacketsPerSec = float_from_bits(0x7f800000);
    status_fixture.m_flOutBytesPerSec = float_from_bits(0xff800000);
    status_fixture.m_flInPacketsPerSec = float_from_bits(0x00000001); // subnormal
    status_fixture.m_flInBytesPerSec = -29.5f;
    status_fixture.m_nSendRateBytesPerSecond = -31;
    status_fixture.m_cbPendingUnreliable = -41;
    status_fixture.m_cbPendingReliable = 43;
    status_fixture.m_cbSentUnackedReliable = -47;
    status_fixture.m_usecQueueTime = INT64_MIN + 53;
    status_fixture.m_usecMaxJitter = -59;
    for (int i = 0; i < SW_NETWORKING_MAX_LANES; ++i) {
        lane_fixtures[i].m_cbPendingUnreliable = -100 - i;
        lane_fixtures[i].m_cbPendingReliable = 200 + i;
        lane_fixtures[i].m_cbSentUnackedReliable = -300 - i;
        lane_fixtures[i].m_usecQueueTime = INT64_MAX - i;
    }
    SwConnectionRealTimeStatus out = {};
    SwLaneRealTimeStatus lanes[SW_NETWORKING_MAX_LANES + 1] = {};
    int32_t result = -987;
    const int counts[] = {0, 1, 3, SW_NETWORKING_MAX_LANES};
    for (int count : counts) {
        expected_lanes = count;
        assert(sw_networking_real_time_status(79, &out, count ? lanes : nullptr, count, &result) == 1);
        assert(result == k_EResultOK);
        assert(out.state == 12345 && out.ping_ms == -11);
        assert(float_bits(out.connection_quality_local) == 0x80000000);
        assert(float_bits(out.connection_quality_remote) == 0x7fc12345);
        assert(float_bits(out.out_packets_per_second) == 0x7f800000);
        assert(float_bits(out.out_bytes_per_second) == 0xff800000);
        assert(float_bits(out.in_packets_per_second) == 1);
        assert(out.in_bytes_per_second == -29.5f);
        assert(out.send_rate_bytes_per_second == -31);
        assert(out.pending_unreliable == -41 && out.pending_reliable == 43 && out.sent_unacked_reliable == -47);
        assert(out.queue_time_us == INT64_MIN + 53 && out.max_jitter_us == -59);
        for (int i = 0; i < count; ++i) {
            assert(lanes[i].pending_unreliable == -100 - i && lanes[i].pending_reliable == 200 + i);
            assert(lanes[i].sent_unacked_reliable == -300 - i && lanes[i].queue_time_us == INT64_MAX - i);
        }
        assert(lanes[count].pending_reliable == 0); // Unrequested suffix is untouched.
    }
    unsigned char saved_out[sizeof(out)], saved_lanes[sizeof(lanes)];
    memcpy(saved_out, &out, sizeof(out));
    memcpy(saved_lanes, lanes, sizeof(lanes));
    // 255 is unnamed in SDK 1.65 but within EResult's representable range.
    const EResult rejections[] = {k_EResultNoConnection, k_EResultInvalidParam, static_cast<EResult>(255)};
    for (EResult rejected : rejections) {
        status_result = rejected;
        expected_lanes = 3;
        assert(sw_networking_real_time_status(79, &out, lanes, 3, &result) == 1 && result == rejected);
        assert(memcmp(saved_out, &out, sizeof(out)) == 0 && memcmp(saved_lanes, lanes, sizeof(lanes)) == 0);
    }
    const int calls = status_calls, accessors = socket_accessors;
    assert(sw_networking_real_time_status(79, &out, lanes, -1, &result) == -1);
    assert(sw_networking_real_time_status(79, &out, lanes, SW_NETWORKING_MAX_LANES + 1, &result) == -1);
    assert(sw_networking_real_time_status(79, &out, nullptr, 1, &result) == -1);
    assert(sw_networking_real_time_status(79, nullptr, lanes, 1, &result) == -1);
    assert(sw_networking_real_time_status(79, &out, lanes, 1, nullptr) == -1);
    assert(socket_accessors == accessors && status_calls == calls);
    sockets_available = false;
    result = -987;
    assert(sw_networking_real_time_status(79, &out, lanes, 1, &result) == 0 && result == -987);
    assert(status_calls == calls);
    assert(memcmp(saved_out, &out, sizeof(out)) == 0 && memcmp(saved_lanes, lanes, sizeof(lanes)) == 0);
    sockets_available = true;
}
static void test_detailed_status() {
    int32_t result = -987;
    text_capacity = 0;
    text_buffer = nullptr;
    text_result = 4;
    assert(sw_networking_detailed_status(79, nullptr, 0, &result) == 1 && result == 4);
    char buffer[5] = {'a', 'b', 'c', 'd', '!'};
    text_buffer = buffer;
    text_capacity = 4;
    terminate_text = true;
    text_result = 0;
    assert(sw_networking_detailed_status(79, buffer, 4, &result) == 1 && result == 0);
    assert(memcmp(buffer, "xxx\0!", 5) == 0);
    text_capacity = 2;
    text_result = 4;
    assert(sw_networking_detailed_status(79, buffer, 2, &result) == 1 && result == 4);
    assert(buffer[0] == 'x' && buffer[1] == 0 && buffer[4] == '!');
    terminate_text = false;
    const int results[] = {-1, -71, INT32_MIN, INT32_MAX, 0};
    for (int native_result : results) {
        text_result = native_result;
        assert(sw_networking_detailed_status(79, buffer, 2, &result) == 1 && result == native_result);
        assert(buffer[0] == 'x' && buffer[1] == 'x');
    }
    const int calls = status_calls, accessors = socket_accessors;
    assert(sw_networking_detailed_status(79, buffer, -1, &result) == -1);
    assert(sw_networking_detailed_status(79, nullptr, 1, &result) == -1);
    assert(sw_networking_detailed_status(79, buffer, 1, nullptr) == -1);
    assert(socket_accessors == accessors && status_calls == calls);
    sockets_available = false;
    result = -987;
    buffer[0] = '!';
    assert(sw_networking_detailed_status(79, buffer, 1, &result) == 0 && result == -987);
    assert(status_calls == calls && buffer[0] == '!');
    sockets_available = true;
}
int main() {
    test_real_time_status();
    test_detailed_status();
    test_configure_lanes();
    test_send_batch();
    SwAddress address = {};
    address.ipv6[15] = 1;
    address.port = 27015;
    const auto native = native_address(address);
    assert(native.m_ipv6[15] == 1 && native.m_port == 27015);
    SwAddress roundtrip = {};
    copy_address(native, &roundtrip);
    assert(memcmp(address.ipv6, roundtrip.ipv6, sizeof(address.ipv6)) == 0 && roundtrip.port == address.port);

    SteamNetConnectionInfo_t info = {};
    info.m_identityRemote.SetSteamID64(76561198000000000ULL);
    info.m_hListenSocket = 19;
    info.m_eState = static_cast<ESteamNetworkingConnectionState>(12345);
    info.m_eEndReason = 4567;
    memset(info.m_szEndDebug, 'x', sizeof(info.m_szEndDebug));
    SwConnectionInfo copied;
    copy_info(23, info, &copied);
    assert(copied.connection == 23 && copied.listen_socket == 19);
    assert(copied.peer_steam_id == 76561198000000000ULL && copied.state == 12345 && copied.end_reason == 4567);
    assert(copied.end_debug[127] == 'x');

    MessageFixture fixture = {};
    fixture.m_pfnRelease = release_fixture;
    fixture.m_nMessageNumber = 123;
    fixture.m_conn = 71;
    fixture.m_nChannel = 4;
    fixture.m_idxLane = UINT16_MAX;
    fixture.m_usecTimeReceived = 567;
    fixture.m_identityPeer.SetSteamID64(76561198000000000ULL);
    SteamNetworkingMessage_t *messages[2] = { &fixture, nullptr };
    SwMessageView views[2] = {};
    assert(finish_receive(messages, 1, 2, views) == 1);
    assert(views[0].size == 0 && !views[0].data && views[0].handle);
    assert(views[0].number == 123 && views[0].connection == 71 && views[0].channel == 4 && views[0].received_at == 567);
    assert(views[0].peer_steam_id == 76561198000000000ULL && views[0].lane == UINT16_MAX);
    sw_networking_release_message(&views[0].handle);
    sw_networking_release_message(&views[0].handle);
    assert(released_messages == 1 && !views[0].handle);
    fixture.m_cbSize = -1;
    assert(finish_receive(messages, 1, 2, views) == -1);
    assert(released_messages == 2 && !views[0].handle);
    fixture.m_cbSize = 1; // Missing payload must also release the batch.
    assert(finish_receive(messages, 1, 2, views) == -1);
    assert(released_messages == 3);
    assert(finish_receive(messages, -1, 2, views) == -1);
    assert(released_messages == 4);
    assert(finish_receive(messages, 3, 2, views) == -1);
    assert(released_messages == 5);
    uint8_t byte = 42;
    fixture.m_pData = &byte;
    assert(finish_receive(messages, 1, 2, views) == 1 && views[0].data[0] == 42);
    sw_networking_release_message(&views[0].handle);
    assert(released_messages == 6);
    MessageFixture malformed = {};
    malformed.m_pfnRelease = release_fixture;
    malformed.m_cbSize = -1;
    messages[1] = &malformed;
    assert(finish_receive(messages, 2, 2, views) == -1);
    assert(released_messages == 8 && !views[0].handle && !views[1].handle);
    assert(sw_networking_receive(0, 0, nullptr, -1) == -1);
    assert(sw_networking_receive(0, 0, nullptr, SW_NETWORKING_MAX_RECEIVE + 1) == -1);
    assert(sw_networking_receive(0, 0, nullptr, 0) == 0);
}
#endif
