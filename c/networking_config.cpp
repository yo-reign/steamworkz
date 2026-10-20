#include "networking_config.h"
#include <steam/steam_api_flat.h>

#ifdef SW_NETWORKING_CONFIG_TEST
#include <stdio.h>
#include <stdlib.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #x); abort(); } } while (0)
namespace config_test {
static char token;
static ISteamNetworkingUtils *const utils = reinterpret_cast<ISteamNetworkingUtils *>(&token);
static bool available = true;
static unsigned accessors, calls, reject_at;
struct Call {
    ESteamNetworkingConfigValue key;
    ESteamNetworkingConfigScope scope;
    intptr_t handle;
    ESteamNetworkingConfigDataType type;
    bool clear;
    int32_t integer;
    float real;
};
static Call history[8];
static Call applied[7];
static bool track_simulation;
static ESteamNetworkingGetConfigValueResult status = k_ESteamNetworkingGetConfigValue_OK;
static ESteamNetworkingConfigDataType data_type = k_ESteamNetworkingConfig_Int32;
static size_t reported_size = sizeof(int32_t);
static int32_t returned_value = -1234567;
static bool write_value = true;
static decltype(SteamAPI_SteamNetworkingUtils_SteamAPI_v004) accessor;
static ISteamNetworkingUtils *accessor() { ++accessors; return available ? utils : nullptr; }
static decltype(SteamAPI_ISteamNetworkingUtils_SetConfigValue) setter;
static bool setter(ISteamNetworkingUtils *self, ESteamNetworkingConfigValue key, ESteamNetworkingConfigScope scope, intptr_t handle, ESteamNetworkingConfigDataType type, const void *value) {
    CHECK(self == utils && calls < 8);
    Call &c = history[calls++];
    c = {key, scope, handle, type, value == nullptr, 0, 0};
    if (value) {
        if (type == k_ESteamNetworkingConfig_Int32) c.integer = *static_cast<const int32_t *>(value);
        else { CHECK(type == k_ESteamNetworkingConfig_Float); c.real = *static_cast<const float *>(value); }
    }
    const bool accepted = calls != reject_at;
    if (accepted && track_simulation) { CHECK(calls <= 7); applied[calls - 1] = c; }
    return accepted;
}
static decltype(SteamAPI_ISteamNetworkingUtils_GetConfigValue) getter;
static ESteamNetworkingGetConfigValueResult getter(ISteamNetworkingUtils *self, ESteamNetworkingConfigValue key, ESteamNetworkingConfigScope scope, intptr_t handle, ESteamNetworkingConfigDataType *type, void *value, size_t *size) {
    CHECK(self == utils && calls < 8 && *size == sizeof(int32_t));
    CHECK(*static_cast<int32_t *>(value) == 0);
    history[calls++] = {key, scope, handle, k_ESteamNetworkingConfig_Int32, false, 0, 0};
    *type = data_type; *size = reported_size;
    if (write_value) *static_cast<int32_t *>(value) = returned_value;
    return status;
}
static void reset() {
    accessors = calls = reject_at = 0; available = true; track_simulation = false;
    for (auto &c : applied) c = {k_ESteamNetworkingConfig_Invalid, k_ESteamNetworkingConfig_Global, 0, k_ESteamNetworkingConfig_Int32, false, -999, -999};
}
}
#define SteamAPI_SteamNetworkingUtils_SteamAPI_v004 config_test::accessor
#define SteamAPI_ISteamNetworkingUtils_SetConfigValue config_test::setter
#define SteamAPI_ISteamNetworkingUtils_GetConfigValue config_test::getter
#endif

