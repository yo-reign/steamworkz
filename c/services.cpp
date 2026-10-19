#include "services.h"
#include <steam/steam_api_flat.h>
#include <string.h>

const char *sw_persona_name(void) { return SteamAPI_ISteamFriends_GetPersonaName(SteamAPI_SteamFriends()); }
int32_t sw_friend_count(void) { return SteamAPI_ISteamFriends_GetFriendCount(SteamAPI_SteamFriends(), k_EFriendFlagImmediate); }
uint64_t sw_friend_at(int32_t index) { return SteamAPI_ISteamFriends_GetFriendByIndex(SteamAPI_SteamFriends(), index, k_EFriendFlagImmediate); }
const char *sw_friend_name(uint64_t user) { return SteamAPI_ISteamFriends_GetFriendPersonaName(SteamAPI_SteamFriends(), user); }
int32_t sw_friend_state(uint64_t user) {
    const EPersonaState state = SteamAPI_ISteamFriends_GetFriendPersonaState(SteamAPI_SteamFriends(), user);
    int32_t value; static_assert(sizeof(state) == sizeof(value), "Persona state width changed");
    memcpy(&value, &state, sizeof(value)); return value;
}
uint8_t sw_request_user(uint64_t user, uint8_t name_only) { return SteamAPI_ISteamFriends_RequestUserInformation(SteamAPI_SteamFriends(), user, name_only != 0); }
uint8_t sw_set_presence(const char *key, const char *value) { return SteamAPI_ISteamFriends_SetRichPresence(SteamAPI_SteamFriends(), key, value); }
void sw_clear_presence(void) { SteamAPI_ISteamFriends_ClearRichPresence(SteamAPI_SteamFriends()); }
const char *sw_friend_presence(uint64_t user, const char *key) { return SteamAPI_ISteamFriends_GetFriendRichPresence(SteamAPI_SteamFriends(), user, key); }
void sw_request_presence(uint64_t user) { SteamAPI_ISteamFriends_RequestFriendRichPresence(SteamAPI_SteamFriends(), user); }
uint8_t sw_invite_game(uint64_t user, const char *connect) { return SteamAPI_ISteamFriends_InviteUserToGame(SteamAPI_SteamFriends(), user, connect); }
void sw_open_overlay(const char *dialog) { SteamAPI_ISteamFriends_ActivateGameOverlay(SteamAPI_SteamFriends(), dialog); }
void sw_open_store(uint32_t app) { SteamAPI_ISteamFriends_ActivateGameOverlayToStore(SteamAPI_SteamFriends(), app, k_EOverlayToStoreFlag_None); }
void sw_open_invite(uint64_t lobby) { SteamAPI_ISteamFriends_ActivateGameOverlayInviteDialog(SteamAPI_SteamFriends(), lobby); }
int32_t sw_avatar(uint64_t user, int32_t size) {
    switch (size) {
        case 0: return SteamAPI_ISteamFriends_GetSmallFriendAvatar(SteamAPI_SteamFriends(), user);
        case 1: return SteamAPI_ISteamFriends_GetMediumFriendAvatar(SteamAPI_SteamFriends(), user);
        case 2: return SteamAPI_ISteamFriends_GetLargeFriendAvatar(SteamAPI_SteamFriends(), user);
        default: return 0;
    }
}
uint8_t sw_image_size(int32_t image, uint32_t *width, uint32_t *height) { return SteamAPI_ISteamUtils_GetImageSize(SteamAPI_SteamUtils(), image, width, height); }
uint8_t sw_image_rgba(int32_t image, uint8_t *buffer, int32_t size) { return SteamAPI_ISteamUtils_GetImageRGBA(SteamAPI_SteamUtils(), image, buffer, size); }

uint8_t sw_subscribed(void) { return SteamAPI_ISteamApps_BIsSubscribed(SteamAPI_SteamApps()); }
uint8_t sw_owns_app(uint32_t app) { return SteamAPI_ISteamApps_BIsSubscribedApp(SteamAPI_SteamApps(), app); }
uint8_t sw_app_installed(uint32_t app) { return SteamAPI_ISteamApps_BIsAppInstalled(SteamAPI_SteamApps(), app); }
uint8_t sw_dlc_installed(uint32_t app) { return SteamAPI_ISteamApps_BIsDlcInstalled(SteamAPI_SteamApps(), app); }
int32_t sw_dlc_count(void) { return SteamAPI_ISteamApps_GetDLCCount(SteamAPI_SteamApps()); }
uint8_t sw_dlc_data(int32_t index, uint32_t *app, uint8_t *available, char *name, int32_t capacity) {
    bool owned = false;
    const bool ok = SteamAPI_ISteamApps_BGetDLCDataByIndex(SteamAPI_SteamApps(), index, app, &owned, name, capacity);
    *available = owned; return ok;
}
uint8_t sw_dlc_progress(uint32_t app, uint64_t *downloaded, uint64_t *total) {
    uint64 native_downloaded = 0, native_total = 0;
    const bool ok = SteamAPI_ISteamApps_GetDlcDownloadProgress(SteamAPI_SteamApps(), app, &native_downloaded, &native_total);
    *downloaded = native_downloaded; *total = native_total; return ok;
}
const char *sw_game_language(void) { return SteamAPI_ISteamApps_GetCurrentGameLanguage(SteamAPI_SteamApps()); }
const char *sw_available_languages(void) { return SteamAPI_ISteamApps_GetAvailableGameLanguages(SteamAPI_SteamApps()); }
uint64_t sw_app_owner(void) { return SteamAPI_ISteamApps_GetAppOwner(SteamAPI_SteamApps()); }
int32_t sw_build_id(void) { return SteamAPI_ISteamApps_GetAppBuildId(SteamAPI_SteamApps()); }
int32_t sw_launch_command_line(char *buffer, int32_t capacity) { return SteamAPI_ISteamApps_GetLaunchCommandLine(SteamAPI_SteamApps(), buffer, capacity); }

