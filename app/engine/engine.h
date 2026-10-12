#ifndef ENGINE_H
#define ENGINE_H

#include <stdbool.h>
#include <stdint.h>


// DO NOT EDIT: SEE sprite_system.asm! This is only a
// reference, the assembly files can not function with
// any other format!
//#[ASM_EXPOSED]
typedef struct {
    uint8_t flags;  // Bit 0: 1 = blit entry, 0 = skip
    uint8_t vert_trunc;
    uint8_t vis_width;
    uint8_t full_height;

    void*   sprite_data_ptr;
    void*   screen_location;
} Renderlist_Entry;

// DO NOT EDIT: SEE sprite_system.asm! This is only a
// reference, the assembly files can not function with
// any other format!
//#[ASM_EXPOSED]
typedef struct {
    uint8_t flags; // Bit 0: 1 = blit entry, 0 = skip

    int16_t x_pos;

    uint8_t width_cols;
    uint16_t width_px;


    int16_t y_pos;
    uint8_t height_px;

    Renderlist_Entry rl_entry; // Might be null
    void* rotation_entries[8];
    
    char sprite_data[]; // Only exists for the sprite cache entries, not
} Sprite;               // sprites attached to instances




//#[ASM_EXPOSED]
typedef struct {
    // Keep these first
    void* begin_step;
    void* step;
    void* end_step;

    void* draw;
    void* pre_draw;
    void* post_draw;
    void* draw_begin;
    void* draw_end;
    void* draw_gui;
    void* create;

    uint8_t sprite_count;
    Sprite* sprites[16];

    void* user_events[16];
    void* alarm_callbacks[12];

    void* destroy;
    void* clean_up;
    uint8_t initial_flags;
} Object;


// DO NOT MODIFY, asm needs order
//#[ASM_EXPOSED]
typedef struct {
    Object*  obj;
    uint8_t flags;
                // Bit 0: Is Active (Does it step?)
                // Bit 1: Is visible
                // Bit 2: Needs new RL
                // Bit 3: Is persistent
                // Bit 4: Is solid (tbd) 
                // Bit 5: Pending destruction
                // Bit 6: Awaiting render-queue insertion
                // Bit 7: Awaiting render-queue depth update
    uint16_t depth;
    
    int16_t x, y;
    int16_t xprev, yprev;

    int16_t hspeed, vspeed;

    // These are the 'back pointers' used for callback book
    // keeping, NEVER touch these yourself! Only init to null
    void* _begin_step;
    void* _step;
    void* _end_step;

    void* _draw;
    void* _pre_draw;
    void* _post_draw;
    void* _draw_begin;
    void* _draw_end;
    void* _draw_gui;

    void* _alarms;
    

    

    uint8_t  alarm_count;
    int16_t alarms[12];

    uint8_t sprite_index_max;
    uint8_t sprite_index;    // Frame in obj->sprites; applied by draw_self
    uint8_t last_sprite_index; // Frame currently copied into displayed_sprite
    Sprite displayed_sprite;
    uint16_t id; // Stable until destruction; zero is never assigned
    int16_t queued_depth; // Depth currently stored in the render queue
} Instance;


// The high byte contains the page,
// the low byte is the room number
typedef uint16_t Room;

//#[ASM_EXPOSED]
typedef struct {
    void* create;
    uint16_t width, height;
    uint16_t bg_fill_color; // What the background is filled to

    Room prev, next;
} RoomObj;




//#[ASM_EXPOSED]
typedef struct {
    Instance* instance;
    Instance* other;

    Room current_room;
    RoomObj* current_room_obj;

    
    Instance** old_history; // A pointer WITHIN with_history

    
    Instance* with_history[8];
} GamemakerCTX;


extern GamemakerCTX gmctx;


extern void return_to_loop();

// These DO NOT RETURN if the room you are going to is valid.
// But they do return if invalid, such as of no next or prev room
// exists. (Not the same behavior as gamemaker)
extern void room_goto(Room room) __z88dk_fastcall;
extern void room_goto_next(void);
extern void room_goto_prev(void);

extern Instance* instance_create_depth(int16_t depth, uint16_t x, uint16_t y, Object* obj) __z88dk_callee;
extern Instance* instance_find_id(uint16_t id) __z88dk_fastcall;
extern void instance_destroy(uint16_t id) __z88dk_fastcall;
extern void event_perform_user(uint8_t index) __z88dk_fastcall;
extern void set_alarm(uint16_t alarm_idx, int16_t value) __z88dk_callee;



#define instance_create(x, y, obj) \
    instance_create_depth(gmctx.instance ? gmctx.instance->depth : 0, (x), (y), (obj))

#define BEGIN_WITH(obj) \
    *(gmctc.old_history++) = gmctx.instance; \
    gmctx.instance = obj;

#define END_WITH() \
    gmctx.instance = *(--gmctx.old_history)

#define set_x(__OBJ, __X) do { \
    Instance* _set_x_instance = (__OBJ); \
    int16_t _set_x_value = (__X); \
    if (_set_x_instance->x != _set_x_value) { \
        _set_x_instance->x = _set_x_instance->displayed_sprite.x_pos = _set_x_value; \
        _set_x_instance->flags |= 0x04; \
    } \
} while (0)
#define set_y(__OBJ, __Y) do { \
    Instance* _set_y_instance = (__OBJ); \
    int16_t _set_y_value = (__Y); \
    if (_set_y_instance->y != _set_y_value) { \
        _set_y_instance->y = _set_y_instance->displayed_sprite.y_pos = _set_y_value; \
        _set_y_instance->flags |= 0x04; \
    } \
} while (0)


extern void set_depth(Instance* ins, int16_t depth) __z88dk_callee;

extern void draw_self(void);



#ifdef OBJECT
#define self (gmctx.instance)
#endif




#endif
