#include "voice.h"
#include <steam/steam_api_flat.h>
#include <string.h>

static_assert(k_EVoiceResultOK == 0 && k_EVoiceResultNotInitialized == 1 &&
    k_EVoiceResultNotRecording == 2 && k_EVoiceResultNoData == 3 &&
    k_EVoiceResultBufferTooSmall == 4 && k_EVoiceResultDataCorrupted == 5 &&
    k_EVoiceResultRestricted == 6 && k_EVoiceResultUnsupportedCodec == 7 &&
    k_EVoiceResultReceiverOutOfDate == 8 && k_EVoiceResultReceiverDidNotAnswer == 9);

#ifdef SW_VOICE_TEST
#include <stdio.h>
#include <stdlib.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #x); abort(); } } while (0)
namespace voice_test {
static char token;
static ISteamUser *const user = reinterpret_cast<ISteamUser *>(&token);
static bool present = true;
static unsigned accessors, calls, starts, stops;
static EVoiceResult result = k_EVoiceResultOK;
static uint32 count = 2, rate = 24000;
static const void *input;
static void *output;
static uint32 input_size, output_size;
static decltype(SteamAPI_SteamUser_v023) accessor;
static ISteamUser *accessor() { ++accessors; return present ? user : nullptr; }
static void check(ISteamUser *self) { CHECK(self == user); ++calls; }
static decltype(SteamAPI_ISteamUser_StartVoiceRecording) start;
static void start(ISteamUser *self) { check(self); ++starts; }
static decltype(SteamAPI_ISteamUser_StopVoiceRecording) stop;
static void stop(ISteamUser *self) { check(self); ++stops; }
static decltype(SteamAPI_ISteamUser_GetAvailableVoice) available;
static EVoiceResult available(ISteamUser *self, uint32 *bytes, uint32 *deprecated_bytes, uint32 deprecated_rate) {
    check(self); CHECK(bytes && *bytes == 0); CHECK(deprecated_bytes == nullptr && deprecated_rate == 0);
    *bytes = count; return result;
}
static decltype(SteamAPI_ISteamUser_GetVoice) read;
static EVoiceResult read(ISteamUser *self, bool compressed, void *out, uint32 capacity, uint32 *bytes,
    bool deprecated_uncompressed, void *deprecated_out, uint32 deprecated_capacity, uint32 *deprecated_bytes, uint32 deprecated_rate) {
    check(self); CHECK(compressed && out == output && capacity == output_size);
    CHECK(bytes && *bytes == 0);
    CHECK(!deprecated_uncompressed && deprecated_out == nullptr && deprecated_capacity == 0 && deprecated_bytes == nullptr && deprecated_rate == 0);
    if (capacity) static_cast<unsigned char *>(out)[0] = 0x7b;
    *bytes = count; return result;
}
static decltype(SteamAPI_ISteamUser_DecompressVoice) decode;
static EVoiceResult decode(ISteamUser *self, const void *compressed, uint32 compressed_bytes, void *out, uint32 capacity, uint32 *bytes, uint32 sample_rate) {
    check(self); CHECK(compressed == input && compressed_bytes == input_size);
    CHECK(out == output && capacity == output_size && sample_rate == rate);
    CHECK(bytes && *bytes == 0);
    if (capacity) static_cast<unsigned char *>(out)[0] = 0x7b;
    *bytes = count; return result;
}
static decltype(SteamAPI_ISteamUser_GetVoiceOptimalSampleRate) optimal;
static uint32 optimal(ISteamUser *self) { check(self); return rate; }
}
#define SteamAPI_SteamUser_v023 voice_test::accessor
#define SteamAPI_ISteamUser_StartVoiceRecording voice_test::start
#define SteamAPI_ISteamUser_StopVoiceRecording voice_test::stop
#define SteamAPI_ISteamUser_GetAvailableVoice voice_test::available
#define SteamAPI_ISteamUser_GetVoice voice_test::read
#define SteamAPI_ISteamUser_DecompressVoice voice_test::decode
#define SteamAPI_ISteamUser_GetVoiceOptimalSampleRate voice_test::optimal
#endif

namespace {
static int32_t result_bits(const EVoiceResult &value) {
    int32_t result;
    static_assert(sizeof(value) == sizeof(result), "Voice result width changed");
    memcpy(&result, &value, sizeof(result));
    return result;
}
}

