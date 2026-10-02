#ifndef ARM_RETRO_HOST_H
#define ARM_RETRO_HOST_H
#include <stdint.h>
#include <stddef.h>
int arm_query_options(const char *core);
unsigned arm_option_count(void);
const char *arm_option_key(unsigned index);
const char *arm_option_definition(unsigned index);
int arm_inspect(const char *core);
int arm_load(const char *core, const char *game, const char *system, const char *saves, const char *options);
void arm_run(void);
void arm_reset(void);
void arm_stop(void);
const char *arm_error(void);
const char *arm_core_name(void);
double arm_fps(void);
double arm_aspect_ratio(void);
double arm_sample_rate(void);
const uint32_t *arm_pixels(void);
unsigned arm_width(void);
unsigned arm_height(void);
uint64_t arm_frames(void);
void arm_analog(unsigned port, unsigned stick, unsigned axis, int16_t value);
void arm_pointer(int16_t x, int16_t y, int pressed);
void arm_input(unsigned port, unsigned button, int16_t value);
size_t arm_audio(float *out, size_t frames);
int arm_state(const char *path, int save);
int arm_sram(const char *path, int save);
#endif
