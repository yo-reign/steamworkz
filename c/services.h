#ifndef MEIKYUU_STEAMWORKS_SERVICES_H
#define MEIKYUU_STEAMWORKS_SERVICES_H
#include "types.h"
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
#ifdef __cplusplus
}
#endif
#endif
