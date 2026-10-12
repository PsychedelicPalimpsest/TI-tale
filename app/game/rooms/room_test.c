#include "engine/engine.h"
void room_entry(void);
#include "game/rooms/room_test.h"

// TODO: Generated object header will declare `extern Object obj_test;`
// Declaring it here allows room creation code to instantiate it dynamically.
extern Object obj_test;

// TODO: Expose room navigation and management helpers in engine.h:
// extern void room_goto(uint16_t room_id);
// extern void room_restart(void);

// TODO: Expose camera and background configuration helpers:
// extern void camera_set_pos(int16_t x, int16_t y);
// extern void background_set_color(uint16_t color);

/*
 * Room Creation Code: Executed when entering room_test.
 * Matches GameMaker's per-room creation code.
 */
void room_entry(void) {
    // 1. Initial instances placed in room_test.json (e.g. obj_test at 40, 24)
    // are spawned automatically by the engine runtime during room transition.

    // 2. Demonstration of dynamic instance creation inside room creation code:
    // TODO: Verify instance_create_depth works when called dynamically from C:
    // Instance* inst = instance_create_depth(0, 16, 16, &obj_test);

    // 3. Room-specific camera / background setup:
    // TODO: Connect camera reset to room origin:
    // cur_camx = 0;
    // cur_camy = 0;

    // Start the looping background track from page 0, where its bytecode lives.
    #asm
        EXTERN song_raining_somewhere_else
        EXTERN set_song
        di
        ld hl, song_raining_somewhere_else
        call set_song
        ei
    #endasm
}
