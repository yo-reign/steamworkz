#include "workshop.h"
#include <steam/steam_api_flat.h>
#include <string.h>

static_assert(k_cchPublishedDocumentTitleMax == 129);
static_assert(k_cchPublishedDocumentDescriptionMax == 8000);
static_assert(k_cchTagListMax == 1025);
static_assert(k_cchFilenameMax == 260);
static_assert(k_cchPublishedFileURLMax == 256);
static_assert(k_UGCQueryHandleInvalid == UINT64_MAX);

namespace {
// Preserve native output representations without evaluating an unknown enum.
template<class T> int32_t enum_value(const T &value) {
    static_assert(sizeof(T) == sizeof(int32_t), "SDK enum width changed");
    int32_t result;
    memcpy(&result, &value, sizeof(result));
    return result;
}
}

#ifdef SW_WORKSHOP_TEST
#include <stdio.h>
#include <stdlib.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #x); abort(); } } while (0)
namespace workshop_test {
static char token;
static ISteamUGC *const ugc = reinterpret_cast<ISteamUGC *>(&token);
static bool available = true, accepted = true, include_disabled, priority;
static unsigned accessors, calls;
static uint64_t handle, item;
static uint32_t row, reported = 3;
static SteamUGCDetails_t scratch{};
static decltype(SteamAPI_SteamUGC_v021) accessor;
static ISteamUGC *accessor() { ++accessors; return available ? ugc : nullptr; }
static void check(ISteamUGC *self) { CHECK(self == ugc); ++calls; }
static decltype(SteamAPI_ISteamUGC_CreateQueryUGCDetailsRequest) create;
static UGCQueryHandle_t create(ISteamUGC *self, PublishedFileId_t *ids, uint32 count) {
    check(self); CHECK(count == 3); CHECK(ids[0] == 17 && ids[1] == 0 && ids[2] == 17);
    ids[0] = 99; // Official mutable boundary must not alias caller const input.
    return handle;
}
static decltype(SteamAPI_ISteamUGC_SendQueryUGCRequest) send;
static SteamAPICall_t send(ISteamUGC *self, UGCQueryHandle_t h) { check(self); handle = h; return accepted ? 71 : 0; }
static decltype(SteamAPI_ISteamUGC_ReleaseQueryUGCRequest) release;
static bool release(ISteamUGC *self, UGCQueryHandle_t h) { check(self); handle = h; return accepted; }
static decltype(SteamAPI_ISteamUGC_GetQueryUGCResult) details;
static bool details(ISteamUGC *self, UGCQueryHandle_t h, uint32 index, SteamUGCDetails_t *out) {
    check(self); handle = h; row = index; CHECK(out->m_nPublishedFileId == 0); *out = scratch; return accepted;
}
static decltype(SteamAPI_ISteamUGC_GetNumSubscribedItems) count;
static uint32 count(ISteamUGC *self, bool disabled) { check(self); include_disabled = disabled; return reported; }
static decltype(SteamAPI_ISteamUGC_GetSubscribedItems) subscriptions;
static uint32 subscriptions(ISteamUGC *self, PublishedFileId_t *out, uint32 capacity, bool disabled) {
    check(self); include_disabled = disabled;
    for (uint32 i = 0; i < capacity; ++i) out[i] = i % 2 ? 0 : 17;
    return reported;
}
static decltype(SteamAPI_ISteamUGC_GetItemState) state;
static uint32 state(ISteamUGC *self, PublishedFileId_t id) { check(self); item = id; return 0x80000045; }
static decltype(SteamAPI_ISteamUGC_GetItemInstallInfo) install;
static bool install(ISteamUGC *self, PublishedFileId_t id, uint64 *size, char *path, uint32 capacity, uint32 *timestamp) {
    check(self); item = id; *size = UINT64_MAX; *timestamp = 31;
    memset(path, 'x', capacity); if (accepted && capacity > 1) path[capacity - 1] = 0;
    return accepted;
}
static decltype(SteamAPI_ISteamUGC_GetItemDownloadInfo) progress;
static bool progress(ISteamUGC *self, PublishedFileId_t id, uint64 *downloaded, uint64 *total) {
    check(self); item = id; *downloaded = UINT64_MAX; *total = 0; return accepted;
}
static decltype(SteamAPI_ISteamUGC_DownloadItem) download;
static bool download(ISteamUGC *self, PublishedFileId_t id, bool high) { check(self); item = id; priority = high; return accepted; }
}
#define SteamAPI_SteamUGC_v021 workshop_test::accessor
#define SteamAPI_ISteamUGC_CreateQueryUGCDetailsRequest workshop_test::create
#define SteamAPI_ISteamUGC_SendQueryUGCRequest workshop_test::send
#define SteamAPI_ISteamUGC_ReleaseQueryUGCRequest workshop_test::release
#define SteamAPI_ISteamUGC_GetQueryUGCResult workshop_test::details
#define SteamAPI_ISteamUGC_GetNumSubscribedItems workshop_test::count
#define SteamAPI_ISteamUGC_GetSubscribedItems workshop_test::subscriptions
#define SteamAPI_ISteamUGC_GetItemState workshop_test::state
#define SteamAPI_ISteamUGC_GetItemInstallInfo workshop_test::install
#define SteamAPI_ISteamUGC_GetItemDownloadInfo workshop_test::progress
#define SteamAPI_ISteamUGC_DownloadItem workshop_test::download
#endif

