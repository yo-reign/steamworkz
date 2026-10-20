#include "input.h"
#include <steam/steam_api_flat.h>
#include <string.h>

static_assert(SW_INPUT_MAX_CONTROLLERS == STEAM_INPUT_MAX_COUNT);
static_assert(SW_INPUT_MAX_LAYERS == STEAM_INPUT_MAX_ACTIVE_LAYERS);
static_assert(SW_INPUT_MAX_ORIGINS == STEAM_INPUT_MAX_ORIGINS);
static_assert(SW_INPUT_MAX_ANALOG_ACTIONS == STEAM_INPUT_MAX_ANALOG_ACTIONS);
static_assert(SW_INPUT_MAX_DIGITAL_ACTIONS == STEAM_INPUT_MAX_DIGITAL_ACTIONS);
static_assert(SW_INPUT_MAX_ORIGIN == k_EInputActionOrigin_MaximumPossibleValue);
static_assert(SW_INPUT_MAX_TYPE == k_ESteamInputType_MaximumPossibleValue);

#ifdef SW_INPUT_TEST
#include <stdio.h>
#include <stdlib.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #x); abort(); } } while (0)
namespace input_test {
static char token;
static ISteamInput *const input = reinterpret_cast<ISteamInput *>(&token);
static bool available = true, accepted = true;
static unsigned calls, accessors, notifications;
static int count;
static uint64_t controller, action_set, action;
static uint16_t motors[4];
static int32_t origin, device_type, glyph_size;
static uint32_t glyph_style, operation;
static const char *text = "glyph/path";
static bool digital_state = true, active = false;
static float x = -1234.5f, y = -0.0f;
static decltype(SteamAPI_SteamInput_v007) accessor;
static ISteamInput *accessor() { ++accessors; return available ? input : nullptr; }
static void check(ISteamInput *self) { CHECK(self == input); ++calls; }
static decltype(SteamAPI_ISteamInput_Init) init;
static bool init(ISteamInput *self, bool explicit_frame) { check(self); CHECK(explicit_frame); return accepted; }
static decltype(SteamAPI_ISteamInput_Shutdown) stop;
static bool stop(ISteamInput *self) { check(self); return accepted; }
static decltype(SteamAPI_ISteamInput_EnableDeviceCallbacks) callbacks;
static void callbacks(ISteamInput *self) { check(self); ++notifications; }
static decltype(SteamAPI_ISteamInput_RunFrame) frame;
static void frame(ISteamInput *self, bool reserved) { check(self); CHECK(reserved); }
static decltype(SteamAPI_ISteamInput_SetInputActionManifestFilePath) manifest;
static bool manifest(ISteamInput *self, const char *path) { check(self); CHECK(strcmp(path, "/manifest.vdf") == 0); return accepted; }
template<class T, size_t N> static int enumeration(T *out) {
    // Fill the whole official capacity even when reporting zero/invalid counts.
    for (size_t i = 0; i < N; ++i) out[i] = static_cast<T>(1000 + i);
    return count;
}
static decltype(SteamAPI_ISteamInput_GetConnectedControllers) controllers;
static int controllers(ISteamInput *self, InputHandle_t *out) { check(self); return enumeration<InputHandle_t, STEAM_INPUT_MAX_COUNT>(out); }
static decltype(SteamAPI_ISteamInput_GetActiveActionSetLayers) layers;
static int layers(ISteamInput *self, InputHandle_t h, InputActionSetHandle_t *out) { check(self); controller = h; return enumeration<InputActionSetHandle_t, STEAM_INPUT_MAX_ACTIVE_LAYERS>(out); }
static decltype(SteamAPI_ISteamInput_GetActionSetHandle) set_handle;
static InputActionSetHandle_t set_handle(ISteamInput *self, const char *name) { check(self); CHECK(strcmp(name, "action") == 0); return UINT64_MAX - 1; }
static decltype(SteamAPI_ISteamInput_GetDigitalActionHandle) digital_handle;
static InputDigitalActionHandle_t digital_handle(ISteamInput *self, const char *name) { return set_handle(self, name); }
static decltype(SteamAPI_ISteamInput_GetAnalogActionHandle) analog_handle;
static InputAnalogActionHandle_t analog_handle(ISteamInput *self, const char *name) { return set_handle(self, name); }
static decltype(SteamAPI_ISteamInput_ActivateActionSet) activate;
static void activate(ISteamInput *self, InputHandle_t h, InputActionSetHandle_t a) { check(self); controller = h; action_set = a; operation = 0; }
static decltype(SteamAPI_ISteamInput_ActivateActionSetLayer) activate_layer;
static void activate_layer(ISteamInput *self, InputHandle_t h, InputActionSetHandle_t a) { activate(self, h, a); operation = 1; }
static decltype(SteamAPI_ISteamInput_DeactivateActionSetLayer) deactivate_layer;
static void deactivate_layer(ISteamInput *self, InputHandle_t h, InputActionSetHandle_t a) { activate(self, h, a); operation = 2; }
static decltype(SteamAPI_ISteamInput_DeactivateAllActionSetLayers) deactivate_all;
static void deactivate_all(ISteamInput *self, InputHandle_t h) { activate(self, h, 0); operation = 3; }
static decltype(SteamAPI_ISteamInput_GetCurrentActionSet) current_set;
static InputActionSetHandle_t current_set(ISteamInput *self, InputHandle_t h) { check(self); controller = h; return UINT64_MAX; }
static decltype(SteamAPI_ISteamInput_GetDigitalActionData) digital_data;
static InputDigitalActionData_t digital_data(ISteamInput *self, InputHandle_t h, InputDigitalActionHandle_t a) { check(self); controller = h; action = a; return {digital_state, active}; }
static decltype(SteamAPI_ISteamInput_GetAnalogActionData) analog_data;
static InputAnalogActionData_t analog_data(ISteamInput *self, InputHandle_t h, InputAnalogActionHandle_t a) { check(self); controller = h; action = a; return {k_EInputSourceMode_RelativeMouse, x, y, active}; }
static decltype(SteamAPI_ISteamInput_GetDigitalActionOrigins) digital_origins;
static int digital_origins(ISteamInput *self, InputHandle_t h, InputActionSetHandle_t s, InputDigitalActionHandle_t a, EInputActionOrigin *out) { check(self); controller = h; action_set = s; action = a; return enumeration<EInputActionOrigin, STEAM_INPUT_MAX_ORIGINS>(out); }
static decltype(SteamAPI_ISteamInput_GetAnalogActionOrigins) analog_origins;
static int analog_origins(ISteamInput *self, InputHandle_t h, InputActionSetHandle_t s, InputAnalogActionHandle_t a, EInputActionOrigin *out) { return digital_origins(self, h, s, a, out); }
static decltype(SteamAPI_ISteamInput_GetInputTypeForHandle) input_type;
static ESteamInputType input_type(ISteamInput *self, InputHandle_t h) { check(self); controller = h; return static_cast<ESteamInputType>(254); }
static decltype(SteamAPI_ISteamInput_TranslateActionOrigin) translate;
static EInputActionOrigin translate(ISteamInput *self, ESteamInputType type, EInputActionOrigin from) { check(self); device_type = type; origin = from; return static_cast<EInputActionOrigin>(32000); }
static decltype(SteamAPI_ISteamInput_GetGlyphPNGForActionOrigin) png;
static const char *png(ISteamInput *self, EInputActionOrigin from, ESteamInputGlyphSize size, uint32 style) { check(self); origin = from; glyph_size = size; glyph_style = style; return text; }
static decltype(SteamAPI_ISteamInput_GetGlyphSVGForActionOrigin) svg;
static const char *svg(ISteamInput *self, EInputActionOrigin from, uint32 style) { check(self); origin = from; glyph_style = style; return text; }
static decltype(SteamAPI_ISteamInput_GetStringForActionOrigin) origin_name;
static const char *origin_name(ISteamInput *self, EInputActionOrigin from) { check(self); origin = from; return text; }
static decltype(SteamAPI_ISteamInput_GetStringForDigitalActionName) digital_name;
static const char *digital_name(ISteamInput *self, InputDigitalActionHandle_t a) { check(self); action = a; return text; }
static decltype(SteamAPI_ISteamInput_GetStringForAnalogActionName) analog_name;
static const char *analog_name(ISteamInput *self, InputAnalogActionHandle_t a) { check(self); action = a; return text; }
static decltype(SteamAPI_ISteamInput_TriggerVibration) vibrate;
static void vibrate(ISteamInput *self, InputHandle_t h, unsigned short l, unsigned short r) { check(self); controller = h; motors[0] = l; motors[1] = r; }
static decltype(SteamAPI_ISteamInput_TriggerVibrationExtended) vibrate_extended;
static void vibrate_extended(ISteamInput *self, InputHandle_t h, unsigned short l, unsigned short r, unsigned short lt, unsigned short rt) { vibrate(self, h, l, r); motors[2] = lt; motors[3] = rt; }
}
#define SteamAPI_SteamInput_v007 input_test::accessor
#define SteamAPI_ISteamInput_Init input_test::init
#define SteamAPI_ISteamInput_Shutdown input_test::stop
#define SteamAPI_ISteamInput_EnableDeviceCallbacks input_test::callbacks
#define SteamAPI_ISteamInput_RunFrame input_test::frame
#define SteamAPI_ISteamInput_SetInputActionManifestFilePath input_test::manifest
#define SteamAPI_ISteamInput_GetConnectedControllers input_test::controllers
#define SteamAPI_ISteamInput_GetActionSetHandle input_test::set_handle
#define SteamAPI_ISteamInput_GetDigitalActionHandle input_test::digital_handle
#define SteamAPI_ISteamInput_GetAnalogActionHandle input_test::analog_handle
#define SteamAPI_ISteamInput_ActivateActionSet input_test::activate
#define SteamAPI_ISteamInput_ActivateActionSetLayer input_test::activate_layer
#define SteamAPI_ISteamInput_DeactivateActionSetLayer input_test::deactivate_layer
#define SteamAPI_ISteamInput_DeactivateAllActionSetLayers input_test::deactivate_all
#define SteamAPI_ISteamInput_GetCurrentActionSet input_test::current_set
#define SteamAPI_ISteamInput_GetActiveActionSetLayers input_test::layers
#define SteamAPI_ISteamInput_GetDigitalActionData input_test::digital_data
#define SteamAPI_ISteamInput_GetAnalogActionData input_test::analog_data
#define SteamAPI_ISteamInput_GetDigitalActionOrigins input_test::digital_origins
#define SteamAPI_ISteamInput_GetAnalogActionOrigins input_test::analog_origins
#define SteamAPI_ISteamInput_GetInputTypeForHandle input_test::input_type
#define SteamAPI_ISteamInput_TranslateActionOrigin input_test::translate
#define SteamAPI_ISteamInput_GetGlyphPNGForActionOrigin input_test::png
#define SteamAPI_ISteamInput_GetGlyphSVGForActionOrigin input_test::svg
#define SteamAPI_ISteamInput_GetStringForActionOrigin input_test::origin_name
#define SteamAPI_ISteamInput_GetStringForDigitalActionName input_test::digital_name
#define SteamAPI_ISteamInput_GetStringForAnalogActionName input_test::analog_name
#define SteamAPI_ISteamInput_TriggerVibration input_test::vibrate
#define SteamAPI_ISteamInput_TriggerVibrationExtended input_test::vibrate_extended
#endif