namespace {
static constexpr ESteamNetworkingConfigValue options[] = {
    k_ESteamNetworkingConfig_TimeoutInitial, k_ESteamNetworkingConfig_TimeoutConnected,
    k_ESteamNetworkingConfig_SendBufferSize, k_ESteamNetworkingConfig_SendRateMin,
    k_ESteamNetworkingConfig_SendRateMax, k_ESteamNetworkingConfig_NagleTime,
};
static constexpr ESteamNetworkingConfigValue simulation_keys[] = {
    k_ESteamNetworkingConfig_FakePacketLoss_Send, k_ESteamNetworkingConfig_FakePacketLoss_Recv,
    k_ESteamNetworkingConfig_FakePacketLag_Send, k_ESteamNetworkingConfig_FakePacketLag_Recv,
    k_ESteamNetworkingConfig_FakePacketReorder_Send, k_ESteamNetworkingConfig_FakePacketReorder_Recv,
    k_ESteamNetworkingConfig_FakePacketReorder_Time,
};
static bool scope_from(uint32_t scope, ESteamNetworkingConfigScope &out) {
    switch (scope) {
    case 0: out = k_ESteamNetworkingConfig_Global; return true;
    case 1: out = k_ESteamNetworkingConfig_ListenSocket; return true;
    case 2: out = k_ESteamNetworkingConfig_Connection; return true;
    default: return false;
    }
}
static bool percentage(float value) { return value >= 0.0f && value <= 100.0f; }
static bool valid(const sw_config_simulation &s) {
    return percentage(s.send_loss_percent) && percentage(s.receive_loss_percent) &&
        percentage(s.send_reorder_percent) && percentage(s.receive_reorder_percent) &&
        s.send_lag_ms >= 0 && s.receive_lag_ms >= 0 && s.reorder_delay_ms >= 0;
}
static int32_t simulate(const sw_config_simulation *s, sw_config_simulation_result *out) {
    *out = {};
    if (s && !valid(*s)) return -2;
    auto *const utils = SteamAPI_SteamNetworkingUtils_SteamAPI_v004();
    if (!utils) return -1;
    // Keep one resolved interface for the entire operation: no late local error
    // may discard an already applied prefix.
    for (unsigned i = 0; i < 7; ++i) {
        const bool real = i == 0 || i == 1 || i == 4 || i == 5;
        float f = 0;
        int32_t n = 0;
        if (s) {
            switch (i) {
            case 0: f = s->send_loss_percent; break;
            case 1: f = s->receive_loss_percent; break;
            case 2: n = s->send_lag_ms; break;
            case 3: n = s->receive_lag_ms; break;
            case 4: f = s->send_reorder_percent; break;
            case 5: f = s->receive_reorder_percent; break;
            case 6: n = s->reorder_delay_ms; break;
            }
        }
        const void *const value = !s ? nullptr : real ? static_cast<const void *>(&f) : &n;
        const bool accepted = SteamAPI_ISteamNetworkingUtils_SetConfigValue(utils, simulation_keys[i],
            k_ESteamNetworkingConfig_Global, 0, real ? k_ESteamNetworkingConfig_Float : k_ESteamNetworkingConfig_Int32, value);
        out->fields[i] = accepted ? 1 : 2;
        if (!accepted && s) break;
    }
    return 0;
}
}

extern "C" int32_t sw_config_set(uint32_t scope, uint32_t handle, uint32_t option, int32_t value, bool clear, bool *accepted) {
    *accepted = false;
    ESteamNetworkingConfigScope native_scope = k_ESteamNetworkingConfig_Global;
    if (option >= 6 || !scope_from(scope, native_scope) || (scope != 0 && uint64_t(handle) > INTPTR_MAX)) return -2;
    auto *const utils = SteamAPI_SteamNetworkingUtils_SteamAPI_v004();
    if (!utils) return -1;
    *accepted = SteamAPI_ISteamNetworkingUtils_SetConfigValue(utils, options[option], native_scope,
        scope == 0 ? 0 : static_cast<intptr_t>(handle), k_ESteamNetworkingConfig_Int32, clear ? nullptr : &value);
    return 0;
}
extern "C" int32_t sw_config_get(uint32_t scope, uint32_t handle, uint32_t option, sw_config_get_result *out) {
    *out = {};
    ESteamNetworkingConfigScope native_scope = k_ESteamNetworkingConfig_Global;
    if (option >= 6 || !scope_from(scope, native_scope) || (scope != 0 && uint64_t(handle) > INTPTR_MAX)) return -2;
    auto *const utils = SteamAPI_SteamNetworkingUtils_SteamAPI_v004();
    if (!utils) return -1;
    int32_t value = 0;
    auto type = static_cast<ESteamNetworkingConfigDataType>(0);
    size_t size = sizeof(value);
    const auto result = SteamAPI_ISteamNetworkingUtils_GetConfigValue(utils, options[option], native_scope,
        scope == 0 ? 0 : static_cast<intptr_t>(handle), &type, &value, &size);
    out->status = static_cast<int32_t>(result);
    out->data_type = static_cast<int32_t>(type);
    out->size = size;
    if ((result == k_ESteamNetworkingGetConfigValue_OK || result == k_ESteamNetworkingGetConfigValue_OKInherited) &&
        type == k_ESteamNetworkingConfig_Int32 && size == sizeof(value)) out->value = value;
    return 0;
}
extern "C" int32_t sw_config_simulation_apply(const sw_config_simulation *settings, sw_config_simulation_result *out) {
    if (!settings) { *out = {}; return -2; }
    return simulate(settings, out);
}
extern "C" int32_t sw_config_simulation_reset(sw_config_simulation_result *out) { return simulate(nullptr, out); }

