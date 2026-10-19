#include "services.h"
#include <steam/steam_api_flat.h>
#include <string.h>

#ifdef SW_SERVICES_TEST
#include <stdio.h>
#include <stdlib.h>

// No SDK symbols are defined or interposed. The official declarations above
// type-check these file-local substitutes, including Windows flat API types.
#define CHECK(condition) do { if (!(condition)) { fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition); abort(); } } while (0)
#define STUB(result, name, args) static decltype(SteamAPI_##name) name; static result name args
namespace services_test {
static char friends_token, utils_token, apps_token, stats_token, cloud_token;
static ISteamFriends *const friends = reinterpret_cast<ISteamFriends *>(&friends_token);
static ISteamUtils *const utils = reinterpret_cast<ISteamUtils *>(&utils_token);
static ISteamApps *const apps = reinterpret_cast<ISteamApps *>(&apps_token);
static ISteamUserStats *const stats = reinterpret_cast<ISteamUserStats *>(&stats_token);
static ISteamRemoteStorage *const cloud = reinterpret_cast<ISteamRemoteStorage *>(&cloud_token);
static unsigned calls, accessors;
static const char *last_call;
#define OBSERVE(interface) do { CHECK(self == interface); ++calls; last_call = __func__; } while (0)
static constexpr uint64_steamid user = 0xfedcba9876543210ULL;
static constexpr AppId_t app = 0xf1234567U;
static constexpr uint64 large_total = 0xf123456789abcdefULL;
static constexpr uint64 large_part = 0x123456789abcdef0ULL;
static SteamAPICall_t call = 0xe123456789abcdefULL;
static const char key[] = "fixture-key";
static const char text[] = "fixture value";
static const char *presence_value;
static const char *returned_text = text;
static constexpr bool booleans[] = { false, true };
static constexpr uint8 name_only_inputs[] = { 0, 1, 255 };
static constexpr int avatar_results[] = { -1, 0, 37 };
static bool ok = true, output_bool = true, name_only;
static int avatar_result;
static int32 persona_bits;
static constexpr int32 signed_value = -123456789;
static constexpr float float_value = -123.625f;
static constexpr uint32 unlock_time = 0xfedcba98U;
static void *output_buffer;
static const void *input_buffer;
static int capacity;
static uint32 *width_output, *height_output, *app_output, *time_output;
static int32 *int_output;
static float *float_output;
static const uint8 binary[] = { 0x41, 0, 0xff, 0x7f, 0x42 };

STUB(ISteamFriends *, SteamFriends, ()) { ++accessors; return friends; }
STUB(ISteamUtils *, SteamUtils, ()) { ++accessors; return utils; }
STUB(ISteamApps *, SteamApps, ()) { ++accessors; return apps; }
STUB(ISteamUserStats *, SteamUserStats, ()) { ++accessors; return stats; }
STUB(ISteamRemoteStorage *, SteamRemoteStorage, ()) { ++accessors; return cloud; }

STUB(const char *, ISteamFriends_GetPersonaName, (ISteamFriends *self)) { OBSERVE(friends); return returned_text; }
STUB(int, ISteamFriends_GetFriendCount, (ISteamFriends *self, int flags)) { OBSERVE(friends); CHECK(flags == k_EFriendFlagImmediate); return 3; }
STUB(uint64_steamid, ISteamFriends_GetFriendByIndex, (ISteamFriends *self, int index, int flags)) { OBSERVE(friends); CHECK(index == 2 && flags == k_EFriendFlagImmediate); return user; }
STUB(const char *, ISteamFriends_GetFriendPersonaName, (ISteamFriends *self, uint64_steamid id)) { OBSERVE(friends); CHECK(id == user); return returned_text; }
STUB(EPersonaState, ISteamFriends_GetFriendPersonaState, (ISteamFriends *self, uint64_steamid id)) {
    OBSERVE(friends); CHECK(id == user);
    EPersonaState state; static_assert(sizeof(state) == sizeof(persona_bits), "Persona state width changed");
    memcpy(&state, &persona_bits, sizeof(state)); return state;
}
STUB(bool, ISteamFriends_RequestUserInformation, (ISteamFriends *self, uint64_steamid id, bool only)) { OBSERVE(friends); CHECK(id == user && only == name_only); return ok; }
STUB(bool, ISteamFriends_SetRichPresence, (ISteamFriends *self, const char *k, const char *value)) { OBSERVE(friends); CHECK(k == key && value == presence_value); return ok; }
STUB(void, ISteamFriends_ClearRichPresence, (ISteamFriends *self)) { OBSERVE(friends); }
STUB(const char *, ISteamFriends_GetFriendRichPresence, (ISteamFriends *self, uint64_steamid id, const char *k)) { OBSERVE(friends); CHECK(id == user && k == key); return returned_text; }
STUB(void, ISteamFriends_RequestFriendRichPresence, (ISteamFriends *self, uint64_steamid id)) { OBSERVE(friends); CHECK(id == user); }
STUB(bool, ISteamFriends_InviteUserToGame, (ISteamFriends *self, uint64_steamid id, const char *connect)) { OBSERVE(friends); CHECK(id == user && connect == text); return ok; }
STUB(void, ISteamFriends_ActivateGameOverlay, (ISteamFriends *self, const char *dialog)) { OBSERVE(friends); CHECK(dialog == text); }
STUB(void, ISteamFriends_ActivateGameOverlayToStore, (ISteamFriends *self, AppId_t id, EOverlayToStoreFlag flag)) { OBSERVE(friends); CHECK(id == app && flag == k_EOverlayToStoreFlag_None); }
STUB(void, ISteamFriends_ActivateGameOverlayInviteDialog, (ISteamFriends *self, uint64_steamid id)) { OBSERVE(friends); CHECK(id == user); }
STUB(int, ISteamFriends_GetSmallFriendAvatar, (ISteamFriends *self, uint64_steamid id)) { OBSERVE(friends); CHECK(id == user); return avatar_result; }
STUB(int, ISteamFriends_GetMediumFriendAvatar, (ISteamFriends *self, uint64_steamid id)) { OBSERVE(friends); CHECK(id == user); return avatar_result; }
STUB(int, ISteamFriends_GetLargeFriendAvatar, (ISteamFriends *self, uint64_steamid id)) { OBSERVE(friends); CHECK(id == user); return avatar_result; }
STUB(bool, ISteamUtils_GetImageSize, (ISteamUtils *self, int image, uint32 *width, uint32 *height)) {
    OBSERVE(utils); CHECK(image == 37 && width == width_output && height == height_output);
    if (ok) { *width = 2; *height = 3; } return ok;
}
STUB(bool, ISteamUtils_GetImageRGBA, (ISteamUtils *self, int image, uint8 *buffer, int size)) {
    OBSERVE(utils); CHECK(image == 37 && buffer == output_buffer && size == capacity);
    if (ok) { CHECK(size == 24); for (int i = 0; i < size; ++i) buffer[i] = static_cast<uint8>(i * 7); } return ok;
}

STUB(bool, ISteamApps_BIsSubscribed, (ISteamApps *self)) { OBSERVE(apps); return ok; }
STUB(bool, ISteamApps_BIsSubscribedApp, (ISteamApps *self, AppId_t id)) { OBSERVE(apps); CHECK(id == app); return ok; }
STUB(bool, ISteamApps_BIsAppInstalled, (ISteamApps *self, AppId_t id)) { OBSERVE(apps); CHECK(id == app); return ok; }
STUB(bool, ISteamApps_BIsDlcInstalled, (ISteamApps *self, AppId_t id)) { OBSERVE(apps); CHECK(id == app); return ok; }
STUB(int, ISteamApps_GetDLCCount, (ISteamApps *self)) { OBSERVE(apps); return 4; }
STUB(bool, ISteamApps_BGetDLCDataByIndex, (ISteamApps *self, int index, AppId_t *id, bool *available, char *name, int size)) {
    OBSERVE(apps); CHECK(index == 2 && id == app_output && available != nullptr && name == output_buffer && size == capacity);
    if (ok) { CHECK(size >= static_cast<int>(sizeof(text))); *id = app; *available = output_bool; memcpy(name, text, sizeof(text)); } return ok;
}
STUB(bool, ISteamApps_GetDlcDownloadProgress, (ISteamApps *self, AppId_t id, uint64 *downloaded, uint64 *total)) {
    OBSERVE(apps); CHECK(id == app && downloaded != nullptr && total != nullptr && downloaded != total);
    if (ok) { *downloaded = large_part; *total = large_total; } return ok;
}
STUB(const char *, ISteamApps_GetCurrentGameLanguage, (ISteamApps *self)) { OBSERVE(apps); return returned_text; }
STUB(const char *, ISteamApps_GetAvailableGameLanguages, (ISteamApps *self)) { OBSERVE(apps); return returned_text; }
STUB(uint64_steamid, ISteamApps_GetAppOwner, (ISteamApps *self)) { OBSERVE(apps); return user; }
STUB(int, ISteamApps_GetAppBuildId, (ISteamApps *self)) { OBSERVE(apps); return signed_value; }
STUB(int, ISteamApps_GetLaunchCommandLine, (ISteamApps *self, char *buffer, int size)) {
    OBSERVE(apps); CHECK(buffer == output_buffer && size == capacity && size >= static_cast<int>(sizeof(text)));
    memcpy(buffer, text, sizeof(text)); return sizeof(text) - 1;
}

STUB(bool, ISteamUserStats_GetStatInt32, (ISteamUserStats *self, const char *name, int32 *value)) { OBSERVE(stats); CHECK(name == key && value == int_output); if (ok) *value = signed_value; return ok; }
STUB(bool, ISteamUserStats_GetStatFloat, (ISteamUserStats *self, const char *name, float *value)) { OBSERVE(stats); CHECK(name == key && value == float_output); if (ok) *value = float_value; return ok; }
STUB(bool, ISteamUserStats_SetStatInt32, (ISteamUserStats *self, const char *name, int32 value)) { OBSERVE(stats); CHECK(name == key && value == signed_value); return ok; }
STUB(bool, ISteamUserStats_SetStatFloat, (ISteamUserStats *self, const char *name, float value)) { OBSERVE(stats); CHECK(name == key && value == float_value); return ok; }
STUB(bool, ISteamUserStats_GetAchievementAndUnlockTime, (ISteamUserStats *self, const char *name, bool *unlocked, uint32 *time)) {
    OBSERVE(stats); CHECK(name == key && unlocked != nullptr && time == time_output);
    if (ok) { *unlocked = output_bool; *time = unlock_time; } return ok;
}
STUB(bool, ISteamUserStats_SetAchievement, (ISteamUserStats *self, const char *name)) { OBSERVE(stats); CHECK(name == key); return ok; }
STUB(bool, ISteamUserStats_ClearAchievement, (ISteamUserStats *self, const char *name)) { OBSERVE(stats); CHECK(name == key); return ok; }
STUB(bool, ISteamUserStats_IndicateAchievementProgress, (ISteamUserStats *self, const char *name, uint32 current, uint32 maximum)) { OBSERVE(stats); CHECK(name == key && current == 0x87654321U && maximum == 0xfedcba98U); return ok; }
STUB(uint32, ISteamUserStats_GetNumAchievements, (ISteamUserStats *self)) { OBSERVE(stats); return 7; }
STUB(const char *, ISteamUserStats_GetAchievementName, (ISteamUserStats *self, uint32 index)) { OBSERVE(stats); CHECK(index == 6); return returned_text; }
STUB(const char *, ISteamUserStats_GetAchievementDisplayAttribute, (ISteamUserStats *self, const char *name, const char *attribute)) { OBSERVE(stats); CHECK(name == key && attribute == text); return returned_text; }
STUB(bool, ISteamUserStats_StoreStats, (ISteamUserStats *self)) { OBSERVE(stats); return ok; }
STUB(SteamAPICall_t, ISteamUserStats_RequestUserStats, (ISteamUserStats *self, uint64_steamid id)) { OBSERVE(stats); CHECK(id == user); return call; }
STUB(bool, ISteamUserStats_GetUserStatInt32, (ISteamUserStats *self, uint64_steamid id, const char *name, int32 *value)) { OBSERVE(stats); CHECK(id == user && name == key && value == int_output); if (ok) *value = signed_value; return ok; }
STUB(bool, ISteamUserStats_GetUserStatFloat, (ISteamUserStats *self, uint64_steamid id, const char *name, float *value)) { OBSERVE(stats); CHECK(id == user && name == key && value == float_output); if (ok) *value = float_value; return ok; }
STUB(bool, ISteamUserStats_GetUserAchievementAndUnlockTime, (ISteamUserStats *self, uint64_steamid id, const char *name, bool *unlocked, uint32 *time)) {
    OBSERVE(stats); CHECK(id == user && name == key && unlocked != nullptr && time == time_output);
    if (ok) { *unlocked = output_bool; *time = unlock_time; } return ok;
}

STUB(bool, ISteamRemoteStorage_IsCloudEnabledForAccount, (ISteamRemoteStorage *self)) { OBSERVE(cloud); return ok; }
STUB(bool, ISteamRemoteStorage_IsCloudEnabledForApp, (ISteamRemoteStorage *self)) { OBSERVE(cloud); return ok; }
STUB(bool, ISteamRemoteStorage_FileExists, (ISteamRemoteStorage *self, const char *name)) { OBSERVE(cloud); CHECK(name == key); return ok; }
STUB(int32, ISteamRemoteStorage_GetFileSize, (ISteamRemoteStorage *self, const char *name)) { OBSERVE(cloud); CHECK(name == key); return sizeof(binary); }
STUB(int32, ISteamRemoteStorage_FileRead, (ISteamRemoteStorage *self, const char *name, void *buffer, int32 size)) {
    OBSERVE(cloud); CHECK(name == key && buffer == output_buffer && size == capacity && size >= 0);
    if (!ok) return 0;
    const int32 copied = size < static_cast<int32>(sizeof(binary)) ? size : sizeof(binary);
    memcpy(buffer, binary, copied); return copied;
}
STUB(bool, ISteamRemoteStorage_FileWrite, (ISteamRemoteStorage *self, const char *name, const void *buffer, int32 size)) {
    OBSERVE(cloud); CHECK(name == key && buffer == input_buffer && size == static_cast<int32>(sizeof(binary)) && memcmp(buffer, binary, size) == 0); return ok;
}
STUB(SteamAPICall_t, ISteamRemoteStorage_FileWriteAsync, (ISteamRemoteStorage *self, const char *name, const void *buffer, uint32 size)) {
    OBSERVE(cloud); CHECK(name == key && buffer == input_buffer && size == sizeof(binary) && memcmp(buffer, binary, size) == 0); return call;
}
STUB(bool, ISteamRemoteStorage_FileDelete, (ISteamRemoteStorage *self, const char *name)) { OBSERVE(cloud); CHECK(name == key); return ok; }
STUB(bool, ISteamRemoteStorage_GetQuota, (ISteamRemoteStorage *self, uint64 *total, uint64 *available)) {
    OBSERVE(cloud); CHECK(total != nullptr && available != nullptr && total != available);
    if (ok) { *total = large_total; *available = large_part; } return ok;
}
STUB(int32, ISteamRemoteStorage_GetFileCount, (ISteamRemoteStorage *self)) { OBSERVE(cloud); return 3; }
STUB(const char *, ISteamRemoteStorage_GetFileNameAndSize, (ISteamRemoteStorage *self, int index, int32 *size)) {
    OBSERVE(cloud); CHECK(index == 2 && size == int_output);
    if (ok) *size = sizeof(binary); return ok ? returned_text : nullptr;
}
#undef OBSERVE
#undef STUB
} // namespace services_test