namespace {
template<class T> static int32_t enum_bits(const T &value) {
    int32_t result;
    static_assert(sizeof(value) == sizeof(result), "Input enum width changed");
    memcpy(&result, &value, sizeof(result));
    return result;
}
static bool valid_origin(int32_t origin) { return origin >= 0 && origin <= k_EInputActionOrigin_MaximumPossibleValue; }
static bool valid_style(uint32_t style) { return (style & ~uint32_t(0x33)) == 0 && (style & 3) != 3; }
template<class Native, class Owned, size_t N>
static int32_t publish(const Native (&values)[N], int count, Owned *out, size_t capacity, size_t *written) {
    *written = 0;
    if (count < 0 || size_t(count) > N) return -3;
    if (size_t(count) > capacity) return -4;
    static_assert(sizeof(Native) == sizeof(Owned), "Input output width changed");
    // The arrays contain only native u64 handles or i32 enum representations.
    for (int i = 0; i < count; ++i) memcpy(out + i, values + i, sizeof(Owned));
    *written = size_t(count);
    return 0;
}
}

extern "C" int32_t sw_input_start(bool notifications, bool *accepted) {
    *accepted = false;
    auto *const input = SteamAPI_SteamInput_v007();
    if (!input) return -1;
    *accepted = SteamAPI_ISteamInput_Init(input, true);
    if (*accepted && notifications) SteamAPI_ISteamInput_EnableDeviceCallbacks(input);
    return 0;
}
extern "C" int32_t sw_input_stop(bool *accepted) {
    *accepted = false;
    auto *const input = SteamAPI_SteamInput_v007();
    if (!input) return -1;
    *accepted = SteamAPI_ISteamInput_Shutdown(input);
    return 0;
}
extern "C" int32_t sw_input_frame() {
    auto *const input = SteamAPI_SteamInput_v007();
    if (!input) return -1;
    // Match ISteamInput::RunFrame's reserved default.
    SteamAPI_ISteamInput_RunFrame(input, true);
    return 0;
}
extern "C" int32_t sw_input_manifest(const char *path, bool *accepted) {
    *accepted = false;
    auto *const input = SteamAPI_SteamInput_v007();
    if (!input) return -1;
    *accepted = SteamAPI_ISteamInput_SetInputActionManifestFilePath(input, path);
    return 0;
}
extern "C" int32_t sw_input_controllers(uint64_t *out, size_t capacity, size_t *count) {
    *count = 0;
    auto *const input = SteamAPI_SteamInput_v007();
    if (!input) return -1;
    InputHandle_t values[STEAM_INPUT_MAX_COUNT]{};
    const int n = SteamAPI_ISteamInput_GetConnectedControllers(input, values);
    return publish(values, n, out, capacity, count);
}
extern "C" int32_t sw_input_lookup(uint32_t kind, const char *name, uint64_t *out) {
    *out = 0;
    if (kind > 2) return -2;
    auto *const input = SteamAPI_SteamInput_v007();
    if (!input) return -1;
    switch (kind) {
    case 0: *out = SteamAPI_ISteamInput_GetActionSetHandle(input, name); break;
    case 1: *out = SteamAPI_ISteamInput_GetDigitalActionHandle(input, name); break;
    case 2: *out = SteamAPI_ISteamInput_GetAnalogActionHandle(input, name); break;
    }
    return 0;
}
extern "C" int32_t sw_input_activate(uint32_t operation, uint64_t controller, uint64_t set) {
    if (operation > 3) return -2;
    auto *const input = SteamAPI_SteamInput_v007();
    if (!input) return -1;
    switch (operation) {
    case 0: SteamAPI_ISteamInput_ActivateActionSet(input, controller, set); break;
    case 1: SteamAPI_ISteamInput_ActivateActionSetLayer(input, controller, set); break;
    case 2: SteamAPI_ISteamInput_DeactivateActionSetLayer(input, controller, set); break;
    case 3: SteamAPI_ISteamInput_DeactivateAllActionSetLayers(input, controller); break;
    }
    return 0;
}
extern "C" int32_t sw_input_current_set(uint64_t controller, uint64_t *out) {
    *out = 0;
    auto *const input = SteamAPI_SteamInput_v007();
    if (!input) return -1;
    *out = SteamAPI_ISteamInput_GetCurrentActionSet(input, controller);
    return 0;
}
extern "C" int32_t sw_input_layers(uint64_t controller, uint64_t *out, size_t capacity, size_t *count) {
    *count = 0;
    auto *const input = SteamAPI_SteamInput_v007();
    if (!input) return -1;
    InputActionSetHandle_t values[STEAM_INPUT_MAX_ACTIVE_LAYERS]{};
    const int n = SteamAPI_ISteamInput_GetActiveActionSetLayers(input, controller, values);
    return publish(values, n, out, capacity, count);
}
extern "C" int32_t sw_input_digital_data(uint64_t controller, uint64_t action, sw_input_digital *out) {
    *out = {};
    auto *const input = SteamAPI_SteamInput_v007();
    if (!input) return -1;
    const auto data = SteamAPI_ISteamInput_GetDigitalActionData(input, controller, action);
    out->state = data.bState; out->active = data.bActive;
    return 0;
}
extern "C" int32_t sw_input_analog_data(uint64_t controller, uint64_t action, sw_input_analog *out) {
    *out = {};
    auto *const input = SteamAPI_SteamInput_v007();
    if (!input) return -1;
    const auto data = SteamAPI_ISteamInput_GetAnalogActionData(input, controller, action);
    out->mode = enum_bits(data.eMode); out->x = data.x; out->y = data.y; out->active = data.bActive;
    return 0;
}
extern "C" int32_t sw_input_origins(bool analog, uint64_t controller, uint64_t set, uint64_t action, int32_t *out, size_t capacity, size_t *count) {
    *count = 0;
    auto *const input = SteamAPI_SteamInput_v007();
    if (!input) return -1;
    EInputActionOrigin values[STEAM_INPUT_MAX_ORIGINS]{};
    const int n = analog ? SteamAPI_ISteamInput_GetAnalogActionOrigins(input, controller, set, action, values) : SteamAPI_ISteamInput_GetDigitalActionOrigins(input, controller, set, action, values);
    return publish(values, n, out, capacity, count);
}
extern "C" int32_t sw_input_type(uint64_t controller, int32_t *out) {
    *out = 0;
    auto *const input = SteamAPI_SteamInput_v007();
    if (!input) return -1;
    *out = enum_bits(SteamAPI_ISteamInput_GetInputTypeForHandle(input, controller));
    return 0;
}
extern "C" int32_t sw_input_translate(int32_t type, int32_t origin, int32_t *out) {
    *out = 0;
    if (type < 0 || type > k_ESteamInputType_MaximumPossibleValue || !valid_origin(origin)) return -2;
    auto *const input = SteamAPI_SteamInput_v007();
    if (!input) return -1;
    *out = enum_bits(SteamAPI_ISteamInput_TranslateActionOrigin(input, static_cast<ESteamInputType>(type), static_cast<EInputActionOrigin>(origin)));
    return 0;
}
extern "C" int32_t sw_input_text(uint32_t kind, uint64_t action, int32_t origin, int32_t size, uint32_t style, char *out, size_t capacity, size_t *length) {
    *length = 0;
    if (kind > 4 || (kind <= 2 && !valid_origin(origin)) ||
        (kind <= 1 && !valid_style(style)) || (kind == 0 && (size < 0 || size >= k_ESteamInputGlyphSize_Count))) return -2;
    auto *const input = SteamAPI_SteamInput_v007();
    if (!input) return -1;
    const char *text = nullptr;
    switch (kind) {
    case 0: text = SteamAPI_ISteamInput_GetGlyphPNGForActionOrigin(input, static_cast<EInputActionOrigin>(origin), static_cast<ESteamInputGlyphSize>(size), style); break;
    case 1: text = SteamAPI_ISteamInput_GetGlyphSVGForActionOrigin(input, static_cast<EInputActionOrigin>(origin), style); break;
    case 2: text = SteamAPI_ISteamInput_GetStringForActionOrigin(input, static_cast<EInputActionOrigin>(origin)); break;
    case 3: text = SteamAPI_ISteamInput_GetStringForDigitalActionName(input, action); break;
    case 4: text = SteamAPI_ISteamInput_GetStringForAnalogActionName(input, action); break;
    }
    if (!text) return -5;
    const size_t n = strlen(text);
    if (n > capacity) return -4;
    if (n) memcpy(out, text, n);
    *length = n;
    return 0;
}
extern "C" int32_t sw_input_vibration(uint64_t controller, uint16_t left, uint16_t right) {
    auto *const input = SteamAPI_SteamInput_v007();
    if (!input) return -1;
    SteamAPI_ISteamInput_TriggerVibration(input, controller, left, right);
    return 0;
}
extern "C" int32_t sw_input_vibration_extended(uint64_t controller, uint16_t left, uint16_t right, uint16_t left_trigger, uint16_t right_trigger) {
    auto *const input = SteamAPI_SteamInput_v007();
    if (!input) return -1;
    SteamAPI_ISteamInput_TriggerVibrationExtended(input, controller, left, right, left_trigger, right_trigger);
    return 0;
}

