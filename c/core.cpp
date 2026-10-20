#include "core.h"
#include "services.h"
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
#ifdef SW_CORE_TEST
void identity_text(const SteamNetworkingIdentity &identity, char *buffer, size_t capacity);
#else
void identity_text(const SteamNetworkingIdentity &identity, char *buffer, size_t capacity) {
    identity.ToString(buffer, capacity);
}
#endif
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
    identity_text(v.m_info.m_identityRemote, info.peer_identity, sizeof(info.peer_identity));
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

void convert(const UserAchievementIconFetched_t &v, SwEvent &e) {
    static_assert(sizeof(v.m_rgchAchievementName) == sizeof(e.data.achievement_icon.name), "Icon name size changed");
    e.kind = SW_ACHIEVEMENT_ICON; e.data.achievement_icon.game = v.m_nGameID.ToUint64();
    memcpy(e.data.achievement_icon.name, v.m_rgchAchievementName, sizeof(v.m_rgchAchievementName));
    e.data.achievement_icon.achieved = v.m_bAchieved; e.data.achievement_icon.image = v.m_nIconHandle;
}
void convert(const LeaderboardFindResult_t &v, SwEvent &e) {
    e.kind = SW_LEADERBOARD_FOUND; e.data.leaderboard_found.leaderboard = v.m_hSteamLeaderboard;
    e.data.leaderboard_found.found = v.m_bLeaderboardFound;
}
void convert(const LeaderboardScoresDownloaded_t &v, SwEvent &e) {
    e.kind = SW_LEADERBOARD_ENTRIES; e.data.leaderboard_download.leaderboard = v.m_hSteamLeaderboard;
    auto &capture = e.data.leaderboard_download.capture;
    capture.status = SW_LEADERBOARD_CAPTURE_UNTRACKED; capture.reported_count = v.m_cEntryCount; capture.failure_index = -1;
}
void convert(const LeaderboardScoreUploaded_t &v, SwEvent &e) {
    e.kind = SW_LEADERBOARD_UPLOADED;
    auto &out = e.data.leaderboard_upload;
    out.leaderboard = v.m_hSteamLeaderboard; out.success = v.m_bSuccess; out.score = v.m_nScore;
    out.changed = v.m_bScoreChanged; out.rank_new = v.m_nGlobalRankNew; out.rank_previous = v.m_nGlobalRankPrevious;
}
void convert(const GlobalAchievementPercentagesReady_t &v, SwEvent &e) {
    e.kind = SW_GLOBAL_PERCENTAGES_READY; e.data.global_percentages.game = v.m_nGameID;
    e.data.global_percentages.result = enum_value(v.m_eResult);
}
void convert(const GamepadTextInputDismissed_t &v, SwEvent &e) {
    e.kind = SW_GAMEPAD_DISMISSED; e.data.gamepad.app = v.m_unAppID; e.data.gamepad.submitted = v.m_bSubmitted;
    e.data.gamepad.capture.status = SW_UTILS_TEXT_UNTRACKED;
    e.data.gamepad.capture.reported_length = v.m_unSubmittedText;
}
void convert(const FloatingGamepadTextInputDismissed_t &, SwEvent &e) { e.kind = SW_FLOATING_DISMISSED; }
void convert(const AppResumingFromSuspend_t &, SwEvent &e) { e.kind = SW_RESUMED; }
void convert(const RemoteStorageLocalFileChange_t &, SwEvent &e) { e.kind = SW_CLOUD_CHANGED; }
void convert(const SteamInputDeviceConnected_t &v, SwEvent &e) {
    e.kind = SW_INPUT_CONNECTED; e.data.input_device.controller = v.m_ulConnectedDeviceHandle;
}
void convert(const SteamInputDeviceDisconnected_t &v, SwEvent &e) {
    e.kind = SW_INPUT_DISCONNECTED; e.data.input_device.controller = v.m_ulDisconnectedDeviceHandle;
}

void convert(const SteamUGCQueryCompleted_t &v, SwEvent &e) {
    static_assert(sizeof(v.m_rgchNextCursor) == sizeof(e.data.workshop_query.cursor), "Workshop cursor size changed");
    e.kind = SW_WORKSHOP_QUERY_COMPLETED;
    auto &out = e.data.workshop_query;
    out.query = v.m_handle; out.result = enum_value(v.m_eResult);
    out.returned = v.m_unNumResultsReturned; out.total = v.m_unTotalMatchingResults;
    out.cached = v.m_bCachedData;
    memcpy(out.cursor, v.m_rgchNextCursor, sizeof(out.cursor));
}
void convert(const ItemInstalled_t &v, SwEvent &e) {
    e.kind = SW_WORKSHOP_ITEM_INSTALLED;
    auto &out = e.data.workshop_installed;
    out.app = v.m_unAppID; out.item = v.m_nPublishedFileId;
    out.legacy_content = v.m_hLegacyContent; out.manifest = v.m_unManifestID;
}
void convert(const DownloadItemResult_t &v, SwEvent &e) {
    e.kind = SW_WORKSHOP_DOWNLOADED;
    e.data.workshop_download.app = v.m_unAppID; e.data.workshop_download.item = v.m_nPublishedFileId;
    e.data.workshop_download.result = enum_value(v.m_eResult);
}
void convert(const UserSubscribedItemsListChanged_t &v, SwEvent &e) {
    e.kind = SW_WORKSHOP_SUBSCRIPTIONS_CHANGED; e.data.workshop_subscriptions.app = v.m_nAppID;
}
void convert(const SteamRemotePlaySessionConnected_t &v, SwEvent &e) {
    e.kind = SW_REMOTE_PLAY_CONNECTED; e.data.remote_session.session = v.m_unSessionID;
}
void convert(const SteamRemotePlaySessionDisconnected_t &v, SwEvent &e) {
    e.kind = SW_REMOTE_PLAY_DISCONNECTED; e.data.remote_session.session = v.m_unSessionID;
}
void convert(const SteamRemotePlayTogetherGuestInvite_t &v, SwEvent &e) {
    static_assert(sizeof(v.m_szConnectURL) == sizeof(e.data.remote_invite.url), "Remote Play invitation size changed");
    e.kind = SW_REMOTE_PLAY_GUEST_INVITE;
    memcpy(e.data.remote_invite.url, v.m_szConnectURL, sizeof(e.data.remote_invite.url));
}
void convert(const SteamRemotePlaySessionAvatarLoaded_t &v, SwEvent &e) {
    e.kind = SW_REMOTE_PLAY_AVATAR_LOADED;
    auto &out = e.data.remote_avatar;
    out.session = v.m_unSessionID; out.image = v.m_iImage; out.width = v.m_iWide; out.height = v.m_iTall;
}
void convert(const ScreenshotReady_t &v, SwEvent &e) {
    e.kind = SW_SCREENSHOT_READY; e.data.screenshot.handle = v.m_hLocal;
    e.data.screenshot.result = enum_value(v.m_eResult);
}
void convert(const ScreenshotRequested_t &, SwEvent &e) { e.kind = SW_SCREENSHOT_REQUESTED; }

