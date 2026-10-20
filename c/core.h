#ifndef MEIKYUU_STEAMWORKS_CORE_H
#define MEIKYUU_STEAMWORKS_CORE_H
#include "types.h"
#include "utils.h"
#ifdef __cplusplus
extern "C" {
#endif

enum { SW_INIT_MESSAGE_SIZE = 1024 };
enum SwEventKind {
    SW_UNHANDLED, SW_MALFORMED, SW_CALL_FAILED,
    SW_CONNECTED, SW_DISCONNECTED, SW_CONNECT_FAILURE, SW_SHUTDOWN,
    SW_OVERLAY, SW_DLC_INSTALLED, SW_PERSONA_CHANGED, SW_AVATAR_LOADED, SW_PRESENCE_CHANGED,
    SW_GAME_JOIN_REQUESTED, SW_LOBBY_JOIN_REQUESTED, SW_LOBBY_INVITE,
    SW_LOBBY_CREATED, SW_LOBBY_ENTERED, SW_LOBBY_LIST,
    SW_LOBBY_DATA, SW_LOBBY_MEMBERS, SW_LOBBY_CHAT, SW_LOBBY_KICKED, SW_LOBBY_GAME_CREATED,
    SW_CONNECTION_CHANGED, SW_RELAY_STATUS,
    SW_AUTH_TICKET, SW_WEB_TICKET, SW_AUTH_VALIDATED,
    SW_STATS_RECEIVED, SW_STATS_STORED, SW_ACHIEVEMENT_STORED,
    SW_CLOUD_WRITTEN, SW_STATS_UNLOADED,
    SW_ACHIEVEMENT_ICON, SW_LEADERBOARD_FOUND, SW_LEADERBOARD_ENTRIES,
    SW_LEADERBOARD_UPLOADED, SW_GLOBAL_PERCENTAGES_READY,
    SW_GAMEPAD_DISMISSED, SW_FLOATING_DISMISSED, SW_RESUMED,
    SW_CLOUD_CHANGED, SW_INPUT_CONNECTED, SW_INPUT_DISCONNECTED
};
enum SwCallFailure { SW_RESULT_UNAVAILABLE = 1, SW_IO_FAILURE = 2 };

typedef struct SwEvent {
    int32_t kind;
    int32_t callback_id;
    uint64_t call;
    union {
        struct { int32_t result; uint8_t retrying; } connection;
        struct { uint8_t active; uint8_t user_initiated; uint32_t app; } overlay;
        struct { uint32_t app; } dlc;
        struct { uint64_t user; uint32_t flags; } persona;
        struct { uint64_t user; int32_t image; uint32_t width; uint32_t height; } avatar;
        struct { uint64_t user; uint32_t app; } presence;
        struct { uint64_t user; char connect[256]; } game_join;
        struct { uint64_t lobby; uint64_t user; uint64_t game; } lobby_invite;
        struct { uint64_t lobby; int32_t result; } lobby_created;
        struct { uint64_t lobby; uint32_t response; uint8_t locked; } lobby_entered;
        struct { uint32_t count; } lobby_list;
        struct { uint64_t lobby; uint64_t member; uint8_t success; } lobby_data;
        struct { uint64_t lobby; uint64_t member; uint64_t actor; uint32_t changes; } lobby_members;
        struct { uint64_t lobby; uint64_t user; uint32_t chat_id; uint8_t entry_type; } lobby_chat;
        struct { uint64_t lobby; uint64_t actor; uint8_t disconnected; } lobby_kicked;
        struct { uint64_t lobby; uint64_t server; uint32_t ipv4; uint16_t port; } lobby_game;
        struct { SwConnectionInfo info; int32_t old_state; } network;
        struct { int32_t availability; uint8_t measuring; char debug[256]; } relay;
        struct { uint32_t ticket; int32_t result; } auth_ticket;
        struct { uint32_t ticket; int32_t result; uint32_t size; uint8_t bytes[2560]; } web_ticket;
        struct { uint64_t user; uint64_t owner; int32_t response; } auth_validated;
        struct { uint64_t game; uint64_t user; int32_t result; } stats;
        struct { uint64_t game; char name[128]; uint32_t current; uint32_t maximum; uint8_t group; } achievement;
        struct { int32_t result; } cloud;
        struct { uint64_t game; char name[128]; uint8_t achieved; int32_t image; } achievement_icon;
        struct { uint64_t leaderboard; uint8_t found; } leaderboard_found;
        struct { uint64_t leaderboard; SwLeaderboardEntries capture; } leaderboard_download;
        struct { uint64_t leaderboard; uint8_t success; int32_t score; uint8_t changed; int32_t rank_new; int32_t rank_previous; } leaderboard_upload;
        struct { uint64_t game; int32_t result; } global_percentages;
        struct { uint32_t app; uint8_t submitted, matched; SwUtilsTextCapture capture; } gamepad;
        struct { uint64_t controller; } input_device;
        struct { int32_t reason; } call_failure;
    } data;
} SwEvent;

/* Init checks interface versions using the supplied official headers. */
int32_t sw_init(char message[SW_INIT_MESSAGE_SIZE]);
void sw_shutdown(void);
uint8_t sw_restart_if_necessary(uint32_t app);
int32_t sw_pipe(void);
void sw_run_frame(int32_t pipe);
/* Borrowed call-time correlation only; no retained Context pointer. */
typedef struct SwPollState {
    uint64_t leaderboard_download_call;
    uint32_t keyboard_app_id;
    uint8_t gamepad_pending;
} SwPollState;
/* Returns an owned event. Captures secondary data before freeing the callback. */
uint8_t sw_next_event(int32_t pipe, const SwPollState *state, SwEvent *event);
uint64_t sw_user_id(void);
uint8_t sw_logged_on(void);
uint32_t sw_app_id(void);
uint8_t sw_overlay_enabled(void);
uint32_t sw_server_time(void);

uint32_t sw_auth_ticket(void *buffer, int32_t capacity, uint32_t *size, uint64_t recipient);
uint32_t sw_web_ticket(const char *identity);
void sw_cancel_ticket(uint32_t ticket);
int32_t sw_begin_auth(const void *ticket, int32_t size, uint64_t user);
void sw_end_auth(uint64_t user);
int32_t sw_user_license(uint64_t user, uint32_t app);
#ifdef __cplusplus
}
#endif
#endif
