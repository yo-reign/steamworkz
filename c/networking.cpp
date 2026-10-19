#include "networking.h"
#include "steam/steam_api_flat.h"
#include <string.h>

static_assert(SW_SEND_UNRELIABLE == k_nSteamNetworkingSend_Unreliable, "unreliable send flag");
static_assert(SW_SEND_NO_NAGLE == k_nSteamNetworkingSend_NoNagle, "no Nagle send flag");
static_assert(SW_SEND_NO_DELAY == k_nSteamNetworkingSend_NoDelay, "no delay send flag");
static_assert(SW_SEND_RELIABLE == k_nSteamNetworkingSend_Reliable, "reliable send flag");
static_assert(SW_SEND_USE_CURRENT_THREAD == k_nSteamNetworkingSend_UseCurrentThread, "current thread send flag");
static_assert(SW_ADDRESS_TEXT_SIZE >= SteamNetworkingIPAddr::k_cchMaxString, "address text capacity");
static_assert(sizeof(((SwConnectionInfo *)nullptr)->peer_identity) >= SteamNetworkingIdentity::k_cchMaxString, "identity text capacity");

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
int main() {
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
    fixture.m_usecTimeReceived = 567;
    fixture.m_identityPeer.SetSteamID64(76561198000000000ULL);
    SteamNetworkingMessage_t *messages[2] = { &fixture, nullptr };
    SwMessageView views[2] = {};
    assert(finish_receive(messages, 1, 2, views) == 1);
    assert(views[0].size == 0 && !views[0].data && views[0].handle);
    assert(views[0].number == 123 && views[0].connection == 71 && views[0].channel == 4 && views[0].received_at == 567);
    assert(views[0].peer_steam_id == 76561198000000000ULL);
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
