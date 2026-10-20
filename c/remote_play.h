#ifndef SW_REMOTE_PLAY_H
#define SW_REMOTE_PLAY_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

/* Status: 0 success, -1 unavailable, -2 invalid argument.
 * Boolean methods return 0/1, or a negative status. */
int32_t sw_remote_play_session_count(uint32_t *count);
int32_t sw_remote_play_session_id(int32_t index, uint32_t *session);
int32_t sw_remote_play_together(uint32_t session);
int32_t sw_remote_play_steam_id(uint32_t session, uint64_t *steam_id);
int32_t sw_remote_play_guest_id(uint32_t session, uint32_t *guest_id);
/* Name status: 0 complete (including empty), 1 NULL, 2 exceeds wrapper
 * scan bound, 3 short output. Scan at most 1024 bytes including NUL.
 * required and copied exclude NUL; required is known only for 0/3.
 * No terminator is copied. Non-complete output is unchanged. */
int32_t sw_remote_play_client_name(uint32_t session, uint8_t *output, size_t capacity, uint32_t *required, uint32_t *copied);
int32_t sw_remote_play_form_factor(uint32_t session, int32_t *form_factor);
/* Returns the native boolean independently of signed output dimensions. */
int32_t sw_remote_play_resolution(uint32_t session, int32_t *width, int32_t *height);
int32_t sw_remote_play_show_together_ui(void);
/* Zero deliberately requests a guest invitation; Zig validates friend IDs. */
int32_t sw_remote_play_invite(uint64_t friend_id);

#ifdef __cplusplus
}
#endif
#endif
