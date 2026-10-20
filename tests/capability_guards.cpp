// SDK-free fail-closed boundary for the capability lease tests. An escaped
// adapter abort cannot match the runner's required lease-panic diagnostic.
#include "core.h"
#include "voice.h"
#include "remote_play.h"
#include "timeline.h"
#include "workshop.h"
#include "screenshots.h"
#include <stdlib.h>

void sw_shutdown(void) { abort(); }
uint8_t sw_next_event(int32_t, const SwPollState *, SwEvent *) { abort(); }
int32_t sw_voice_start(void) { abort(); }
int32_t sw_voice_stop(void) { abort(); }
int32_t sw_voice_available(int32_t *, uint32_t *) { abort(); }
int32_t sw_voice_read(void *, uint32_t, int32_t *, uint32_t *) { abort(); }
int32_t sw_voice_decode(const void *, uint32_t, void *, uint32_t, uint32_t, int32_t *, uint32_t *) { abort(); }
int32_t sw_voice_optimal_sample_rate(uint32_t *) { abort(); }
int32_t sw_remote_play_session_count(uint32_t *) { abort(); }
int32_t sw_remote_play_session_id(int32_t, uint32_t *) { abort(); }
int32_t sw_remote_play_together(uint32_t) { abort(); }
int32_t sw_remote_play_steam_id(uint32_t, uint64_t *) { abort(); }
int32_t sw_remote_play_guest_id(uint32_t, uint32_t *) { abort(); }
int32_t sw_remote_play_client_name(uint32_t, uint8_t *, size_t, uint32_t *, uint32_t *) { abort(); }
int32_t sw_remote_play_form_factor(uint32_t, int32_t *) { abort(); }
int32_t sw_remote_play_resolution(uint32_t, int32_t *, int32_t *) { abort(); }
int32_t sw_remote_play_show_together_ui(void) { abort(); }
int32_t sw_remote_play_invite(uint64_t) { abort(); }
int32_t sw_timeline_mode(int32_t) { abort(); }
int32_t sw_timeline_tooltip(const char *, float) { abort(); }
int32_t sw_timeline_clear_tooltip(float) { abort(); }
int32_t sw_timeline_instant(const char *, const char *, const char *, uint32_t, float, int32_t, uint64_t *) { abort(); }
int32_t sw_timeline_completed(const char *, const char *, const char *, uint32_t, float, float, int32_t, uint64_t *) { abort(); }
int32_t sw_timeline_start(const char *, const char *, const char *, uint32_t, float, int32_t, uint64_t *) { abort(); }
int32_t sw_timeline_update(uint64_t, const char *, const char *, const char *, uint32_t, int32_t) { abort(); }
int32_t sw_timeline_end(uint64_t, float) { abort(); }
int32_t sw_timeline_remove(uint64_t) { abort(); }
int32_t sw_workshop_create(const uint64_t *, size_t, uint64_t *) { abort(); }
int32_t sw_workshop_send(uint64_t, uint64_t *) { abort(); }
int32_t sw_workshop_release(uint64_t, bool *) { abort(); }
int32_t sw_workshop_details(uint64_t, uint32_t, struct sw_workshop_details *, bool *) { abort(); }
int32_t sw_workshop_count(bool, uint32_t *) { abort(); }
int32_t sw_workshop_subscriptions(bool, uint64_t *, size_t, uint32_t *) { abort(); }
int32_t sw_workshop_state(uint64_t, uint32_t *) { abort(); }
int32_t sw_workshop_install(uint64_t, char *, size_t, bool *, uint64_t *, uint32_t *, size_t *) { abort(); }
int32_t sw_workshop_progress(uint64_t, bool *, uint64_t *, uint64_t *) { abort(); }
int32_t sw_workshop_download(uint64_t, bool, bool *) { abort(); }
bool sw_screenshots_write(void *, uint32_t, int32_t, int32_t, uint32_t *) { abort(); }
bool sw_screenshots_add(const char *, const char *, int32_t, int32_t, uint32_t *) { abort(); }
bool sw_screenshots_trigger(void) { abort(); }
bool sw_screenshots_hook(bool) { abort(); }
bool sw_screenshots_is_hooked(bool *) { abort(); }
