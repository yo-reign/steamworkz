#include "utils.h"
#include <steam/steam_api_flat.h>
#include <string.h>

#ifdef SW_UTILS_TEST
#include <stdio.h>
#include <stdlib.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #x); abort(); } } while (0)
namespace utils_test {
static char token;
static ISteamUtils *const utils = reinterpret_cast<ISteamUtils *>(&token);
static bool available = true, accepted = true, retrieval = true, terminate = true;
static unsigned accesses, shows, dismissals, inits, filters, configs, app_queries, length_queries, text_queries;
static uint32_t length = 1;
static char text[SW_UTILS_TEXT_CAPACITY];
static decltype(SteamAPI_SteamUtils_v011) accessor;
static ISteamUtils *accessor() { ++accesses; return available ? utils : nullptr; }
static decltype(SteamAPI_ISteamUtils_ShowGamepadTextInput) show_gamepad;
static bool show_gamepad(ISteamUtils *self, EGamepadTextInputMode mode, EGamepadTextInputLineMode lines, const char *description, uint32 chars, const char *existing) {
    CHECK(self == utils && mode == k_EGamepadTextInputModePassword && lines == k_EGamepadTextInputLineModeMultipleLines);
    CHECK(strcmp(description, "description") == 0 && chars == UINT32_MAX && strcmp(existing, "existing") == 0);
    ++shows; return accepted;
}
static decltype(SteamAPI_ISteamUtils_GetAppID) app_id;
static uint32 app_id(ISteamUtils *self) { CHECK(self == utils); ++app_queries; return 73; }
static decltype(SteamAPI_ISteamUtils_ShowFloatingGamepadTextInput) show_floating;
static bool show_floating(ISteamUtils *self, EFloatingGamepadTextInputMode mode, int x, int y, int width, int height) {
    CHECK(self == utils && mode == k_EFloatingGamepadTextInputModeModeNumeric && x == -7 && y == -9 && width == 23 && height == 31);
    ++shows; return accepted;
}
static decltype(SteamAPI_ISteamUtils_DismissGamepadTextInput) dismiss_gamepad;
static bool dismiss_gamepad(ISteamUtils *self) { CHECK(self == utils); ++dismissals; return accepted; }
static decltype(SteamAPI_ISteamUtils_DismissFloatingGamepadTextInput) dismiss_floating;
static bool dismiss_floating(ISteamUtils *self) { CHECK(self == utils); ++dismissals; return accepted; }
static decltype(SteamAPI_ISteamUtils_InitFilterText) init_filter;
static bool init_filter(ISteamUtils *self, uint32 options) { CHECK(self == utils && options == 0); ++inits; return accepted; }
static decltype(SteamAPI_ISteamUtils_FilterText) filter;
static int filter(ISteamUtils *self, ETextFilteringContext context, uint64 source, const char *input, char *output, uint32 capacity) {
    CHECK(self == utils && context == k_ETextFilteringContextChat && source == 123456 && strcmp(input, "input") == 0 && capacity == 12);
    ++filters; memcpy(output, "\xc3\xa9*", 4); return -3;
}
static decltype(SteamAPI_ISteamUtils_GetSteamHardwareDefaultConfig) default_config;
static ESteamHardwareDefaultConfig default_config(ISteamUtils *self) { CHECK(self == utils); ++configs; return k_ESteamHardwareDefaultConfigSteamFrame; }
static decltype(SteamAPI_ISteamUtils_GetEnteredGamepadTextLength) text_length;
static uint32 text_length(ISteamUtils *self) { CHECK(self == utils); ++length_queries; return length; }
static decltype(SteamAPI_ISteamUtils_GetEnteredGamepadTextInput) get_text;
static bool get_text(ISteamUtils *self, char *output, uint32 capacity) {
    CHECK(self == utils && capacity == length && capacity <= sizeof(text));
    for (uint32 i = 0; i < capacity; ++i) CHECK(output[i] != 0);
    ++text_queries;
    if (retrieval && terminate) memcpy(output, text, capacity);
    return retrieval;
}
static void reset() {
    available = accepted = retrieval = terminate = true;
    accesses = shows = dismissals = inits = filters = configs = app_queries = length_queries = text_queries = 0;
    length = 1; memset(text, 0, sizeof(text));
}
}
#define SteamAPI_SteamUtils_v011 utils_test::accessor
#define SteamAPI_ISteamUtils_ShowGamepadTextInput utils_test::show_gamepad
#define SteamAPI_ISteamUtils_GetAppID utils_test::app_id
#define SteamAPI_ISteamUtils_ShowFloatingGamepadTextInput utils_test::show_floating
#define SteamAPI_ISteamUtils_DismissGamepadTextInput utils_test::dismiss_gamepad
#define SteamAPI_ISteamUtils_DismissFloatingGamepadTextInput utils_test::dismiss_floating
#define SteamAPI_ISteamUtils_InitFilterText utils_test::init_filter
#define SteamAPI_ISteamUtils_FilterText utils_test::filter
#define SteamAPI_ISteamUtils_GetSteamHardwareDefaultConfig utils_test::default_config
#define SteamAPI_ISteamUtils_GetEnteredGamepadTextLength utils_test::text_length
#define SteamAPI_ISteamUtils_GetEnteredGamepadTextInput utils_test::get_text
#endif

