#include "remote_play.h"
#include <steam/steam_api_flat.h>
#include <string.h>

#ifdef SW_REMOTE_PLAY_TEST
#include <stdio.h>
#include <stdlib.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #x); abort(); } } while (0)
namespace remote_play_test {
static char token;
static ISteamRemotePlay *const remote = reinterpret_cast<ISteamRemotePlay *>(&token);
static bool available = true, accepted = true;
static unsigned accesses, calls;
static uint32 session_value = 73, guest_value = 0;
static uint64 expected_friend = 123456;
static int width_value = -7, height_value = 0;
static char name_storage[1025] = "client";
static const char *name_value = name_storage;
static decltype(SteamAPI_SteamRemotePlay_v004) accessor;
static ISteamRemotePlay *accessor() { ++accesses; return available ? remote : nullptr; }
static void check(ISteamRemotePlay *self) { CHECK(self == remote); ++calls; }
static void check_session(ISteamRemotePlay *self, RemotePlaySessionID_t session) { check(self); CHECK(session == 73); }
static decltype(SteamAPI_ISteamRemotePlay_GetSessionCount) count;
static uint32 count(ISteamRemotePlay *self) { check(self); return 1; }
static decltype(SteamAPI_ISteamRemotePlay_GetSessionID) session_id;
static RemotePlaySessionID_t session_id(ISteamRemotePlay *self, int index) { check(self); CHECK(index == 0 || index == INT32_MAX); return session_value; }
static decltype(SteamAPI_ISteamRemotePlay_BSessionRemotePlayTogether) together;
static bool together(ISteamRemotePlay *self, RemotePlaySessionID_t session) { check_session(self, session); return accepted; }
static decltype(SteamAPI_ISteamRemotePlay_GetSessionSteamID) steam_id;
static uint64_steamid steam_id(ISteamRemotePlay *self, RemotePlaySessionID_t session) { check_session(self, session); return UINT64_MAX; }
static decltype(SteamAPI_ISteamRemotePlay_GetSessionGuestID) guest_id;
static uint32 guest_id(ISteamRemotePlay *self, RemotePlaySessionID_t session) { check_session(self, session); return guest_value; }
static decltype(SteamAPI_ISteamRemotePlay_GetSessionClientName) client_name;
static const char *client_name(ISteamRemotePlay *self, RemotePlaySessionID_t session) { check_session(self, session); return name_value; }
static decltype(SteamAPI_ISteamRemotePlay_GetSessionClientFormFactor) form_factor;
static ESteamDeviceFormFactor form_factor(ISteamRemotePlay *self, RemotePlaySessionID_t session) { check_session(self, session); return k_ESteamDeviceFormFactorVRHeadset; }
static decltype(SteamAPI_ISteamRemotePlay_BGetSessionClientResolution) resolution;
static bool resolution(ISteamRemotePlay *self, RemotePlaySessionID_t session, int *width, int *height) { check_session(self, session); CHECK(*width == 0 && *height == 0); *width = width_value; *height = height_value; return accepted; }
static decltype(SteamAPI_ISteamRemotePlay_ShowRemotePlayTogetherUI) show_ui;
static bool show_ui(ISteamRemotePlay *self) { check(self); return accepted; }
static decltype(SteamAPI_ISteamRemotePlay_BSendRemotePlayTogetherInvite) invite;
static bool invite(ISteamRemotePlay *self, uint64_steamid friend_id) { check(self); CHECK(friend_id == expected_friend); return accepted; }
}
#define SteamAPI_SteamRemotePlay_v004 remote_play_test::accessor
#define SteamAPI_ISteamRemotePlay_GetSessionCount remote_play_test::count
#define SteamAPI_ISteamRemotePlay_GetSessionID remote_play_test::session_id
#define SteamAPI_ISteamRemotePlay_BSessionRemotePlayTogether remote_play_test::together
#define SteamAPI_ISteamRemotePlay_GetSessionSteamID remote_play_test::steam_id
#define SteamAPI_ISteamRemotePlay_GetSessionGuestID remote_play_test::guest_id
#define SteamAPI_ISteamRemotePlay_GetSessionClientName remote_play_test::client_name
#define SteamAPI_ISteamRemotePlay_GetSessionClientFormFactor remote_play_test::form_factor
#define SteamAPI_ISteamRemotePlay_BGetSessionClientResolution remote_play_test::resolution
#define SteamAPI_ISteamRemotePlay_ShowRemotePlayTogetherUI remote_play_test::show_ui
#define SteamAPI_ISteamRemotePlay_BSendRemotePlayTogetherInvite remote_play_test::invite
#endif

