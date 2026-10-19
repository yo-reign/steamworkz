#ifndef MEIKYUU_STEAMWORKS_LOBBIES_H
#define MEIKYUU_STEAMWORKS_LOBBIES_H
#include "types.h"
#ifdef __cplusplus
extern "C" {
#endif

/* Private bridge protocol. All aggregates are naturally aligned and pointer-only.
 * Text inputs are NUL terminated; Zig validates lengths and embedded NULs first.
 * A zero boolean/call/ID and a negative count signal native failure. */
typedef struct SwLobbyFilter {
    int32_t kind; /* 0 string, 1 numerical, 2 near, 3 slots, 4 distance,
                   5 result count, 6 compatible members */
    const char *key;
    const char *text;
    int32_t value;
    int32_t comparison;
    uint64_t lobby;
} SwLobbyFilter;

typedef struct SwLobbyChat {
    uint64_t sender;
    int32_t entry_type;
    int32_t size;
} SwLobbyChat;

typedef struct SwLobbyGameServer {
    uint64_t steam_id;
    uint32_t ipv4; /* host byte order */
    uint16_t port;
} SwLobbyGameServer;

uint64_t sw_lobbies_create(int32_t type, int32_t limit);
uint64_t sw_lobbies_join(uint64_t lobby);
int sw_lobbies_leave(uint64_t lobby);
uint64_t sw_lobbies_request_list(const SwLobbyFilter *filters, size_t count);
uint64_t sw_lobbies_at(int32_t index);
int32_t sw_lobbies_member_count(uint64_t lobby);
uint64_t sw_lobbies_member_at(uint64_t lobby, int32_t index);
uint64_t sw_lobbies_owner(uint64_t lobby);
int sw_lobbies_set_owner(uint64_t lobby, uint64_t owner);
/* Borrowed SDK strings. Empty is ambiguous (unset, empty, or invalid lobby). */
const char *sw_lobbies_data(uint64_t lobby, const char *key);
const char *sw_lobbies_member_data(uint64_t lobby, uint64_t member, const char *key);
int sw_lobbies_set_data(uint64_t lobby, const char *key, const char *value);
int sw_lobbies_set_member_data(uint64_t lobby, const char *key, const char *value);
int sw_lobbies_delete_data(uint64_t lobby, const char *key);
int32_t sw_lobbies_data_count(uint64_t lobby);
int sw_lobbies_data_at(uint64_t lobby, int32_t index, char *key, int32_t key_size, char *value, int32_t value_size);
int sw_lobbies_request_data(uint64_t lobby);
int sw_lobbies_invite(uint64_t lobby, uint64_t invitee);
int sw_lobbies_set_joinable(uint64_t lobby, int joinable);
int sw_lobbies_set_type(uint64_t lobby, int32_t type);
int sw_lobbies_set_limit(uint64_t lobby, int32_t limit);
int32_t sw_lobbies_limit(uint64_t lobby);
int sw_lobbies_send_chat(uint64_t lobby, const uint8_t *data, int32_t size);
int sw_lobbies_read_chat(uint64_t lobby, int32_t chat_id, uint8_t *data, int32_t capacity, SwLobbyChat *out);
int sw_lobbies_set_game_server(uint64_t lobby, const SwLobbyGameServer *server);
/* 1 present, 0 absent OR invalid lobby, -1 interface unavailable. */
int sw_lobbies_game_server(uint64_t lobby, SwLobbyGameServer *out);

#ifdef __cplusplus
}
#endif
#endif