extern "C" int32_t sw_utils_show_gamepad(int32_t mode, int32_t lines, const char *description, uint32_t max_chars, const char *existing, uint32_t *app_id) {
    *app_id = 0;
    if (mode < 0 || mode > 1 || lines < 0 || lines > 1) return -2;
    auto *const utils = SteamAPI_SteamUtils_v011();
    if (!utils) return -1;
    const bool accepted = SteamAPI_ISteamUtils_ShowGamepadTextInput(utils, static_cast<EGamepadTextInputMode>(mode), static_cast<EGamepadTextInputLineMode>(lines), description, max_chars, existing);
    if (accepted) *app_id = SteamAPI_ISteamUtils_GetAppID(utils);
    return accepted;
}
extern "C" int32_t sw_utils_show_floating(int32_t mode, int32_t x, int32_t y, int32_t width, int32_t height) {
    if (mode < 0 || mode > 3 || width <= 0 || height <= 0) return -2;
    auto *const utils = SteamAPI_SteamUtils_v011();
    return utils ? SteamAPI_ISteamUtils_ShowFloatingGamepadTextInput(utils, static_cast<EFloatingGamepadTextInputMode>(mode), x, y, width, height) : -1;
}
extern "C" int32_t sw_utils_dismiss_gamepad() {
    auto *const utils = SteamAPI_SteamUtils_v011();
    return utils ? SteamAPI_ISteamUtils_DismissGamepadTextInput(utils) : -1;
}
extern "C" int32_t sw_utils_dismiss_floating() {
    auto *const utils = SteamAPI_SteamUtils_v011();
    return utils ? SteamAPI_ISteamUtils_DismissFloatingGamepadTextInput(utils) : -1;
}
extern "C" int32_t sw_utils_init_filter() {
    auto *const utils = SteamAPI_SteamUtils_v011();
    return utils ? SteamAPI_ISteamUtils_InitFilterText(utils, 0) : -1;
}
extern "C" int32_t sw_utils_filter(int32_t context, uint64_t source, const char *input, char *output, uint32_t capacity, int32_t *filtered_chars) {
    *filtered_chars = 0;
    if (context < 0 || context > 3) return -2;
    auto *const utils = SteamAPI_SteamUtils_v011();
    if (!utils) return -1;
    *filtered_chars = SteamAPI_ISteamUtils_FilterText(utils, static_cast<ETextFilteringContext>(context), source, input, output, capacity);
    return 0;
}
extern "C" int32_t sw_utils_default_config(int32_t *config) {
    *config = 0;
    auto *const utils = SteamAPI_SteamUtils_v011();
    if (!utils) return -1;
    const auto value = SteamAPI_ISteamUtils_GetSteamHardwareDefaultConfig(utils);
    static_assert(sizeof(value) == sizeof(*config), "Hardware configuration enum width changed");
    memcpy(config, &value, sizeof(*config));
    return 0;
}
extern "C" void sw_utils_capture_gamepad_text(uint8_t submitted, uint32_t reported_length, SwUtilsTextCapture *out) {
    *out = {};
    out->reported_length = reported_length;
    if (!submitted) { out->status = SW_UTILS_TEXT_CANCELED; return; }
    auto *const utils = SteamAPI_SteamUtils_v011();
    if (!utils) { out->status = SW_UTILS_TEXT_UNAVAILABLE; return; }
    out->queried_length = SteamAPI_ISteamUtils_GetEnteredGamepadTextLength(utils);
    if (reported_length == 0 || out->queried_length != reported_length) { out->status = SW_UTILS_TEXT_MALFORMED; return; }
    if (reported_length > sizeof(out->bytes)) { out->status = SW_UTILS_TEXT_TOO_LARGE; return; }
    memset(out->bytes, 0x7f, reported_length);
    if (!SteamAPI_ISteamUtils_GetEnteredGamepadTextInput(utils, reinterpret_cast<char *>(out->bytes), reported_length)) {
        out->status = SW_UTILS_TEXT_RETRIEVAL_FAILED; return;
    }
    const auto *const end = static_cast<const uint8_t *>(memchr(out->bytes, 0, reported_length));
    if (!end) { out->status = SW_UTILS_TEXT_MALFORMED; return; }
    out->copied_length = static_cast<uint32_t>(end - out->bytes);
    out->status = SW_UTILS_TEXT_COMPLETE;
}

