#ifndef MEIKYUU_STEAMWORKS_NETWORKING_H
#define MEIKYUU_STEAMWORKS_NETWORKING_H
#include "types.h"
#ifdef __cplusplus
extern "C" {
#endif

enum { SW_NETWORKING_MAX_RECEIVE = 64, SW_ADDRESS_TEXT_SIZE = 48, SW_NETWORKING_MAX_LANES = 255 };
enum {
    SW_SEND_UNRELIABLE = 0,
    SW_SEND_NO_NAGLE = 1,
    SW_SEND_NO_DELAY = 4,
    SW_SEND_RELIABLE = 8,
    SW_SEND_USE_CURRENT_THREAD = 16
};
/* Wrapper batch bound, independent of receive and SDK limits. */
enum { SW_NETWORKING_MAX_SEND_BATCH = 64, SW_NETWORKING_MAX_SEND_SIZE = 512 * 1024 };
typedef struct SwLaneConfig {
    int32_t priority;
    uint16_t weight;
} SwLaneConfig;
typedef struct SwBatchSend {
    uint32_t connection;
    const uint8_t *data;
    uint32_t size;
    uint16_t lane;
    int32_t flags;
} SwBatchSend;
/* -1 invalid arguments, 0 unavailable, 1 called; result unchanged otherwise. */
int sw_networking_configure_lanes(uint32_t connection, const SwLaneConfig *lanes, int count, int32_t *native_result);
/* Borrow descriptors/payloads synchronously. -2 allocation failure, -1 invalid,
 * 0 unavailable, 1 transferred (or empty). Results unchanged before transfer.
 * Acquired messages are released on failure; one SendMessages(true) transfers all. */
int sw_networking_send_batch(const SwBatchSend *messages, int count, int64_t *results);

typedef struct SwRelayStatus {
    int32_t availability;
    int32_t ping_measurement_in_progress;
    int32_t network_config;
    int32_t any_relay;
    char debug[256];
} SwRelayStatus;

/* Owned fieldwise snapshots, not SDK layout aliases. Reserved fields omitted. */
typedef struct SwConnectionRealTimeStatus {
    int32_t state;
    int32_t ping_ms;
    float connection_quality_local;
    float connection_quality_remote;
    float out_packets_per_second;
    float out_bytes_per_second;
    float in_packets_per_second;
    float in_bytes_per_second;
    int32_t send_rate_bytes_per_second;
    int32_t pending_unreliable;
    int32_t pending_reliable;
    int32_t sent_unacked_reliable;
    int64_t queue_time_us;
    int32_t max_jitter_us;
} SwConnectionRealTimeStatus;
typedef struct SwLaneRealTimeStatus {
    int32_t pending_unreliable;
    int32_t pending_reliable;
    int32_t sent_unacked_reliable;
    int64_t queue_time_us;
} SwLaneRealTimeStatus;

/* Return -1 for invalid bridge arguments, 0 for missing interface, 1 if called.
 * native_result is written only if called and preserves the native result.
 * Status and lanes are written only on native OK. lane_count must be 0..255.
 * Detailed text may be modified even when too short; null/zero queries size. */
int sw_networking_real_time_status(uint32_t connection, SwConnectionRealTimeStatus *out,
    SwLaneRealTimeStatus *lanes, int lane_count, int32_t *native_result);
int sw_networking_detailed_status(uint32_t connection, char *buffer, int capacity, int32_t *native_result);

/* Parsing returns -1 if utils is unavailable, 0 for invalid text, 1 on success.
 * Formatting returns 0 if utils is unavailable or the buffer is too small. */
int sw_networking_parse_address(const char *text, SwAddress *out);
int sw_networking_format_address(const SwAddress *address, char *out, int capacity, int with_port);
uint32_t sw_networking_listen_ip(const SwAddress *address);
uint32_t sw_networking_connect_ip(const SwAddress *address);
uint32_t sw_networking_listen_p2p(int virtual_port);
uint32_t sw_networking_connect_p2p(uint64_t steam_id, int virtual_port);
int32_t sw_networking_accept(uint32_t connection);
int sw_networking_close(uint32_t connection, int reason, const char *debug, int linger);
int sw_networking_close_listen(uint32_t socket);
int sw_networking_socket_pair(uint32_t *first, uint32_t *second, int network_loopback);
int32_t sw_networking_send(uint32_t connection, const uint8_t *data, uint32_t size, int flags, int64_t *number);
int32_t sw_networking_flush(uint32_t connection);
/* Capacity must be 0..SW_NETWORKING_MAX_RECEIVE. On failure no messages escape.
 * On success each view owns one handle, including a zero-length message. */
int sw_networking_receive(uint32_t handle, int poll_group, SwMessageView *out, int capacity);
void sw_networking_release_message(SwMessage **handle);
int sw_networking_connection_info(uint32_t connection, SwConnectionInfo *out);
int sw_networking_listen_address(uint32_t socket, SwAddress *out);
uint32_t sw_networking_create_poll_group(void);
int sw_networking_destroy_poll_group(uint32_t group);
int sw_networking_set_poll_group(uint32_t connection, uint32_t group);
int sw_networking_init_relay(void);
int sw_networking_relay_status(SwRelayStatus *out);
#ifdef __cplusplus
}
#endif
#endif
