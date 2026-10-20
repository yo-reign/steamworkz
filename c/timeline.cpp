#include "timeline.h"
#include <steam/steam_api_flat.h>

static_assert(SW_TIMELINE_MAX_PRIORITY == k_unMaxTimelinePriority);
static_assert(SW_TIMELINE_KEEP_PRIORITY == k_unTimelinePriority_KeepCurrentValue);
static_assert(SW_TIMELINE_DEFAULT_CLIP == k_ETimelineEventClipPriority_None);
static_assert(k_ETimelineGameMode_Playing == 1 && k_ETimelineGameMode_Staging == 2 &&
              k_ETimelineGameMode_Menus == 3 && k_ETimelineGameMode_LoadingScreen == 4);
static_assert(k_ETimelineEventClipPriority_Standard == 2 && k_ETimelineEventClipPriority_Featured == 3);

#ifdef SW_TIMELINE_TEST
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
// Debug emits the official abstract base vtable. A pure call is always a
// fixture defect; satisfy its ABI entry point without a C++ runtime library.
extern "C" void __cxa_pure_virtual() { abort(); }
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #x); abort(); } } while (0)
namespace timeline_test {
static char token;
static ISteamTimeline *const timeline = reinterpret_cast<ISteamTimeline *>(&token);
static bool available = true;
static unsigned calls, accessors, ends, removes;
static uint64_t result, handle;
static uint32 priority;
static float offset, duration;
static ETimelineEventClipPriority clip = k_ETimelineEventClipPriority_None;
static ETimelineGameMode mode = k_ETimelineGameMode_Playing;
static void check(ISteamTimeline *self) { CHECK(self == timeline); ++calls; }
static void fields(const char *t, const char *d, const char *i, uint32 p, ETimelineEventClipPriority c) {
    CHECK(strcmp(t, "title") == 0); CHECK(strcmp(d, "description") == 0); CHECK(strcmp(i, "icon") == 0);
    priority = p; clip = c;
}
static decltype(SteamAPI_SteamTimeline_v004) accessor;
static ISteamTimeline *accessor() { ++accessors; return available ? timeline : nullptr; }
static decltype(SteamAPI_ISteamTimeline_SetTimelineGameMode) set_mode;
static void set_mode(ISteamTimeline *self, ETimelineGameMode value) { check(self); mode = value; }
static decltype(SteamAPI_ISteamTimeline_SetTimelineTooltip) tooltip;
static void tooltip(ISteamTimeline *self, const char *d, float o) { check(self); CHECK(strcmp(d, "description") == 0); offset = o; }
static decltype(SteamAPI_ISteamTimeline_ClearTimelineTooltip) clear;
static void clear(ISteamTimeline *self, float o) { check(self); offset = o; }
static decltype(SteamAPI_ISteamTimeline_AddInstantaneousTimelineEvent) instant;
static TimelineEventHandle_t instant(ISteamTimeline *self, const char *t, const char *d, const char *i, uint32 p, float o, ETimelineEventClipPriority c) {
    check(self); fields(t, d, i, p, c); offset = o; return result;
}
static decltype(SteamAPI_ISteamTimeline_AddRangeTimelineEvent) completed;
static TimelineEventHandle_t completed(ISteamTimeline *self, const char *t, const char *d, const char *i, uint32 p, float o, float dur, ETimelineEventClipPriority c) {
    duration = dur; return instant(self, t, d, i, p, o, c);
}
static decltype(SteamAPI_ISteamTimeline_StartRangeTimelineEvent) start;
static TimelineEventHandle_t start(ISteamTimeline *self, const char *t, const char *d, const char *i, uint32 p, float o, ETimelineEventClipPriority c) {
    return instant(self, t, d, i, p, o, c);
}
static decltype(SteamAPI_ISteamTimeline_UpdateRangeTimelineEvent) update;
static void update(ISteamTimeline *self, TimelineEventHandle_t h, const char *t, const char *d, const char *i, uint32 p, ETimelineEventClipPriority c) {
    check(self); fields(t, d, i, p, c); handle = h;
}
static decltype(SteamAPI_ISteamTimeline_EndRangeTimelineEvent) end;
static void end(ISteamTimeline *self, TimelineEventHandle_t h, float o) { check(self); handle = h; offset = o; ++ends; }
static decltype(SteamAPI_ISteamTimeline_RemoveTimelineEvent) remove;
static void remove(ISteamTimeline *self, TimelineEventHandle_t h) { check(self); handle = h; ++removes; }

// A real official-interface object verifies default arguments at the SDK's
// declaration, rather than comparing two copies of wrapper constants.
struct Defaults final : ISteamTimeline {
    void SetTimelineTooltip(const char *, float) override { CHECK(false); }
    void ClearTimelineTooltip(float) override { CHECK(false); }
    void SetTimelineGameMode(ETimelineGameMode) override { CHECK(false); }
    TimelineEventHandle_t AddInstantaneousTimelineEvent(const char *t, const char *d, const char *i, uint32 p, float o, ETimelineEventClipPriority c) override {
        return instant(timeline, t, d, i, p, o, c);
    }
    TimelineEventHandle_t AddRangeTimelineEvent(const char *t, const char *d, const char *i, uint32 p, float o, float dur, ETimelineEventClipPriority c) override {
        return completed(timeline, t, d, i, p, o, dur, c);
    }
    TimelineEventHandle_t StartRangeTimelineEvent(const char *, const char *, const char *, uint32, float, ETimelineEventClipPriority) override { CHECK(false); return 0; }
    void UpdateRangeTimelineEvent(TimelineEventHandle_t, const char *, const char *, const char *, uint32, ETimelineEventClipPriority) override { CHECK(false); }
    void EndRangeTimelineEvent(TimelineEventHandle_t, float) override { CHECK(false); }
    void RemoveTimelineEvent(TimelineEventHandle_t) override { CHECK(false); }
    SteamAPICall_t DoesEventRecordingExist(TimelineEventHandle_t) override { CHECK(false); return 0; }
    void StartGamePhase() override { CHECK(false); }
    void EndGamePhase() override { CHECK(false); }
    void SetGamePhaseID(const char *) override { CHECK(false); }
    SteamAPICall_t DoesGamePhaseRecordingExist(const char *) override { CHECK(false); return 0; }
    void AddGamePhaseTag(const char *, const char *, const char *, uint32) override { CHECK(false); }
    void SetGamePhaseAttribute(const char *, const char *, uint32) override { CHECK(false); }
    void OpenOverlayToGamePhase(const char *) override { CHECK(false); }
    void OpenOverlayToTimelineEvent(TimelineEventHandle_t) override { CHECK(false); }
};
}
#define SteamAPI_SteamTimeline_v004 timeline_test::accessor
#define SteamAPI_ISteamTimeline_SetTimelineGameMode timeline_test::set_mode
#define SteamAPI_ISteamTimeline_SetTimelineTooltip timeline_test::tooltip
#define SteamAPI_ISteamTimeline_ClearTimelineTooltip timeline_test::clear
#define SteamAPI_ISteamTimeline_AddInstantaneousTimelineEvent timeline_test::instant
#define SteamAPI_ISteamTimeline_AddRangeTimelineEvent timeline_test::completed
#define SteamAPI_ISteamTimeline_StartRangeTimelineEvent timeline_test::start
#define SteamAPI_ISteamTimeline_UpdateRangeTimelineEvent timeline_test::update
#define SteamAPI_ISteamTimeline_EndRangeTimelineEvent timeline_test::end
#define SteamAPI_ISteamTimeline_RemoveTimelineEvent timeline_test::remove
#endif

