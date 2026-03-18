#pragma once

#include <stdint.h>

/*
 * Symbols are defined in asm_globals.def and exported with PUBLIC.
 * They are fixed RAM addresses used by the app runtime.
 */

/* Current display buffers (pointers stored in RAM) */
extern uint8_t *working_light_buff;
extern uint8_t *working_dark_buff;

