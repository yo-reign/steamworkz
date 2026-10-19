#include "lobbies.h"
#include "steam/steam_api_flat.h"
#include <string.h>

static bool valid_filters(const SwLobbyFilter *filters, size_t count) {
    if (count && !filters) return false;
    for (size_t i = 0; i < count; ++i) {
        const SwLobbyFilter &f = filters[i];
        switch (f.kind) {
        case 0:
            if (!f.text) return false;
            // fall through
        case 1:
            if (f.comparison < -2 || f.comparison > 3) return false;
            // fall through
        case 2:
            if (!f.key) return false;
            break;
        case 3:
            if (f.value < 1 || f.value > 250) return false;
            break;
        case 4:
            if (f.value < 0 || f.value > 3) return false;
            break;
        case 5:
            if (f.value < 1) return false;
            break;
        case 6:
            if (!f.lobby) return false;
            break;
        default: return false;
        }
    }
    return true;
}

static bool write_chat(SwLobbyChat *out, const CSteamID &sender,
                       const EChatEntryType *type, int size, int capacity) {
    if (size <= 0 || size > capacity) return false;
    out->sender = sender.ConvertToUint64();
    // New SDK enum values must not be evaluated as an out-of-range C++ enum.
    static_assert(sizeof(*type) == sizeof(out->entry_type), "chat enum width");
    memcpy(&out->entry_type, type, sizeof(out->entry_type));
    out->size = size;
    return true;
}

static void write_server(SwLobbyGameServer *out, const CSteamID &id,
                         uint32 ip, uint16 port) {
    out->steam_id = id.ConvertToUint64();
    out->ipv4 = ip;
    out->port = port;
}

#ifndef SW_LOBBIES_TEST
// Only the official flat exports call the interface; never dispatch a C++ vtable.
static ISteamMatchmaking *matchmaking() { return SteamAPI_SteamMatchmaking_v009(); }