// Only these two callbacks require secondary native reads. Correlate first.
template<class T, class Source> void capture(const T &, SwEvent &, const SwPollState &, Source &) {}
template<class Source> void capture(const GamepadTextInputDismissed_t &v, SwEvent &out, const SwPollState &state, Source &source) {
    if (!state.gamepad_pending || state.keyboard_app_id != v.m_unAppID) return;
    out.data.gamepad.matched = 1;
    source.gamepad(v.m_bSubmitted, v.m_unSubmittedText, &out.data.gamepad.capture);
}
template<class Source> void capture(const LeaderboardScoresDownloaded_t &v, SwEvent &out, const SwPollState &state, Source &source) {
    if (!out.call || out.call != state.leaderboard_download_call) return;
    source.entries(v.m_hSteamLeaderboardEntries, v.m_cEntryCount, &out.data.leaderboard_download.capture);
}
template<class T, class Source> void decode_captured(const CallbackMsg_t &message, SwEvent &out, const SwPollState &state, Source &source) {
    if (message.m_cubParam != sizeof(T) || !message.m_pubParam) { out.kind = SW_MALFORMED; return; }
    T value = {};
    memcpy(&value, message.m_pubParam, sizeof(value));
    convert(value, out);
    capture(value, out, state, source);
}
template<class T> void decode(const CallbackMsg_t &message, SwEvent &out) {
    if (message.m_cubParam != sizeof(T) || !message.m_pubParam) { out.kind = SW_MALFORMED; return; }
    T value;
    memcpy(&value, message.m_pubParam, sizeof(value));
    convert(value, out);
}
// CGameID has a non-trivial copy constructor. Read its declared integer member
// by SDK-derived offsets, then use Set; never memcpy into the class object.
void decode_icon(const CallbackMsg_t &message, SwEvent &out) {
    using T = UserAchievementIconFetched_t;
    if (message.m_cubParam != sizeof(T) || !message.m_pubParam) { out.kind = SW_MALFORMED; return; }
    T value = {};
    uint64 game = 0;
    const auto *const bytes = message.m_pubParam;
    memcpy(&game, bytes + offsetof(T, m_nGameID) + offsetof(CGameID, m_ulGameID), sizeof(game));
    value.m_nGameID.Set(game);
    memcpy(value.m_rgchAchievementName, bytes + offsetof(T, m_rgchAchievementName), sizeof(value.m_rgchAchievementName));
    memcpy(&value.m_bAchieved, bytes + offsetof(T, m_bAchieved), sizeof(value.m_bAchieved));
    memcpy(&value.m_nIconHandle, bytes + offsetof(T, m_nIconHandle), sizeof(value.m_nIconHandle));
    convert(value, out);
}
struct NativeCallbacks {
    void gamepad(uint8_t submitted, uint32_t length, SwUtilsTextCapture *out) { sw_utils_capture_gamepad_text(submitted, length, out); }
    void entries(uint64_t handle, int32_t count, SwLeaderboardEntries *out) { sw_stats_copy_leaderboard_entries(handle, count, out); }
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
template<class T, class Source> void completion(Source &source, int32_t pipe, const SteamAPICallCompleted_t &call, SwEvent &out, const SwPollState &state = {}) {
    if (call.m_cubParam != sizeof(T)) { out.kind = SW_MALFORMED; return; }
    T value = {};
    bool failed = false;
    if (!source.result(pipe, call.m_hAsyncCall, &value, sizeof(value), T::k_iCallback, &failed)) {
        out.kind = SW_CALL_FAILED; out.data.call_failure.reason = SW_RESULT_UNAVAILABLE;
    } else if (failed) {
        out.kind = SW_CALL_FAILED; out.data.call_failure.reason = SW_IO_FAILURE;
    } else {
        convert(value, out);
        capture(value, out, state, source);
    }
}
template<class Source> bool poll(Source &source, int32_t pipe, SwEvent &out, const SwPollState &state = {}) {
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
        case UserAchievementIconFetched_t::k_iCallback: decode_icon(message, out); break;
        case LeaderboardFindResult_t::k_iCallback: decode<LeaderboardFindResult_t>(message, out); break;
        case LeaderboardScoresDownloaded_t::k_iCallback: decode<LeaderboardScoresDownloaded_t>(message, out); break;
        case LeaderboardScoreUploaded_t::k_iCallback: decode<LeaderboardScoreUploaded_t>(message, out); break;
        case GlobalAchievementPercentagesReady_t::k_iCallback: decode<GlobalAchievementPercentagesReady_t>(message, out); break;
        case GamepadTextInputDismissed_t::k_iCallback: decode_captured<GamepadTextInputDismissed_t>(message, out, state, source); break;
        case FloatingGamepadTextInputDismissed_t::k_iCallback: decode<FloatingGamepadTextInputDismissed_t>(message, out); break;
        case AppResumingFromSuspend_t::k_iCallback: decode<AppResumingFromSuspend_t>(message, out); break;
        case RemoteStorageLocalFileChange_t::k_iCallback: decode<RemoteStorageLocalFileChange_t>(message, out); break;
        case SteamInputDeviceConnected_t::k_iCallback: decode<SteamInputDeviceConnected_t>(message, out); break;
        case SteamInputDeviceDisconnected_t::k_iCallback: decode<SteamInputDeviceDisconnected_t>(message, out); break;
        case SteamUGCQueryCompleted_t::k_iCallback: decode<SteamUGCQueryCompleted_t>(message, out); break;
        case ItemInstalled_t::k_iCallback: decode<ItemInstalled_t>(message, out); break;
        case DownloadItemResult_t::k_iCallback: decode<DownloadItemResult_t>(message, out); break;
        case UserSubscribedItemsListChanged_t::k_iCallback: decode<UserSubscribedItemsListChanged_t>(message, out); break;
        case SteamRemotePlaySessionConnected_t::k_iCallback: decode<SteamRemotePlaySessionConnected_t>(message, out); break;
        case SteamRemotePlaySessionDisconnected_t::k_iCallback: decode<SteamRemotePlaySessionDisconnected_t>(message, out); break;
        case SteamRemotePlayTogetherGuestInvite_t::k_iCallback: decode<SteamRemotePlayTogetherGuestInvite_t>(message, out); break;
        case SteamRemotePlaySessionAvatarLoaded_t::k_iCallback: decode<SteamRemotePlaySessionAvatarLoaded_t>(message, out); break;
        case ScreenshotReady_t::k_iCallback: decode<ScreenshotReady_t>(message, out); break;
        case ScreenshotRequested_t::k_iCallback: decode<ScreenshotRequested_t>(message, out); break;
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
                case LeaderboardFindResult_t::k_iCallback: completion<LeaderboardFindResult_t>(source, pipe, call, out); break;
                case LeaderboardScoresDownloaded_t::k_iCallback: completion<LeaderboardScoresDownloaded_t>(source, pipe, call, out, state); break;
                case LeaderboardScoreUploaded_t::k_iCallback: completion<LeaderboardScoreUploaded_t>(source, pipe, call, out); break;
                case GlobalAchievementPercentagesReady_t::k_iCallback: completion<GlobalAchievementPercentagesReady_t>(source, pipe, call, out); break;
                case SteamUGCQueryCompleted_t::k_iCallback: completion<SteamUGCQueryCompleted_t>(source, pipe, call, out); break;
                default: break;
            }
            break;
        }
        default: break;
    }
    return true;
}
} // namespace

