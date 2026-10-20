#ifndef MEIKYUU_STEAMWORKS_SERVICES_H
#define MEIKYUU_STEAMWORKS_SERVICES_H
#include "types.h"
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
const char *sw_persona_name(void);
int32_t sw_friend_count(void);
uint64_t sw_friend_at(int32_t index);
const char *sw_friend_name(uint64_t user);
int32_t sw_friend_state(uint64_t user);
uint8_t sw_request_user(uint64_t user, uint8_t name_only);
uint8_t sw_set_presence(const char *key, const char *value);
void sw_clear_presence(void);
const char *sw_friend_presence(uint64_t user, const char *key);
void sw_request_presence(uint64_t user);
uint8_t sw_invite_game(uint64_t user, const char *connect);
void sw_open_overlay(const char *dialog);
void sw_open_store(uint32_t app);
void sw_open_invite(uint64_t lobby);
int32_t sw_avatar(uint64_t user, int32_t size);
uint8_t sw_image_size(int32_t image, uint32_t *width, uint32_t *height);
uint8_t sw_image_rgba(int32_t image, uint8_t *buffer, int32_t size);

uint8_t sw_subscribed(void);
uint8_t sw_owns_app(uint32_t app);
uint8_t sw_app_installed(uint32_t app);
uint8_t sw_dlc_installed(uint32_t app);
int32_t sw_dlc_count(void);
uint8_t sw_dlc_data(int32_t index, uint32_t *app, uint8_t *available, char *name, int32_t capacity);
uint8_t sw_dlc_progress(uint32_t app, uint64_t *downloaded, uint64_t *total);
const char *sw_game_language(void);
const char *sw_available_languages(void);
uint64_t sw_app_owner(void);
int32_t sw_build_id(void);
int32_t sw_launch_command_line(char *buffer, int32_t capacity);

uint8_t sw_stat_int(const char *name, int32_t *value);
uint8_t sw_stat_float(const char *name, float *value);
uint8_t sw_set_stat_int(const char *name, int32_t value);
uint8_t sw_set_stat_float(const char *name, float value);
uint8_t sw_achievement(const char *name, uint8_t *unlocked, uint32_t *time);
uint8_t sw_unlock_achievement(const char *name);
uint8_t sw_clear_achievement(const char *name);
uint8_t sw_achievement_progress(const char *name, uint32_t current, uint32_t maximum);
uint32_t sw_achievement_count(void);
const char *sw_achievement_name(uint32_t index);
const char *sw_achievement_attribute(const char *name, const char *key);
uint8_t sw_store_stats(void);
uint64_t sw_request_user_stats(uint64_t user);
uint8_t sw_user_stat_int(uint64_t user, const char *name, int32_t *value);
uint8_t sw_user_stat_float(uint64_t user, const char *name, float *value);
uint8_t sw_user_achievement(uint64_t user, const char *name, uint8_t *unlocked, uint32_t *time);

/* New stats calls return 0 only for interface absence unless stated otherwise.
 * API-call acceptance is represented separately by the output call handle. */
uint8_t sw_stats_achievement_icon(const char *name, int32_t *image);
uint8_t sw_stats_find_leaderboard(const char *name, uint64_t *call);
enum sw_stats_text_status { SW_STATS_TEXT_OK, SW_STATS_TEXT_UNAVAILABLE, SW_STATS_TEXT_NULL, SW_STATS_TEXT_SHORT };
typedef struct sw_stats_leaderboard_metadata {
    size_t name_length;
    int32_t entry_count, sort, display;
} sw_stats_leaderboard_metadata;
uint8_t sw_stats_leaderboard_metadata_copy(uint64_t leaderboard, char *buffer, size_t capacity, sw_stats_leaderboard_metadata *out);
/* around: 0 global, 1 around-user; validated bounded signed ranges only. */
uint8_t sw_stats_download(uint64_t leaderboard, uint8_t around, int32_t first, int32_t last, uint64_t *call);
uint8_t sw_stats_download_users(uint64_t leaderboard, const uint64_t *users, int32_t count, uint64_t *call);
uint8_t sw_stats_upload(uint64_t leaderboard, uint8_t force, int32_t score, const int32_t *details, int32_t count, uint64_t *call);
void sw_stats_copy_leaderboard_entries(uint64_t entries, int32_t count, SwLeaderboardEntries *out);
uint8_t sw_stats_request_global_percentages(uint64_t *call);
enum sw_stats_percentage_status { SW_STATS_PERCENTAGE_ITEM, SW_STATS_PERCENTAGE_UNAVAILABLE, SW_STATS_PERCENTAGE_END, SW_STATS_PERCENTAGE_NEGATIVE, SW_STATS_PERCENTAGE_UNTERMINATED };
typedef struct sw_stats_percentage {
    int32_t iterator;
    uint32_t name_length, percent_bits;
    uint8_t achieved;
    char name[128];
} sw_stats_percentage;
/* first ignores previous; next requires a nonnegative previous iterator. */
uint8_t sw_stats_percentage_step(uint8_t first, int32_t previous, sw_stats_percentage *out);
/* -1 unavailable, 0 native false, 1 native true (only true publishes bits). */
int32_t sw_stats_achievement_percentage(const char *name, uint32_t *percent_bits);

uint8_t sw_cloud_account_enabled(void);
uint8_t sw_cloud_app_enabled(void);
uint8_t sw_cloud_exists(const char *name);
int32_t sw_cloud_file_size(const char *name);
int32_t sw_cloud_read(const char *name, void *buffer, int32_t capacity);
uint8_t sw_cloud_write(const char *name, const void *buffer, int32_t size);
uint64_t sw_cloud_write_async(const char *name, const void *buffer, uint32_t size);
uint8_t sw_cloud_delete(const char *name);
uint8_t sw_cloud_quota(uint64_t *total, uint64_t *available);
int32_t sw_cloud_file_count(void);
const char *sw_cloud_file_at(int32_t index, int32_t *size);

/* Count preserves signed native failure; return 0 means unavailable interface. */
uint8_t sw_cloud_local_change_count(int32_t *count);
enum sw_cloud_change_status {
    SW_CLOUD_CHANGE_OK, SW_CLOUD_CHANGE_UNAVAILABLE, SW_CLOUD_CHANGE_COUNT_FAILED,
    SW_CLOUD_CHANGE_INVALID_INDEX, SW_CLOUD_CHANGE_NULL_PATH, SW_CLOUD_CHANGE_SHORT_BUFFER
};
/* Copies immediately, without NUL or truncation. Metadata/length exist for OK/SHORT_BUFFER. */
typedef struct sw_cloud_local_change {
    size_t path_length;
    int32_t change;
    int32_t path_type;
} sw_cloud_local_change;
uint8_t sw_cloud_local_change_copy(int32_t index, char *buffer, size_t capacity, sw_cloud_local_change *out);
/* -1: unavailable (no native call), 0/1: native false/true. */
int32_t sw_cloud_begin_write_batch(void);
int32_t sw_cloud_end_write_batch(void);
#ifdef __cplusplus
}
#endif
#endif
