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
static bool cloud_available = true;
static bool stats_available = true;
static int32 local_count = 1;
static char local_path[32] = "save.dat";
static const char *local_result = local_path;
static ERemoteStorageLocalFileChange local_change = k_ERemoteStorageLocalFileChange_FileUpdated;
static ERemoteStorageFilePathType local_path_type = k_ERemoteStorageFilePathType_Absolute;
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
STUB(ISteamUserStats *, SteamUserStats, ()) { ++accessors; return stats_available ? stats : nullptr; }
STUB(ISteamRemoteStorage *, SteamRemoteStorage, ()) { ++accessors; return cloud_available ? cloud : nullptr; }

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
STUB(int32, ISteamRemoteStorage_GetLocalFileChangeCount, (ISteamRemoteStorage *self)) { OBSERVE(cloud); return local_count; }
STUB(const char *, ISteamRemoteStorage_GetLocalFileChange, (ISteamRemoteStorage *self, int index, ERemoteStorageLocalFileChange *change, ERemoteStorageFilePathType *path_type)) {
    OBSERVE(cloud); CHECK(index == 0); *change = local_change; *path_type = local_path_type; return local_result;
}
STUB(bool, ISteamRemoteStorage_BeginFileWriteBatch, (ISteamRemoteStorage *self)) { OBSERVE(cloud); return ok; }
STUB(bool, ISteamRemoteStorage_EndFileWriteBatch, (ISteamRemoteStorage *self)) { OBSERVE(cloud); return ok; }
static constexpr SteamLeaderboard_t board = 0xf123456789abcdefULL;
static constexpr SteamLeaderboardEntries_t entry_set = 0xe123456789abcdefULL;
static int icon;
static char board_name[128] = "board";
static const char *board_name_result = board_name;
static ELeaderboardSortMethod sort_result = k_ELeaderboardSortMethodDescending;
static ELeaderboardDisplayType display_result = k_ELeaderboardDisplayTypeTimeMilliSeconds;
static int expected_first, expected_last, expected_users, expected_detail_count;
static bool expected_around, expected_force;
static int32 expected_score;
static uint64_t expected_ids[100];
static int32 expected_details[64];
static LeaderboardEntry_t stored_rows[100];
static int32 stored_details[100][64];
static int store_count, row_calls, failed_row = -1, second_failed_row = -1;
static bool store_valid;
static int percentage_iterator, expected_previous;
static int percentage_name_mode; // 0 normal, 1 empty, 2 full terminated, 3 unterminated, 4 unwritten
static uint32 percentage_bits = 0x7fc12345U;
STUB(int, ISteamUserStats_GetAchievementIcon, (ISteamUserStats *self, const char *name)) { OBSERVE(stats); CHECK(name == key); return icon; }
STUB(SteamAPICall_t, ISteamUserStats_FindLeaderboard, (ISteamUserStats *self, const char *name)) { OBSERVE(stats); CHECK(name == key); return call; }
STUB(const char *, ISteamUserStats_GetLeaderboardName, (ISteamUserStats *self, SteamLeaderboard_t id)) { OBSERVE(stats); CHECK(id == board); return board_name_result; }
STUB(int, ISteamUserStats_GetLeaderboardEntryCount, (ISteamUserStats *self, SteamLeaderboard_t id)) { OBSERVE(stats); CHECK(id == board); memset(board_name, 'x', 5); return signed_value; }
STUB(ELeaderboardSortMethod, ISteamUserStats_GetLeaderboardSortMethod, (ISteamUserStats *self, SteamLeaderboard_t id)) { OBSERVE(stats); CHECK(id == board); return sort_result; }
STUB(ELeaderboardDisplayType, ISteamUserStats_GetLeaderboardDisplayType, (ISteamUserStats *self, SteamLeaderboard_t id)) { OBSERVE(stats); CHECK(id == board); return display_result; }
STUB(SteamAPICall_t, ISteamUserStats_DownloadLeaderboardEntries, (ISteamUserStats *self, SteamLeaderboard_t id, ELeaderboardDataRequest request, int first, int last)) {
    OBSERVE(stats); CHECK(id == board && first == expected_first && last == expected_last);
    CHECK(request == (expected_around ? k_ELeaderboardDataRequestGlobalAroundUser : k_ELeaderboardDataRequestGlobal)); return call;
}
STUB(SteamAPICall_t, ISteamUserStats_DownloadLeaderboardEntriesForUsers, (ISteamUserStats *self, SteamLeaderboard_t id, CSteamID *users, int count)) {
    OBSERVE(stats); CHECK(id == board && count == expected_users);
    for (int i = 0; i < count; ++i) CHECK(users[i].ConvertToUint64() == expected_ids[i]); return call;
}
STUB(SteamAPICall_t, ISteamUserStats_UploadLeaderboardScore, (ISteamUserStats *self, SteamLeaderboard_t id, ELeaderboardUploadScoreMethod method, int32 score, const int32 *details, int count)) {
    OBSERVE(stats); CHECK(id == board && score == expected_score && count == expected_detail_count);
    CHECK(method == (expected_force ? k_ELeaderboardUploadScoreMethodForceUpdate : k_ELeaderboardUploadScoreMethodKeepBest));
    if (!count) CHECK(details == nullptr);
    for (int i = 0; i < count; ++i) CHECK(details[i] == expected_details[i]); return call;
}
STUB(bool, ISteamUserStats_GetDownloadedLeaderboardEntry, (ISteamUserStats *self, SteamLeaderboardEntries_t entries, int index, LeaderboardEntry_t *row, int32 *details, int maximum)) {
    OBSERVE(stats); CHECK(entries == entry_set && store_valid && index == row_calls && index < store_count && maximum == 64);
    CHECK(row->m_nScore == 0 && row->m_cDetails == 0);
    for (int i = 0; i < 64; ++i) CHECK(details[i] == 0);
    ++row_calls;
    if (index == failed_row || index == second_failed_row) {
        row->m_cDetails = -999; row->m_nScore = 999; details[0] = 999; return false;
    }
    *row = stored_rows[index]; memcpy(details, stored_details[index], sizeof(stored_details[index]));
    if (row_calls == store_count && failed_row < 0 && second_failed_row < 0) {
        store_valid = false;
        // Outputs are caller-owned, while the most recent native set expires.
        memset(stored_details, 0xcc, sizeof(stored_details));
        for (int i = 0; i < store_count; ++i) stored_rows[i] = {};
    }
    return true;
}
STUB(SteamAPICall_t, ISteamUserStats_RequestGlobalAchievementPercentages, (ISteamUserStats *self)) { OBSERVE(stats); return call; }
static int percentage_output(char *name, uint32 size, float *percent, bool *achieved) {
    CHECK(size == 128);
    for (uint32 i = 0; i < size; ++i) CHECK(static_cast<unsigned char>(name[i]) == 0xa5);
    if (percentage_name_mode == 0) memcpy(name, "achievement", 12);
    if (percentage_name_mode == 1) name[0] = 0;
    if (percentage_name_mode == 2) { memset(name, 'a', size); name[size - 1] = 0; }
    if (percentage_name_mode == 3) memset(name, 'b', size);
    memcpy(percent, &percentage_bits, sizeof(*percent)); *achieved = output_bool; return percentage_iterator;
}
STUB(int, ISteamUserStats_GetMostAchievedAchievementInfo, (ISteamUserStats *self, char *name, uint32 size, float *percent, bool *achieved)) {
    OBSERVE(stats); return percentage_output(name, size, percent, achieved);
}
STUB(int, ISteamUserStats_GetNextMostAchievedAchievementInfo, (ISteamUserStats *self, int previous, char *name, uint32 size, float *percent, bool *achieved)) {
    OBSERVE(stats); CHECK(previous == expected_previous); return percentage_output(name, size, percent, achieved);
}
STUB(bool, ISteamUserStats_GetAchievementAchievedPercent, (ISteamUserStats *self, const char *name, float *percent)) {
    OBSERVE(stats); CHECK(name == key); memcpy(percent, &percentage_bits, sizeof(*percent)); return ok;
}

