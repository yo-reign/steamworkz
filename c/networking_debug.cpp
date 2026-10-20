#include "networking_debug.h"
#include "steam/steam_api_flat.h"

static void debug_output(ESteamNetworkingSocketsDebugOutputType level, const char *message) {
    sw_networking_debug_sink(static_cast<int32_t>(level), message);
}
static_assert(k_ESteamNetworkingSocketsDebugOutputType_Bug == 1, "first active level");
static_assert(k_ESteamNetworkingSocketsDebugOutputType_Everything == 8, "last active level");

#ifdef SW_NETWORKING_DEBUG_TEST
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <string.h>

// The official protected destructor has no SDK-exported implementation.
// The fixture supplies it solely for its local, valid derived object.
ISteamNetworkingUtils::~ISteamNetworkingUtils() = default;

// Valid official-interface object; unrelated virtual calls must never occur.
struct FixtureUtils final : ISteamNetworkingUtils {
    SteamNetworkingMessage_t *AllocateMessage(int) override { assert(false); return nullptr; }
    ESteamNetworkingAvailability GetRelayNetworkStatus(SteamRelayNetworkStatus_t *) override { assert(false); return k_ESteamNetworkingAvailability_Unknown; }
    float GetLocalPingLocation(SteamNetworkPingLocation_t &) override { assert(false); return 0; }
    int EstimatePingTimeBetweenTwoLocations(const SteamNetworkPingLocation_t &, const SteamNetworkPingLocation_t &) override { assert(false); return 0; }
    int EstimatePingTimeFromLocalHost(const SteamNetworkPingLocation_t &) override { assert(false); return 0; }
    void ConvertPingLocationToString(const SteamNetworkPingLocation_t &, char *, int) override { assert(false); }
    bool ParsePingLocationString(const char *, SteamNetworkPingLocation_t &) override { assert(false); return false; }
    bool CheckPingDataUpToDate(float) override { assert(false); return false; }
    int GetPingToDataCenter(SteamNetworkingPOPID, SteamNetworkingPOPID *) override { assert(false); return 0; }
    int GetDirectPingToPOP(SteamNetworkingPOPID) override { assert(false); return 0; }
    int GetPOPCount() override { assert(false); return 0; }
    int GetPOPList(SteamNetworkingPOPID *, int) override { assert(false); return 0; }
    SteamNetworkingMicroseconds GetLocalTimestamp() override { assert(false); return 0; }
    void SetDebugOutputFunction(ESteamNetworkingSocketsDebugOutputType, FSteamNetworkingSocketsDebugOutput) override { assert(false); }
    ESteamNetworkingFakeIPType GetIPv4FakeIPType(uint32) override { assert(false); return k_ESteamNetworkingFakeIPType_Invalid; }
    EResult GetRealIdentityForFakeIP(const SteamNetworkingIPAddr &, SteamNetworkingIdentity *) override { assert(false); return k_EResultFail; }
    bool SetConfigValue(ESteamNetworkingConfigValue, ESteamNetworkingConfigScope, intptr_t, ESteamNetworkingConfigDataType, const void *) override { assert(false); return false; }
    ESteamNetworkingGetConfigValueResult GetConfigValue(ESteamNetworkingConfigValue, ESteamNetworkingConfigScope, intptr_t, ESteamNetworkingConfigDataType *, void *, size_t *) override { assert(false); return k_ESteamNetworkingGetConfigValue_BadValue; }
    const char *GetConfigValueInfo(ESteamNetworkingConfigValue, ESteamNetworkingConfigDataType *, ESteamNetworkingConfigScope *) override { assert(false); return nullptr; }
    ESteamNetworkingConfigValue IterateGenericEditableConfigValues(ESteamNetworkingConfigValue, bool) override { assert(false); return k_ESteamNetworkingConfig_Invalid; }
    void SteamNetworkingIPAddr_ToString(const SteamNetworkingIPAddr &, char *, size_t, bool) override { assert(false); }
    bool SteamNetworkingIPAddr_ParseString(SteamNetworkingIPAddr *, const char *) override { assert(false); return false; }
    ESteamNetworkingFakeIPType SteamNetworkingIPAddr_GetFakeIPType(const SteamNetworkingIPAddr &) override { assert(false); return k_ESteamNetworkingFakeIPType_Invalid; }
    void SteamNetworkingIdentity_ToString(const SteamNetworkingIdentity &, char *, size_t) override { assert(false); }
    bool SteamNetworkingIdentity_ParseString(SteamNetworkingIdentity *, const char *) override { assert(false); return false; }
};
static FixtureUtils fixture;
static bool available = true;
static unsigned accesses = 0, registrations = 0, sink_calls = 0;
static ESteamNetworkingSocketsDebugOutputType observed_level;
static FSteamNetworkingSocketsDebugOutput observed_callback;
static ISteamNetworkingUtils *fixture_access() { ++accesses; return available ? &fixture : nullptr; }
static void fixture_register(ISteamNetworkingUtils *self, ESteamNetworkingSocketsDebugOutputType level, FSteamNetworkingSocketsDebugOutput callback) {
    assert(self == &fixture);
    ++registrations;
    observed_level = level;
    observed_callback = callback;
}
// Assignments check both fake signatures against official flat declarations.
static decltype(&SteamAPI_SteamNetworkingUtils_SteamAPI_v004) const access_utils = fixture_access;
static decltype(&SteamAPI_ISteamNetworkingUtils_SetDebugOutputFunction) const register_output = fixture_register;
extern "C" void sw_networking_debug_sink(int32_t level, const char *message) {
    ++sink_calls;
    assert(level == 123); // Representable unknown official output enum value.
    assert(strcmp(message, "raw\xff") == 0);
}
#else
#define access_utils SteamAPI_SteamNetworkingUtils_SteamAPI_v004
#define register_output SteamAPI_ISteamNetworkingUtils_SetDebugOutputFunction
#endif