extern "C" int32_t sw_remote_play_session_count(uint32_t *count) {
    *count = 0;
    auto *const remote = SteamAPI_SteamRemotePlay_v004();
    if (!remote) return -1;
    *count = SteamAPI_ISteamRemotePlay_GetSessionCount(remote);
    return 0;
}
extern "C" int32_t sw_remote_play_session_id(int32_t index, uint32_t *session) {
    *session = 0;
    if (index < 0) return -2;
    auto *const remote = SteamAPI_SteamRemotePlay_v004();
    if (!remote) return -1;
    *session = SteamAPI_ISteamRemotePlay_GetSessionID(remote, index);
    return 0;
}
extern "C" int32_t sw_remote_play_together(uint32_t session) {
    if (!session) return -2;
    auto *const remote = SteamAPI_SteamRemotePlay_v004();
    return remote ? SteamAPI_ISteamRemotePlay_BSessionRemotePlayTogether(remote, session) : -1;
}
extern "C" int32_t sw_remote_play_steam_id(uint32_t session, uint64_t *steam_id) {
    *steam_id = 0;
    if (!session) return -2;
    auto *const remote = SteamAPI_SteamRemotePlay_v004();
    if (!remote) return -1;
    *steam_id = SteamAPI_ISteamRemotePlay_GetSessionSteamID(remote, session);
    return 0;
}
extern "C" int32_t sw_remote_play_guest_id(uint32_t session, uint32_t *guest_id) {
    *guest_id = 0;
    if (!session) return -2;
    auto *const remote = SteamAPI_SteamRemotePlay_v004();
    if (!remote) return -1;
    *guest_id = SteamAPI_ISteamRemotePlay_GetSessionGuestID(remote, session);
    return 0;
}
extern "C" int32_t sw_remote_play_client_name(uint32_t session, uint8_t *output, size_t capacity, uint32_t *required, uint32_t *copied) {
    *required = *copied = 0;
    if (!session) return -2;
    auto *const remote = SteamAPI_SteamRemotePlay_v004();
    if (!remote) return -1;
    const char *const name = SteamAPI_ISteamRemotePlay_GetSessionClientName(remote, session);
    if (!name) return 1;
    // Wrapper policy, not an SDK string-size promise. No intervening SDK call.
    size_t length = 0;
    while (length < 1024 && name[length] != '\0') ++length;
    if (length == 1024) return 2;
    *required = static_cast<uint32_t>(length);
    if (length > capacity) return 3;
    if (length) memcpy(output, name, length);
    *copied = static_cast<uint32_t>(length);
    return 0;
}
extern "C" int32_t sw_remote_play_form_factor(uint32_t session, int32_t *form_factor) {
    *form_factor = 0;
    if (!session) return -2;
    auto *const remote = SteamAPI_SteamRemotePlay_v004();
    if (!remote) return -1;
    const auto value = SteamAPI_ISteamRemotePlay_GetSessionClientFormFactor(remote, session);
    static_assert(sizeof(value) == sizeof(*form_factor), "Form factor enum width changed");
    memcpy(form_factor, &value, sizeof(*form_factor));
    return 0;
}
extern "C" int32_t sw_remote_play_resolution(uint32_t session, int32_t *width, int32_t *height) {
    *width = *height = 0;
    if (!session) return -2;
    auto *const remote = SteamAPI_SteamRemotePlay_v004();
    return remote ? SteamAPI_ISteamRemotePlay_BGetSessionClientResolution(remote, session, width, height) : -1;
}
extern "C" int32_t sw_remote_play_show_together_ui() {
    auto *const remote = SteamAPI_SteamRemotePlay_v004();
    return remote ? SteamAPI_ISteamRemotePlay_ShowRemotePlayTogetherUI(remote) : -1;
}
extern "C" int32_t sw_remote_play_invite(uint64_t friend_id) {
    auto *const remote = SteamAPI_SteamRemotePlay_v004();
    return remote ? SteamAPI_ISteamRemotePlay_BSendRemotePlayTogetherInvite(remote, friend_id) : -1;
}