#undef OBSERVE
#undef STUB
} // namespace services_test

// Substitution starts only after parsing official headers and type-checking all
// local functions. Tokens stand in for opaque interfaces and are never read.
#define SteamAPI_ISteamUserStats_GetAchievementIcon services_test::ISteamUserStats_GetAchievementIcon
#define SteamAPI_ISteamUserStats_FindLeaderboard services_test::ISteamUserStats_FindLeaderboard
#define SteamAPI_ISteamUserStats_GetLeaderboardName services_test::ISteamUserStats_GetLeaderboardName
#define SteamAPI_ISteamUserStats_GetLeaderboardEntryCount services_test::ISteamUserStats_GetLeaderboardEntryCount
#define SteamAPI_ISteamUserStats_GetLeaderboardSortMethod services_test::ISteamUserStats_GetLeaderboardSortMethod
#define SteamAPI_ISteamUserStats_GetLeaderboardDisplayType services_test::ISteamUserStats_GetLeaderboardDisplayType
#define SteamAPI_ISteamUserStats_DownloadLeaderboardEntries services_test::ISteamUserStats_DownloadLeaderboardEntries
#define SteamAPI_ISteamUserStats_DownloadLeaderboardEntriesForUsers services_test::ISteamUserStats_DownloadLeaderboardEntriesForUsers
#define SteamAPI_ISteamUserStats_UploadLeaderboardScore services_test::ISteamUserStats_UploadLeaderboardScore
#define SteamAPI_ISteamUserStats_GetDownloadedLeaderboardEntry services_test::ISteamUserStats_GetDownloadedLeaderboardEntry
#define SteamAPI_ISteamUserStats_RequestGlobalAchievementPercentages services_test::ISteamUserStats_RequestGlobalAchievementPercentages
#define SteamAPI_ISteamUserStats_GetMostAchievedAchievementInfo services_test::ISteamUserStats_GetMostAchievedAchievementInfo
#define SteamAPI_ISteamUserStats_GetNextMostAchievedAchievementInfo services_test::ISteamUserStats_GetNextMostAchievedAchievementInfo
#define SteamAPI_ISteamUserStats_GetAchievementAchievedPercent services_test::ISteamUserStats_GetAchievementAchievedPercent
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
#define SteamAPI_ISteamRemoteStorage_GetLocalFileChangeCount services_test::ISteamRemoteStorage_GetLocalFileChangeCount
#define SteamAPI_ISteamRemoteStorage_GetLocalFileChange services_test::ISteamRemoteStorage_GetLocalFileChange
#define SteamAPI_ISteamRemoteStorage_BeginFileWriteBatch services_test::ISteamRemoteStorage_BeginFileWriteBatch
#define SteamAPI_ISteamRemoteStorage_EndFileWriteBatch services_test::ISteamRemoteStorage_EndFileWriteBatch
#endif


