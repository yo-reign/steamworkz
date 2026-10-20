#ifndef SW_SCREENSHOTS_H
#define SW_SCREENSHOTS_H
#include <stdbool.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Private validated-input bridge. False means interface unavailable; output
 * is not published. True means invocation, not completion or operation success.
 * Zero output handle is rejected submission. No pointer is stored here. */
bool sw_screenshots_write(void *rgb, uint32_t bytes, int32_t width, int32_t height, uint32_t *handle);
bool sw_screenshots_add(const char *path, const char *thumbnail, int32_t width, int32_t height, uint32_t *handle);
bool sw_screenshots_trigger(void);
bool sw_screenshots_hook(bool enabled);
bool sw_screenshots_is_hooked(bool *hooked);
#ifdef __cplusplus
}
#endif
#endif
