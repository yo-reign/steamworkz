#ifndef SW_VOICE_H
#define SW_VOICE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Status: 0 invoked, -1 interface unavailable. Native EVoiceResult is a
 * separate signed output. Counts are initialized before lookup and preserved
 * verbatim. Buffers belong to the caller and may change even on native failure.
 * Zig validates sizes, sample rate and non-overlap before entering this bridge. */
int32_t sw_voice_start(void);
int32_t sw_voice_stop(void);
int32_t sw_voice_available(int32_t *result, uint32_t *bytes);
int32_t sw_voice_read(void *out, uint32_t capacity, int32_t *result, uint32_t *bytes);
int32_t sw_voice_decode(const void *compressed, uint32_t compressed_bytes, void *out, uint32_t capacity_bytes, uint32_t sample_rate, int32_t *result, uint32_t *bytes);
int32_t sw_voice_optimal_sample_rate(uint32_t *sample_rate);
#ifdef __cplusplus
}
#endif
#endif