template <typename T> static int32_t enum_bits(const T &value) {
    int32_t bits; static_assert(sizeof(value) == sizeof(bits), "Native enum width changed");
    memcpy(&bits, &value, sizeof(bits)); return bits;
}

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

uint8_t sw_stats_achievement_icon(const char *name, int32_t *image) {
    ISteamUserStats *const stats = SteamAPI_SteamUserStats();
    if (!stats) return 0;
    *image = SteamAPI_ISteamUserStats_GetAchievementIcon(stats, name); return 1;
}
uint8_t sw_stats_find_leaderboard(const char *name, uint64_t *call) {
    ISteamUserStats *const stats = SteamAPI_SteamUserStats();
    if (!stats) return 0;
    *call = SteamAPI_ISteamUserStats_FindLeaderboard(stats, name); return 1;
}
uint8_t sw_stats_leaderboard_metadata_copy(uint64_t leaderboard, char *buffer, size_t capacity, sw_stats_leaderboard_metadata *out) {
    *out = {};
    ISteamUserStats *const stats = SteamAPI_SteamUserStats();
    if (!stats) return SW_STATS_TEXT_UNAVAILABLE;
    const char *const name = SteamAPI_ISteamUserStats_GetLeaderboardName(stats, leaderboard);
    // Copy the borrowed name before any other native operation.
    const bool present = name != nullptr;
    out->name_length = present ? strlen(name) : 0;
    if (present && out->name_length <= capacity && out->name_length) memcpy(buffer, name, out->name_length);
    out->entry_count = SteamAPI_ISteamUserStats_GetLeaderboardEntryCount(stats, leaderboard);
    out->sort = enum_bits(SteamAPI_ISteamUserStats_GetLeaderboardSortMethod(stats, leaderboard));
    out->display = enum_bits(SteamAPI_ISteamUserStats_GetLeaderboardDisplayType(stats, leaderboard));
    return !present ? SW_STATS_TEXT_NULL : out->name_length > capacity ? SW_STATS_TEXT_SHORT : SW_STATS_TEXT_OK;
}
uint8_t sw_stats_download(uint64_t leaderboard, uint8_t around, int32_t first, int32_t last, uint64_t *call) {
    ISteamUserStats *const stats = SteamAPI_SteamUserStats();
    if (!stats) return 0;
    *call = SteamAPI_ISteamUserStats_DownloadLeaderboardEntries(stats, leaderboard,
        around ? k_ELeaderboardDataRequestGlobalAroundUser : k_ELeaderboardDataRequestGlobal, first, last);
    return 1;
}
uint8_t sw_stats_download_users(uint64_t leaderboard, const uint64_t *users, int32_t count, uint64_t *call) {
    *call = 0;
    ISteamUserStats *const stats = SteamAPI_SteamUserStats();
    if (!stats) return 0;
    if (count < 1 || count > SW_LEADERBOARD_MAX_ENTRIES) return 1;
    CSteamID native_users[SW_LEADERBOARD_MAX_ENTRIES] = {};
    for (int32_t i = 0; i < count; ++i) native_users[i] = CSteamID(static_cast<uint64>(users[i]));
    *call = SteamAPI_ISteamUserStats_DownloadLeaderboardEntriesForUsers(stats, leaderboard, native_users, count);
    return 1;
}
uint8_t sw_stats_upload(uint64_t leaderboard, uint8_t force, int32_t score, const int32_t *details, int32_t count, uint64_t *call) {
    ISteamUserStats *const stats = SteamAPI_SteamUserStats();
    if (!stats) return 0;
    *call = SteamAPI_ISteamUserStats_UploadLeaderboardScore(stats, leaderboard,
        force ? k_ELeaderboardUploadScoreMethodForceUpdate : k_ELeaderboardUploadScoreMethodKeepBest, score, count ? details : nullptr, count);
    return 1;
}
void sw_stats_copy_leaderboard_entries(uint64_t entries, int32_t count, SwLeaderboardEntries *out) {
    static_assert(SW_LEADERBOARD_MAX_DETAILS == k_cLeaderboardDetailsMax, "Leaderboard detail capacity changed");
    *out = {};
    out->reported_count = count;
    out->failure_index = -1;
    if (count < 0) { out->status = SW_LEADERBOARD_CAPTURE_INVALID_COUNT; return; }
    if (count > SW_LEADERBOARD_MAX_ENTRIES) { out->status = SW_LEADERBOARD_CAPTURE_TOO_MANY_ROWS; return; }
    if (count == 0) { out->all_rows_accessed = 1; return; }
    if (!entries) { out->status = SW_LEADERBOARD_CAPTURE_INVALID_HANDLE; return; }
    ISteamUserStats *const stats = SteamAPI_SteamUserStats();
    if (!stats) { out->status = SW_LEADERBOARD_CAPTURE_UNAVAILABLE; return; }
    out->all_rows_accessed = 1;
    for (int32_t i = 0; i < count; ++i) {
        LeaderboardEntry_t row = {};
        int32 details[SW_LEADERBOARD_MAX_DETAILS] = {};
        const bool ok = SteamAPI_ISteamUserStats_GetDownloadedLeaderboardEntry(stats, entries, i, &row, details, SW_LEADERBOARD_MAX_DETAILS);
        if (!ok) {
            out->all_rows_accessed = 0;
            if (out->failure_index == -1) { out->status = SW_LEADERBOARD_CAPTURE_ENTRY_FAILED; out->failure_index = i; }
            continue;
        }
        if (row.m_cDetails < 0 || row.m_cDetails > SW_LEADERBOARD_MAX_DETAILS) {
            if (out->failure_index == -1) {
                out->status = SW_LEADERBOARD_CAPTURE_INVALID_DETAILS;
                out->failure_index = i; out->reported_details = row.m_cDetails;
            }
            continue;
        }
        if (out->failure_index != -1) continue;
        SwLeaderboardEntry &owned = out->entries[out->copied_count++];
        owned.user = row.m_steamIDUser.ConvertToUint64();
        owned.global_rank = row.m_nGlobalRank; owned.score = row.m_nScore;
        owned.ugc = row.m_hUGC; owned.detail_count = static_cast<uint32_t>(row.m_cDetails);
        if (row.m_cDetails) memcpy(owned.details, details, sizeof(int32) * row.m_cDetails);
    }
}
uint8_t sw_stats_request_global_percentages(uint64_t *call) {
    ISteamUserStats *const stats = SteamAPI_SteamUserStats();
    if (!stats) return 0;
    *call = SteamAPI_ISteamUserStats_RequestGlobalAchievementPercentages(stats); return 1;
}
uint8_t sw_stats_percentage_step(uint8_t first, int32_t previous, sw_stats_percentage *out) {
    *out = {};
    ISteamUserStats *const stats = SteamAPI_SteamUserStats();
    if (!stats) return SW_STATS_PERCENTAGE_UNAVAILABLE;
    char name[k_cchStatNameMax];
    static_assert(sizeof(name) == sizeof(out->name), "Achievement name bound changed");
    memset(name, 0xa5, sizeof(name));
    float percent = 0; bool achieved = false;
    const int iterator = first ? SteamAPI_ISteamUserStats_GetMostAchievedAchievementInfo(stats, name, sizeof(name), &percent, &achieved)
        : SteamAPI_ISteamUserStats_GetNextMostAchievedAchievementInfo(stats, previous, name, sizeof(name), &percent, &achieved);
    out->iterator = iterator;
    if (iterator == -1) return SW_STATS_PERCENTAGE_END;
    if (iterator < 0) return SW_STATS_PERCENTAGE_NEGATIVE;
    const char *const end = static_cast<const char *>(memchr(name, 0, sizeof(name)));
    if (!end) return SW_STATS_PERCENTAGE_UNTERMINATED;
    out->name_length = static_cast<uint32_t>(end - name);
    memcpy(out->name, name, out->name_length);
    static_assert(sizeof(percent) == sizeof(out->percent_bits), "Float width changed");
    memcpy(&out->percent_bits, &percent, sizeof(percent));
    out->achieved = achieved;
    return SW_STATS_PERCENTAGE_ITEM;
}
int32_t sw_stats_achievement_percentage(const char *name, uint32_t *percent_bits) {
    ISteamUserStats *const stats = SteamAPI_SteamUserStats();
    if (!stats) return -1;
    float percent = 0;
    if (!SteamAPI_ISteamUserStats_GetAchievementAchievedPercent(stats, name, &percent)) return 0;
    memcpy(percent_bits, &percent, sizeof(percent)); return 1;
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

uint8_t sw_cloud_local_change_count(int32_t *count) {
    ISteamRemoteStorage *const storage = SteamAPI_SteamRemoteStorage();
    if (!storage) return 0;
    *count = SteamAPI_ISteamRemoteStorage_GetLocalFileChangeCount(storage);
    return 1;
}
uint8_t sw_cloud_local_change_copy(int32_t index, char *buffer, size_t capacity, sw_cloud_local_change *out) {
    *out = {};
    ISteamRemoteStorage *const storage = SteamAPI_SteamRemoteStorage();
    if (!storage) return SW_CLOUD_CHANGE_UNAVAILABLE;
    const int32 count = SteamAPI_ISteamRemoteStorage_GetLocalFileChangeCount(storage);
    if (count < 0) return SW_CLOUD_CHANGE_COUNT_FAILED;
    if (index < 0 || index >= count) return SW_CLOUD_CHANGE_INVALID_INDEX;
    ERemoteStorageLocalFileChange change = k_ERemoteStorageLocalFileChange_Invalid;
    ERemoteStorageFilePathType path_type = k_ERemoteStorageFilePathType_Invalid;
    const char *const path = SteamAPI_ISteamRemoteStorage_GetLocalFileChange(storage, index, &change, &path_type);
    if (!path) return SW_CLOUD_CHANGE_NULL_PATH;
    out->change = enum_bits(change);
    out->path_type = enum_bits(path_type);
    out->path_length = strlen(path);
    if (out->path_length > capacity) return SW_CLOUD_CHANGE_SHORT_BUFFER;
    if (out->path_length) memcpy(buffer, path, out->path_length);
    return SW_CLOUD_CHANGE_OK;
}
int32_t sw_cloud_begin_write_batch(void) {
    ISteamRemoteStorage *const storage = SteamAPI_SteamRemoteStorage();
    return storage ? static_cast<int32_t>(SteamAPI_ISteamRemoteStorage_BeginFileWriteBatch(storage)) : -1;
}
int32_t sw_cloud_end_write_batch(void) {
    ISteamRemoteStorage *const storage = SteamAPI_SteamRemoteStorage();
    return storage ? static_cast<int32_t>(SteamAPI_ISteamRemoteStorage_EndFileWriteBatch(storage)) : -1;
}

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
static void change_calls(unsigned expected) {
    CHECK(calls == expected && accessors == 1);
    calls = accessors = 0; last_call = nullptr;
}
static void test_cloud_coordination() {
    int32_t count = 99;
    const int32 counts[] = { -7, 0, 1 };
    for (const int32 value : counts) {
        local_count = value;
        EXPECT(ISteamRemoteStorage_GetLocalFileChangeCount, sw_cloud_local_change_count(&count) == 1);
        CHECK(count == value);
    }
    char buffer[32]; memset(buffer, 0xa5, sizeof(buffer));
    sw_cloud_local_change out = {};
    local_count = -1;
    CHECK(sw_cloud_local_change_copy(0, buffer, sizeof(buffer), &out) == SW_CLOUD_CHANGE_COUNT_FAILED); change_calls(1);
    local_count = 0;
    CHECK(sw_cloud_local_change_copy(0, buffer, sizeof(buffer), &out) == SW_CLOUD_CHANGE_INVALID_INDEX); change_calls(1);
    local_count = 1;
    const int indices[] = { -1, 1, 2147483647 };
    for (const int index : indices) {
        CHECK(sw_cloud_local_change_copy(index, buffer, sizeof(buffer), &out) == SW_CLOUD_CHANGE_INVALID_INDEX); change_calls(1);
    }
    CHECK(sw_cloud_local_change_copy(0, buffer, 7, &out) == SW_CLOUD_CHANGE_SHORT_BUFFER); change_calls(2);
    CHECK(out.path_length == 8 && static_cast<unsigned char>(buffer[0]) == 0xa5);
    CHECK(sw_cloud_local_change_copy(0, buffer, 8, &out) == SW_CLOUD_CHANGE_OK); change_calls(2);
    CHECK(out.path_length == 8 && out.change == 1 && out.path_type == 1 && memcmp(buffer, "save.dat", 8) == 0);
    strcpy(local_path, "next.dat");
    CHECK(memcmp(buffer, "save.dat", 8) == 0 && static_cast<unsigned char>(buffer[8]) == 0xa5);
    local_change = k_ERemoteStorageLocalFileChange_FileDeleted;
    local_path_type = k_ERemoteStorageFilePathType_APIFilename;
    CHECK(sw_cloud_local_change_copy(0, buffer, sizeof(buffer), &out) == SW_CLOUD_CHANGE_OK); change_calls(2);
    CHECK(out.change == 2 && out.path_type == 2 && memcmp(buffer, "next.dat", 8) == 0);
    // Future numeric values are tested at the owned integer/Zig boundary.
    local_change = k_ERemoteStorageLocalFileChange_Invalid;
    local_path_type = k_ERemoteStorageFilePathType_Invalid;
    local_result = "";
    CHECK(sw_cloud_local_change_copy(0, nullptr, 0, &out) == SW_CLOUD_CHANGE_OK); change_calls(2);
    CHECK(out.path_length == 0 && out.change == 0 && out.path_type == 0);
    local_result = nullptr;
    CHECK(sw_cloud_local_change_copy(0, buffer, sizeof(buffer), &out) == SW_CLOUD_CHANGE_NULL_PATH); change_calls(2);
    for (const bool result : booleans) {
        ok = result;
        EXPECT(ISteamRemoteStorage_BeginFileWriteBatch, sw_cloud_begin_write_batch() == result);
        EXPECT(ISteamRemoteStorage_EndFileWriteBatch, sw_cloud_end_write_batch() == result);
    }
    cloud_available = false;
    CHECK(sw_cloud_local_change_count(&count) == 0); change_calls(0);
    CHECK(sw_cloud_local_change_copy(0, buffer, sizeof(buffer), &out) == SW_CLOUD_CHANGE_UNAVAILABLE); change_calls(0);
    CHECK(sw_cloud_begin_write_batch() == -1); change_calls(0);
    CHECK(sw_cloud_end_write_batch() == -1); change_calls(0);
    cloud_available = true;
}
static void reset_store(int count) {
    store_count = count; row_calls = 0; failed_row = second_failed_row = -1; store_valid = true;
    for (int i = 0; i < count; ++i) {
        stored_rows[i] = {};
        stored_rows[i].m_steamIDUser = CSteamID(user + i);
        stored_rows[i].m_nGlobalRank = -i; stored_rows[i].m_nScore = signed_value + i;
        stored_rows[i].m_hUGC = large_total + i; stored_rows[i].m_cDetails = i % 65;
        for (int j = 0; j < 64; ++j) stored_details[i][j] = i * 100 - j;
    }
}
static void check_prefix(const SwLeaderboardEntries &out, int count) {
    CHECK(out.copied_count == static_cast<uint32_t>(count));
    for (int i = 0; i < count; ++i) {
        const SwLeaderboardEntry &row = out.entries[i];
        CHECK(row.user == user + i && row.global_rank == -i && row.score == signed_value + i && row.ugc == large_total + i);
        CHECK(row.detail_count == static_cast<uint32_t>(i % 65));
        for (uint32_t j = 0; j < row.detail_count; ++j) CHECK(row.details[j] == i * 100 - static_cast<int32_t>(j));
    }
    for (int i = count; i < 100; ++i) CHECK(out.entries[i].detail_count == 0 && out.entries[i].user == 0);
}
static void test_leaderboard_capture() {
    SwLeaderboardEntries out;
    const int invalid_counts[] = { -2147483647 - 1, -1, 101, 2147483647 };
    for (const int n : invalid_counts) {
        sw_stats_copy_leaderboard_entries(entry_set, n, &out);
        CHECK(out.reported_count == n && out.failure_index == -1 && out.copied_count == 0 && !out.all_rows_accessed);
        CHECK(out.status == (n < 0 ? SW_LEADERBOARD_CAPTURE_INVALID_COUNT : SW_LEADERBOARD_CAPTURE_TOO_MANY_ROWS));
        CHECK(calls == 0 && accessors == 0);
    }
    stats_available = false;
    sw_stats_copy_leaderboard_entries(0, 0, &out);
    CHECK(out.status == SW_LEADERBOARD_CAPTURE_COMPLETE && out.all_rows_accessed && calls == 0 && accessors == 0);
    sw_stats_copy_leaderboard_entries(0, 1, &out);
    CHECK(out.status == SW_LEADERBOARD_CAPTURE_INVALID_HANDLE && !out.all_rows_accessed && calls == 0 && accessors == 0);
    sw_stats_copy_leaderboard_entries(entry_set, 1, &out);
    CHECK(out.status == SW_LEADERBOARD_CAPTURE_UNAVAILABLE && !out.all_rows_accessed); change_calls(0);
    stats_available = true;
    for (int n = 1; n <= 100; ++n) {
        reset_store(n); sw_stats_copy_leaderboard_entries(entry_set, n, &out); change_calls(n);
        CHECK(row_calls == n && !store_valid && out.status == SW_LEADERBOARD_CAPTURE_COMPLETE && out.all_rows_accessed && out.failure_index == -1);
        check_prefix(out, n); // Includes last row, after final native access invalidated store.
    }
    for (int failure = 0; failure < 100; ++failure) {
        reset_store(100); failed_row = failure;
        sw_stats_copy_leaderboard_entries(entry_set, 100, &out); change_calls(100);
        CHECK(row_calls == 100 && store_valid && out.status == SW_LEADERBOARD_CAPTURE_ENTRY_FAILED && !out.all_rows_accessed && out.failure_index == failure && out.reported_details == 0);
        check_prefix(out, failure);
        const int invalid_detail_counts[] = { -2147483647 - 1, -1, 65, 2147483647 };
        for (const int invalid_details : invalid_detail_counts) {
            reset_store(100); stored_rows[failure].m_cDetails = invalid_details;
            sw_stats_copy_leaderboard_entries(entry_set, 100, &out); change_calls(100);
            CHECK(row_calls == 100 && !store_valid && out.status == SW_LEADERBOARD_CAPTURE_INVALID_DETAILS && out.all_rows_accessed && out.failure_index == failure && out.reported_details == invalid_details);
            check_prefix(out, failure);
        }
    }
    // First error wins even when later cleanup fails or has invalid metadata.
    reset_store(100); stored_rows[2].m_cDetails = 65; failed_row = 3; second_failed_row = 99;
    sw_stats_copy_leaderboard_entries(entry_set, 100, &out); change_calls(100);
    CHECK(out.status == SW_LEADERBOARD_CAPTURE_INVALID_DETAILS && out.failure_index == 2 && out.reported_details == 65 && !out.all_rows_accessed); check_prefix(out, 2);
    reset_store(100); failed_row = 2; stored_rows[3].m_cDetails = -1;
    sw_stats_copy_leaderboard_entries(entry_set, 100, &out); change_calls(100);
    CHECK(out.status == SW_LEADERBOARD_CAPTURE_ENTRY_FAILED && out.failure_index == 2 && out.reported_details == 0 && !out.all_rows_accessed); check_prefix(out, 2);
    // Every valid detail count, including 64 on the final row.
    for (int n = 0; n <= 64; ++n) {
        reset_store(1); stored_rows[0].m_cDetails = n;
        sw_stats_copy_leaderboard_entries(entry_set, 1, &out); change_calls(1);
        CHECK(out.copied_count == 1 && out.entries[0].detail_count == static_cast<uint32_t>(n) && !store_valid);
        for (int j = 0; j < n; ++j) CHECK(out.entries[0].details[j] == -j);
    }
}
static void test_progression() {
    call = 0xe123456789abcdefULL;
    uint64_t result = 0; int32_t image = -77;
    for (const int value : avatar_results) {
        icon = value; CHECK(sw_stats_achievement_icon(key, &image)); called("ISteamUserStats_GetAchievementIcon"); CHECK(image == value);
    }
    const uint64_t call_values[] = { 0, 0xe123456789abcdefULL };
    for (const uint64_t value : call_values) {
        call = value;
        CHECK(sw_stats_find_leaderboard(key, &result)); called("ISteamUserStats_FindLeaderboard"); CHECK(result == value);
        CHECK(sw_stats_request_global_percentages(&result)); called("ISteamUserStats_RequestGlobalAchievementPercentages"); CHECK(result == value);
        for (const bool around : booleans) {
            expected_around = around; expected_first = around ? -99 : 1; expected_last = around ? 0 : 100;
            CHECK(sw_stats_download(board, around, expected_first, expected_last, &result)); called("ISteamUserStats_DownloadLeaderboardEntries"); CHECK(result == value);
        }
        for (int n = 1; n <= 100; ++n) {
            expected_users = n;
            for (int i = 0; i < n; ++i) expected_ids[i] = i % 3 == 0 ? 0 : user; // Includes exact duplicates/invalid IDs.
            CHECK(sw_stats_download_users(board, expected_ids, n, &result)); called("ISteamUserStats_DownloadLeaderboardEntriesForUsers"); CHECK(result == value);
        }
        for (const bool force : booleans) for (int n = 0; n <= 64; ++n) {
            expected_force = force; expected_detail_count = n; expected_score = force ? (-2147483647 - 1) : 2147483647;
            for (int i = 0; i < n; ++i) expected_details[i] = -i;
            CHECK(sw_stats_upload(board, force, expected_score, expected_details, n, &result)); called("ISteamUserStats_UploadLeaderboardScore"); CHECK(result == value);
        }
    }
    char buffer[128]; memset(buffer, 0xa5, sizeof(buffer)); sw_stats_leaderboard_metadata metadata;
    strcpy(board_name, "board"); board_name_result = board_name;
    CHECK(sw_stats_leaderboard_metadata_copy(board, buffer, 4, &metadata) == SW_STATS_TEXT_SHORT); change_calls(4);
    CHECK(metadata.name_length == 5 && static_cast<unsigned char>(buffer[0]) == 0xa5);
    strcpy(board_name, "board");
    CHECK(sw_stats_leaderboard_metadata_copy(board, buffer, 5, &metadata) == SW_STATS_TEXT_OK); change_calls(4);
    CHECK(metadata.name_length == 5 && memcmp(buffer, "board", 5) == 0 && memcmp(board_name, "xxxxx", 5) == 0 && metadata.entry_count == signed_value && metadata.sort == 2 && metadata.display == 3);
    // Sort's enumerators 0..2 permit 0..3. 3 is unknown but a valid enum value.
    sort_result = static_cast<ELeaderboardSortMethod>(3);
    board_name_result = "";
    CHECK(sw_stats_leaderboard_metadata_copy(board, nullptr, 0, &metadata) == SW_STATS_TEXT_OK); change_calls(4); CHECK(metadata.name_length == 0 && metadata.sort == 3);
    board_name_result = nullptr;
    CHECK(sw_stats_leaderboard_metadata_copy(board, nullptr, 0, &metadata) == SW_STATS_TEXT_NULL); change_calls(4);
    sw_stats_percentage percent;
    const int iterators[] = { -2147483647 - 1, -2, -1, 0, 123456789, 2147483647 };
    for (const int iterator : iterators) for (int mode = 0; mode <= 4; ++mode) for (const bool first : booleans) {
        percentage_iterator = iterator; percentage_name_mode = mode; expected_previous = 123456789;
        const uint8_t status = sw_stats_percentage_step(first, expected_previous, &percent);
        called(first ? "ISteamUserStats_GetMostAchievedAchievementInfo" : "ISteamUserStats_GetNextMostAchievedAchievementInfo");
        CHECK(percent.iterator == iterator);
        CHECK(status == (iterator == -1 ? SW_STATS_PERCENTAGE_END : iterator < 0 ? SW_STATS_PERCENTAGE_NEGATIVE : mode >= 3 ? SW_STATS_PERCENTAGE_UNTERMINATED : SW_STATS_PERCENTAGE_ITEM));
        if (status == SW_STATS_PERCENTAGE_ITEM) {
            CHECK(percent.name_length == (mode == 0 ? 11U : mode == 1 ? 0U : 127U) && percent.percent_bits == percentage_bits && percent.achieved == output_bool);
        } else CHECK(percent.name_length == 0 && percent.percent_bits == 0 && percent.achieved == 0);
    }
    const uint32 bits[] = { 0, 0x80000000U, 0x7fc12345U, 0x7f800000U, 0xff800000U, 0xc1234567U };
    for (const uint32 value : bits) for (const bool success : booleans) {
        percentage_bits = value; ok = success; uint32_t output = 0xabcdef01U;
        CHECK(sw_stats_achievement_percentage(key, &output) == success); called("ISteamUserStats_GetAchievementAchievedPercent");
        CHECK(output == (success ? value : 0xabcdef01U));
        percentage_name_mode = 0; percentage_iterator = 0; output_bool = success;
        CHECK(sw_stats_percentage_step(1, 0, &percent) == SW_STATS_PERCENTAGE_ITEM); called("ISteamUserStats_GetMostAchievedAchievementInfo");
        CHECK(percent.percent_bits == value && percent.achieved == success);
    }
    stats_available = false;
    CHECK(!sw_stats_achievement_icon(key, &image)); change_calls(0);
    CHECK(!sw_stats_find_leaderboard(key, &result)); change_calls(0);
    CHECK(sw_stats_leaderboard_metadata_copy(board, buffer, sizeof(buffer), &metadata) == SW_STATS_TEXT_UNAVAILABLE); change_calls(0);
    CHECK(!sw_stats_download(board, 0, 1, 100, &result)); change_calls(0);
    CHECK(!sw_stats_download_users(board, expected_ids, 1, &result)); change_calls(0);
    CHECK(!sw_stats_upload(board, 0, 0, nullptr, 0, &result)); change_calls(0);
    CHECK(!sw_stats_request_global_percentages(&result)); change_calls(0);
    CHECK(sw_stats_percentage_step(1, 0, &percent) == SW_STATS_PERCENTAGE_UNAVAILABLE); change_calls(0);
    uint32_t output = 99;
    CHECK(sw_stats_achievement_percentage(key, &output) == -1 && output == 99); change_calls(0);
    stats_available = true;
}

#undef EXPECT
} // namespace services_test

int main() {
    services_test::test_friends();
    services_test::test_images();
    services_test::test_apps();
    services_test::test_stats();
    services_test::test_cloud();
    services_test::test_cloud_coordination();
    services_test::test_leaderboard_capture();
    services_test::test_progression();
    puts("services fixtures: progression, friends, images, apps, stats, cloud and coordination passed (SDK calls substituted)");
}
#undef CHECK
#endif