int32_t sw_workshop_create(const uint64_t *items, size_t count, uint64_t *handle) {
    if (!items || count == 0 || count > 50) return -2;
    auto *ugc = SteamAPI_SteamUGC_v021(); if (!ugc) return -1;
    PublishedFileId_t ids[50]{};
    for (size_t i = 0; i < count; ++i) ids[i] = items[i];
    *handle = SteamAPI_ISteamUGC_CreateQueryUGCDetailsRequest(ugc, ids, static_cast<uint32>(count));
    return 0;
}
int32_t sw_workshop_send(uint64_t handle, uint64_t *call) {
    auto *ugc = SteamAPI_SteamUGC_v021(); if (!ugc) return -1;
    *call = SteamAPI_ISteamUGC_SendQueryUGCRequest(ugc, handle); return 0;
}
int32_t sw_workshop_release(uint64_t handle, bool *accepted) {
    auto *ugc = SteamAPI_SteamUGC_v021(); if (!ugc) return -1;
    *accepted = SteamAPI_ISteamUGC_ReleaseQueryUGCRequest(ugc, handle); return 0;
}
int32_t sw_workshop_details(uint64_t handle, uint32_t index, struct sw_workshop_details *out, bool *found) {
    auto *ugc = SteamAPI_SteamUGC_v021(); if (!ugc) return -1;
    SteamUGCDetails_t value{};
    *found = SteamAPI_ISteamUGC_GetQueryUGCResult(ugc, handle, index, &value);
    if (!*found) return 0;
    struct sw_workshop_details copy{};
    copy.item = value.m_nPublishedFileId;
    copy.result = enum_value(value.m_eResult);
    copy.file_type = enum_value(value.m_eFileType);
    copy.creator_app = value.m_nCreatorAppID;
    copy.consumer_app = value.m_nConsumerAppID;
    memcpy(copy.title, value.m_rgchTitle, sizeof(copy.title));
    memcpy(copy.description, value.m_rgchDescription, sizeof(copy.description));
    copy.owner = value.m_ulSteamIDOwner;
    copy.created = value.m_rtimeCreated;
    copy.updated = value.m_rtimeUpdated;
    copy.added_to_list = value.m_rtimeAddedToUserList;
    copy.visibility = enum_value(value.m_eVisibility);
    copy.banned = value.m_bBanned;
    copy.accepted_for_use = value.m_bAcceptedForUse;
    copy.tags_truncated = value.m_bTagsTruncated;
    memcpy(copy.tags, value.m_rgchTags, sizeof(copy.tags));
    copy.file = value.m_hFile;
    copy.preview_file = value.m_hPreviewFile;
    memcpy(copy.filename, value.m_pchFileName, sizeof(copy.filename));
    copy.file_size = value.m_nFileSize;
    copy.preview_file_size = value.m_nPreviewFileSize;
    memcpy(copy.url, value.m_rgchURL, sizeof(copy.url));
    copy.votes_up = value.m_unVotesUp;
    copy.votes_down = value.m_unVotesDown;
    copy.score = value.m_flScore;
    copy.children = value.m_unNumChildren;
    copy.total_files_size = value.m_ulTotalFilesSize;
    *out = copy;
    return 0;
}
int32_t sw_workshop_count(bool include_locally_disabled, uint32_t *count) {
    auto *ugc = SteamAPI_SteamUGC_v021(); if (!ugc) return -1;
    // ISteamUGC's C++ default is false; flat exports require an explicit bool.
    *count = SteamAPI_ISteamUGC_GetNumSubscribedItems(ugc, include_locally_disabled); return 0;
}
int32_t sw_workshop_subscriptions(bool include_locally_disabled, uint64_t *out, size_t capacity, uint32_t *count) {
    if (capacity > 1024 || (!out && capacity)) return -2;
    if (!capacity) { *count = 0; return 0; }
    auto *ugc = SteamAPI_SteamUGC_v021(); if (!ugc) return -1;
    PublishedFileId_t ids[1024]{};
    // This distinct C++ method also defaults to false (not inferred from count).
    *count = SteamAPI_ISteamUGC_GetSubscribedItems(ugc, ids, static_cast<uint32>(capacity), include_locally_disabled);
    if (*count > capacity) return -3;
    for (uint32_t i = 0; i < *count; ++i) out[i] = ids[i];
    return 0;
}
int32_t sw_workshop_state(uint64_t item, uint32_t *flags) {
    auto *ugc = SteamAPI_SteamUGC_v021(); if (!ugc) return -1;
    *flags = SteamAPI_ISteamUGC_GetItemState(ugc, item); return 0;
}
int32_t sw_workshop_install(uint64_t item, char *path, size_t capacity, bool *found, uint64_t *size, uint32_t *timestamp, size_t *length) {
    if (!path || !capacity || capacity > UINT32_MAX) return -2;
    auto *ugc = SteamAPI_SteamUGC_v021(); if (!ugc) return -1;
    uint64 bytes = 0; uint32 time = 0;
    *found = SteamAPI_ISteamUGC_GetItemInstallInfo(ugc, item, &bytes, path, static_cast<uint32>(capacity), &time);
    *size = bytes; *timestamp = time; *length = 0;
    if (*found) {
        const auto *end = static_cast<const char *>(memchr(path, 0, capacity));
        if (!end) return -4;
        *length = static_cast<size_t>(end - path);
    }
    return 0;
}
int32_t sw_workshop_progress(uint64_t item, bool *found, uint64_t *downloaded, uint64_t *total) {
    auto *ugc = SteamAPI_SteamUGC_v021(); if (!ugc) return -1;
    uint64 bytes = 0, all = 0;
    *found = SteamAPI_ISteamUGC_GetItemDownloadInfo(ugc, item, &bytes, &all);
    *downloaded = bytes; *total = all; return 0;
}
int32_t sw_workshop_download(uint64_t item, bool high_priority, bool *accepted) {
    auto *ugc = SteamAPI_SteamUGC_v021(); if (!ugc) return -1;
    *accepted = SteamAPI_ISteamUGC_DownloadItem(ugc, item, high_priority); return 0;
}