#ifdef SW_NETWORKING_CONFIG_TEST
int main() {
    using namespace config_test;
    const int32_t values[] = {INT32_MIN, -1, 0, INT32_MAX};
    const bool booleans[] = {false, true};
    const size_t sizes[] = {0, 3, 4, 8, SIZE_MAX};
    const ESteamNetworkingConfigScope scopes[] = {k_ESteamNetworkingConfig_Global, k_ESteamNetworkingConfig_ListenSocket, k_ESteamNetworkingConfig_Connection};
    const ESteamNetworkingConfigValue expected[] = {k_ESteamNetworkingConfig_TimeoutInitial, k_ESteamNetworkingConfig_TimeoutConnected, k_ESteamNetworkingConfig_SendBufferSize, k_ESteamNetworkingConfig_SendRateMin, k_ESteamNetworkingConfig_SendRateMax, k_ESteamNetworkingConfig_NagleTime};
    for (uint32_t scope = 0; scope < 3; ++scope) for (uint32_t key = 0; key < 6; ++key) {
        for (int32_t value : values) for (bool clear : booleans) {
            reset(); bool accepted = false;
            CHECK(sw_config_set(scope, UINT32_MAX, key, value, clear, &accepted) == 0 && accepted);
            CHECK(calls == 1 && accessors == 1);
            const Call &c = history[0];
            CHECK(c.key == expected[key] && c.scope == scopes[scope] && c.handle == (scope == 0 ? 0 : intptr_t(UINT32_MAX)));
            CHECK(c.clear == clear && c.type == k_ESteamNetworkingConfig_Int32 && (clear || c.integer == value));
            reset(); reject_at = 1;
            CHECK(sw_config_set(scope, 0, key, value, clear, &accepted) == 0 && !accepted);
        }
        reset(); sw_config_get_result out{};
        CHECK(sw_config_get(scope, UINT32_MAX, key, &out) == 0);
        CHECK(history[0].key == expected[key] && history[0].scope == scopes[scope] && history[0].handle == (scope == 0 ? 0 : intptr_t(UINT32_MAX)));
    }
    const ESteamNetworkingGetConfigValueResult statuses[] = {k_ESteamNetworkingGetConfigValue_BadValue, k_ESteamNetworkingGetConfigValue_BadScopeObj, k_ESteamNetworkingGetConfigValue_BufferTooSmall, k_ESteamNetworkingGetConfigValue_OK, k_ESteamNetworkingGetConfigValue_OKInherited, static_cast<ESteamNetworkingGetConfigValueResult>(0), k_ESteamNetworkingGetConfigValueResult__Force32Bit};
    const ESteamNetworkingConfigDataType types[] = {k_ESteamNetworkingConfig_Int32, k_ESteamNetworkingConfig_Int64, k_ESteamNetworkingConfig_Float, k_ESteamNetworkingConfig_String, k_ESteamNetworkingConfig_Ptr, static_cast<ESteamNetworkingConfigDataType>(0), k_ESteamNetworkingConfigDataType__Force32Bit};
    for (auto st : statuses) for (auto type : types) for (size_t size : sizes) for (bool write : booleans) {
        reset(); status = st; data_type = type; reported_size = size; write_value = write;
        sw_config_get_result out{};
        CHECK(sw_config_get(0, 0, 0, &out) == 0);
        CHECK(out.status == st && out.data_type == type && out.size == size);
        const bool good = (st == k_ESteamNetworkingGetConfigValue_OK || st == k_ESteamNetworkingGetConfigValue_OKInherited) && type == k_ESteamNetworkingConfig_Int32 && size == 4;
        CHECK(out.value == (good && write ? returned_value : 0));
    }
    reset(); bool accepted = true; sw_config_get_result out{}; sw_config_simulation_result report{};
    CHECK(sw_config_set(3, 0, 0, 0, false, &accepted) == -2 && !accepted);
    CHECK(sw_config_get(0, 0, 6, &out) == -2 && calls == 0 && accessors == 0);
    CHECK(sw_config_get(3, 0, 0, &out) == -2);
    CHECK(sw_config_set(0, 0, UINT32_MAX, 0, false, &accepted) == -2 && !accepted && calls == 0 && accessors == 0);
    available = false;
    CHECK(sw_config_set(0, 0, 0, 0, false, &accepted) == -1 && !accepted);
    CHECK(sw_config_get(0, 0, 0, &out) == -1 && out.value == 0);
    const sw_config_simulation settings{12.5f, 23.5f, 101, 202, 34.5f, 45.5f, 303};
    CHECK(sw_config_simulation_apply(&settings, &report) == -1);
    CHECK(sw_config_simulation_reset(&report) == -1 && calls == 0);
    const ESteamNetworkingConfigValue sim_expected[] = {k_ESteamNetworkingConfig_FakePacketLoss_Send, k_ESteamNetworkingConfig_FakePacketLoss_Recv, k_ESteamNetworkingConfig_FakePacketLag_Send, k_ESteamNetworkingConfig_FakePacketLag_Recv, k_ESteamNetworkingConfig_FakePacketReorder_Send, k_ESteamNetworkingConfig_FakePacketReorder_Recv, k_ESteamNetworkingConfig_FakePacketReorder_Time};
    for (unsigned reject = 0; reject <= 7; ++reject) for (bool clear : booleans) {
        reset(); reject_at = reject; track_simulation = true;
        CHECK((clear ? sw_config_simulation_reset(&report) : sw_config_simulation_apply(&settings, &report)) == 0);
        const unsigned attempted = clear || reject == 0 ? 7 : reject;
        CHECK(calls == attempted && accessors == 1);
        for (unsigned i = 0; i < 7; ++i) {
            CHECK(report.fields[i] == (i >= attempted ? 0 : i + 1 == reject ? 2 : 1));
            if (i >= attempted || i + 1 == reject) {
                CHECK(applied[i].key == k_ESteamNetworkingConfig_Invalid && applied[i].integer == -999 && applied[i].real == -999);
            } else {
                CHECK(applied[i].key == sim_expected[i] && applied[i].clear == clear);
                CHECK(applied[i].integer == history[i].integer && applied[i].real == history[i].real);
            }
            if (i >= attempted) continue;
            const Call &c = history[i];
            CHECK(c.key == sim_expected[i] && c.scope == k_ESteamNetworkingConfig_Global && c.handle == 0 && c.clear == clear);
            const bool real = i == 0 || i == 1 || i == 4 || i == 5;
            CHECK(c.type == (real ? k_ESteamNetworkingConfig_Float : k_ESteamNetworkingConfig_Int32));
            if (!clear) {
                const float floats[] = {12.5f, 23.5f, 0, 0, 34.5f, 45.5f, 0};
                const int32_t ints[] = {0, 0, 101, 202, 0, 0, 303};
                CHECK(real ? c.real == floats[i] : c.integer == ints[i]);
            }
        }
    }
    for (unsigned i = 0; i < 7; ++i) {
        auto bad = settings;
        switch (i) {
        case 0: bad.send_loss_percent = -1; break;
        case 1: bad.receive_loss_percent = 101; break;
        case 2: bad.send_lag_ms = -1; break;
        case 3: bad.receive_lag_ms = -1; break;
        case 4: bad.send_reorder_percent = __builtin_nanf(""); break;
        case 5: bad.receive_reorder_percent = __builtin_inff(); break;
        case 6: bad.reorder_delay_ms = -1; break;
        }
        reset(); CHECK(sw_config_simulation_apply(&bad, &report) == -2 && calls == 0 && accessors == 0);
        for (auto field : report.fields) CHECK(field == 0);
    }
    reset(); const sw_config_simulation zero{};
    CHECK(sw_config_simulation_apply(&zero, &report) == 0 && calls == 7);
    for (unsigned i = 0; i < 7; ++i) CHECK(!history[i].clear && history[i].integer == 0 && history[i].real == 0);
    reset(); CHECK(sw_config_simulation_reset(&report) == 0 && calls == 7);
    for (unsigned i = 0; i < 7; ++i) CHECK(history[i].clear);
    puts("networking_config fixtures passed");
}
#endif
