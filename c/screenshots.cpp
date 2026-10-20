#include "screenshots.h"
#include <steam/steam_api_flat.h>

static_assert(sizeof(ScreenshotHandle) == sizeof(uint32_t));
static_assert(sizeof(int) == sizeof(int32_t));

#ifdef SW_SCREENSHOTS_TEST
#include <stdio.h>
#include <stdlib.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #x); abort(); } } while (0)
namespace screenshots_test {
static char token;
static ISteamScreenshots *const screenshots = reinterpret_cast<ISteamScreenshots *>(&token);
static bool available = true, hooked = false;
static unsigned accessors, calls, triggers, setters;
static ScreenshotHandle result = 1;
static void *rgb;
static uint32 bytes;
static int width, height;
static const char *path, *thumbnail;
static decltype(SteamAPI_SteamScreenshots_v003) accessor;
static ISteamScreenshots *accessor() { ++accessors; return available ? screenshots : nullptr; }
static void check(ISteamScreenshots *self) { CHECK(self == screenshots); ++calls; }
static decltype(SteamAPI_ISteamScreenshots_WriteScreenshot) write;
static ScreenshotHandle write(ISteamScreenshots *self, void *input, uint32 size, int w, int h) {
    check(self); rgb = input; bytes = size; width = w; height = h; return result;
}
static decltype(SteamAPI_ISteamScreenshots_AddScreenshotToLibrary) add;
static ScreenshotHandle add(ISteamScreenshots *self, const char *file, const char *thumb, int w, int h) {
    check(self); path = file; thumbnail = thumb; width = w; height = h; return result;
}
static decltype(SteamAPI_ISteamScreenshots_TriggerScreenshot) trigger;
static void trigger(ISteamScreenshots *self) { check(self); ++triggers; }
static decltype(SteamAPI_ISteamScreenshots_HookScreenshots) hook;
static void hook(ISteamScreenshots *self, bool value) { check(self); ++setters; hooked = value; }
static decltype(SteamAPI_ISteamScreenshots_IsScreenshotsHooked) is_hooked;
static bool is_hooked(ISteamScreenshots *self) { check(self); return hooked; }
}
#define SteamAPI_SteamScreenshots_v003 screenshots_test::accessor
#define SteamAPI_ISteamScreenshots_WriteScreenshot screenshots_test::write
#define SteamAPI_ISteamScreenshots_AddScreenshotToLibrary screenshots_test::add
#define SteamAPI_ISteamScreenshots_TriggerScreenshot screenshots_test::trigger
#define SteamAPI_ISteamScreenshots_HookScreenshots screenshots_test::hook
#define SteamAPI_ISteamScreenshots_IsScreenshotsHooked screenshots_test::is_hooked
#endif

// SDK 1.65: none of these five selected methods has default/reserved arguments.
bool sw_screenshots_write(void *rgb, uint32_t bytes, int32_t width, int32_t height, uint32_t *handle) {
    auto *const screenshots = SteamAPI_SteamScreenshots_v003();
    if (!screenshots) return false;
    *handle = SteamAPI_ISteamScreenshots_WriteScreenshot(screenshots, rgb, bytes, width, height);
    return true;
}
bool sw_screenshots_add(const char *path, const char *thumbnail, int32_t width, int32_t height, uint32_t *handle) {
    auto *const screenshots = SteamAPI_SteamScreenshots_v003();
    if (!screenshots) return false;
    *handle = SteamAPI_ISteamScreenshots_AddScreenshotToLibrary(screenshots, path, thumbnail, width, height);
    return true;
}
bool sw_screenshots_trigger(void) {
    auto *const screenshots = SteamAPI_SteamScreenshots_v003();
    if (!screenshots) return false;
    SteamAPI_ISteamScreenshots_TriggerScreenshot(screenshots);
    return true;
}
bool sw_screenshots_hook(bool enabled) {
    auto *const screenshots = SteamAPI_SteamScreenshots_v003();
    if (!screenshots) return false;
    SteamAPI_ISteamScreenshots_HookScreenshots(screenshots, enabled);
    return true;
}
bool sw_screenshots_is_hooked(bool *hooked) {
    auto *const screenshots = SteamAPI_SteamScreenshots_v003();
    if (!screenshots) return false;
    *hooked = SteamAPI_ISteamScreenshots_IsScreenshotsHooked(screenshots);
    return true;
}

#ifdef SW_SCREENSHOTS_TEST
int main() {
    using namespace screenshots_test;
    uint8_t storage[6] = {};
    const char file[] = "/inert-shot", thumb[] = "/inert-thumb";
    uint32_t handle = 99;
    bool state = true;
    const uint32_t handles[] = {0, 1, UINT32_MAX};
    for (const uint32_t value : handles) {
        result = value;
        CHECK(sw_screenshots_write(storage, sizeof(storage), 2, 1, &handle));
        CHECK(handle == value && rgb == storage && bytes == sizeof(storage) && width == 2 && height == 1);
        CHECK(sw_screenshots_add(file, nullptr, 400, 200, &handle));
        CHECK(handle == value && path == file && thumbnail == nullptr && width == 400 && height == 200);
        CHECK(sw_screenshots_add(file, thumb, 400, 200, &handle));
        CHECK(handle == value && thumbnail == thumb);
    }
    CHECK(sw_screenshots_is_hooked(&state) && !state);
    CHECK(sw_screenshots_hook(true));
    CHECK(sw_screenshots_is_hooked(&state) && state);
    CHECK(sw_screenshots_trigger() && triggers == 1);
    CHECK(sw_screenshots_hook(false));
    CHECK(sw_screenshots_is_hooked(&state) && !state && setters == 2);
    available = false;
    const unsigned previous_calls = calls, previous_accessors = accessors;
    handle = 99; state = true;
    CHECK(!sw_screenshots_write(storage, sizeof(storage), 2, 1, &handle));
    CHECK(!sw_screenshots_add(file, nullptr, 2, 1, &handle));
    CHECK(!sw_screenshots_trigger());
    CHECK(!sw_screenshots_hook(false));
    CHECK(!sw_screenshots_is_hooked(&state));
    CHECK(handle == 99 && state && calls == previous_calls && accessors == previous_accessors + 5);
    return 0;
}
#endif
