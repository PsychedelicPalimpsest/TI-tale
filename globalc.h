#pragma once

#include <stdint.h>

/*
 * Symbols are defined in asm_globals.def and exported with PUBLIC.
 * They are fixed RAM addresses used by the app runtime.
 */

/* Current display buffers (pointers stored in RAM) */
extern uint8_t *current_light_buff;
extern uint8_t *current_dark_buff;

/* Aux/write buffers (pointers stored in RAM) */
extern uint8_t *aux_light_buff;
extern uint8_t *aux_dark_buff;

/* Backing buffer memory regions */
extern uint8_t light_buff_1[768];
extern uint8_t grey_buff_1[768];
extern uint8_t light_buff_2[768];
extern uint8_t grey_buff_2[768];

/* Optional: first ROM page byte captured at startup */
extern uint8_t first_rom_page;
