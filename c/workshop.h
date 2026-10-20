#ifndef SW_WORKSHOP_H
#define SW_WORKSHOP_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Private owned ABI, not SDK layout. Status: 0 invoked, -1 unavailable,
 * -2 invalid input, -3 malformed count, -4 unterminated successful path.
 * Getter false does not publish details. Install failure may mutate path. */
struct sw_workshop_details {
    uint64_t item;
    int32_t result, file_type;
    uint32_t creator_app, consumer_app;
    char title[129], description[8000];
    uint64_t owner;
    uint32_t created, updated, added_to_list;
    int32_t visibility;
    bool banned, accepted_for_use, tags_truncated;
    char tags[1025];
    uint64_t file, preview_file;
    char filename[260];
    int32_t file_size, preview_file_size;
    char url[256];
    uint32_t votes_up, votes_down;
    float score;
    uint32_t children;
    uint64_t total_files_size;
};
int32_t sw_workshop_create(const uint64_t *items, size_t count, uint64_t *handle);
int32_t sw_workshop_send(uint64_t handle, uint64_t *call);
int32_t sw_workshop_release(uint64_t handle, bool *accepted);
int32_t sw_workshop_details(uint64_t handle, uint32_t index, struct sw_workshop_details *out, bool *found);
int32_t sw_workshop_count(bool include_locally_disabled, uint32_t *count);
int32_t sw_workshop_subscriptions(bool include_locally_disabled, uint64_t *out, size_t capacity, uint32_t *count);
int32_t sw_workshop_state(uint64_t item, uint32_t *flags);
int32_t sw_workshop_install(uint64_t item, char *path, size_t capacity, bool *found, uint64_t *size, uint32_t *timestamp, size_t *length);
int32_t sw_workshop_progress(uint64_t item, bool *found, uint64_t *downloaded, uint64_t *total);
int32_t sw_workshop_download(uint64_t item, bool high_priority, bool *accepted);
#ifdef __cplusplus
}
#endif
#endif
