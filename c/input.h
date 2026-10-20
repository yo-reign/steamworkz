#ifndef SW_INPUT_H
#define SW_INPUT_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Owned bridge contracts, checked against the official SDK in input.cpp.
 * Status: 0 success, -1 unavailable, -2 invalid input, -3 malformed count,
 * -4 insufficient destination, -5 null native text. No partial publication.
 * Text copies exclude the terminator; size is the copied byte length. */
#define SW_INPUT_MAX_CONTROLLERS 16
#define SW_INPUT_MAX_LAYERS 16
#define SW_INPUT_MAX_ORIGINS 8
#define SW_INPUT_MAX_ANALOG_ACTIONS 24
#define SW_INPUT_MAX_DIGITAL_ACTIONS 256
#define SW_INPUT_MAX_ORIGIN 32767
#define SW_INPUT_MAX_TYPE 255
struct sw_input_digital { bool state; bool active; };
struct sw_input_analog { int32_t mode; float x; float y; bool active; };
int32_t sw_input_start(bool notifications, bool *accepted);
int32_t sw_input_stop(bool *accepted);
int32_t sw_input_frame(void);
int32_t sw_input_manifest(const char *path, bool *accepted);
int32_t sw_input_controllers(uint64_t *out, size_t capacity, size_t *count);
/* kind: 0 action set, 1 digital, 2 analog */
int32_t sw_input_lookup(uint32_t kind, const char *name, uint64_t *out);
/* operation: 0 activate set, 1 activate layer, 2 deactivate layer, 3 deactivate all */
int32_t sw_input_activate(uint32_t operation, uint64_t controller, uint64_t set);
int32_t sw_input_current_set(uint64_t controller, uint64_t *out);
int32_t sw_input_layers(uint64_t controller, uint64_t *out, size_t capacity, size_t *count);
int32_t sw_input_digital_data(uint64_t controller, uint64_t action, struct sw_input_digital *out);
int32_t sw_input_analog_data(uint64_t controller, uint64_t action, struct sw_input_analog *out);
int32_t sw_input_origins(bool analog, uint64_t controller, uint64_t set, uint64_t action, int32_t *out, size_t capacity, size_t *count);
int32_t sw_input_type(uint64_t controller, int32_t *out);
int32_t sw_input_translate(int32_t type, int32_t origin, int32_t *out);
/* kind: 0 PNG, 1 SVG, 2 origin name, 3 digital name, 4 analog name */
int32_t sw_input_text(uint32_t kind, uint64_t action, int32_t origin, int32_t size, uint32_t style, char *out, size_t capacity, size_t *length);
int32_t sw_input_vibration(uint64_t controller, uint16_t left, uint16_t right);
int32_t sw_input_vibration_extended(uint64_t controller, uint16_t left, uint16_t right, uint16_t left_trigger, uint16_t right_trigger);
#ifdef __cplusplus
}
#endif
#endif