extern "C" int32_t sw_timeline_mode(int32_t mode) {
    auto *const timeline = SteamAPI_SteamTimeline_v004();
    if (!timeline) return -1;
    SteamAPI_ISteamTimeline_SetTimelineGameMode(timeline, static_cast<ETimelineGameMode>(mode));
    return 0;
}
extern "C" int32_t sw_timeline_tooltip(const char *description, float offset) {
    auto *const timeline = SteamAPI_SteamTimeline_v004();
    if (!timeline) return -1;
    SteamAPI_ISteamTimeline_SetTimelineTooltip(timeline, description, offset);
    return 0;
}
extern "C" int32_t sw_timeline_clear_tooltip(float offset) {
    auto *const timeline = SteamAPI_SteamTimeline_v004();
    if (!timeline) return -1;
    SteamAPI_ISteamTimeline_ClearTimelineTooltip(timeline, offset);
    return 0;
}
extern "C" int32_t sw_timeline_instant(const char *title, const char *description, const char *icon, uint32_t priority, float offset, int32_t clip, uint64_t *handle) {
    *handle = 0;
    auto *const timeline = SteamAPI_SteamTimeline_v004();
    if (!timeline) return -1;
    *handle = SteamAPI_ISteamTimeline_AddInstantaneousTimelineEvent(timeline, title, description, icon, priority, offset, static_cast<ETimelineEventClipPriority>(clip));
    return 0;
}
extern "C" int32_t sw_timeline_completed(const char *title, const char *description, const char *icon, uint32_t priority, float offset, float duration, int32_t clip, uint64_t *handle) {
    *handle = 0;
    auto *const timeline = SteamAPI_SteamTimeline_v004();
    if (!timeline) return -1;
    *handle = SteamAPI_ISteamTimeline_AddRangeTimelineEvent(timeline, title, description, icon, priority, offset, duration, static_cast<ETimelineEventClipPriority>(clip));
    return 0;
}
extern "C" int32_t sw_timeline_start(const char *title, const char *description, const char *icon, uint32_t priority, float offset, int32_t clip, uint64_t *handle) {
    *handle = 0;
    auto *const timeline = SteamAPI_SteamTimeline_v004();
    if (!timeline) return -1;
    *handle = SteamAPI_ISteamTimeline_StartRangeTimelineEvent(timeline, title, description, icon, priority, offset, static_cast<ETimelineEventClipPriority>(clip));
    return 0;
}
extern "C" int32_t sw_timeline_update(uint64_t handle, const char *title, const char *description, const char *icon, uint32_t priority, int32_t clip) {
    auto *const timeline = SteamAPI_SteamTimeline_v004();
    if (!timeline) return -1;
    SteamAPI_ISteamTimeline_UpdateRangeTimelineEvent(timeline, handle, title, description, icon, priority, static_cast<ETimelineEventClipPriority>(clip));
    return 0;
}
extern "C" int32_t sw_timeline_end(uint64_t handle, float offset) {
    auto *const timeline = SteamAPI_SteamTimeline_v004();
    if (!timeline) return -1;
    SteamAPI_ISteamTimeline_EndRangeTimelineEvent(timeline, handle, offset);
    return 0;
}
extern "C" int32_t sw_timeline_remove(uint64_t handle) {
    auto *const timeline = SteamAPI_SteamTimeline_v004();
    if (!timeline) return -1;
    SteamAPI_ISteamTimeline_RemoveTimelineEvent(timeline, handle);
    return 0;
}