#ifdef SW_UTILS_TEST
int main() {
    using namespace utils_test;
    reset();
    uint32_t app = 999;
    CHECK(sw_utils_show_gamepad(2, 1, "", 0, "", &app) == -2 && accesses == 0 && app == 0);
    CHECK(sw_utils_show_gamepad(1, -1, "", 0, "", &app) == -2 && accesses == 0);
    CHECK(sw_utils_show_floating(4, 0, 0, 1, 1) == -2 && accesses == 0);
    CHECK(sw_utils_show_floating(0, 0, 0, 0, 1) == -2 && accesses == 0);
    CHECK(sw_utils_show_gamepad(1, 1, "description", UINT32_MAX, "existing", &app) == 1 && app == 73 && accesses == 1 && app_queries == 1);
    accepted = false;
    CHECK(sw_utils_show_gamepad(1, 1, "description", UINT32_MAX, "existing", &app) == 0 && app == 0 && app_queries == 1);
    CHECK(sw_utils_show_floating(3, -7, -9, 23, 31) == 0);
    CHECK(sw_utils_dismiss_gamepad() == 0 && sw_utils_dismiss_floating() == 0);
    CHECK(sw_utils_init_filter() == 0);
    accepted = true;
    CHECK(sw_utils_show_floating(3, -7, -9, 23, 31) == 1);
    CHECK(sw_utils_dismiss_gamepad() == 1 && sw_utils_dismiss_floating() == 1);
    CHECK(sw_utils_init_filter() == 1);
    char output[12]; int32_t count = 99, config = -1;
    const auto before = accesses;
    CHECK(sw_utils_filter(4, 0, "", output, sizeof(output), &count) == -2 && accesses == before);
    CHECK(sw_utils_filter(2, 123456, "input", output, sizeof(output), &count) == 0 && count == -3 && strlen(output) == 3);
    CHECK(sw_utils_default_config(&config) == 0 && config == 7);
    available = false;
    CHECK(sw_utils_show_gamepad(1, 1, "description", UINT32_MAX, "existing", &app) == -1);
    CHECK(sw_utils_show_floating(3, -7, -9, 23, 31) == -1);
    CHECK(sw_utils_dismiss_gamepad() == -1 && sw_utils_dismiss_floating() == -1 && sw_utils_init_filter() == -1);
    CHECK(sw_utils_filter(2, 123456, "input", output, sizeof(output), &count) == -1);
    CHECK(sw_utils_default_config(&config) == -1);
    CHECK(shows == 4 && dismissals == 4 && inits == 2 && filters == 1 && configs == 1);

    reset(); SwUtilsTextCapture capture;
    sw_utils_capture_gamepad_text(0, 5000, &capture);
    CHECK(capture.status == SW_UTILS_TEXT_CANCELED && capture.reported_length == 5000 && accesses == 0 && length_queries == 0 && text_queries == 0);
    sw_utils_capture_gamepad_text(1, 1, &capture);
    CHECK(capture.status == SW_UTILS_TEXT_COMPLETE && capture.copied_length == 0 && capture.queried_length == 1);
    length = 4; memcpy(text, "\xc3\xa9!", 4);
    sw_utils_capture_gamepad_text(1, 4, &capture);
    CHECK(capture.status == SW_UTILS_TEXT_COMPLETE && capture.copied_length == 3);
    memset(text, 'X', sizeof(text));
    CHECK(memcmp(capture.bytes, "\xc3\xa9!", 4) == 0);
    const auto gets = text_queries;
    sw_utils_capture_gamepad_text(1, 3, &capture);
    CHECK(capture.status == SW_UTILS_TEXT_MALFORMED && capture.reported_length == 3 && capture.queried_length == 4 && text_queries == gets);
    length = 0; sw_utils_capture_gamepad_text(1, 0, &capture);
    CHECK(capture.status == SW_UTILS_TEXT_MALFORMED && text_queries == gets);
    length = sizeof(text); text[sizeof(text) - 1] = 0;
    sw_utils_capture_gamepad_text(1, length, &capture);
    CHECK(capture.status == SW_UTILS_TEXT_COMPLETE && capture.copied_length == sizeof(text) - 1);
    length = sizeof(text) + 1;
    sw_utils_capture_gamepad_text(1, length, &capture);
    CHECK(capture.status == SW_UTILS_TEXT_TOO_LARGE && text_queries == gets + 1);
    length = 4; retrieval = false;
    sw_utils_capture_gamepad_text(1, length, &capture);
    CHECK(capture.status == SW_UTILS_TEXT_RETRIEVAL_FAILED && capture.copied_length == 0);
    retrieval = true; terminate = false;
    sw_utils_capture_gamepad_text(1, length, &capture);
    CHECK(capture.status == SW_UTILS_TEXT_MALFORMED && capture.copied_length == 0);
    available = false; const auto queries = length_queries;
    sw_utils_capture_gamepad_text(1, length, &capture);
    CHECK(capture.status == SW_UTILS_TEXT_UNAVAILABLE && length_queries == queries);
    puts("utils native fixtures passed");
}
#endif
