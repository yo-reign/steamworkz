/* Private guard executable only. Never link these aborting stubs into a game.
 * SDK-free linkage proves that broken lease checks cannot call Steam here. */
#include "networking.h"
#include "networking_config.h"
#include <stdlib.h>

int sw_networking_real_time_status(uint32_t, SwConnectionRealTimeStatus *, SwLaneRealTimeStatus *, int, int32_t *) { abort(); }
int sw_networking_detailed_status(uint32_t, char *, int, int32_t *) { abort(); }
int sw_networking_configure_lanes(uint32_t, const SwLaneConfig *, int, int32_t *) { abort(); }
int sw_networking_send_batch(const SwBatchSend *, int, int64_t *) { abort(); }
int32_t sw_config_set(uint32_t, uint32_t, uint32_t, int32_t, bool, bool *) { abort(); }
int32_t sw_config_get(uint32_t, uint32_t, uint32_t, sw_config_get_result *) { abort(); }
int32_t sw_config_simulation_apply(const sw_config_simulation *, sw_config_simulation_result *) { abort(); }
int32_t sw_config_simulation_reset(sw_config_simulation_result *) { abort(); }
