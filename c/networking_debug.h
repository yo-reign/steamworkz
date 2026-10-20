#ifndef SW_NETWORKING_DEBUG_H
#define SW_NETWORKING_DEBUG_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Owner-thread only. Returns 1 on registration/removal, 0 if unavailable,
 * -1 for an invalid active level. Removal uses level 0 and a null callback.
 * Removal does not establish callback quiescence. */
int sw_networking_debug_start(int32_t level);
int sw_networking_debug_stop(void);
/* Required Zig sink. Process-lifetime code/storage; never a game callback. */
void sw_networking_debug_sink(int32_t level, const char *message);
#ifdef __cplusplus
}
#endif
#endif
