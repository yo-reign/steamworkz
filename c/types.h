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

/* Wrapper row bound and the complete native detail capacity, not SDK layouts. */
enum { SW_LEADERBOARD_MAX_ENTRIES = 100, SW_LEADERBOARD_MAX_DETAILS = 64 };
enum SwLeaderboardCaptureStatus {
    SW_LEADERBOARD_CAPTURE_COMPLETE,
    SW_LEADERBOARD_CAPTURE_INVALID_COUNT,
    SW_LEADERBOARD_CAPTURE_TOO_MANY_ROWS,
    SW_LEADERBOARD_CAPTURE_INVALID_HANDLE,
    SW_LEADERBOARD_CAPTURE_UNAVAILABLE,
    SW_LEADERBOARD_CAPTURE_ENTRY_FAILED,
    SW_LEADERBOARD_CAPTURE_INVALID_DETAILS,
    SW_LEADERBOARD_CAPTURE_UNTRACKED
};
typedef struct SwLeaderboardEntry {
    uint64_t user;
    int32_t global_rank;
    int32_t score;
    uint64_t ugc;
    uint32_t detail_count;
    int32_t details[SW_LEADERBOARD_MAX_DETAILS];
} SwLeaderboardEntry;
typedef struct SwLeaderboardEntries {
    int32_t status;
    int32_t reported_count;
    uint32_t copied_count;
    int32_t failure_index;
    int32_t reported_details;
    uint8_t all_rows_accessed;
    SwLeaderboardEntry entries[SW_LEADERBOARD_MAX_ENTRIES];
} SwLeaderboardEntries;
#endif