extern "C" {
int32_t sw_voice_start(void) {
    auto *user = SteamAPI_SteamUser_v023();
    if (!user) return -1;
    SteamAPI_ISteamUser_StartVoiceRecording(user);
    return 0;
}
int32_t sw_voice_stop(void) {
    auto *user = SteamAPI_SteamUser_v023();
    if (!user) return -1;
    SteamAPI_ISteamUser_StopVoiceRecording(user);
    return 0;
}
int32_t sw_voice_available(int32_t *result, uint32_t *bytes) {
    *bytes = 0;
    auto *user = SteamAPI_SteamUser_v023();
    if (!user) return -1;
    // isteamuser.h: GetAvailableVoice's deprecated count and rate are NULL/0.
    *result = result_bits(SteamAPI_ISteamUser_GetAvailableVoice(user, bytes, nullptr, 0));
    return 0;
}
int32_t sw_voice_read(void *out, uint32_t capacity, int32_t *result, uint32_t *bytes) {
    *bytes = 0;
    auto *user = SteamAPI_SteamUser_v023();
    if (!user) return -1;
    // Independently audited GetVoice tail: false, NULL, 0, NULL, 0.
    *result = result_bits(SteamAPI_ISteamUser_GetVoice(user, true, out, capacity, bytes, false, nullptr, 0, nullptr, 0));
    return 0;
}
int32_t sw_voice_decode(const void *compressed, uint32_t compressed_bytes, void *out, uint32_t capacity_bytes, uint32_t sample_rate, int32_t *result, uint32_t *bytes) {
    *bytes = 0;
    auto *user = SteamAPI_SteamUser_v023();
    if (!user) return -1;
    *result = result_bits(SteamAPI_ISteamUser_DecompressVoice(user, compressed, compressed_bytes, out, capacity_bytes, bytes, sample_rate));
    return 0;
}
int32_t sw_voice_optimal_sample_rate(uint32_t *sample_rate) {
    *sample_rate = 0;
    auto *user = SteamAPI_SteamUser_v023();
    if (!user) return -1;
    *sample_rate = SteamAPI_ISteamUser_GetVoiceOptimalSampleRate(user);
    return 0;
}
}

#ifdef SW_VOICE_TEST
int main() {
    using namespace voice_test;
    unsigned char compressed[4] = {};
    int16_t pcm[4] = {};
    int32_t native_result = -77;
    uint32_t bytes = 99, sample_rate = 99;
    output = compressed; output_size = sizeof(compressed);
    present = false;
    CHECK(sw_voice_start() == -1 && sw_voice_stop() == -1);
    CHECK(sw_voice_available(&native_result, &bytes) == -1 && bytes == 0 && native_result == -77);
    CHECK(sw_voice_read(compressed, sizeof(compressed), &native_result, &bytes) == -1);
    CHECK(sw_voice_decode(compressed, sizeof(compressed), pcm, sizeof(pcm), rate, &native_result, &bytes) == -1);
    CHECK(sw_voice_optimal_sample_rate(&sample_rate) == -1 && sample_rate == 0);
    CHECK(calls == 0 && accessors == 6);
    present = true;
    CHECK(sw_voice_start() == 0 && starts == 1 && stops == 0);
    CHECK(sw_voice_stop() == 0 && stops == 1 && starts == 1);
    input = compressed; input_size = sizeof(compressed);
    // 15 is unknown but representable in the official enum's [0,15] range.
    for (int value = 0; value <= 15; ++value) {
        result = static_cast<EVoiceResult>(value);
        count = value == 4 ? UINT32_MAX : 2;
        CHECK(sw_voice_available(&native_result, &bytes) == 0 && native_result == value && bytes == count);
        output = compressed; output_size = sizeof(compressed);
        CHECK(sw_voice_read(compressed, sizeof(compressed), &native_result, &bytes) == 0);
        CHECK(native_result == value && bytes == count && compressed[0] == 0x7b);
        output = pcm; output_size = sizeof(pcm);
        CHECK(sw_voice_decode(compressed, sizeof(compressed), pcm, sizeof(pcm), rate, &native_result, &bytes) == 0);
        CHECK(native_result == value && bytes == count && reinterpret_cast<unsigned char *>(pcm)[0] == 0x7b);
    }
    count = 3; // Preserve odd PCM counts; Zig owns publication validation.
    CHECK(sw_voice_decode(compressed, sizeof(compressed), pcm, sizeof(pcm), rate, &native_result, &bytes) == 0 && bytes == 3);
    CHECK(sw_voice_optimal_sample_rate(&sample_rate) == 0 && sample_rate == rate);
    CHECK(starts == 1 && stops == 1 && calls == 52 && accessors == 58);
    puts("voice fixture: exact flat arguments, missing interface, raw results/counts and failure mutation passed");
}
#endif