uint8_t sw_stat_int(const char *name, int32_t *value) { return SteamAPI_ISteamUserStats_GetStatInt32(SteamAPI_SteamUserStats(), name, value); }
uint8_t sw_stat_float(const char *name, float *value) { return SteamAPI_ISteamUserStats_GetStatFloat(SteamAPI_SteamUserStats(), name, value); }
uint8_t sw_set_stat_int(const char *name, int32_t value) { return SteamAPI_ISteamUserStats_SetStatInt32(SteamAPI_SteamUserStats(), name, value); }
uint8_t sw_set_stat_float(const char *name, float value) { return SteamAPI_ISteamUserStats_SetStatFloat(SteamAPI_SteamUserStats(), name, value); }
uint8_t sw_achievement(const char *name, uint8_t *unlocked, uint32_t *time) {
    bool native_unlocked = false;
    const bool ok = SteamAPI_ISteamUserStats_GetAchievementAndUnlockTime(SteamAPI_SteamUserStats(), name, &native_unlocked, time);
    *unlocked = native_unlocked; return ok;
}
uint8_t sw_unlock_achievement(const char *name) { return SteamAPI_ISteamUserStats_SetAchievement(SteamAPI_SteamUserStats(), name); }
uint8_t sw_clear_achievement(const char *name) { return SteamAPI_ISteamUserStats_ClearAchievement(SteamAPI_SteamUserStats(), name); }
uint8_t sw_achievement_progress(const char *name, uint32_t current, uint32_t maximum) { return SteamAPI_ISteamUserStats_IndicateAchievementProgress(SteamAPI_SteamUserStats(), name, current, maximum); }
uint32_t sw_achievement_count(void) { return SteamAPI_ISteamUserStats_GetNumAchievements(SteamAPI_SteamUserStats()); }
const char *sw_achievement_name(uint32_t index) { return SteamAPI_ISteamUserStats_GetAchievementName(SteamAPI_SteamUserStats(), index); }
const char *sw_achievement_attribute(const char *name, const char *key) { return SteamAPI_ISteamUserStats_GetAchievementDisplayAttribute(SteamAPI_SteamUserStats(), name, key); }
uint8_t sw_store_stats(void) { return SteamAPI_ISteamUserStats_StoreStats(SteamAPI_SteamUserStats()); }
uint64_t sw_request_user_stats(uint64_t user) { return SteamAPI_ISteamUserStats_RequestUserStats(SteamAPI_SteamUserStats(), user); }
uint8_t sw_user_stat_int(uint64_t user, const char *name, int32_t *value) { return SteamAPI_ISteamUserStats_GetUserStatInt32(SteamAPI_SteamUserStats(), user, name, value); }
uint8_t sw_user_stat_float(uint64_t user, const char *name, float *value) { return SteamAPI_ISteamUserStats_GetUserStatFloat(SteamAPI_SteamUserStats(), user, name, value); }
uint8_t sw_user_achievement(uint64_t user, const char *name, uint8_t *unlocked, uint32_t *time) {
    bool native_unlocked = false;
    const bool ok = SteamAPI_ISteamUserStats_GetUserAchievementAndUnlockTime(SteamAPI_SteamUserStats(), user, name, &native_unlocked, time);
    *unlocked = native_unlocked; return ok;
}

uint8_t sw_cloud_account_enabled(void) { return SteamAPI_ISteamRemoteStorage_IsCloudEnabledForAccount(SteamAPI_SteamRemoteStorage()); }
uint8_t sw_cloud_app_enabled(void) { return SteamAPI_ISteamRemoteStorage_IsCloudEnabledForApp(SteamAPI_SteamRemoteStorage()); }
uint8_t sw_cloud_exists(const char *name) { return SteamAPI_ISteamRemoteStorage_FileExists(SteamAPI_SteamRemoteStorage(), name); }
int32_t sw_cloud_file_size(const char *name) { return SteamAPI_ISteamRemoteStorage_GetFileSize(SteamAPI_SteamRemoteStorage(), name); }
int32_t sw_cloud_read(const char *name, void *buffer, int32_t capacity) { return SteamAPI_ISteamRemoteStorage_FileRead(SteamAPI_SteamRemoteStorage(), name, buffer, capacity); }
uint8_t sw_cloud_write(const char *name, const void *buffer, int32_t size) { return SteamAPI_ISteamRemoteStorage_FileWrite(SteamAPI_SteamRemoteStorage(), name, buffer, size); }
uint64_t sw_cloud_write_async(const char *name, const void *buffer, uint32_t size) { return SteamAPI_ISteamRemoteStorage_FileWriteAsync(SteamAPI_SteamRemoteStorage(), name, buffer, size); }
uint8_t sw_cloud_delete(const char *name) { return SteamAPI_ISteamRemoteStorage_FileDelete(SteamAPI_SteamRemoteStorage(), name); }
uint8_t sw_cloud_quota(uint64_t *total, uint64_t *available) {
    uint64 native_total = 0, native_available = 0;
    const bool ok = SteamAPI_ISteamRemoteStorage_GetQuota(SteamAPI_SteamRemoteStorage(), &native_total, &native_available);
    *total = native_total; *available = native_available; return ok;
}
int32_t sw_cloud_file_count(void) { return SteamAPI_ISteamRemoteStorage_GetFileCount(SteamAPI_SteamRemoteStorage()); }
const char *sw_cloud_file_at(int32_t index, int32_t *size) { return SteamAPI_ISteamRemoteStorage_GetFileNameAndSize(SteamAPI_SteamRemoteStorage(), index, size); }
