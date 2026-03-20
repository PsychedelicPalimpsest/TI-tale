#pragma once

#include <stdint.h>

#define PACKED __attribute__((packed))

/*
 * Symbols are defined in asm_globals.def and exported with PUBLIC.
 * They are fixed RAM addresses used by the app runtime.
 */

/* Current display buffers (pointers stored in RAM) */

/* Backing buffer memory regions */
extern uint8_t working_light[768];
extern uint8_t working_dark[768];

/* Optional: first ROM page byte captured at startup */
extern uint8_t first_rom_page;