// Substitution starts only after parsing official headers and type-checking all
// local functions. Tokens stand in for opaque interfaces and are never read.
#define SteamAPI_SteamFriends services_test::SteamFriends
#define SteamAPI_SteamUtils services_test::SteamUtils
#define SteamAPI_SteamApps services_test::SteamApps
#define SteamAPI_SteamUserStats services_test::SteamUserStats
#define SteamAPI_SteamRemoteStorage services_test::SteamRemoteStorage
#define SteamAPI_ISteamFriends_GetPersonaName services_test::ISteamFriends_GetPersonaName
#define SteamAPI_ISteamFriends_GetFriendCount services_test::ISteamFriends_GetFriendCount
#define SteamAPI_ISteamFriends_GetFriendByIndex services_test::ISteamFriends_GetFriendByIndex
#define SteamAPI_ISteamFriends_GetFriendPersonaName services_test::ISteamFriends_GetFriendPersonaName
#define SteamAPI_ISteamFriends_GetFriendPersonaState services_test::ISteamFriends_GetFriendPersonaState
#define SteamAPI_ISteamFriends_RequestUserInformation services_test::ISteamFriends_RequestUserInformation
#define SteamAPI_ISteamFriends_SetRichPresence services_test::ISteamFriends_SetRichPresence
#define SteamAPI_ISteamFriends_ClearRichPresence services_test::ISteamFriends_ClearRichPresence
#define SteamAPI_ISteamFriends_GetFriendRichPresence services_test::ISteamFriends_GetFriendRichPresence
#define SteamAPI_ISteamFriends_RequestFriendRichPresence services_test::ISteamFriends_RequestFriendRichPresence
#define SteamAPI_ISteamFriends_InviteUserToGame services_test::ISteamFriends_InviteUserToGame
#define SteamAPI_ISteamFriends_ActivateGameOverlay services_test::ISteamFriends_ActivateGameOverlay
#define SteamAPI_ISteamFriends_ActivateGameOverlayToStore services_test::ISteamFriends_ActivateGameOverlayToStore
#define SteamAPI_ISteamFriends_ActivateGameOverlayInviteDialog services_test::ISteamFriends_ActivateGameOverlayInviteDialog
#define SteamAPI_ISteamFriends_GetSmallFriendAvatar services_test::ISteamFriends_GetSmallFriendAvatar
#define SteamAPI_ISteamFriends_GetMediumFriendAvatar services_test::ISteamFriends_GetMediumFriendAvatar
#define SteamAPI_ISteamFriends_GetLargeFriendAvatar services_test::ISteamFriends_GetLargeFriendAvatar
#define SteamAPI_ISteamUtils_GetImageSize services_test::ISteamUtils_GetImageSize
#define SteamAPI_ISteamUtils_GetImageRGBA services_test::ISteamUtils_GetImageRGBA
#define SteamAPI_ISteamApps_BIsSubscribed services_test::ISteamApps_BIsSubscribed
#define SteamAPI_ISteamApps_BIsSubscribedApp services_test::ISteamApps_BIsSubscribedApp
#define SteamAPI_ISteamApps_BIsAppInstalled services_test::ISteamApps_BIsAppInstalled
#define SteamAPI_ISteamApps_BIsDlcInstalled services_test::ISteamApps_BIsDlcInstalled
#define SteamAPI_ISteamApps_GetDLCCount services_test::ISteamApps_GetDLCCount
#define SteamAPI_ISteamApps_BGetDLCDataByIndex services_test::ISteamApps_BGetDLCDataByIndex
#define SteamAPI_ISteamApps_GetDlcDownloadProgress services_test::ISteamApps_GetDlcDownloadProgress
#define SteamAPI_ISteamApps_GetCurrentGameLanguage services_test::ISteamApps_GetCurrentGameLanguage
#define SteamAPI_ISteamApps_GetAvailableGameLanguages services_test::ISteamApps_GetAvailableGameLanguages
#define SteamAPI_ISteamApps_GetAppOwner services_test::ISteamApps_GetAppOwner
#define SteamAPI_ISteamApps_GetAppBuildId services_test::ISteamApps_GetAppBuildId
#define SteamAPI_ISteamApps_GetLaunchCommandLine services_test::ISteamApps_GetLaunchCommandLine
#define SteamAPI_ISteamUserStats_GetStatInt32 services_test::ISteamUserStats_GetStatInt32
#define SteamAPI_ISteamUserStats_GetStatFloat services_test::ISteamUserStats_GetStatFloat
#define SteamAPI_ISteamUserStats_SetStatInt32 services_test::ISteamUserStats_SetStatInt32
#define SteamAPI_ISteamUserStats_SetStatFloat services_test::ISteamUserStats_SetStatFloat
#define SteamAPI_ISteamUserStats_GetAchievementAndUnlockTime services_test::ISteamUserStats_GetAchievementAndUnlockTime
#define SteamAPI_ISteamUserStats_SetAchievement services_test::ISteamUserStats_SetAchievement
#define SteamAPI_ISteamUserStats_ClearAchievement services_test::ISteamUserStats_ClearAchievement
#define SteamAPI_ISteamUserStats_IndicateAchievementProgress services_test::ISteamUserStats_IndicateAchievementProgress
#define SteamAPI_ISteamUserStats_GetNumAchievements services_test::ISteamUserStats_GetNumAchievements
#define SteamAPI_ISteamUserStats_GetAchievementName services_test::ISteamUserStats_GetAchievementName
#define SteamAPI_ISteamUserStats_GetAchievementDisplayAttribute services_test::ISteamUserStats_GetAchievementDisplayAttribute
#define SteamAPI_ISteamUserStats_StoreStats services_test::ISteamUserStats_StoreStats
#define SteamAPI_ISteamUserStats_RequestUserStats services_test::ISteamUserStats_RequestUserStats
#define SteamAPI_ISteamUserStats_GetUserStatInt32 services_test::ISteamUserStats_GetUserStatInt32
#define SteamAPI_ISteamUserStats_GetUserStatFloat services_test::ISteamUserStats_GetUserStatFloat
#define SteamAPI_ISteamUserStats_GetUserAchievementAndUnlockTime services_test::ISteamUserStats_GetUserAchievementAndUnlockTime
#define SteamAPI_ISteamRemoteStorage_IsCloudEnabledForAccount services_test::ISteamRemoteStorage_IsCloudEnabledForAccount
#define SteamAPI_ISteamRemoteStorage_IsCloudEnabledForApp services_test::ISteamRemoteStorage_IsCloudEnabledForApp
#define SteamAPI_ISteamRemoteStorage_FileExists services_test::ISteamRemoteStorage_FileExists
#define SteamAPI_ISteamRemoteStorage_GetFileSize services_test::ISteamRemoteStorage_GetFileSize
#define SteamAPI_ISteamRemoteStorage_FileRead services_test::ISteamRemoteStorage_FileRead
#define SteamAPI_ISteamRemoteStorage_FileWrite services_test::ISteamRemoteStorage_FileWrite
#define SteamAPI_ISteamRemoteStorage_FileWriteAsync services_test::ISteamRemoteStorage_FileWriteAsync
#define SteamAPI_ISteamRemoteStorage_FileDelete services_test::ISteamRemoteStorage_FileDelete
#define SteamAPI_ISteamRemoteStorage_GetQuota services_test::ISteamRemoteStorage_GetQuota
#define SteamAPI_ISteamRemoteStorage_GetFileCount services_test::ISteamRemoteStorage_GetFileCount
#define SteamAPI_ISteamRemoteStorage_GetFileNameAndSize services_test::ISteamRemoteStorage_GetFileNameAndSize
#endif


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

