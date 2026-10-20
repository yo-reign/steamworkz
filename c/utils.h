#ifndef STEAMWORKZ_UTILS_H
#define STEAMWORKZ_UTILS_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Private bridge: boolean operations return -1 unavailable, -2 invalid, 0/1 native acceptance. */
int32_t sw_utils_show_gamepad(int32_t mode, int32_t lines, const char *description, uint32_t max_chars, const char *existing, uint32_t *app_id);
int32_t sw_utils_show_floating(int32_t mode, int32_t x, int32_t y, int32_t width, int32_t height);
int32_t sw_utils_dismiss_gamepad(void);
int32_t sw_utils_dismiss_floating(void);
int32_t sw_utils_init_filter(void);
/* Returns 0 on success, -1 unavailable, -2 invalid. Output scanning belongs to Zig. */
int32_t sw_utils_filter(int32_t context, uint64_t source, const char *input, char *output, uint32_t capacity, int32_t *filtered_chars);
int32_t sw_utils_default_config(int32_t *config);

enum { SW_UTILS_TEXT_CAPACITY = 1024 };
enum SwUtilsTextStatus {
    SW_UTILS_TEXT_CANCELED = 0,
    SW_UTILS_TEXT_COMPLETE = 1,
    SW_UTILS_TEXT_TOO_LARGE = 2,
    SW_UTILS_TEXT_UNAVAILABLE = 3,
    SW_UTILS_TEXT_RETRIEVAL_FAILED = 4,
    SW_UTILS_TEXT_MALFORMED = 5,
    SW_UTILS_TEXT_UNTRACKED = 6
};
typedef struct SwUtilsTextCapture {
    int32_t status;
    uint32_t reported_length;
    uint32_t queried_length;
    uint32_t copied_length;
    uint8_t bytes[SW_UTILS_TEXT_CAPACITY];
} SwUtilsTextCapture;
/* Call inside dismissal conversion, before releasing the native callback. Owns all bytes. */
void sw_utils_capture_gamepad_text(uint8_t submitted, uint32_t reported_length, SwUtilsTextCapture *out);
#ifdef __cplusplus
}
#endif
#endif