#ifdef SW_TIMELINE_TEST
int main() {
    using namespace timeline_test;
    CHECK(SW_TIMELINE_MAX_DURATION == k_flMaxTimelineEventDuration);
    Defaults defaults;
    ISteamTimeline &official = defaults;
    official.AddInstantaneousTimelineEvent("title", "description", "icon", 0);
    CHECK(offset == SW_TIMELINE_DEFAULT_OFFSET && clip == SW_TIMELINE_DEFAULT_CLIP);
    official.AddRangeTimelineEvent("title", "description", "icon", 0);
    CHECK(offset == SW_TIMELINE_DEFAULT_OFFSET && duration == SW_TIMELINE_DEFAULT_DURATION && clip == SW_TIMELINE_DEFAULT_CLIP);
    CHECK(sw_timeline_mode(k_ETimelineGameMode_LoadingScreen) == 0 && mode == k_ETimelineGameMode_LoadingScreen);
    CHECK(sw_timeline_tooltip("description", -3) == 0 && offset == -3);
    CHECK(sw_timeline_clear_tooltip(-2) == 0 && offset == -2);
    uint64_t out = UINT64_MAX;
    result = 0;
    CHECK(sw_timeline_instant("title", "description", "icon", 0, SW_TIMELINE_DEFAULT_OFFSET, SW_TIMELINE_DEFAULT_CLIP, &out) == 0);
    CHECK(out == 0 && priority == 0 && offset == 0 && clip == k_ETimelineEventClipPriority_None);
    result = UINT64_MAX;
    CHECK(sw_timeline_completed("title", "description", "icon", SW_TIMELINE_MAX_PRIORITY, -600, SW_TIMELINE_MAX_DURATION, k_ETimelineEventClipPriority_Featured, &out) == 0);
    CHECK(out == UINT64_MAX && priority == k_unMaxTimelinePriority && offset == -600 && duration == k_flMaxTimelineEventDuration && clip == k_ETimelineEventClipPriority_Featured);
    result = 0;
    CHECK(sw_timeline_start("title", "description", "icon", 7, -4, k_ETimelineEventClipPriority_Standard, &out) == 0);
    CHECK(out == 0 && priority == 7 && offset == -4 && clip == k_ETimelineEventClipPriority_Standard);
    CHECK(sw_timeline_update(0, "title", "description", "icon", SW_TIMELINE_KEEP_PRIORITY, k_ETimelineEventClipPriority_None) == 0);
    CHECK(handle == 0 && priority == k_unTimelinePriority_KeepCurrentValue && clip == k_ETimelineEventClipPriority_None);
    CHECK(sw_timeline_end(0, -1) == 0 && handle == 0 && offset == -1 && ends == 1);
    CHECK(sw_timeline_remove(UINT64_MAX) == 0 && handle == UINT64_MAX && removes == 1);
    available = false;
    const unsigned before = calls, before_accessors = accessors;
    CHECK(sw_timeline_mode(k_ETimelineGameMode_Playing) == -1);
    CHECK(sw_timeline_tooltip("description", 0) == -1);
    CHECK(sw_timeline_clear_tooltip(0) == -1);
    out = UINT64_MAX;
    CHECK(sw_timeline_instant("title", "description", "icon", 0, 0, SW_TIMELINE_DEFAULT_CLIP, &out) == -1 && out == 0);
    out = UINT64_MAX;
    CHECK(sw_timeline_completed("title", "description", "icon", 0, 0, 0, SW_TIMELINE_DEFAULT_CLIP, &out) == -1 && out == 0);
    out = UINT64_MAX;
    CHECK(sw_timeline_start("title", "description", "icon", 0, 0, SW_TIMELINE_DEFAULT_CLIP, &out) == -1 && out == 0);
    CHECK(sw_timeline_update(0, "title", "description", "icon", 0, SW_TIMELINE_DEFAULT_CLIP) == -1);
    CHECK(sw_timeline_end(0, 0) == -1);
    CHECK(sw_timeline_remove(0) == -1);
    CHECK(calls == before && accessors == before_accessors + 9);
    puts("Timeline native fixture passed (all 10 native symbols substituted)");
}
#endif