#ifdef SW_SERVICES_TEST
namespace services_test {
static void called(const char *name) {
    CHECK(calls == 1 && accessors == 1);
    CHECK(last_call != nullptr && strcmp(last_call, name) == 0);
    calls = accessors = 0;
    last_call = nullptr;
}
#define EXPECT(entry, condition) do { CHECK(condition); called(#entry); } while (0)

static void test_friends() {
    EXPECT(ISteamFriends_GetPersonaName, sw_persona_name() == text);
    EXPECT(ISteamFriends_GetFriendCount, sw_friend_count() == 3);
    EXPECT(ISteamFriends_GetFriendByIndex, sw_friend_at(2) == user);
    EXPECT(ISteamFriends_GetFriendPersonaName, sw_friend_name(user) == text);
    // SDK 1.65's unfixed enum has enumerators 0..8, hence valid values 0..15.
    // Unknown values must remain in that range even when populated via memcpy.
    const int32 states[] = { k_EPersonaStateBusy, 9, 15 };
    for (const int32 bits : states) {
        persona_bits = bits;
        EXPECT(ISteamFriends_GetFriendPersonaState, sw_friend_state(user) == bits);
    }
    for (const bool result : booleans) {
        ok = result;
        for (const uint8 input : name_only_inputs) {
            name_only = input != 0;
            EXPECT(ISteamFriends_RequestUserInformation, sw_request_user(user, input) == result);
        }
        presence_value = text;
        EXPECT(ISteamFriends_SetRichPresence, sw_set_presence(key, text) == result);
        presence_value = nullptr;
        EXPECT(ISteamFriends_SetRichPresence, sw_set_presence(key, nullptr) == result);
        EXPECT(ISteamFriends_InviteUserToGame, sw_invite_game(user, text) == result);
    }
    ok = true;
    EXPECT(ISteamFriends_GetFriendRichPresence, sw_friend_presence(user, key) == text);
    returned_text = nullptr;
    EXPECT(ISteamFriends_GetPersonaName, sw_persona_name() == nullptr);
    EXPECT(ISteamFriends_GetFriendPersonaName, sw_friend_name(user) == nullptr);
    EXPECT(ISteamFriends_GetFriendRichPresence, sw_friend_presence(user, key) == nullptr);
    returned_text = text;
    sw_clear_presence(); called("ISteamFriends_ClearRichPresence");
    sw_request_presence(user); called("ISteamFriends_RequestFriendRichPresence");
    sw_open_overlay(text); called("ISteamFriends_ActivateGameOverlay");
    sw_open_store(app); called("ISteamFriends_ActivateGameOverlayToStore");
    sw_open_invite(user); called("ISteamFriends_ActivateGameOverlayInviteDialog");
    for (const int result : avatar_results) {
        avatar_result = result;
        EXPECT(ISteamFriends_GetSmallFriendAvatar, sw_avatar(user, 0) == result);
        EXPECT(ISteamFriends_GetMediumFriendAvatar, sw_avatar(user, 1) == result);
        EXPECT(ISteamFriends_GetLargeFriendAvatar, sw_avatar(user, 2) == result);
    }
    CHECK(sw_avatar(user, -1) == 0 && sw_avatar(user, 3) == 0);
    CHECK(calls == 0 && accessors == 0);
}

static void test_images() {
    uint32_t width = 0, height = 0;
    width_output = &width; height_output = &height;
    EXPECT(ISteamUtils_GetImageSize, sw_image_size(37, &width, &height) == 1);
    CHECK(width == 2 && height == 3);
    uint8 pixels[26]; memset(pixels, 0xa5, sizeof(pixels));
    output_buffer = pixels + 1; capacity = 24;
    EXPECT(ISteamUtils_GetImageRGBA, sw_image_rgba(37, pixels + 1, capacity) == 1);
    for (int i = 0; i < capacity; ++i) CHECK(pixels[i + 1] == i * 7);
    CHECK(pixels[0] == 0xa5 && pixels[25] == 0xa5);
    ok = false;
    EXPECT(ISteamUtils_GetImageSize, sw_image_size(37, &width, &height) == 0);
    capacity = 23;
    EXPECT(ISteamUtils_GetImageRGBA, sw_image_rgba(37, pixels + 1, capacity) == 0);
    // Failure outputs are unspecified; assert only the returned status.
    ok = true;
}

static void test_apps() {
    char buffer[32]; output_buffer = buffer; capacity = sizeof(buffer);
    uint32_t id = 0; app_output = &id;
    uint8_t available = 0;
    uint64_t downloaded = 0, total = 0;
    for (const bool result : booleans) {
        ok = result;
        EXPECT(ISteamApps_BIsSubscribed, sw_subscribed() == result);
        EXPECT(ISteamApps_BIsSubscribedApp, sw_owns_app(app) == result);
        EXPECT(ISteamApps_BIsAppInstalled, sw_app_installed(app) == result);
        EXPECT(ISteamApps_BIsDlcInstalled, sw_dlc_installed(app) == result);
        for (const bool owned : booleans) {
            output_bool = owned;
            EXPECT(ISteamApps_BGetDLCDataByIndex, sw_dlc_data(2, &id, &available, buffer, capacity) == result);
            if (result) CHECK(id == app && available == owned && strcmp(buffer, text) == 0);
        }
        EXPECT(ISteamApps_GetDlcDownloadProgress, sw_dlc_progress(app, &downloaded, &total) == result);
        if (result) CHECK(downloaded == large_part && total == large_total);
    }
    EXPECT(ISteamApps_GetDLCCount, sw_dlc_count() == 4);
    EXPECT(ISteamApps_GetCurrentGameLanguage, sw_game_language() == text);
    EXPECT(ISteamApps_GetAvailableGameLanguages, sw_available_languages() == text);
    EXPECT(ISteamApps_GetAppOwner, sw_app_owner() == user);
    EXPECT(ISteamApps_GetAppBuildId, sw_build_id() == signed_value);
    EXPECT(ISteamApps_GetLaunchCommandLine, sw_launch_command_line(buffer, capacity) == sizeof(text) - 1);
    CHECK(strcmp(buffer, text) == 0);
}

static void test_stats() {
    int32_t integer = 0; int_output = &integer;
    float floating = 0; float_output = &floating;
    uint8_t unlocked = 0;
    uint32_t time = 0; time_output = &time;
    for (const bool result : booleans) {
        ok = result;
        EXPECT(ISteamUserStats_GetStatInt32, sw_stat_int(key, &integer) == result);
        if (result) CHECK(integer == signed_value);
        EXPECT(ISteamUserStats_GetStatFloat, sw_stat_float(key, &floating) == result);
        if (result) CHECK(floating == float_value);
        EXPECT(ISteamUserStats_SetStatInt32, sw_set_stat_int(key, signed_value) == result);
        EXPECT(ISteamUserStats_SetStatFloat, sw_set_stat_float(key, float_value) == result);
        integer = 0; floating = 0;
        EXPECT(ISteamUserStats_GetUserStatInt32, sw_user_stat_int(user, key, &integer) == result);
        if (result) CHECK(integer == signed_value);
        EXPECT(ISteamUserStats_GetUserStatFloat, sw_user_stat_float(user, key, &floating) == result);
        if (result) CHECK(floating == float_value);
        for (const bool achieved : booleans) {
            output_bool = achieved;
            EXPECT(ISteamUserStats_GetAchievementAndUnlockTime, sw_achievement(key, &unlocked, &time) == result);
            if (result) CHECK(unlocked == achieved && time == unlock_time);
            unlocked = 0; time = 0;
            EXPECT(ISteamUserStats_GetUserAchievementAndUnlockTime, sw_user_achievement(user, key, &unlocked, &time) == result);
            if (result) CHECK(unlocked == achieved && time == unlock_time);
        }
        EXPECT(ISteamUserStats_SetAchievement, sw_unlock_achievement(key) == result);
        EXPECT(ISteamUserStats_ClearAchievement, sw_clear_achievement(key) == result);
        EXPECT(ISteamUserStats_IndicateAchievementProgress, sw_achievement_progress(key, 0x87654321U, 0xfedcba98U) == result);
        EXPECT(ISteamUserStats_StoreStats, sw_store_stats() == result);
    }
    EXPECT(ISteamUserStats_GetNumAchievements, sw_achievement_count() == 7);
    EXPECT(ISteamUserStats_GetAchievementName, sw_achievement_name(6) == text);
    EXPECT(ISteamUserStats_GetAchievementDisplayAttribute, sw_achievement_attribute(key, text) == text);
    EXPECT(ISteamUserStats_RequestUserStats, sw_request_user_stats(user) == call);
    const SteamAPICall_t saved = call; call = k_uAPICallInvalid;
    EXPECT(ISteamUserStats_RequestUserStats, sw_request_user_stats(user) == 0);
    call = saved;
}

static void test_cloud() {
    uint8 buffer[sizeof(binary) + 2]; output_buffer = buffer + 1;
    input_buffer = binary;
    uint64_t total = 0, available = 0;
    int32_t size = 0; int_output = &size;
    for (const bool result : booleans) {
        ok = result;
        EXPECT(ISteamRemoteStorage_IsCloudEnabledForAccount, sw_cloud_account_enabled() == result);
        EXPECT(ISteamRemoteStorage_IsCloudEnabledForApp, sw_cloud_app_enabled() == result);
        EXPECT(ISteamRemoteStorage_FileExists, sw_cloud_exists(key) == result);
        EXPECT(ISteamRemoteStorage_FileWrite, sw_cloud_write(key, binary, sizeof(binary)) == result);
        EXPECT(ISteamRemoteStorage_FileDelete, sw_cloud_delete(key) == result);
        EXPECT(ISteamRemoteStorage_GetQuota, sw_cloud_quota(&total, &available) == result);
        if (result) CHECK(total == large_total && available == large_part);
        EXPECT(ISteamRemoteStorage_GetFileNameAndSize, sw_cloud_file_at(2, &size) == (result ? text : nullptr));
        if (result) CHECK(size == sizeof(binary));
        const int capacities[] = { 0, 2, sizeof(binary) };
        for (const int length : capacities) {
            capacity = length; memset(buffer, 0xa5, sizeof(buffer));
            EXPECT(ISteamRemoteStorage_FileRead, sw_cloud_read(key, buffer + 1, capacity) == (result ? length : 0));
            if (result) {
                CHECK(memcmp(buffer + 1, binary, length) == 0);
                CHECK(buffer[0] == 0xa5 && buffer[length + 1] == 0xa5);
            }
        }
    }
    EXPECT(ISteamRemoteStorage_GetFileSize, sw_cloud_file_size(key) == sizeof(binary));
    EXPECT(ISteamRemoteStorage_GetFileCount, sw_cloud_file_count() == 3);
    // This proves submission-handle forwarding only, not asynchronous completion.
    EXPECT(ISteamRemoteStorage_FileWriteAsync, sw_cloud_write_async(key, binary, sizeof(binary)) == call);
    call = k_uAPICallInvalid;
    EXPECT(ISteamRemoteStorage_FileWriteAsync, sw_cloud_write_async(key, binary, sizeof(binary)) == 0);
}
#undef EXPECT
} // namespace services_test

int main() {
    services_test::test_friends();
    services_test::test_images();
    services_test::test_apps();
    services_test::test_stats();
    services_test::test_cloud();
    puts("services fixtures: friends, images, apps, stats, cloud passed (SDK calls substituted)");
}
#undef CHECK
#endif
