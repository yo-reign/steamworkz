#include "core.h"
#include <steam/steam_api.h>
#include <steam/steam_api_flat.h>
#include <string.h>

static_assert(sizeof(SteamErrMsg) == SW_INIT_MESSAGE_SIZE, "SDK diagnostic size changed");
static_assert(sizeof(uint64_steamid) == sizeof(uint64_t), "Steam ID width changed");
static_assert(sizeof(SwEvent{}.data.game_join.connect) == sizeof(GameRichPresenceJoinRequested_t{}.m_rgchConnect), "join text size changed");
static_assert(sizeof(SwEvent{}.data.network.info.end_debug) == sizeof(SteamNetConnectionInfo_t{}.m_szEndDebug), "connection text size changed");
static_assert(sizeof(SwEvent{}.data.relay.debug) == sizeof(SteamRelayNetworkStatus_t{}.m_debugMsg), "relay text size changed");
static_assert(sizeof(SwEvent{}.data.achievement.name) == sizeof(UserAchievementStored_t{}.m_rgchAchievementName), "achievement name size changed");
static_assert(sizeof(SwEvent{}.data.web_ticket.bytes) == sizeof(GetTicketForWebApiResponse_t{}.m_rgubTicket), "web ticket capacity changed");

namespace {
// Do not evaluate out-of-range native enums when preserving future SDK values.
template<class T> int32_t enum_value(const T &value) {
    static_assert(sizeof(T) == sizeof(int32_t), "SDK enum width changed");
    int32_t result;
    memcpy(&result, &value, sizeof(result));
    return result;
}
}

int32_t sw_init(char message[SW_INIT_MESSAGE_SIZE]) {
    SteamErrMsg native_message = {};
    const auto native_result = SteamAPI_InitEx(&native_message);
    const int32_t result = enum_value(native_result);
    memcpy(message, native_message, sizeof(native_message));
    message[SW_INIT_MESSAGE_SIZE - 1] = 0;
    if (result != k_ESteamAPIInitResult_OK) return int32_t(result);
    if (!SteamAPI_SteamUser() || !SteamAPI_SteamFriends() || !SteamAPI_SteamUtils() ||
        !SteamAPI_SteamApps() || !SteamAPI_SteamMatchmaking() || !SteamAPI_SteamUserStats() ||
        !SteamAPI_SteamRemoteStorage() || !SteamAPI_SteamNetworkingSockets_SteamAPI() ||
        !SteamAPI_SteamNetworkingUtils_SteamAPI() || SteamAPI_GetHSteamPipe() == 0) {
        SteamAPI_Shutdown();
        const char unavailable[] = "Steam initialized, but a required interface is unavailable.";
        memcpy(message, unavailable, sizeof(unavailable));
        return 4;
    }
    SteamAPI_ManualDispatch_Init();
    return 0;
}
void sw_shutdown(void) { SteamAPI_Shutdown(); }
uint8_t sw_restart_if_necessary(uint32_t app) { return SteamAPI_RestartAppIfNecessary(app); }
int32_t sw_pipe(void) { return SteamAPI_GetHSteamPipe(); }
void sw_run_frame(int32_t pipe) { SteamAPI_ManualDispatch_RunFrame(pipe); }
uint64_t sw_user_id(void) { return SteamAPI_ISteamUser_GetSteamID(SteamAPI_SteamUser()); }
uint8_t sw_logged_on(void) { return SteamAPI_ISteamUser_BLoggedOn(SteamAPI_SteamUser()); }
uint32_t sw_app_id(void) { return SteamAPI_ISteamUtils_GetAppID(SteamAPI_SteamUtils()); }
uint8_t sw_overlay_enabled(void) { return SteamAPI_ISteamUtils_IsOverlayEnabled(SteamAPI_SteamUtils()); }
uint32_t sw_server_time(void) { return SteamAPI_ISteamUtils_GetServerRealTime(SteamAPI_SteamUtils()); }
uint32_t sw_auth_ticket(void *buffer, int32_t capacity, uint32_t *size, uint64_t recipient) {
    SteamNetworkingIdentity identity;
    identity.Clear();
    identity.SetSteamID64(recipient);
    return SteamAPI_ISteamUser_GetAuthSessionTicket(SteamAPI_SteamUser(), buffer, capacity, size,
        recipient ? &identity : nullptr);
}
uint32_t sw_web_ticket(const char *identity) {
    return SteamAPI_ISteamUser_GetAuthTicketForWebApi(SteamAPI_SteamUser(), identity);
}
void sw_cancel_ticket(uint32_t ticket) { SteamAPI_ISteamUser_CancelAuthTicket(SteamAPI_SteamUser(), ticket); }
int32_t sw_begin_auth(const void *ticket, int32_t size, uint64_t user) {
    const auto result = SteamAPI_ISteamUser_BeginAuthSession(SteamAPI_SteamUser(), ticket, size, user);
    return enum_value(result);
}
void sw_end_auth(uint64_t user) { SteamAPI_ISteamUser_EndAuthSession(SteamAPI_SteamUser(), user); }
int32_t sw_user_license(uint64_t user, uint32_t app) {
    const auto result = SteamAPI_ISteamUser_UserHasLicenseForApp(SteamAPI_SteamUser(), user, app);
    return enum_value(result);
}

