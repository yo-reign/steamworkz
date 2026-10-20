/* SDK-free public-guard fixture. Never link these aborting adapters into a game.
 * Every native path exercised here must fail if an owner check is bypassed. */
#include "core.h"
#include "services.h"
#include <stdlib.h>

void sw_shutdown(void) { abort(); }
uint8_t sw_next_event(int32_t, const SwPollState *, SwEvent *) { abort(); }
uint8_t sw_cloud_local_change_count(int32_t *) { abort(); }
uint8_t sw_cloud_local_change_copy(int32_t, char *, size_t, sw_cloud_local_change *) { abort(); }
int32_t sw_cloud_begin_write_batch(void) { abort(); }
int32_t sw_cloud_end_write_batch(void) { abort(); }
uint8_t sw_stats_achievement_icon(const char *, int32_t *) { abort(); }
uint8_t sw_stats_find_leaderboard(const char *, uint64_t *) { abort(); }
uint8_t sw_stats_leaderboard_metadata_copy(uint64_t, char *, size_t, sw_stats_leaderboard_metadata *) { abort(); }
uint8_t sw_stats_download(uint64_t, uint8_t, int32_t, int32_t, uint64_t *) { abort(); }
uint8_t sw_stats_download_users(uint64_t, const uint64_t *, int32_t, uint64_t *) { abort(); }
uint8_t sw_stats_upload(uint64_t, uint8_t, int32_t, const int32_t *, int32_t, uint64_t *) { abort(); }
uint8_t sw_stats_request_global_percentages(uint64_t *) { abort(); }
uint8_t sw_stats_percentage_step(uint8_t, int32_t, sw_stats_percentage *) { abort(); }
int32_t sw_stats_achievement_percentage(const char *, uint32_t *) { abort(); }
