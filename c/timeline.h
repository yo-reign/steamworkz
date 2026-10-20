#ifndef SW_TIMELINE_H
#define SW_TIMELINE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
#define SW_TIMELINE_MAX_PRIORITY 1000
#define SW_TIMELINE_KEEP_PRIORITY 1000000
#define SW_TIMELINE_MAX_DURATION 600.0f
#define SW_TIMELINE_DEFAULT_OFFSET 0.0f
#define SW_TIMELINE_DEFAULT_DURATION 0.0f
#define SW_TIMELINE_DEFAULT_CLIP 1
/* Status 0 means forwarded, -1 means interface unavailable. Void SDK calls
 * do not establish recorded content or backend success. Text is borrowed for
 * the call. Output handles include zero; no failure sentinel is invented. */
int32_t sw_timeline_mode(int32_t mode);
int32_t sw_timeline_tooltip(const char *description, float offset);
int32_t sw_timeline_clear_tooltip(float offset);
int32_t sw_timeline_instant(const char *title, const char *description, const char *icon, uint32_t priority, float offset, int32_t clip, uint64_t *handle);
int32_t sw_timeline_completed(const char *title, const char *description, const char *icon, uint32_t priority, float offset, float duration, int32_t clip, uint64_t *handle);
int32_t sw_timeline_start(const char *title, const char *description, const char *icon, uint32_t priority, float offset, int32_t clip, uint64_t *handle);
int32_t sw_timeline_update(uint64_t handle, const char *title, const char *description, const char *icon, uint32_t priority, int32_t clip);
int32_t sw_timeline_end(uint64_t handle, float offset);
int32_t sw_timeline_remove(uint64_t handle);
#ifdef __cplusplus
}
#endif
#endif