namespace {
void convert(const SteamServersConnected_t &, SwEvent &e) { e.kind = SW_CONNECTED; }
void convert(const SteamServersDisconnected_t &v, SwEvent &e) {
    e.kind = SW_DISCONNECTED; e.data.connection.result = enum_value(v.m_eResult);
}
void convert(const SteamServerConnectFailure_t &v, SwEvent &e) {
    e.kind = SW_CONNECT_FAILURE; e.data.connection.result = enum_value(v.m_eResult);
    e.data.connection.retrying = v.m_bStillRetrying;
}
void convert(const SteamShutdown_t &, SwEvent &e) { e.kind = SW_SHUTDOWN; }
void convert(const GameOverlayActivated_t &v, SwEvent &e) {
    e.kind = SW_OVERLAY;
    e.data.overlay.active = v.m_bActive;
    e.data.overlay.user_initiated = v.m_bUserInitiated;
    e.data.overlay.app = v.m_nAppID;
}
void convert(const DlcInstalled_t &v, SwEvent &e) { e.kind = SW_DLC_INSTALLED; e.data.dlc.app = v.m_nAppID; }
void convert(const PersonaStateChange_t &v, SwEvent &e) {
    e.kind = SW_PERSONA_CHANGED; e.data.persona.user = v.m_ulSteamID; e.data.persona.flags = v.m_nChangeFlags;
}
void convert(const AvatarImageLoaded_t &v, SwEvent &e) {
    if (v.m_iWide < 0 || v.m_iTall < 0) { e.kind = SW_MALFORMED; return; }
    e.kind = SW_AVATAR_LOADED; e.data.avatar.user = v.m_steamID.ConvertToUint64();
    e.data.avatar.image = v.m_iImage; e.data.avatar.width = uint32_t(v.m_iWide); e.data.avatar.height = uint32_t(v.m_iTall);
}
void convert(const FriendRichPresenceUpdate_t &v, SwEvent &e) {
    e.kind = SW_PRESENCE_CHANGED; e.data.presence.user = v.m_steamIDFriend.ConvertToUint64(); e.data.presence.app = v.m_nAppID;
}
void convert(const GameRichPresenceJoinRequested_t &v, SwEvent &e) {
    e.kind = SW_GAME_JOIN_REQUESTED; e.data.game_join.user = v.m_steamIDFriend.ConvertToUint64();
    memcpy(e.data.game_join.connect, v.m_rgchConnect, sizeof(e.data.game_join.connect));
}
void convert(const GameLobbyJoinRequested_t &v, SwEvent &e) {
    e.kind = SW_LOBBY_JOIN_REQUESTED; e.data.lobby_invite.lobby = v.m_steamIDLobby.ConvertToUint64();
    e.data.lobby_invite.user = v.m_steamIDFriend.ConvertToUint64();
}
void convert(const LobbyInvite_t &v, SwEvent &e) {
    e.kind = SW_LOBBY_INVITE; e.data.lobby_invite.lobby = v.m_ulSteamIDLobby;
    e.data.lobby_invite.user = v.m_ulSteamIDUser; e.data.lobby_invite.game = v.m_ulGameID;
}
void convert(const LobbyCreated_t &v, SwEvent &e) {
    e.kind = SW_LOBBY_CREATED; e.data.lobby_created.lobby = v.m_ulSteamIDLobby; e.data.lobby_created.result = enum_value(v.m_eResult);
}
void convert(const LobbyEnter_t &v, SwEvent &e) {
    e.kind = SW_LOBBY_ENTERED; e.data.lobby_entered.lobby = v.m_ulSteamIDLobby;
    e.data.lobby_entered.response = v.m_EChatRoomEnterResponse; e.data.lobby_entered.locked = v.m_bLocked;
}
void convert(const LobbyMatchList_t &v, SwEvent &e) { e.kind = SW_LOBBY_LIST; e.data.lobby_list.count = v.m_nLobbiesMatching; }
void convert(const LobbyDataUpdate_t &v, SwEvent &e) {
    e.kind = SW_LOBBY_DATA; e.data.lobby_data.lobby = v.m_ulSteamIDLobby;
    e.data.lobby_data.member = v.m_ulSteamIDMember; e.data.lobby_data.success = v.m_bSuccess;
}
void convert(const LobbyChatUpdate_t &v, SwEvent &e) {
    e.kind = SW_LOBBY_MEMBERS; e.data.lobby_members.lobby = v.m_ulSteamIDLobby;
    e.data.lobby_members.member = v.m_ulSteamIDUserChanged;
    e.data.lobby_members.actor = v.m_ulSteamIDMakingChange;
    e.data.lobby_members.changes = v.m_rgfChatMemberStateChange;
}
void convert(const LobbyChatMsg_t &v, SwEvent &e) {
    e.kind = SW_LOBBY_CHAT; e.data.lobby_chat.lobby = v.m_ulSteamIDLobby;
    e.data.lobby_chat.user = v.m_ulSteamIDUser;
    e.data.lobby_chat.chat_id = v.m_iChatID; e.data.lobby_chat.entry_type = v.m_eChatEntryType;
}
void convert(const LobbyGameCreated_t &v, SwEvent &e) {
    e.kind = SW_LOBBY_GAME_CREATED; e.data.lobby_game.lobby = v.m_ulSteamIDLobby;
    e.data.lobby_game.server = v.m_ulSteamIDGameServer; e.data.lobby_game.ipv4 = v.m_unIP; e.data.lobby_game.port = v.m_usPort;
}
void convert(const LobbyKicked_t &v, SwEvent &e) {
    e.kind = SW_LOBBY_KICKED; e.data.lobby_kicked.lobby = v.m_ulSteamIDLobby;
    e.data.lobby_kicked.actor = v.m_ulSteamIDAdmin; e.data.lobby_kicked.disconnected = v.m_bKickedDueToDisconnect;
}
void convert(const SteamNetConnectionStatusChangedCallback_t &v, SwEvent &e) {
    e.kind = SW_CONNECTION_CHANGED;
    auto &info = e.data.network.info;
    info.connection = v.m_hConn; info.listen_socket = v.m_info.m_hListenSocket;
    info.state = enum_value(v.m_info.m_eState); info.end_reason = v.m_info.m_eEndReason;
    info.peer_steam_id = v.m_info.m_identityRemote.GetSteamID64();
    v.m_info.m_identityRemote.ToString(info.peer_identity, sizeof(info.peer_identity));
    memcpy(info.end_debug, v.m_info.m_szEndDebug, sizeof(info.end_debug));
    e.data.network.old_state = enum_value(v.m_eOldState);
}
void convert(const SteamRelayNetworkStatus_t &v, SwEvent &e) {
    e.kind = SW_RELAY_STATUS; e.data.relay.availability = enum_value(v.m_eAvail);
    e.data.relay.measuring = v.m_bPingMeasurementInProgress;
    memcpy(e.data.relay.debug, v.m_debugMsg, sizeof(e.data.relay.debug));
}
void convert(const GetAuthSessionTicketResponse_t &v, SwEvent &e) {
    e.kind = SW_AUTH_TICKET; e.data.auth_ticket.ticket = v.m_hAuthTicket; e.data.auth_ticket.result = enum_value(v.m_eResult);
}
void convert(const GetTicketForWebApiResponse_t &v, SwEvent &e) {
    if (v.m_cubTicket < 0 || size_t(v.m_cubTicket) > sizeof(v.m_rgubTicket)) { e.kind = SW_MALFORMED; return; }
    e.kind = SW_WEB_TICKET; e.data.web_ticket.ticket = v.m_hAuthTicket;
    e.data.web_ticket.result = enum_value(v.m_eResult); e.data.web_ticket.size = uint32_t(v.m_cubTicket);
    memcpy(e.data.web_ticket.bytes, v.m_rgubTicket, size_t(v.m_cubTicket));
}
void convert(const ValidateAuthTicketResponse_t &v, SwEvent &e) {
    e.kind = SW_AUTH_VALIDATED; e.data.auth_validated.user = v.m_SteamID.ConvertToUint64();
    e.data.auth_validated.owner = v.m_OwnerSteamID.ConvertToUint64(); e.data.auth_validated.response = enum_value(v.m_eAuthSessionResponse);
}
void convert(const UserStatsReceived_t &v, SwEvent &e) {
    e.kind = SW_STATS_RECEIVED; e.data.stats.game = v.m_nGameID;
    e.data.stats.user = v.m_steamIDUser.ConvertToUint64(); e.data.stats.result = enum_value(v.m_eResult);
}
void convert(const UserStatsStored_t &v, SwEvent &e) {
    e.kind = SW_STATS_STORED; e.data.stats.game = v.m_nGameID; e.data.stats.result = enum_value(v.m_eResult);
}
void convert(const UserStatsUnloaded_t &v, SwEvent &e) {
    e.kind = SW_STATS_UNLOADED; e.data.stats.user = v.m_steamIDUser.ConvertToUint64();
}
void convert(const UserAchievementStored_t &v, SwEvent &e) {
    e.kind = SW_ACHIEVEMENT_STORED; e.data.achievement.game = v.m_nGameID;
    memcpy(e.data.achievement.name, v.m_rgchAchievementName, sizeof(e.data.achievement.name));
    e.data.achievement.current = v.m_nCurProgress; e.data.achievement.maximum = v.m_nMaxProgress;
    e.data.achievement.group = v.m_bGroupAchievement;
}
void convert(const RemoteStorageFileWriteAsyncComplete_t &v, SwEvent &e) {
    e.kind = SW_CLOUD_WRITTEN; e.data.cloud.result = enum_value(v.m_eResult);
}

template<class T> void decode(const CallbackMsg_t &message, SwEvent &out) {
    if (message.m_cubParam != sizeof(T) || !message.m_pubParam) { out.kind = SW_MALFORMED; return; }
    T value;
    memcpy(&value, message.m_pubParam, sizeof(value));
    convert(value, out);
}
struct NativeCallbacks {
    bool next(int32_t pipe, CallbackMsg_t *message) { return SteamAPI_ManualDispatch_GetNextCallback(pipe, message); }
    void free(int32_t pipe) { SteamAPI_ManualDispatch_FreeLastCallback(pipe); }
    bool result(int32_t pipe, SteamAPICall_t call, void *value, int size, int id, bool *failed) {
        return SteamAPI_ManualDispatch_GetAPICallResult(pipe, call, value, size, id, failed);
    }
};
template<class Source> struct CallbackRelease {
    Source &source;
    int32_t pipe;
    ~CallbackRelease() { source.free(pipe); }
};
template<class T, class Source> void completion(Source &source, int32_t pipe, const SteamAPICallCompleted_t &call, SwEvent &out) {
    if (call.m_cubParam != sizeof(T)) { out.kind = SW_MALFORMED; return; }
    T value = {};
    bool failed = false;
    if (!source.result(pipe, call.m_hAsyncCall, &value, sizeof(value), T::k_iCallback, &failed)) {
        out.kind = SW_CALL_FAILED; out.data.call_failure.reason = SW_RESULT_UNAVAILABLE;
    } else if (failed) {
        out.kind = SW_CALL_FAILED; out.data.call_failure.reason = SW_IO_FAILURE;
    } else {
        convert(value, out);
    }
}
template<class Source> bool poll(Source &source, int32_t pipe, SwEvent &out) {
    CallbackMsg_t message = {};
    if (!source.next(pipe, &message)) return false;
    const CallbackRelease<Source> release{source, pipe};
    out = {};
    out.callback_id = message.m_iCallback;
    switch (message.m_iCallback) {
        case SteamServersConnected_t::k_iCallback: decode<SteamServersConnected_t>(message, out); break;
        case SteamServersDisconnected_t::k_iCallback: decode<SteamServersDisconnected_t>(message, out); break;
        case SteamServerConnectFailure_t::k_iCallback: decode<SteamServerConnectFailure_t>(message, out); break;
        case SteamShutdown_t::k_iCallback: decode<SteamShutdown_t>(message, out); break;
        case GameOverlayActivated_t::k_iCallback: decode<GameOverlayActivated_t>(message, out); break;
        case DlcInstalled_t::k_iCallback: decode<DlcInstalled_t>(message, out); break;
        case PersonaStateChange_t::k_iCallback: decode<PersonaStateChange_t>(message, out); break;
        case AvatarImageLoaded_t::k_iCallback: decode<AvatarImageLoaded_t>(message, out); break;
        case FriendRichPresenceUpdate_t::k_iCallback: decode<FriendRichPresenceUpdate_t>(message, out); break;
        case GameRichPresenceJoinRequested_t::k_iCallback: decode<GameRichPresenceJoinRequested_t>(message, out); break;
        case GameLobbyJoinRequested_t::k_iCallback: decode<GameLobbyJoinRequested_t>(message, out); break;
        case LobbyInvite_t::k_iCallback: decode<LobbyInvite_t>(message, out); break;
        case LobbyCreated_t::k_iCallback: decode<LobbyCreated_t>(message, out); break;
        case LobbyEnter_t::k_iCallback: decode<LobbyEnter_t>(message, out); break;
        case LobbyMatchList_t::k_iCallback: decode<LobbyMatchList_t>(message, out); break;
        case LobbyDataUpdate_t::k_iCallback: decode<LobbyDataUpdate_t>(message, out); break;
        case LobbyChatUpdate_t::k_iCallback: decode<LobbyChatUpdate_t>(message, out); break;
        case LobbyChatMsg_t::k_iCallback: decode<LobbyChatMsg_t>(message, out); break;
        case LobbyKicked_t::k_iCallback: decode<LobbyKicked_t>(message, out); break;
        case LobbyGameCreated_t::k_iCallback: decode<LobbyGameCreated_t>(message, out); break;
        case SteamNetConnectionStatusChangedCallback_t::k_iCallback: decode<SteamNetConnectionStatusChangedCallback_t>(message, out); break;
        case SteamRelayNetworkStatus_t::k_iCallback: decode<SteamRelayNetworkStatus_t>(message, out); break;
        case GetAuthSessionTicketResponse_t::k_iCallback: decode<GetAuthSessionTicketResponse_t>(message, out); break;
        case GetTicketForWebApiResponse_t::k_iCallback: decode<GetTicketForWebApiResponse_t>(message, out); break;
        case ValidateAuthTicketResponse_t::k_iCallback: decode<ValidateAuthTicketResponse_t>(message, out); break;
        case UserStatsReceived_t::k_iCallback: decode<UserStatsReceived_t>(message, out); break;
        case UserStatsStored_t::k_iCallback: decode<UserStatsStored_t>(message, out); break;
        case UserStatsUnloaded_t::k_iCallback: decode<UserStatsUnloaded_t>(message, out); break;
        case UserAchievementStored_t::k_iCallback: decode<UserAchievementStored_t>(message, out); break;
        case RemoteStorageFileWriteAsyncComplete_t::k_iCallback: decode<RemoteStorageFileWriteAsyncComplete_t>(message, out); break;
        case SteamAPICallCompleted_t::k_iCallback: {
            if (message.m_cubParam != sizeof(SteamAPICallCompleted_t) || !message.m_pubParam) { out.kind = SW_MALFORMED; break; }
            SteamAPICallCompleted_t call;
            memcpy(&call, message.m_pubParam, sizeof(call));
            out.call = call.m_hAsyncCall;
            out.callback_id = call.m_iCallback;
            switch (call.m_iCallback) {
                case LobbyCreated_t::k_iCallback: completion<LobbyCreated_t>(source, pipe, call, out); break;
                case LobbyEnter_t::k_iCallback: completion<LobbyEnter_t>(source, pipe, call, out); break;
                case LobbyMatchList_t::k_iCallback: completion<LobbyMatchList_t>(source, pipe, call, out); break;
                case UserStatsReceived_t::k_iCallback: completion<UserStatsReceived_t>(source, pipe, call, out); break;
                case RemoteStorageFileWriteAsyncComplete_t::k_iCallback: completion<RemoteStorageFileWriteAsyncComplete_t>(source, pipe, call, out); break;
                default: break;
            }
            break;
        }
        default: break;
    }
    return true;
}
} // namespace