extern "C" {
uint64_t sw_lobbies_create(int32_t type, int32_t limit) {
    ISteamMatchmaking *m = matchmaking();
    return m ? SteamAPI_ISteamMatchmaking_CreateLobby(m, static_cast<ELobbyType>(type), limit) : 0;
}
uint64_t sw_lobbies_join(uint64_t lobby) {
    ISteamMatchmaking *m = matchmaking();
    return m ? SteamAPI_ISteamMatchmaking_JoinLobby(m, lobby) : 0;
}
int sw_lobbies_leave(uint64_t lobby) {
    ISteamMatchmaking *m = matchmaking();
    if (!m) return 0;
    SteamAPI_ISteamMatchmaking_LeaveLobby(m, lobby);
    return 1;
}
uint64_t sw_lobbies_request_list(const SwLobbyFilter *filters, size_t count) {
    if (!valid_filters(filters, count)) return 0;
    ISteamMatchmaking *m = matchmaking();
    if (!m) return 0;
    for (size_t i = 0; i < count; ++i) {
        const SwLobbyFilter &f = filters[i];
        switch (f.kind) {
        case 0: SteamAPI_ISteamMatchmaking_AddRequestLobbyListStringFilter(m, f.key, f.text, static_cast<ELobbyComparison>(f.comparison)); break;
        case 1: SteamAPI_ISteamMatchmaking_AddRequestLobbyListNumericalFilter(m, f.key, f.value, static_cast<ELobbyComparison>(f.comparison)); break;
        case 2: SteamAPI_ISteamMatchmaking_AddRequestLobbyListNearValueFilter(m, f.key, f.value); break;
        case 3: SteamAPI_ISteamMatchmaking_AddRequestLobbyListFilterSlotsAvailable(m, f.value); break;
        case 4: SteamAPI_ISteamMatchmaking_AddRequestLobbyListDistanceFilter(m, static_cast<ELobbyDistanceFilter>(f.value)); break;
        case 5: SteamAPI_ISteamMatchmaking_AddRequestLobbyListResultCountFilter(m, f.value); break;
        case 6: SteamAPI_ISteamMatchmaking_AddRequestLobbyListCompatibleMembersFilter(m, f.lobby); break;
        }
    }
    return SteamAPI_ISteamMatchmaking_RequestLobbyList(m);
}
uint64_t sw_lobbies_at(int32_t index) {
    ISteamMatchmaking *m = matchmaking();
    return m ? SteamAPI_ISteamMatchmaking_GetLobbyByIndex(m, index) : 0;
}
int32_t sw_lobbies_member_count(uint64_t lobby) {
    ISteamMatchmaking *m = matchmaking();
    return m ? SteamAPI_ISteamMatchmaking_GetNumLobbyMembers(m, lobby) : -1;
}
uint64_t sw_lobbies_member_at(uint64_t lobby, int32_t index) {
    ISteamMatchmaking *m = matchmaking();
    return m ? SteamAPI_ISteamMatchmaking_GetLobbyMemberByIndex(m, lobby, index) : 0;
}
uint64_t sw_lobbies_owner(uint64_t lobby) {
    ISteamMatchmaking *m = matchmaking();
    return m ? SteamAPI_ISteamMatchmaking_GetLobbyOwner(m, lobby) : 0;
}
int sw_lobbies_set_owner(uint64_t lobby, uint64_t owner) {
    ISteamMatchmaking *m = matchmaking();
    return m && SteamAPI_ISteamMatchmaking_SetLobbyOwner(m, lobby, owner);
}
const char *sw_lobbies_data(uint64_t lobby, const char *key) {
    ISteamMatchmaking *m = matchmaking();
    return m ? SteamAPI_ISteamMatchmaking_GetLobbyData(m, lobby, key) : nullptr;
}
const char *sw_lobbies_member_data(uint64_t lobby, uint64_t member, const char *key) {
    ISteamMatchmaking *m = matchmaking();
    return m ? SteamAPI_ISteamMatchmaking_GetLobbyMemberData(m, lobby, member, key) : nullptr;
}
int sw_lobbies_set_data(uint64_t lobby, const char *key, const char *value) {
    ISteamMatchmaking *m = matchmaking();
    return m && SteamAPI_ISteamMatchmaking_SetLobbyData(m, lobby, key, value);
}
int sw_lobbies_set_member_data(uint64_t lobby, const char *key, const char *value) {
    ISteamMatchmaking *m = matchmaking();
    if (!m) return 0;
    SteamAPI_ISteamMatchmaking_SetLobbyMemberData(m, lobby, key, value);
    return 1;
}
int sw_lobbies_delete_data(uint64_t lobby, const char *key) {
    ISteamMatchmaking *m = matchmaking();
    return m && SteamAPI_ISteamMatchmaking_DeleteLobbyData(m, lobby, key);
}
int32_t sw_lobbies_data_count(uint64_t lobby) {
    ISteamMatchmaking *m = matchmaking();
    return m ? SteamAPI_ISteamMatchmaking_GetLobbyDataCount(m, lobby) : -1;
}
int sw_lobbies_data_at(uint64_t lobby, int32_t index, char *key, int32_t key_size, char *value, int32_t value_size) {
    ISteamMatchmaking *m = matchmaking();
    return m && SteamAPI_ISteamMatchmaking_GetLobbyDataByIndex(m, lobby, index, key, key_size, value, value_size);
}
int sw_lobbies_request_data(uint64_t lobby) {
    ISteamMatchmaking *m = matchmaking();
    return m && SteamAPI_ISteamMatchmaking_RequestLobbyData(m, lobby);
}
int sw_lobbies_invite(uint64_t lobby, uint64_t invitee) {
    ISteamMatchmaking *m = matchmaking();
    return m && SteamAPI_ISteamMatchmaking_InviteUserToLobby(m, lobby, invitee);
}
int sw_lobbies_set_joinable(uint64_t lobby, int joinable) {
    ISteamMatchmaking *m = matchmaking();
    return m && SteamAPI_ISteamMatchmaking_SetLobbyJoinable(m, lobby, joinable != 0);
}
int sw_lobbies_set_type(uint64_t lobby, int32_t type) {
    ISteamMatchmaking *m = matchmaking();
    return m && SteamAPI_ISteamMatchmaking_SetLobbyType(m, lobby, static_cast<ELobbyType>(type));
}
int sw_lobbies_set_limit(uint64_t lobby, int32_t limit) {
    ISteamMatchmaking *m = matchmaking();
    return m && SteamAPI_ISteamMatchmaking_SetLobbyMemberLimit(m, lobby, limit);
}
int32_t sw_lobbies_limit(uint64_t lobby) {
    ISteamMatchmaking *m = matchmaking();
    return m ? SteamAPI_ISteamMatchmaking_GetLobbyMemberLimit(m, lobby) : -1;
}
int sw_lobbies_send_chat(uint64_t lobby, const uint8_t *data, int32_t size) {
    ISteamMatchmaking *m = matchmaking();
    return m && SteamAPI_ISteamMatchmaking_SendLobbyChatMsg(m, lobby, data, size);
}
int sw_lobbies_read_chat(uint64_t lobby, int32_t chat_id, uint8_t *data, int32_t capacity, SwLobbyChat *out) {
    ISteamMatchmaking *m = matchmaking();
    if (!m) return 0;
    CSteamID sender;
    EChatEntryType type = k_EChatEntryTypeInvalid;
    const int size = SteamAPI_ISteamMatchmaking_GetLobbyChatEntry(m, lobby, chat_id, &sender, data, capacity, &type);
    return write_chat(out, sender, &type, size, capacity);
}
int sw_lobbies_set_game_server(uint64_t lobby, const SwLobbyGameServer *server) {
    ISteamMatchmaking *m = matchmaking();
    if (!m) return 0;
    SteamAPI_ISteamMatchmaking_SetLobbyGameServer(m, lobby, server->ipv4, server->port, server->steam_id);
    return 1;
}
int sw_lobbies_game_server(uint64_t lobby, SwLobbyGameServer *out) {
    ISteamMatchmaking *m = matchmaking();
    if (!m) return -1;
    CSteamID id;
    uint32 ip = 0;
    uint16 port = 0;
    if (!SteamAPI_ISteamMatchmaking_GetLobbyGameServer(m, lobby, &ip, &port, &id)) return 0;
    write_server(out, id, ip, port);
    return 1;
}
}
#else
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
int main() {
    SwLobbyFilter filters[2] = {};
    filters[0].kind = 5;
    filters[0].value = 7;
    filters[1].kind = 99;
    assert(!valid_filters(filters, 2)); // reject later invalid filter before mutation
    assert(valid_filters(filters, 1));
    assert(valid_filters(nullptr, 0));
    assert(!valid_filters(nullptr, 1));
    filters[0].kind = 0;
    filters[0].key = "mode";
    filters[0].text = "coop";
    filters[0].comparison = -2;
    assert(valid_filters(filters, 1));
    filters[0].comparison = 4;
    assert(!valid_filters(filters, 1));

    const CSteamID id(static_cast<uint64>(0x0110000101020304ULL));
    SwLobbyChat chat = {};
    EChatEntryType type = k_EChatEntryTypeChatMsg;
    assert(!write_chat(&chat, id, &type, -1, 4));
    assert(!write_chat(&chat, id, &type, 0, 4));
    assert(!write_chat(&chat, id, &type, 5, 4));
    const int32_t unknown_type = 123;
    memcpy(&type, &unknown_type, sizeof(type));
    assert(write_chat(&chat, id, &type, 4, 4));
    assert(chat.sender == id.ConvertToUint64() && chat.entry_type == 123 && chat.size == 4);
    SwLobbyGameServer server = {};
    write_server(&server, id, 0x7f000001, 27015);
    assert(server.steam_id == id.ConvertToUint64());
    assert(server.ipv4 == 0x7f000001 && server.port == 27015);
    return 0;
}
#endif