#ifdef SW_WORKSHOP_TEST
int main() {
    using namespace workshop_test;
    const uint64_t ids[] = {17, 0, 17}; uint64_t h = 42, call = 0;
    CHECK(sw_workshop_create(ids, 3, &h) == 0 && h == 0 && ids[0] == 17);
    handle = UINT64_MAX;
    CHECK(sw_workshop_create(ids, 3, &h) == 0 && h == UINT64_MAX);
    const auto before = accessors;
    CHECK(sw_workshop_create(ids, 0, &h) == -2);
    CHECK(sw_workshop_create(ids, 51, &h) == -2 && accessors == before);
    CHECK(sw_workshop_send(0, &call) == 0 && call == 71 && handle == 0);
    bool ok = false;
    CHECK(sw_workshop_release(0, &ok) == 0 && ok && handle == 0);
    scratch.m_nPublishedFileId = 17; scratch.m_eResult = k_EResultFail;
    scratch.m_eFileType = k_EWorkshopFileTypeGame; scratch.m_nCreatorAppID = 19; scratch.m_nConsumerAppID = 23;
    memset(scratch.m_rgchTitle, 't', sizeof(scratch.m_rgchTitle));
    memset(scratch.m_rgchDescription, 'd', sizeof(scratch.m_rgchDescription));
    scratch.m_ulSteamIDOwner = 29; scratch.m_rtimeCreated = 31; scratch.m_rtimeUpdated = 37; scratch.m_rtimeAddedToUserList = 41;
    scratch.m_eVisibility = k_ERemoteStoragePublishedFileVisibilityUnlisted;
    scratch.m_bBanned = true; scratch.m_bAcceptedForUse = true; scratch.m_bTagsTruncated = true;
    memset(scratch.m_rgchTags, 'g', sizeof(scratch.m_rgchTags));
    scratch.m_hFile = 43; scratch.m_hPreviewFile = 47;
    memset(scratch.m_pchFileName, 'f', sizeof(scratch.m_pchFileName));
    scratch.m_nFileSize = -53; scratch.m_nPreviewFileSize = -59;
    memset(scratch.m_rgchURL, 'u', sizeof(scratch.m_rgchURL));
    scratch.m_unVotesUp = 61; scratch.m_unVotesDown = 67; scratch.m_flScore = 0.25f;
    scratch.m_unNumChildren = 71; scratch.m_ulTotalFilesSize = UINT64_MAX;
    struct sw_workshop_details out{};
    CHECK(sw_workshop_details(0, 2, &out, &ok) == 0 && ok && row == 2 && handle == 0);
    CHECK(out.item == 17 && out.result == k_EResultFail && out.file_type == k_EWorkshopFileTypeGame);
    CHECK(out.creator_app == 19 && out.consumer_app == 23 && out.owner == 29);
    CHECK(out.created == 31 && out.updated == 37 && out.added_to_list == 41);
    CHECK(out.visibility == k_ERemoteStoragePublishedFileVisibilityUnlisted && out.banned && out.accepted_for_use && out.tags_truncated);
    CHECK(out.file == 43 && out.preview_file == 47 && out.file_size == -53 && out.preview_file_size == -59);
    CHECK(out.votes_up == 61 && out.votes_down == 67 && out.score == 0.25f && out.children == 71 && out.total_files_size == UINT64_MAX);
    CHECK(memcmp(out.title, scratch.m_rgchTitle, sizeof(out.title)) == 0);
    CHECK(memcmp(out.description, scratch.m_rgchDescription, sizeof(out.description)) == 0);
    CHECK(memcmp(out.tags, scratch.m_rgchTags, sizeof(out.tags)) == 0);
    CHECK(memcmp(out.filename, scratch.m_pchFileName, sizeof(out.filename)) == 0);
    CHECK(memcmp(out.url, scratch.m_rgchURL, sizeof(out.url)) == 0);
    // SDK 1.65's EResult range is 0..255. This unnamed value is representable.
    constexpr EResult unknown_result = static_cast<EResult>(255);
    scratch.m_eResult = unknown_result;
    CHECK(sw_workshop_details(0, 2, &out, &ok) == 0 && ok && out.result == 255);
    const auto saved = out; scratch = {};
    CHECK(sw_workshop_release(0, &ok) == 0 && memcmp(&out, &saved, sizeof(out)) == 0);
    accepted = false;
    CHECK(sw_workshop_details(0, 0, &out, &ok) == 0 && !ok && memcmp(&out, &saved, sizeof(out)) == 0);
    CHECK(sw_workshop_send(0, &call) == 0 && call == 0);
    CHECK(sw_workshop_release(0, &ok) == 0 && !ok);
    uint32_t n = 0; uint64_t output[3] = {99,99,99};
    CHECK(sw_workshop_count(false, &n) == 0 && n == 3 && !include_disabled);
    CHECK(sw_workshop_count(true, &n) == 0 && include_disabled);
    CHECK(sw_workshop_subscriptions(false, output, 3, &n) == 0 && n == 3 && !include_disabled);
    CHECK(output[0] == 17 && output[1] == 0 && output[2] == 17);
    reported = 4; output[0] = 99;
    CHECK(sw_workshop_subscriptions(true, output, 3, &n) == -3 && n == 4 && output[0] == 99 && include_disabled);
    const auto bounded = accessors;
    CHECK(sw_workshop_subscriptions(false, output, 1025, &n) == -2);
    CHECK(sw_workshop_subscriptions(false, nullptr, 0, &n) == 0 && n == 0 && accessors == bounded);
    CHECK(sw_workshop_state(17, &n) == 0 && n == 0x80000045 && item == 17);
    char path[8]{}; uint64_t size = 0, total = 9; uint32_t time = 0; size_t length = 9;
    CHECK(sw_workshop_install(17, path, sizeof(path), &ok, &size, &time, &length) == 0 && !ok && path[0] == 'x' && length == 0 && size == UINT64_MAX && time == 31);
    CHECK(sw_workshop_progress(17, &ok, &size, &total) == 0 && !ok && size == UINT64_MAX && total == 0);
    CHECK(sw_workshop_download(17, false, &ok) == 0 && !ok && !priority);
    accepted = true;
    CHECK(sw_workshop_install(17, path, sizeof(path), &ok, &size, &time, &length) == 0 && ok && length == 7);
    CHECK(sw_workshop_install(17, path, 1, &ok, &size, &time, &length) == -4);
    CHECK(sw_workshop_progress(17, &ok, &size, &total) == 0 && ok && total == 0);
    CHECK(sw_workshop_download(17, true, &ok) == 0 && ok && priority);
    available = false; const auto invoked = calls;
    CHECK(sw_workshop_create(ids, 3, &h) == -1);
    CHECK(sw_workshop_send(0, &call) == -1);
    CHECK(sw_workshop_release(0, &ok) == -1);
    CHECK(sw_workshop_details(0, 0, &out, &ok) == -1);
    CHECK(sw_workshop_count(false, &n) == -1);
    CHECK(sw_workshop_subscriptions(false, output, 3, &n) == -1);
    CHECK(sw_workshop_state(17, &n) == -1);
    CHECK(sw_workshop_install(17, path, sizeof(path), &ok, &size, &time, &length) == -1);
    CHECK(sw_workshop_progress(17, &ok, &size, &total) == -1);
    CHECK(sw_workshop_download(17, false, &ok) == -1 && calls == invoked);
    puts("Workshop official-signature fixture passed (all 11 substitutions)");
}
#endif
