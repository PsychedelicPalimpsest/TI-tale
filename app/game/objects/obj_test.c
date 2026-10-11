#define OBJECT
#define OBJECTID obj_test

#include "engine/engine.h"
#include <string.h>
#include "game/sprites/spr_test.h"
#include "game/objects/obj_test.h"

// TODO: Move this ergonomic alias into engine/engine.h
#ifndef self
#define self (gmctx.instance)
#endif

// TODO: Expose keyboard / input scan helpers in engine/input.h
// Port 1 Group 7 keys (active low: 0 = pressed, 1 = released)
extern uint8_t current_keymap[8];
#define KEY_GROUP_ARROWS 7
#define KEY_MASK_DOWN    (1 << 0)
#define KEY_MASK_LEFT    (1 << 1)
#define KEY_MASK_RIGHT   (1 << 2)
#define KEY_MASK_UP      (1 << 3)

#define keyboard_check_arrow(mask) (!(current_keymap[KEY_GROUP_ARROWS] & (mask)))

// TODO: Add proper GML naming alias set_alarm(idx, val) in engine.h
extern void inst_update_alarms(uint16_t alarm_idx, int16_t value) __z88dk_callee;
#define set_alarm(idx, val) inst_update_alarms((idx), (val))

// TODO: Add draw_self() alias in engine.h
extern void draw_self(void);


/*
 * Create Event: Executed once when this instance is spawned.
 */
void object_create(void) {
    // Movement velocity
    self->hspeed = 0;
    self->vspeed = 0;

    // Start with frame 0 of spr_test
    self->sprite_index = 0;

    // Set alarm 0 to tick down from 30 steps (~1 second at 30fps)
    // to toggle animation or state
    set_alarm(0, 30);

    // TODO: Verify instance_create properly flags Needs New RL (bit 2) and Visible (bit 1)
    self->flags |= 0x06; // bit 1: visible, bit 2: needs RL
}


/*
 * Step Event: Executed every frame (~30Hz) during gml_step.
 */
void object_step(void) {
    // 1. Interactive D-pad movement controls
    int16_t dx = 0;
    int16_t dy = 0;

    if (keyboard_check_arrow(KEY_MASK_LEFT)) {
        dx -= 1;
    }
    if (keyboard_check_arrow(KEY_MASK_RIGHT)) {
        dx += 1;
    }
    if (keyboard_check_arrow(KEY_MASK_UP)) {
        dy -= 1;
    }
    if (keyboard_check_arrow(KEY_MASK_DOWN)) {
        dy += 1;
    }

    // Update position via engine macros
    if (dx != 0 || dy != 0) {
        set_x(self, self->x + dx);
        set_y(self, self->y + dy);
    }

    // Keep within 96x64 screen boundaries (16x16 sprite)
    if (self->x < 0) {
        set_x(self, 0);
        self->hspeed = -self->hspeed;
    } else if (self->x > (96 - 16)) {
        set_x(self, 96 - 16);
        self->hspeed = -self->hspeed;
    }

    if (self->y < 0) {
        set_y(self, 0);
        self->vspeed = -self->vspeed;
    } else if (self->y > (64 - 16)) {
        set_y(self, 64 - 16);
        self->vspeed = -self->vspeed;
    }

    // TODO: Add instance_destroy(self->id) demonstration when off-screen or on specific key
    // if (keyboard_check_arrow(KEY_MASK_CLEAR)) {
    //     instance_destroy(self);
    // }
}


/*
 * Alarm 0 Event: Periodically triggered when alarm[0] reaches 0.
 */
void object_alarm0(void) {
    // Toggle between frame 0 and frame 1 (winking animation)
    self->sprite_index ^= 1;

    if (self->sprite_index < self->sprite_index_max) {
        memcpy(&self->displayed_sprite,
               self->obj->sprites[self->sprite_index], sizeof(Sprite));
        self->displayed_sprite.x_pos = self->x;
        self->displayed_sprite.y_pos = self->y;
        self->last_sprite_index = self->sprite_index;
    }
    self->flags |= 0x04; // Mark dirty: needs new RL calculation

    // Re-arm alarm 0 for another 30 steps
    set_alarm(0, 30);
}


/*
 * Draw Event: Executed during composition to render the instance.
 */
void object_draw(void) {
    // Standard GameMaker draw_self()
    // In GM, if no Draw event is provided, draw_self() is called automatically.
    // If a custom Draw event is provided, draw_self() must be called explicitly.
    draw_self();

    // TODO: Add support for custom drawing primitives, e.g.:
    // draw_rectangle(self->x, self->y, self->x + 16, self->y + 16, COLOR_BLACK);
    // draw_text(0, 0, "TEST");
}