uint8_t sw_next_event(int32_t pipe, const SwPollState *state, SwEvent *event) {
    NativeCallbacks source;
    if (poll(source, pipe, *event, *state)) return 1;
    SteamAPI_ReleaseCurrentThreadMemory();
    return 0;
}

#ifdef SW_CORE_TEST
#include <stdlib.h>
#include <stdio.h>
namespace {
const char *test_type = "setup";
const char *test_case = "setup";
int test_index = 0;
int test_variant = 0;
int test_callback = 0;
int cases_run = 0;
void check(bool condition, const char *expression, int line) {
    if (condition) return;
    fprintf(stderr, "core.cpp:%d: %s (callback %d) / %s [case %d, variant %d]: %s\n",
        line, test_type, test_callback, test_case, test_index, test_variant, expression);
    abort();
}
#define expect(condition) check((condition), #condition, __LINE__)
constexpr int32_t test_pipe = 73;
constexpr SteamAPICall_t test_call = 0xfedcba9876543210ULL;
constexpr uint64 test_lobby = 0x123456789abcdef0ULL;
constexpr uint64 test_user = 0x23456789abcdef01ULL;
constexpr uint64 test_game = 0x3456789abcdef012ULL;
constexpr int32_t future_value = 123456;
// Unnamed values must still be representable by each SDK enum's value range.
constexpr EResult future_result = static_cast<EResult>(255);
constexpr EAuthSessionResponse future_auth_response = static_cast<EAuthSessionResponse>(15);

int identity_calls = 0;
SteamNetworkingIdentity formatted_identity = {};
char *identity_buffer = nullptr;
size_t identity_capacity = 0;
constexpr char identity_fixture_text[] = "fixture-identity";
// The SDK method needs a live interface. Only the fixture substitutes formatting;
// decoding, forwarding, copying and callback release still use the real paths.
void identity_text(const SteamNetworkingIdentity &identity, char *buffer, size_t capacity) {
    ++identity_calls;
    memcpy(&formatted_identity, &identity, sizeof(identity));
    identity_buffer = buffer; identity_capacity = capacity;
    expect(buffer != nullptr && capacity >= sizeof(identity_fixture_text));
    memcpy(buffer, identity_fixture_text, sizeof(identity_fixture_text));
}

template<class T> struct FakeCallbacks {
    CallbackMsg_t message = {};
    bool available = true;
    bool outstanding = false;
    int nexts = 0;
    int frees = 0;
    bool retrieved = true;
    bool io_failed = false;
    int fetches = 0;
    SteamAPICall_t expected_call = test_call;
    int gamepad_copies = 0, entry_copies = 0;
    char text[4] = "own";
    int32_t detail = -91;
    T value = {};
    void gamepad(uint8_t submitted, uint32_t length, SwUtilsTextCapture *out) {
        expect(outstanding && frees == 0 && length == sizeof(text));
        ++gamepad_copies;
        *out = {}; out->reported_length = length;
        out->status = submitted ? SW_UTILS_TEXT_COMPLETE : SW_UTILS_TEXT_CANCELED;
        if (submitted) { out->queried_length = length; out->copied_length = length - 1; memcpy(out->bytes, text, sizeof(text)); }
    }
    void entries(uint64_t handle, int32_t count, SwLeaderboardEntries *out) {
        expect(outstanding && frees == 0 && handle == 77 && count == 1);
        ++entry_copies;
        *out = {}; out->reported_count = 1; out->copied_count = 1; out->failure_index = -1; out->all_rows_accessed = 1;
        out->entries[0].user = test_user; out->entries[0].detail_count = 1; out->entries[0].details[0] = detail;
    }
    bool next(int32_t pipe, CallbackMsg_t *out) {
        expect(pipe == test_pipe && !outstanding);
        ++nexts;
        if (!available) return false;
        available = false; outstanding = true; *out = message; return true;
    }
    void free(int32_t pipe) {
        expect(pipe == test_pipe && outstanding && frees == 0);
        outstanding = false; ++frees;
        memset(text, 0, sizeof(text)); detail = 0;
    }
    bool result(int32_t pipe, SteamAPICall_t handle, void *out, int size, int id, bool *failed) {
        expect(pipe == test_pipe && outstanding && frees == 0);
        expect(handle == expected_call && out != nullptr && failed != nullptr);
        expect(size == sizeof(T) && id == T::k_iCallback && fetches == 0);
        ++fetches;
        *failed = io_failed;
        if (retrieved && !io_failed) memcpy(out, &value, sizeof(value));
        return retrieved;
    }
};
struct GuardedEvent {
    uint64_t before = 0x1234fedc9876abcdULL;
    SwEvent event = {};
    uint64_t after = 0xabcd9876fedc1234ULL;
    void check_guards() const {
        expect(before == 0x1234fedc9876abcdULL && after == 0xabcd9876fedc1234ULL);
    }
};
template<class T> void drained(FakeCallbacks<T> &source, GuardedEvent &out, int fetches) {
    out.check_guards();
    expect(source.nexts == 1 && source.frees == 1 && !source.outstanding && source.fetches == fetches);
    unsigned char snapshot[sizeof(SwEvent)];
    memcpy(snapshot, &out.event, sizeof(snapshot));
    const int formats = identity_calls;
    expect(!poll(source, test_pipe, out.event));
    expect(!poll(source, test_pipe, out.event));
    expect(identity_calls == formats);
    expect(source.nexts == 3 && source.frees == 1 && source.fetches == fetches && !source.outstanding);
    expect(memcmp(snapshot, &out.event, sizeof(snapshot)) == 0);
    out.check_guards();
    ++cases_run;
}
// Typed construction avoids manufacturing invalid native enum objects. The two
// networking enums have Force32Bit sentinels; EResult and auth responses do not.
void future_enum(EResult &value) { value = future_result; }
void future_enum(EAuthSessionResponse &value) { value = future_auth_response; }
void future_enum(ESteamNetworkingAvailability &value) { value = static_cast<ESteamNetworkingAvailability>(future_value); }
void future_enum(ESteamNetworkingConnectionState &value) { value = static_cast<ESteamNetworkingConnectionState>(future_value); }
void verify_result(const LobbyCreated_t &v, const SwEvent &e) {
    expect(e.kind == SW_LOBBY_CREATED && e.data.lobby_created.lobby == v.m_ulSteamIDLobby);
    expect(e.data.lobby_created.result == enum_value(v.m_eResult));
}
void verify_result(const LobbyEnter_t &v, const SwEvent &e) {
    expect(e.kind == SW_LOBBY_ENTERED && e.data.lobby_entered.lobby == v.m_ulSteamIDLobby);
    expect(e.data.lobby_entered.response == v.m_EChatRoomEnterResponse && e.data.lobby_entered.locked == v.m_bLocked);
}
void verify_result(const LobbyMatchList_t &v, const SwEvent &e) {
    expect(e.kind == SW_LOBBY_LIST && e.data.lobby_list.count == v.m_nLobbiesMatching);
}
void verify_result(const UserStatsReceived_t &v, const SwEvent &e) {
    expect(e.kind == SW_STATS_RECEIVED && e.data.stats.game == v.m_nGameID);
    expect(e.data.stats.user == v.m_steamIDUser.ConvertToUint64() && e.data.stats.result == enum_value(v.m_eResult));
}
void verify_result(const RemoteStorageFileWriteAsyncComplete_t &v, const SwEvent &e) {
    expect(e.kind == SW_CLOUD_WRITTEN && e.data.cloud.result == enum_value(v.m_eResult));
}

void verify_result(const LeaderboardFindResult_t &v, const SwEvent &e) {
    expect(e.kind == SW_LEADERBOARD_FOUND && e.data.leaderboard_found.leaderboard == v.m_hSteamLeaderboard);
    expect(e.data.leaderboard_found.found == v.m_bLeaderboardFound);
}
void verify_result(const LeaderboardScoresDownloaded_t &v, const SwEvent &e) {
    expect(e.kind == SW_LEADERBOARD_ENTRIES && e.data.leaderboard_download.leaderboard == v.m_hSteamLeaderboard);
    expect(e.data.leaderboard_download.capture.reported_count == v.m_cEntryCount);
    expect(e.data.leaderboard_download.capture.status == SW_LEADERBOARD_CAPTURE_UNTRACKED);
}
void verify_result(const LeaderboardScoreUploaded_t &v, const SwEvent &e) {
    expect(e.kind == SW_LEADERBOARD_UPLOADED);
    const auto &out = e.data.leaderboard_upload;
    expect(out.leaderboard == v.m_hSteamLeaderboard && out.success == v.m_bSuccess && out.score == v.m_nScore);
    expect(out.changed == v.m_bScoreChanged && out.rank_new == v.m_nGlobalRankNew && out.rank_previous == v.m_nGlobalRankPrevious);
}
void verify_result(const GlobalAchievementPercentagesReady_t &v, const SwEvent &e) {
    expect(e.kind == SW_GLOBAL_PERCENTAGES_READY && e.data.global_percentages.game == v.m_nGameID);
    expect(e.data.global_percentages.result == enum_value(v.m_eResult));
}

void verify_result(const SteamUGCQueryCompleted_t &v, const SwEvent &e) {
    expect(e.kind == SW_WORKSHOP_QUERY_COMPLETED);
    const auto &out = e.data.workshop_query;
    expect(out.query == v.m_handle && out.result == enum_value(v.m_eResult));
    expect(out.returned == v.m_unNumResultsReturned && out.total == v.m_unTotalMatchingResults && out.cached == v.m_bCachedData);
    expect(memcmp(out.cursor, v.m_rgchNextCursor, sizeof(v.m_rgchNextCursor)) == 0);
}

template<class T> void completion_cases(const char *name, const T &value) {
    test_type = name; test_callback = T::k_iCallback; test_variant = 0;
    const char *modes[] = {"copy", "unavailable", "io-failure", "unavailable-and-io-failure",
        "inner-zero", "inner-short", "inner-long", "inner-max",
        "outer-negative", "outer-zero", "outer-short", "outer-long", "outer-null", "outer-unaligned"};
    for (int mode = 0; mode != 14; ++mode) {
        test_case = modes[mode]; test_index = mode;
        SteamAPICallCompleted_t call = {};
        call.m_hAsyncCall = test_call; call.m_iCallback = T::k_iCallback; call.m_cubParam = sizeof(T);
        if (mode == 4) call.m_cubParam = 0;
        if (mode == 5) --call.m_cubParam;
        if (mode == 6) ++call.m_cubParam;
        if (mode == 7) call.m_cubParam = UINT32_MAX;
        alignas(SteamAPICallCompleted_t) unsigned char bytes[sizeof(call) + 1];
        memcpy(bytes + 1, &call, sizeof(call));
        FakeCallbacks<T> source;
        memcpy(&source.value, &value, sizeof(value));
        source.retrieved = mode != 1 && mode != 3;
        source.io_failed = mode == 2 || mode == 3;
        source.message = {0, SteamAPICallCompleted_t::k_iCallback, reinterpret_cast<uint8_t *>(&call), sizeof(call)};
        if (mode == 8) source.message.m_cubParam = -1;
        if (mode == 9) source.message.m_cubParam = 0;
        if (mode == 10) --source.message.m_cubParam;
        if (mode == 11) ++source.message.m_cubParam;
        if (mode == 12) source.message.m_pubParam = nullptr;
        if (mode == 13) source.message.m_pubParam = bytes + 1;
        GuardedEvent out;
        out.event.call = 1; out.event.callback_id = -1;
        expect(poll(source, test_pipe, out.event));
        const bool outer_bad = mode >= 8 && mode <= 12;
        expect(out.event.call == (outer_bad ? 0 : test_call));
        expect(out.event.callback_id == (outer_bad ? SteamAPICallCompleted_t::k_iCallback : T::k_iCallback));
        if (mode == 0 || mode == 13) {
            // Overwrite the retrieval source and outer bytes before inspecting the owned result.
            const T replacement = {};
            memcpy(&source.value, &replacement, sizeof(replacement));
            memset(bytes, 0, sizeof(bytes)); call = {};
            verify_result(value, out.event);
        } else if (mode == 1 || mode == 3) {
            expect(out.event.kind == SW_CALL_FAILED && out.event.data.call_failure.reason == SW_RESULT_UNAVAILABLE);
        } else if (mode == 2) {
            expect(out.event.kind == SW_CALL_FAILED && out.event.data.call_failure.reason == SW_IO_FAILURE);
        } else expect(out.event.kind == SW_MALFORMED);
        drained(source, out, mode < 4 || mode == 13 ? 1 : 0);
    }
}

// The storage is real and at least sizeof(T)+1 bytes; only bytes copied from
// initialized SDK objects are decoded. Empty SDK structs have alignment one.
template<class T, class Verify> void broadcast_cases(const char *name, const T &value, int kind, Verify verify) {
    test_type = name; test_callback = T::k_iCallback; test_case = "broadcast-size/storage";
    const int sizes[] = {-1, 0, int(sizeof(T)) - 1, int(sizeof(T)), int(sizeof(T)) + 1};
    for (int size_index = 0; size_index != 5; ++size_index) {
        for (int storage = 0; storage != 3; ++storage) {
            test_index = size_index * 3 + storage;
            alignas(T) unsigned char bytes[sizeof(T) + 1] = {};
            const int offset = storage == 2 ? 1 : 0;
            memcpy(bytes + offset, &value, sizeof(value));
            FakeCallbacks<T> source;
            source.message = {0, T::k_iCallback, storage == 0 ? nullptr : bytes + offset, sizes[size_index]};
            GuardedEvent out;
            out.event.call = test_call; out.event.kind = SW_CALL_FAILED;
            identity_calls = 0;
            expect(poll(source, test_pipe, out.event));
            const bool formats = T::k_iCallback == SteamNetConnectionStatusChangedCallback_t::k_iCallback &&
                sizes[size_index] == sizeof(T) && storage != 0;
            expect(identity_calls == (formats ? 1 : 0));
            if (formats) {
                expect(formatted_identity.GetSteamID64() == test_user);
                expect(identity_buffer == out.event.data.network.info.peer_identity);
                expect(identity_capacity == sizeof(out.event.data.network.info.peer_identity));
            }
            memset(bytes, 0xa5, sizeof(bytes));
            expect(out.event.call == 0 && out.event.callback_id == T::k_iCallback);
            if (sizes[size_index] == sizeof(T) && storage != 0) {
                expect(out.event.kind == kind);
                verify(out.event);
            } else expect(out.event.kind == SW_MALFORMED);
            drained(source, out, 0);
        }
    }
}
#define broadcast(value, kind, ...) broadcast_cases(#value, value, kind, [&](const SwEvent &e) { __VA_ARGS__; })

void test_completions() {
    LobbyCreated_t created = {};
    created.m_eResult = k_EResultOK; created.m_ulSteamIDLobby = test_lobby;
    completion_cases("LobbyCreated_t/success", created);
    created.m_eResult = k_EResultAccessDenied; created.m_ulSteamIDLobby = 0;
    completion_cases("LobbyCreated_t/operation-failure", created);
    future_enum(created.m_eResult);
    completion_cases("LobbyCreated_t/unknown-result", created);
    LobbyEnter_t entered = {};
    entered.m_ulSteamIDLobby = test_lobby; entered.m_bLocked = true;
    entered.m_EChatRoomEnterResponse = k_EChatRoomEnterResponseSuccess;
    completion_cases("LobbyEnter_t/success", entered);
    entered.m_bLocked = false; entered.m_EChatRoomEnterResponse = k_EChatRoomEnterResponseBanned;
    completion_cases("LobbyEnter_t/operation-failure", entered);
    entered.m_EChatRoomEnterResponse = 0xfedcba98U; // SDK field is uint32, not an enum object.
    completion_cases("LobbyEnter_t/unknown-response", entered);
    LobbyMatchList_t list = {};
    list.m_nLobbiesMatching = 0x87654321U;
    completion_cases("LobbyMatchList_t/nonempty", list);
    list.m_nLobbiesMatching = 0;
    completion_cases("LobbyMatchList_t/empty", list); // No operation result field exists.
    UserStatsReceived_t stats = {};
    stats.m_nGameID = test_game; stats.m_steamIDUser = CSteamID(test_user); stats.m_eResult = k_EResultOK;
    completion_cases("UserStatsReceived_t/success", stats);
    stats.m_eResult = k_EResultFail;
    completion_cases("UserStatsReceived_t/operation-failure", stats);
    future_enum(stats.m_eResult);
    completion_cases("UserStatsReceived_t/unknown-result", stats);
    RemoteStorageFileWriteAsyncComplete_t written = {};
    written.m_eResult = k_EResultOK;
    completion_cases("RemoteStorageFileWriteAsyncComplete_t/success", written);
    written.m_eResult = k_EResultDiskFull;
    completion_cases("RemoteStorageFileWriteAsyncComplete_t/operation-failure", written);
    future_enum(written.m_eResult);
    completion_cases("RemoteStorageFileWriteAsyncComplete_t/unknown-result", written);
}

void test_platform_completions() {
    LeaderboardFindResult_t found = {}; found.m_hSteamLeaderboard = 53;
    completion_cases("LeaderboardFindResult_t/not-found", found);
    found.m_bLeaderboardFound = 1;
    completion_cases("LeaderboardFindResult_t/found", found);
    LeaderboardScoresDownloaded_t downloaded = {};
    downloaded.m_hSteamLeaderboard = 53; downloaded.m_hSteamLeaderboardEntries = 77; downloaded.m_cEntryCount = -9;
    completion_cases("LeaderboardScoresDownloaded_t/untracked", downloaded);
    LeaderboardScoreUploaded_t uploaded = {}; uploaded.m_hSteamLeaderboard = 53;
    uploaded.m_nScore = INT32_MIN; uploaded.m_nGlobalRankNew = -19; uploaded.m_nGlobalRankPrevious = 0;
    completion_cases("LeaderboardScoreUploaded_t/rejected", uploaded);
    uploaded.m_bSuccess = 1; uploaded.m_bScoreChanged = 1;
    completion_cases("LeaderboardScoreUploaded_t/changed", uploaded);
    GlobalAchievementPercentagesReady_t percentages = {}; percentages.m_nGameID = test_game;
    percentages.m_eResult = k_EResultFail;
    completion_cases("GlobalAchievementPercentagesReady_t/failure", percentages);
    percentages.m_eResult = k_EResultOK;
    completion_cases("GlobalAchievementPercentagesReady_t/success", percentages);

    test_type = "leaderboard correlation and capture lifetime";
    test_callback = LeaderboardScoresDownloaded_t::k_iCallback;
    for (int correlation = 0; correlation < 5; ++correlation) for (int failure = 0; failure < 4; ++failure) {
        test_case = "capture before free"; test_index = correlation; test_variant = failure;
        FakeCallbacks<LeaderboardScoresDownloaded_t> source;
        source.value = downloaded; source.value.m_cEntryCount = 1;
        source.expected_call = correlation == 3 ? 0 : test_call;
        SteamAPICallCompleted_t call = {};
        call.m_hAsyncCall = source.expected_call; call.m_iCallback = test_callback; call.m_cubParam = sizeof(downloaded);
        source.message = {0, SteamAPICallCompleted_t::k_iCallback, reinterpret_cast<uint8_t *>(&call), sizeof(call)};
        if (correlation == 4) source.message = {0, test_callback, reinterpret_cast<uint8_t *>(&source.value), sizeof(downloaded)};
        source.retrieved = failure != 1; source.io_failed = failure == 2;
        if (failure == 3) { --call.m_cubParam; if (correlation == 4) --source.message.m_cubParam; }
        const SwPollState state{correlation == 1 || correlation == 3 ? 0 : correlation == 2 ? test_call + 1 : test_call, 0, 0};
        GuardedEvent out;
        expect(poll(source, test_pipe, out.event, state));
        expect(source.gamepad_copies == 0);
        const bool copied = correlation == 0 && failure == 0;
        expect(source.entry_copies == int(copied));
        if (copied) {
            expect(out.event.data.leaderboard_download.capture.status == SW_LEADERBOARD_CAPTURE_COMPLETE);
            expect(out.event.data.leaderboard_download.capture.entries[0].details[0] == -91);
            expect(source.detail == 0); // Source invalidated by free; output survives.
        }
        drained(source, out, correlation != 4 && failure != 3 ? 1 : 0);
    }
}

void test_keyboard_capture() {
    test_type = "keyboard correlation and capture lifetime"; test_callback = GamepadTextInputDismissed_t::k_iCallback;
    for (int match = 0; match < 3; ++match) for (int submitted = 0; submitted < 2; ++submitted) for (int malformed = 0; malformed < 2; ++malformed) {
        test_case = "pending/app match before getter"; test_index = match; test_variant = submitted * 2 + malformed;
        GamepadTextInputDismissed_t value = {}; value.m_bSubmitted = submitted != 0; value.m_unSubmittedText = 4; value.m_unAppID = 73;
        FakeCallbacks<GamepadTextInputDismissed_t> source;
        source.message = {0, test_callback, reinterpret_cast<uint8_t *>(&value), int(sizeof(value)) - malformed};
        const SwPollState state{0, match == 1 ? 74U : 73U, uint8_t(match != 2)};
        GuardedEvent out;
        expect(poll(source, test_pipe, out.event, state));
        const bool matched = match == 0 && !malformed;
        expect(source.gamepad_copies == int(matched) && source.entry_copies == 0);
        if (!malformed) {
            expect(out.event.data.gamepad.app == 73 && out.event.data.gamepad.submitted == submitted && out.event.data.gamepad.matched == matched);
            expect(out.event.data.gamepad.capture.reported_length == 4);
            expect(out.event.data.gamepad.capture.status == (!matched ? SW_UTILS_TEXT_UNTRACKED : submitted ? SW_UTILS_TEXT_COMPLETE : SW_UTILS_TEXT_CANCELED));
            if (matched && submitted) expect(memcmp(out.event.data.gamepad.capture.bytes, "own", 4) == 0 && source.text[0] == 0);
        } else expect(out.event.kind == SW_MALFORMED);
        drained(source, out, 0);
    }
}

void test_unknown_callbacks() {
    test_type = "unknown callback"; test_callback = 999999; test_variant = 0;
    for (int correlated = 0; correlated != 2; ++correlated) {
        test_case = "no fetch"; test_index = correlated;
        SteamAPICallCompleted_t call = {};
        call.m_hAsyncCall = test_call; call.m_iCallback = 999999; call.m_cubParam = UINT32_MAX;
        FakeCallbacks<LobbyCreated_t> source;
        source.message = {0, correlated ? SteamAPICallCompleted_t::k_iCallback : call.m_iCallback,
            correlated ? reinterpret_cast<uint8_t *>(&call) : nullptr, correlated ? int(sizeof(call)) : -1};
        GuardedEvent out;
        expect(poll(source, test_pipe, out.event));
        expect(out.event.kind == SW_UNHANDLED && out.event.callback_id == 999999);
        expect(out.event.call == (correlated ? test_call : 0));
        drained(source, out, 0);
    }
}

void test_broadcasts() {
    SteamServersConnected_t connected = {};
    broadcast(connected, SW_CONNECTED, (void)e);
    SteamServersDisconnected_t disconnected = {};
    future_enum(disconnected.m_eResult);
    broadcast(disconnected, SW_DISCONNECTED, expect(e.data.connection.result == future_result));
    SteamServerConnectFailure_t failure = {};
    failure.m_eResult = k_EResultNoConnection; failure.m_bStillRetrying = true;
    broadcast(failure, SW_CONNECT_FAILURE, expect(e.data.connection.result == k_EResultNoConnection && e.data.connection.retrying == 1));
    SteamShutdown_t shutdown = {};
    broadcast(shutdown, SW_SHUTDOWN, (void)e);
    GameOverlayActivated_t overlay = {};
    overlay.m_bActive = 1; overlay.m_bUserInitiated = true; overlay.m_nAppID = 480;
    broadcast(overlay, SW_OVERLAY, expect(e.data.overlay.active == 1 && e.data.overlay.user_initiated == 1 && e.data.overlay.app == 480));
    DlcInstalled_t dlc = {}; dlc.m_nAppID = 481;
    broadcast(dlc, SW_DLC_INSTALLED, expect(e.data.dlc.app == 481));
    PersonaStateChange_t persona = {}; persona.m_ulSteamID = test_user; persona.m_nChangeFlags = 0x40000001;
    broadcast(persona, SW_PERSONA_CHANGED, expect(e.data.persona.user == test_user && e.data.persona.flags == 0x40000001));
    AvatarImageLoaded_t avatar = {};
    avatar.m_steamID = CSteamID(test_user); avatar.m_iImage = 17; avatar.m_iWide = 10; avatar.m_iTall = 20;
    broadcast(avatar, SW_AVATAR_LOADED, expect(e.data.avatar.user == test_user && e.data.avatar.image == 17 && e.data.avatar.width == 10 && e.data.avatar.height == 20));
    avatar.m_iWide = -1;
    broadcast(avatar, SW_MALFORMED, (void)e);
    avatar.m_iWide = 10; avatar.m_iTall = -1;
    broadcast(avatar, SW_MALFORMED, (void)e);
    FriendRichPresenceUpdate_t presence = {}; presence.m_steamIDFriend = CSteamID(test_user); presence.m_nAppID = 480;
    broadcast(presence, SW_PRESENCE_CHANGED, expect(e.data.presence.user == test_user && e.data.presence.app == 480));
    GameLobbyJoinRequested_t join = {}; join.m_steamIDLobby = CSteamID(test_lobby); join.m_steamIDFriend = CSteamID(test_user);
    broadcast(join, SW_LOBBY_JOIN_REQUESTED, expect(e.data.lobby_invite.lobby == test_lobby && e.data.lobby_invite.user == test_user));
    LobbyInvite_t invite = {}; invite.m_ulSteamIDLobby = test_lobby; invite.m_ulSteamIDUser = test_user; invite.m_ulGameID = test_game;
    broadcast(invite, SW_LOBBY_INVITE, expect(e.data.lobby_invite.lobby == test_lobby && e.data.lobby_invite.user == test_user && e.data.lobby_invite.game == test_game));
    LobbyCreated_t created = {}; created.m_ulSteamIDLobby = test_lobby; created.m_eResult = k_EResultOK;
    broadcast(created, SW_LOBBY_CREATED, verify_result(created, e));
    LobbyEnter_t entered = {}; entered.m_ulSteamIDLobby = test_lobby; entered.m_bLocked = true; entered.m_EChatRoomEnterResponse = k_EChatRoomEnterResponseSuccess;
    broadcast(entered, SW_LOBBY_ENTERED, verify_result(entered, e));
    LobbyMatchList_t list = {}; list.m_nLobbiesMatching = 91;
    broadcast(list, SW_LOBBY_LIST, verify_result(list, e));
    LobbyDataUpdate_t data = {}; data.m_ulSteamIDLobby = test_lobby; data.m_ulSteamIDMember = test_user; data.m_bSuccess = 1;
    broadcast(data, SW_LOBBY_DATA, expect(e.data.lobby_data.lobby == test_lobby && e.data.lobby_data.member == test_user && e.data.lobby_data.success == 1));
    LobbyChatUpdate_t members = {}; members.m_ulSteamIDLobby = test_lobby; members.m_ulSteamIDUserChanged = test_user; members.m_ulSteamIDMakingChange = test_game; members.m_rgfChatMemberStateChange = 0x80000002U;
    broadcast(members, SW_LOBBY_MEMBERS, expect(e.data.lobby_members.lobby == test_lobby && e.data.lobby_members.member == test_user && e.data.lobby_members.actor == test_game && e.data.lobby_members.changes == 0x80000002U));
    LobbyChatMsg_t chat = {}; chat.m_ulSteamIDLobby = test_lobby; chat.m_ulSteamIDUser = test_user; chat.m_iChatID = 0x87654321U; chat.m_eChatEntryType = 255;
    broadcast(chat, SW_LOBBY_CHAT, expect(e.data.lobby_chat.lobby == test_lobby && e.data.lobby_chat.user == test_user && e.data.lobby_chat.chat_id == 0x87654321U && e.data.lobby_chat.entry_type == 255));
    LobbyKicked_t kicked = {}; kicked.m_ulSteamIDLobby = test_lobby; kicked.m_ulSteamIDAdmin = test_user; kicked.m_bKickedDueToDisconnect = 1;
    broadcast(kicked, SW_LOBBY_KICKED, expect(e.data.lobby_kicked.lobby == test_lobby && e.data.lobby_kicked.actor == test_user && e.data.lobby_kicked.disconnected == 1));
    LobbyGameCreated_t game = {}; game.m_ulSteamIDLobby = test_lobby; game.m_ulSteamIDGameServer = test_user; game.m_unIP = 0x7f000001; game.m_usPort = 27015;
    broadcast(game, SW_LOBBY_GAME_CREATED, expect(e.data.lobby_game.lobby == test_lobby && e.data.lobby_game.server == test_user && e.data.lobby_game.ipv4 == 0x7f000001 && e.data.lobby_game.port == 27015));
    GetAuthSessionTicketResponse_t auth_ticket = {}; auth_ticket.m_hAuthTicket = 0x87654321U; future_enum(auth_ticket.m_eResult);
    broadcast(auth_ticket, SW_AUTH_TICKET, expect(e.data.auth_ticket.ticket == 0x87654321U && e.data.auth_ticket.result == future_result));
    ValidateAuthTicketResponse_t auth = {}; auth.m_SteamID = CSteamID(test_user); auth.m_OwnerSteamID = CSteamID(test_lobby);
    static_assert(k_EAuthSessionResponseAuthTicketNetworkIdentityFailure == 10, "auth response mapping changed");
    auth.m_eAuthSessionResponse = k_EAuthSessionResponseAuthTicketNetworkIdentityFailure;
    broadcast(auth, SW_AUTH_VALIDATED, expect(e.data.auth_validated.user == test_user && e.data.auth_validated.owner == test_lobby && e.data.auth_validated.response == 10));
    future_enum(auth.m_eAuthSessionResponse);
    broadcast(auth, SW_AUTH_VALIDATED, expect(e.data.auth_validated.user == test_user && e.data.auth_validated.owner == test_lobby && e.data.auth_validated.response == future_auth_response));
    UserStatsReceived_t stats = {}; stats.m_nGameID = test_game; stats.m_steamIDUser = CSteamID(test_user); future_enum(stats.m_eResult);
    broadcast(stats, SW_STATS_RECEIVED, verify_result(stats, e));
    UserStatsStored_t stored = {}; stored.m_nGameID = test_game; future_enum(stored.m_eResult);
    broadcast(stored, SW_STATS_STORED, expect(e.data.stats.game == test_game && e.data.stats.result == future_result));
    UserStatsUnloaded_t unloaded = {}; unloaded.m_steamIDUser = CSteamID(test_user);
    broadcast(unloaded, SW_STATS_UNLOADED, expect(e.data.stats.user == test_user));
    RemoteStorageFileWriteAsyncComplete_t written = {}; future_enum(written.m_eResult);
    broadcast(written, SW_CLOUD_WRITTEN, verify_result(written, e));
    FloatingGamepadTextInputDismissed_t floating = {}; broadcast(floating, SW_FLOATING_DISMISSED, (void)e);
    AppResumingFromSuspend_t resumed = {}; broadcast(resumed, SW_RESUMED, (void)e);
    RemoteStorageLocalFileChange_t changed = {}; broadcast(changed, SW_CLOUD_CHANGED, (void)e);
    SteamInputDeviceConnected_t input_connected = {}; input_connected.m_ulConnectedDeviceHandle = UINT64_MAX;
    broadcast(input_connected, SW_INPUT_CONNECTED, expect(e.data.input_device.controller == UINT64_MAX));
    SteamInputDeviceDisconnected_t input_disconnected = {}; input_disconnected.m_ulDisconnectedDeviceHandle = test_user;
    broadcast(input_disconnected, SW_INPUT_DISCONNECTED, expect(e.data.input_device.controller == test_user));
    GamepadTextInputDismissed_t gamepad = {}; gamepad.m_bSubmitted = true; gamepad.m_unSubmittedText = UINT32_MAX; gamepad.m_unAppID = 73;
    broadcast(gamepad, SW_GAMEPAD_DISMISSED, expect(e.data.gamepad.app == 73 && e.data.gamepad.submitted == 1 && !e.data.gamepad.matched); expect(e.data.gamepad.capture.status == SW_UTILS_TEXT_UNTRACKED && e.data.gamepad.capture.reported_length == UINT32_MAX));
}

// Empty, embedded-NUL, final-NUL, and unterminated fixed buffers all copy
// exactly their capacity; the bridge does not promise NUL termination here.
template<size_t N> void text_pattern(char (&text)[N], int pattern) {
    for (size_t i = 0; i != N; ++i) text[i] = char('a' + i % 26);
    if (pattern == 0) memset(text, 0, N);
    if (pattern == 1) text[N / 2] = 0;
    if (pattern == 2) text[N - 1] = 0;
}
void test_capability_callbacks() {
    for (int pattern = 0; pattern != 4; ++pattern) {
        test_variant = pattern;
        SteamUGCQueryCompleted_t query = {};
        query.m_handle = pattern == 0 ? 0 : UINT64_MAX;
        query.m_unNumResultsReturned = pattern == 0 ? 0 : UINT32_MAX;
        query.m_unTotalMatchingResults = 91; query.m_bCachedData = pattern % 2 != 0;
        text_pattern(query.m_rgchNextCursor, pattern);
        const EResult results[] = {k_EResultOK, k_EResultFail, future_result};
        for (EResult result : results) {
            query.m_eResult = result;
            completion_cases("SteamUGCQueryCompleted_t/result-and-owned-cursor", query);
            broadcast(query, SW_WORKSHOP_QUERY_COMPLETED, verify_result(query, e));
        }
        SteamRemotePlayTogetherGuestInvite_t invite = {};
        text_pattern(invite.m_szConnectURL, pattern);
        broadcast(invite, SW_REMOTE_PLAY_GUEST_INVITE,
            expect(memcmp(e.data.remote_invite.url, invite.m_szConnectURL, sizeof(invite.m_szConnectURL)) == 0));
    }
    ItemInstalled_t installed = {};
    installed.m_unAppID = 73; installed.m_nPublishedFileId = test_lobby;
    installed.m_hLegacyContent = test_user; installed.m_unManifestID = test_game;
    broadcast(installed, SW_WORKSHOP_ITEM_INSTALLED,
        expect(e.data.workshop_installed.app == 73 && e.data.workshop_installed.item == test_lobby);
        expect(e.data.workshop_installed.legacy_content == test_user && e.data.workshop_installed.manifest == test_game));
    DownloadItemResult_t downloaded = {}; downloaded.m_unAppID = 73; downloaded.m_nPublishedFileId = test_lobby;
    future_enum(downloaded.m_eResult);
    broadcast(downloaded, SW_WORKSHOP_DOWNLOADED,
        expect(e.data.workshop_download.app == 73 && e.data.workshop_download.item == test_lobby && e.data.workshop_download.result == future_result));
    UserSubscribedItemsListChanged_t subscriptions = {}; subscriptions.m_nAppID = 73;
    broadcast(subscriptions, SW_WORKSHOP_SUBSCRIPTIONS_CHANGED, expect(e.data.workshop_subscriptions.app == 73));
    SteamRemotePlaySessionConnected_t connected = {}; connected.m_unSessionID = UINT32_MAX;
    broadcast(connected, SW_REMOTE_PLAY_CONNECTED, expect(e.data.remote_session.session == UINT32_MAX));
    SteamRemotePlaySessionDisconnected_t disconnected = {}; disconnected.m_unSessionID = 0;
    broadcast(disconnected, SW_REMOTE_PLAY_DISCONNECTED, expect(e.data.remote_session.session == 0));
    SteamRemotePlaySessionAvatarLoaded_t avatar = {};
    avatar.m_unSessionID = 71; avatar.m_iImage = -17; avatar.m_iWide = -1; avatar.m_iTall = 0;
    broadcast(avatar, SW_REMOTE_PLAY_AVATAR_LOADED,
        expect(e.data.remote_avatar.session == 71 && e.data.remote_avatar.image == -17 && e.data.remote_avatar.width == -1 && e.data.remote_avatar.height == 0));
    ScreenshotReady_t screenshot = {}; screenshot.m_hLocal = UINT32_MAX;
    future_enum(screenshot.m_eResult);
    broadcast(screenshot, SW_SCREENSHOT_READY, expect(e.data.screenshot.handle == UINT32_MAX && e.data.screenshot.result == future_result));
    screenshot.m_hLocal = 0; screenshot.m_eResult = k_EResultFail;
    broadcast(screenshot, SW_SCREENSHOT_READY, expect(e.data.screenshot.handle == 0 && e.data.screenshot.result == k_EResultFail));
    ScreenshotRequested_t requested = {};
    broadcast(requested, SW_SCREENSHOT_REQUESTED, (void)e);
}

void test_text_and_ticket_bounds() {
    for (int pattern = 0; pattern != 4; ++pattern) {
        test_variant = pattern;
        GameRichPresenceJoinRequested_t game_join = {}; game_join.m_steamIDFriend = CSteamID(test_user);
        text_pattern(game_join.m_rgchConnect, pattern);
        broadcast(game_join, SW_GAME_JOIN_REQUESTED, expect(e.data.game_join.user == test_user); expect(memcmp(e.data.game_join.connect, game_join.m_rgchConnect, sizeof(game_join.m_rgchConnect)) == 0));
        UserAchievementStored_t achievement = {}; achievement.m_nGameID = test_game; achievement.m_bGroupAchievement = true; achievement.m_nCurProgress = 7; achievement.m_nMaxProgress = 19;
        text_pattern(achievement.m_rgchAchievementName, pattern);
        broadcast(achievement, SW_ACHIEVEMENT_STORED, expect(e.data.achievement.game == test_game && e.data.achievement.group == 1 && e.data.achievement.current == 7 && e.data.achievement.maximum == 19); expect(memcmp(e.data.achievement.name, achievement.m_rgchAchievementName, sizeof(achievement.m_rgchAchievementName)) == 0));
        UserAchievementIconFetched_t icon = {}; icon.m_nGameID = CGameID(test_game); icon.m_bAchieved = true; icon.m_nIconHandle = -17;
        text_pattern(icon.m_rgchAchievementName, pattern);
        broadcast(icon, SW_ACHIEVEMENT_ICON, expect(e.data.achievement_icon.game == test_game && e.data.achievement_icon.achieved && e.data.achievement_icon.image == -17); expect(memcmp(e.data.achievement_icon.name, icon.m_rgchAchievementName, sizeof(icon.m_rgchAchievementName)) == 0));
        SteamRelayNetworkStatus_t relay = {}; future_enum(relay.m_eAvail); relay.m_bPingMeasurementInProgress = 1;
        text_pattern(relay.m_debugMsg, pattern);
        broadcast(relay, SW_RELAY_STATUS, expect(e.data.relay.availability == future_value && e.data.relay.measuring == 1); expect(memcmp(e.data.relay.debug, relay.m_debugMsg, sizeof(relay.m_debugMsg)) == 0));
        SteamNetConnectionStatusChangedCallback_t network = {};
        network.m_hConn = 31; network.m_info.m_hListenSocket = 57; network.m_info.m_eEndReason = 1001;
        network.m_info.m_identityRemote.Clear(); network.m_info.m_identityRemote.SetSteamID64(test_user);
        future_enum(network.m_info.m_eState); future_enum(network.m_eOldState);
        text_pattern(network.m_info.m_szEndDebug, pattern);
        broadcast(network, SW_CONNECTION_CHANGED,
            expect(e.data.network.info.connection == 31 && e.data.network.info.listen_socket == 57 && e.data.network.info.end_reason == 1001);
            expect(e.data.network.info.state == future_value && e.data.network.old_state == future_value && e.data.network.info.peer_steam_id == test_user);
            expect(memchr(e.data.network.info.peer_identity, 0, sizeof(e.data.network.info.peer_identity)) != nullptr);
            expect(strcmp(e.data.network.info.peer_identity, identity_fixture_text) == 0);
            expect(memcmp(e.data.network.info.end_debug, network.m_info.m_szEndDebug, sizeof(network.m_info.m_szEndDebug)) == 0));
    }
    GetTicketForWebApiResponse_t ticket = {};
    ticket.m_hAuthTicket = 0x87654321U; future_enum(ticket.m_eResult);
    for (size_t i = 0; i != sizeof(ticket.m_rgubTicket); ++i) ticket.m_rgubTicket[i] = uint8_t(i * 37 + 11);
    const int lengths[] = {-1, 0, 1, int(sizeof(ticket.m_rgubTicket)) - 1, int(sizeof(ticket.m_rgubTicket)), int(sizeof(ticket.m_rgubTicket)) + 1};
    for (int length : lengths) {
        test_variant = length;
        ticket.m_cubTicket = length;
        const bool valid = length >= 0 && size_t(length) <= sizeof(ticket.m_rgubTicket);
        broadcast(ticket, valid ? SW_WEB_TICKET : SW_MALFORMED,
            if (valid) {
                expect(e.data.web_ticket.ticket == 0x87654321U && e.data.web_ticket.result == future_result && e.data.web_ticket.size == uint32_t(length));
                expect(memcmp(e.data.web_ticket.bytes, ticket.m_rgubTicket, size_t(length)) == 0);
                for (size_t i = size_t(length); i != sizeof(e.data.web_ticket.bytes); ++i) expect(e.data.web_ticket.bytes[i] == 0);
            });
    }
}
#undef broadcast
#undef expect
} // namespace
int main() {
    test_completions();
    test_platform_completions();
    test_keyboard_capture();
    test_unknown_callbacks();
    test_broadcasts();
    test_capability_callbacks();
    test_text_and_ticket_bounds();
    printf("Steamworks callback fixtures passed (%d bounded poll cases)\n", cases_run);
}
#endif
