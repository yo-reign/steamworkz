#ifndef SW_NETWORKING_CONFIG_H
#define SW_NETWORKING_CONFIG_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

/* Owned ABI. Local return codes: 0 available, -1 unavailable, -2 invalid input.
 * These are not EResult or native getter statuses. No pointers are retained.
 * Scope: 0 global, 1 listen socket, 2 connection. Option: 0..5 in Zig order. */
typedef struct sw_config_get_result {
    int32_t status;
    int32_t data_type;
    size_t size;
    int32_t value; /* Zero unless known success, Int32, and exact size. */
} sw_config_get_result;
int32_t sw_config_set(uint32_t scope, uint32_t handle, uint32_t option, int32_t value, bool clear, bool *accepted);
int32_t sw_config_get(uint32_t scope, uint32_t handle, uint32_t option, sw_config_get_result *out);

typedef struct sw_config_simulation {
    float send_loss_percent, receive_loss_percent;
    int32_t send_lag_ms, receive_lag_ms;
    float send_reorder_percent, receive_reorder_percent;
    int32_t reorder_delay_ms;
} sw_config_simulation;
/* Fixed field order matches sw_config_simulation. 0 not attempted, 1 applied,
 * 2 rejected. Apply stops on rejection; reset attempts every null clear.
 * Availability and all validation are resolved before any mutation. */
typedef struct sw_config_simulation_result { uint8_t fields[7]; } sw_config_simulation_result;
int32_t sw_config_simulation_apply(const sw_config_simulation *settings, sw_config_simulation_result *out);
int32_t sw_config_simulation_reset(sw_config_simulation_result *out);
#ifdef __cplusplus
}
#endif
#endif