#ifdef SW_REMOTE_PLAY_TEST
int main() {
    using namespace remote_play_test;
    uint32_t value = 99, required = 99, copied = 99;
    uint64_t user = 99;
    int32_t form = -1, width = 99, height = 99;
    uint8_t output[1024]; memset(output, 0x7f, sizeof(output));
    CHECK(sw_remote_play_session_count(&value) == 0 && value == 1);
    CHECK(sw_remote_play_session_id(0, &value) == 0 && value == 73);
    session_value = 0;
    CHECK(sw_remote_play_session_id(0, &value) == 0 && value == 0);
    CHECK(sw_remote_play_session_id(INT32_MAX, &value) == 0 && value == 0);
    CHECK(sw_remote_play_together(73) == 1);
    CHECK(sw_remote_play_steam_id(73, &user) == 0 && user == UINT64_MAX);
    CHECK(sw_remote_play_guest_id(73, &value) == 0 && value == 0);
    guest_value = UINT32_MAX;
    CHECK(sw_remote_play_guest_id(73, &value) == 0 && value == UINT32_MAX);
    CHECK(sw_remote_play_form_factor(73, &form) == 0 && form == 5);
    CHECK(sw_remote_play_resolution(73, &width, &height) == 1 && width == -7 && height == 0);
    CHECK(sw_remote_play_show_together_ui() == 1 && sw_remote_play_invite(123456) == 1);
    expected_friend = 0;
    CHECK(sw_remote_play_invite(0) == 1);
    accepted = false;
    CHECK(sw_remote_play_together(73) == 0 && sw_remote_play_show_together_ui() == 0 && sw_remote_play_invite(0) == 0);
    CHECK(sw_remote_play_resolution(73, &width, &height) == 0 && width == -7 && height == 0);
    width_value = 0;
    CHECK(sw_remote_play_resolution(73, &width, &height) == 0 && width == 0 && height == 0);

    CHECK(sw_remote_play_client_name(73, output, 6, &required, &copied) == 0 && required == 6 && copied == 6);
    memset(name_storage, 'X', sizeof(name_storage));
    CHECK(memcmp(output, "client", 6) == 0 && output[6] == 0x7f);
    memset(output, 0x7f, sizeof(output));
    CHECK(sw_remote_play_client_name(73, output, sizeof(output), &required, &copied) == 2 && required == 0 && copied == 0);
    name_storage[1024] = 0; // A terminator just outside the bound is still too long.
    CHECK(sw_remote_play_client_name(73, output, sizeof(output), &required, &copied) == 2);
    name_storage[1023] = 0;
    CHECK(sw_remote_play_client_name(73, output, 1022, &required, &copied) == 3 && required == 1023 && copied == 0);
    for (auto byte : output) CHECK(byte == 0x7f);
    CHECK(sw_remote_play_client_name(73, output, 1023, &required, &copied) == 0 && copied == 1023 && required == 1023 && output[1023] == 0x7f);
    name_storage[0] = 0;
    CHECK(sw_remote_play_client_name(73, nullptr, 0, &required, &copied) == 0 && required == 0 && copied == 0);
    name_value = nullptr;
    CHECK(sw_remote_play_client_name(73, output, sizeof(output), &required, &copied) == 1 && required == 0 && copied == 0);

    const auto before = accesses;
    CHECK(sw_remote_play_session_id(-1, &value) == -2 && value == 0);
    CHECK(sw_remote_play_together(0) == -2 && sw_remote_play_steam_id(0, &user) == -2 && user == 0);
    CHECK(sw_remote_play_guest_id(0, &value) == -2 && sw_remote_play_form_factor(0, &form) == -2);
    CHECK(sw_remote_play_client_name(0, output, 0, &required, &copied) == -2);
    CHECK(sw_remote_play_resolution(0, &width, &height) == -2 && accesses == before);
    available = false;
    const auto before_calls = calls;
    CHECK(sw_remote_play_session_count(&value) == -1 && value == 0);
    CHECK(sw_remote_play_session_id(0, &value) == -1 && value == 0);
    CHECK(sw_remote_play_together(73) == -1 && sw_remote_play_steam_id(73, &user) == -1 && user == 0);
    CHECK(sw_remote_play_guest_id(73, &value) == -1 && value == 0);
    CHECK(sw_remote_play_form_factor(73, &form) == -1 && form == 0);
    CHECK(sw_remote_play_client_name(73, output, sizeof(output), &required, &copied) == -1 && required == 0 && copied == 0);
    CHECK(sw_remote_play_resolution(73, &width, &height) == -1 && width == 0 && height == 0);
    CHECK(sw_remote_play_show_together_ui() == -1 && sw_remote_play_invite(0) == -1 && calls == before_calls);
    puts("remote play native fixtures passed");
}
#endif