uint8_t sw_next_event(int32_t pipe, SwEvent *event) {
    NativeCallbacks source;
    if (poll(source, pipe, *event)) return 1;
    SteamAPI_ReleaseCurrentThreadMemory();
    return 0;
}

#ifdef SW_CORE_TEST
#include <stdlib.h>
#include <stdio.h>
namespace {
void expect(bool condition) { if (!condition) abort(); }
struct FakeCallbacks {
    CallbackMsg_t message = {};
    bool available = true;
    int frees = 0;
    bool retrieved = true;
    bool io_failed = false;
    int fetches = 0;
    LobbyCreated_t value = {};
    bool next(int32_t, CallbackMsg_t *out) {
        if (!available) return false;
        available = false; *out = message; return true;
    }
    void free(int32_t) { ++frees; }
    bool result(int32_t, SteamAPICall_t handle, void *out, int size, int id, bool *failed) {
        ++fetches;
        expect(handle == 0xfedcba9876543210ULL);
        expect(size == sizeof(value) && id == LobbyCreated_t::k_iCallback);
        *failed = io_failed;
        if (retrieved && !io_failed) memcpy(out, &value, sizeof(value));
        return retrieved;
    }
};
}
int main() {
    SwEvent event = {};
    LobbyCreated_t created = {};
    created.m_eResult = k_EResultOK; created.m_ulSteamIDLobby = 0x123456789abcdef0ULL;
    uint8_t unaligned[sizeof(created) + 1] = {};
    memcpy(unaligned + 1, &created, sizeof(created));
    FakeCallbacks normal;
    normal.message.m_iCallback = LobbyCreated_t::k_iCallback;
    normal.message.m_pubParam = unaligned + 1; normal.message.m_cubParam = sizeof(created);
    expect(poll(normal, 1, event));
    expect(event.kind == SW_LOBBY_CREATED && event.data.lobby_created.lobby == created.m_ulSteamIDLobby);
    expect(event.call == 0 && normal.frees == 1 && !poll(normal, 1, event));
    expect(normal.frees == 1);
    FakeCallbacks malformed;
    malformed.message = normal.message; --malformed.message.m_cubParam;
    expect(poll(malformed, 1, event) && event.kind == SW_MALFORMED && malformed.frees == 1);
    FakeCallbacks unknown;
    unknown.message.m_iCallback = 999999;
    expect(poll(unknown, 1, event) && event.kind == SW_UNHANDLED && unknown.frees == 1);
    SteamAPICallCompleted_t completed = {};
    completed.m_hAsyncCall = 0xfedcba9876543210ULL;
    completed.m_iCallback = LobbyCreated_t::k_iCallback; completed.m_cubParam = sizeof(created);
    for (int mode = 0; mode != 4; ++mode) {
        FakeCallbacks source;
        source.message.m_iCallback = SteamAPICallCompleted_t::k_iCallback;
        source.message.m_pubParam = reinterpret_cast<uint8_t *>(&completed);
        source.message.m_cubParam = sizeof(completed);
        source.value = created;
        source.retrieved = mode != 1; source.io_failed = mode == 2;
        if (mode == 3) ++completed.m_cubParam;
        expect(poll(source, 1, event) && source.frees == 1 && event.call == completed.m_hAsyncCall);
        if (mode == 0) expect(event.kind == SW_LOBBY_CREATED && event.data.lobby_created.result == k_EResultOK);
        if (mode == 1) expect(event.kind == SW_CALL_FAILED && event.data.call_failure.reason == SW_RESULT_UNAVAILABLE);
        if (mode == 2) expect(event.kind == SW_CALL_FAILED && event.data.call_failure.reason == SW_IO_FAILURE);
        if (mode == 3) expect(event.kind == SW_MALFORMED && source.fetches == 0);
    }
    GetTicketForWebApiResponse_t ticket = {};
    ticket.m_cubTicket = -1; convert(ticket, event); expect(event.kind == SW_MALFORMED);
    ticket.m_cubTicket = sizeof(ticket.m_rgubTicket) + 1; convert(ticket, event); expect(event.kind == SW_MALFORMED);
    const int32_t future_value = 123456;
    memcpy(&created.m_eResult, &future_value, sizeof(future_value));
    convert(created, event); expect(event.data.lobby_created.result == future_value);
    static_assert(k_EAuthSessionResponseAuthTicketNetworkIdentityFailure == 10, "auth response mapping changed");
    ValidateAuthTicketResponse_t auth = {};
    auth.m_SteamID = CSteamID(uint64(23)); auth.m_OwnerSteamID = CSteamID(uint64(99));
    auth.m_eAuthSessionResponse = k_EAuthSessionResponseAuthTicketNetworkIdentityFailure;
    FakeCallbacks auth_source;
    auth_source.message = {0, ValidateAuthTicketResponse_t::k_iCallback, reinterpret_cast<uint8_t *>(&auth), sizeof(auth)};
    expect(poll(auth_source, 1, event) && auth_source.frees == 1 && event.call == 0);
    expect(event.kind == SW_AUTH_VALIDATED && event.callback_id == ValidateAuthTicketResponse_t::k_iCallback);
    expect(event.data.auth_validated.response == 10 && event.data.auth_validated.user == 23 && event.data.auth_validated.owner == 99);
    auth.m_SteamID = CSteamID(uint64(42)); auth.m_OwnerSteamID = CSteamID(uint64(43));
    expect(event.data.auth_validated.user == 23 && event.data.auth_validated.owner == 99);
    memcpy(&auth.m_eAuthSessionResponse, &future_value, sizeof(future_value));
    convert(auth, event); expect(event.data.auth_validated.response == future_value);
    // Synthetic identity with nonzero high bits verifies the full SteamId survives copying.
    const uint64 unloaded_user = 0x123456789abcdef0ULL;
    UserStatsUnloaded_t unloaded = {};
    unloaded.m_steamIDUser = CSteamID(unloaded_user);
    uint8_t unloaded_bytes[sizeof(unloaded) + 1] = {};
    for (int mode = 0; mode != 5; ++mode) {
        memcpy(unloaded_bytes + 1, &unloaded, sizeof(unloaded));
        FakeCallbacks source;
        source.message = {0, UserStatsUnloaded_t::k_iCallback, unloaded_bytes + 1, sizeof(unloaded)};
        if (mode == 1) --source.message.m_cubParam;
        if (mode == 2) ++source.message.m_cubParam;
        if (mode == 3) source.message.m_pubParam = nullptr;
        if (mode == 4) source.message.m_cubParam = -1;
        event.call = 123; // A broadcast must clear any previous correlated result.
        expect(poll(source, 1, event) && source.frees == 1 && source.fetches == 0);
        expect(event.call == 0 && event.callback_id == UserStatsUnloaded_t::k_iCallback);
        memset(unloaded_bytes, 0, sizeof(unloaded_bytes));
        if (mode == 0) expect(event.kind == SW_STATS_UNLOADED && event.data.stats.user == unloaded_user);
        else expect(event.kind == SW_MALFORMED);
        expect(!poll(source, 1, event) && source.frees == 1);
    }
    AvatarImageLoaded_t avatar = {};
    avatar.m_steamID = CSteamID(uint64(99)); avatar.m_iImage = 17; avatar.m_iWide = 10; avatar.m_iTall = 20;
    FakeCallbacks avatar_source;
    avatar_source.message = {0, AvatarImageLoaded_t::k_iCallback, reinterpret_cast<uint8_t *>(&avatar), sizeof(avatar)};
    expect(poll(avatar_source, 1, event) && event.kind == SW_AVATAR_LOADED && avatar_source.frees == 1);
    expect(event.data.avatar.user == 99 && event.data.avatar.image == 17 && event.data.avatar.width == 10 && event.data.avatar.height == 20);
    avatar.m_iWide = -1; convert(avatar, event); expect(event.kind == SW_MALFORMED);
    LobbyGameCreated_t game = {};
    game.m_ulSteamIDLobby = 23; game.m_ulSteamIDGameServer = 99; game.m_unIP = 0x7f000001; game.m_usPort = 27015;
    FakeCallbacks game_source;
    game_source.message = {0, LobbyGameCreated_t::k_iCallback, reinterpret_cast<uint8_t *>(&game), sizeof(game)};
    expect(poll(game_source, 1, event) && event.kind == SW_LOBBY_GAME_CREATED && game_source.frees == 1);
    expect(event.data.lobby_game.lobby == 23 && event.data.lobby_game.server == 99 && event.data.lobby_game.ipv4 == 0x7f000001 && event.data.lobby_game.port == 27015);
    puts("Steamworks callback fixtures passed");
}
#endif
