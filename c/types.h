#ifndef MEIKYUU_STEAMWORKS_TYPES_H
#define MEIKYUU_STEAMWORKS_TYPES_H
#include <stdint.h>
#include <stddef.h>

/* These are our C values, not layout aliases for Valve's packed C++ types.
 * Pass aggregates through pointers. Convert SDK values field by field. */
typedef struct SwAddress {
    uint8_t ipv6[16];
    uint16_t port;
} SwAddress;

typedef struct SwConnectionInfo {
    uint64_t peer_steam_id;
    uint32_t connection;
    uint32_t listen_socket;
    int32_t state;
    int32_t end_reason;
    char peer_identity[128];
    char end_debug[128];
} SwConnectionInfo;

typedef struct SwMessage SwMessage;
typedef struct SwMessageView {
    SwMessage *handle;
    const uint8_t *data;
    int32_t size;
    uint32_t connection;
    uint64_t peer_steam_id;
    int64_t number;
    int64_t received_at;
    int32_t channel;
    uint16_t lane; /* Incoming lane; message numbers are scoped to each lane. */
} SwMessageView;
#endif