#ifdef SW_INPUT_TEST
int main() {
    using namespace input_test;
    bool ok = false;
    const bool booleans[] = {false, true};
    const int32_t bad_sizes[] = {-1, 3, INT32_MAX};
    const uint32_t bad_styles[] = {3u, 4u, 0x40u, UINT32_MAX};
    for (bool acceptance : booleans) {
        accepted = acceptance;
        for (bool notify : booleans) {
            const unsigned before = notifications;
            CHECK(sw_input_start(notify, &ok) == 0 && ok == acceptance);
            CHECK(notifications == before + unsigned(acceptance && notify));
        }
        CHECK(sw_input_stop(&ok) == 0 && ok == acceptance);
        CHECK(sw_input_manifest("/manifest.vdf", &ok) == 0 && ok == acceptance);
    }
    CHECK(sw_input_frame() == 0);
    uint64_t handles[STEAM_INPUT_MAX_COUNT + 1];
    int32_t origins[STEAM_INPUT_MAX_ORIGINS + 1];
    size_t written = 99;
    // Each native function writes its entire official array, even when the
    // requested public capacity is zero. Guard elements check publication.
    for (unsigned which = 0; which < 4; ++which) {
        const int maximum = which < 2 ? STEAM_INPUT_MAX_COUNT : STEAM_INPUT_MAX_ORIGINS;
        const int counts[] = {-1, 0, 1, maximum, maximum + 1};
        for (int n : counts) for (size_t capacity = 0; capacity <= size_t(maximum); ++capacity) {
            for (auto &v : handles) v = UINT64_MAX;
            for (auto &v : origins) v = -1;
            count = n;
            const int32_t expected = n < 0 || n > maximum ? -3 : size_t(n) > capacity ? -4 : 0;
            const int32_t result = which == 0 ? sw_input_controllers(handles, capacity, &written) :
                which == 1 ? sw_input_layers(71, handles, capacity, &written) :
                sw_input_origins(which == 3, 71, 72, 73, origins, capacity, &written);
            CHECK(result == expected && written == (result == 0 ? size_t(n) : 0));
            if (which != 0) CHECK(controller == 71);
            if (which >= 2) CHECK(action_set == 72 && action == 73);
            for (int i = 0; i <= maximum; ++i) {
                if (which < 2) CHECK(handles[i] == (size_t(i) < written ? uint64_t(1000 + i) : UINT64_MAX));
                else CHECK(origins[i] == (size_t(i) < written ? 1000 + i : -1));
            }
        }
    }
    uint64_t value;
    for (uint32_t kind = 0; kind < 3; ++kind) CHECK(sw_input_lookup(kind, "action", &value) == 0 && value == UINT64_MAX - 1);
    for (uint32_t op = 0; op < 4; ++op) {
        CHECK(sw_input_activate(op, STEAM_INPUT_HANDLE_ALL_CONTROLLERS, 91) == 0);
        CHECK(operation == op && controller == UINT64_MAX && action_set == (op == 3 ? 0 : 91));
    }
    CHECK(sw_input_current_set(97, &value) == 0 && value == UINT64_MAX && controller == 97);
    sw_input_digital digital{};
    for (bool a : booleans) for (bool s : booleans) {
        active = a; digital_state = s;
        CHECK(sw_input_digital_data(81, 82, &digital) == 0);
        CHECK(controller == 81 && action == 82 && digital.active == a && digital.state == s);
    }
    sw_input_analog analog{};
    const uint32_t float_bits[] = {0x80000000, 0x7fc12345, 0x7f800000, 0xc49a5000};
    for (uint32_t bits : float_bits) {
        memcpy(&x, &bits, sizeof(x));
        const uint32_t other = bits ^ 0x80000000;
        memcpy(&y, &other, sizeof(y));
        CHECK(sw_input_analog_data(83, 84, &analog) == 0);
        CHECK(controller == 83 && action == 84 && analog.mode == k_EInputSourceMode_RelativeMouse && analog.active == active);
        CHECK(memcmp(&analog.x, &x, sizeof(x)) == 0 && memcmp(&analog.y, &y, sizeof(y)) == 0);
    }
    int32_t translated;
    CHECK(sw_input_type(89, &translated) == 0 && translated == 254 && controller == 89);
    CHECK(sw_input_translate(255, 32767, &translated) == 0 && translated == 32000);
    CHECK(device_type == 255 && origin == 32767);
    char buffer[32];
    for (uint32_t kind = 0; kind < 5; ++kind) {
        for (uint32_t base = 0; base <= 2; ++base) for (uint32_t modifiers = 0; modifiers <= 0x30; modifiers += 0x10) {
            const uint32_t style = base | modifiers;
            text = "glyph/path";
            memset(buffer, '!', sizeof(buffer));
            CHECK(sw_input_text(kind, 99, 32767, 2, style, buffer, 9, &written) == -4 && written == 0 && buffer[0] == '!');
            CHECK(sw_input_text(kind, 99, 32767, 2, style, buffer, 10, &written) == 0 && written == 10);
            CHECK(memcmp(buffer, "glyph/path", 10) == 0 && buffer[10] == '!');
            if (kind <= 2) CHECK(origin == 32767); else CHECK(action == 99);
            if (kind <= 1) CHECK(glyph_style == style);
            if (kind == 0) CHECK(glyph_size == 2);
            text = "changed";
            CHECK(memcmp(buffer, "glyph/path", 10) == 0);
            text = "";
            CHECK(sw_input_text(kind, 99, 32767, 2, style, buffer, 0, &written) == 0 && written == 0);
            text = nullptr;
            CHECK(sw_input_text(kind, 99, 32767, 2, style, buffer, sizeof(buffer), &written) == -5 && written == 0);
        }
    }
    const unsigned before_invalid = accessors;
    CHECK(sw_input_lookup(3, "action", &value) == -2);
    CHECK(sw_input_activate(4, 0, 0) == -2);
    CHECK(sw_input_translate(-1, 0, &translated) == -2);
    CHECK(sw_input_translate(256, 0, &translated) == -2);
    CHECK(sw_input_translate(0, -1, &translated) == -2);
    CHECK(sw_input_translate(0, 32768, &translated) == -2);
    for (int32_t bad : bad_sizes) CHECK(sw_input_text(0, 0, 0, bad, 0, buffer, sizeof(buffer), &written) == -2);
    for (uint32_t bad : bad_styles) {
        CHECK(sw_input_text(0, 0, 0, 0, bad, buffer, sizeof(buffer), &written) == -2);
        CHECK(sw_input_text(1, 0, 0, 0, bad, buffer, sizeof(buffer), &written) == -2);
    }
    CHECK(sw_input_text(2, 0, -1, 0, 0, buffer, sizeof(buffer), &written) == -2);
    CHECK(sw_input_text(5, 0, 0, 0, 0, buffer, sizeof(buffer), &written) == -2);
    CHECK(accessors == before_invalid);
    CHECK(sw_input_vibration(UINT64_MAX, 0, UINT16_MAX) == 0);
    CHECK(controller == UINT64_MAX && motors[0] == 0 && motors[1] == UINT16_MAX);
    CHECK(sw_input_vibration_extended(87, 1, 2, 3, UINT16_MAX) == 0);
    CHECK(controller == 87 && motors[0] == 1 && motors[1] == 2 && motors[2] == 3 && motors[3] == UINT16_MAX);
    available = false;
    const unsigned before = calls;
    CHECK(sw_input_start(true, &ok) == -1 && !ok);
    CHECK(sw_input_stop(&ok) == -1 && !ok);
    CHECK(sw_input_manifest("/manifest.vdf", &ok) == -1 && !ok);
    CHECK(sw_input_frame() == -1);
    CHECK(sw_input_controllers(handles, 0, &written) == -1 && written == 0);
    for (uint32_t kind = 0; kind < 3; ++kind) CHECK(sw_input_lookup(kind, "action", &value) == -1);
    for (uint32_t op = 0; op < 4; ++op) CHECK(sw_input_activate(op, 0, 0) == -1);
    CHECK(sw_input_current_set(0, &value) == -1);
    CHECK(sw_input_layers(0, handles, 0, &written) == -1 && written == 0);
    CHECK(sw_input_digital_data(0, 0, &digital) == -1 && !digital.active && !digital.state);
    CHECK(sw_input_analog_data(0, 0, &analog) == -1 && !analog.active);
    CHECK(sw_input_origins(false, 0, 0, 0, origins, 0, &written) == -1 && written == 0);
    CHECK(sw_input_origins(true, 0, 0, 0, origins, 0, &written) == -1 && written == 0);
    CHECK(sw_input_type(0, &translated) == -1);
    CHECK(sw_input_translate(0, 0, &translated) == -1);
    for (uint32_t kind = 0; kind < 5; ++kind) CHECK(sw_input_text(kind, 0, 0, 0, 0, buffer, sizeof(buffer), &written) == -1 && written == 0);
    CHECK(sw_input_vibration(0, 0, 0) == -1);
    CHECK(sw_input_vibration_extended(0, 0, 0, 0, 0) == -1);
    CHECK(calls == before);
    puts("Input inert fixture passed");
}
#endif