int sw_networking_debug_start(int32_t level) {
    if (level < k_ESteamNetworkingSocketsDebugOutputType_Bug || level > k_ESteamNetworkingSocketsDebugOutputType_Everything) return -1;
    auto *utils = access_utils();
    if (!utils) return 0;
    register_output(utils, static_cast<ESteamNetworkingSocketsDebugOutputType>(level), debug_output);
    return 1;
}
int sw_networking_debug_stop(void) {
    auto *utils = access_utils();
    if (!utils) return 0;
    register_output(utils, k_ESteamNetworkingSocketsDebugOutputType_None, nullptr);
    return 1;
}

#ifdef SW_NETWORKING_DEBUG_TEST
int main() {
    const int32_t invalid_levels[] = {-1, 0, 9, INT32_MAX};
    for (int32_t level : invalid_levels) {
        assert(sw_networking_debug_start(level) == -1);
        assert(accesses == 0 && registrations == 0);
    }
    available = false;
    assert(sw_networking_debug_start(4) == 0);
    assert(sw_networking_debug_stop() == 0);
    assert(registrations == 0);
    available = true;
    for (int32_t level = 1; level <= 8; ++level) {
        assert(sw_networking_debug_start(level) == 1);
        assert(observed_level == level && observed_callback == debug_output);
    }
    auto delayed = observed_callback;
    observed_callback(static_cast<ESteamNetworkingSocketsDebugOutputType>(123), "raw\xff");
    assert(sw_networking_debug_stop() == 1);
    assert(observed_callback == nullptr && observed_level == k_ESteamNetworkingSocketsDebugOutputType_None);
    delayed(static_cast<ESteamNetworkingSocketsDebugOutputType>(123), "raw\xff");
    assert(sink_calls == 2);
    assert(sw_networking_debug_stop() == 1);
    return 0;
}
#endif
