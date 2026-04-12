#pragma once

#include <stdint.h>

#define PACKED __attribute__((packed))

/*
 * Symbols are defined in asm_globals.def and exported with PUBLIC.
 * They are fixed RAM addresses used by the app runtime.
 */

/* Current display buffer */

/* Backing buffer memory regions */
extern uint8_t screen_buffer[768*2];

/* Optional: first ROM page byte captured at startup */
extern uint8_t first_rom_page;

#asm

  ; EVIL EVIL HACK
INCLUDE "core/common.inc"

#endasm
