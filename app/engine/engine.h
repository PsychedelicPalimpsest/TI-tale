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

    Renderlist_Entry* rl_entry; // Might be null
    void* rotation_entries[8];
    
    char sprite_data[]; // Only exists for the sprite cache entries, not
} Sprite;               // sprites attached to instances




//#[ASM_EXPOSED]
typedef struct {
    void* begin_step;
    void* step;
    void* end_step;

    void* draw;
    void* pre_draw;
    void* post_draw;
    void* draw_begin;
    void* draw_end;
    void* draw_gui;
    void* draw_gui_begin;
    void* draw_gui_end;

    
    Sprite* sprite_cache_entries[16];

    void* user_events[16];
    void* alarm_callbacks[12];
} Object;


//#[ASM_EXPOSED]
typedef struct {
    Object*  obj;
    uint8_t flags;
                // Bit 0: Is Active (Does it step?)
                // Bit 1: Is visible
                // Bit 2: Is persistent
                // Bit 3: Is solid (tbd) 

    uint8_t sprite_index_max;
    uint8_t sprite_index;    // An index into the sprite_cache_entries in obj
    
    uint16_t x, y;
    uint16_t xprev, yprev;
    uint16_t hspeed, vspeed;

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
    void* _draw_gui_begin;
    void* _draw_gui_end;

    void* _alarms;
    

    

    uint8_t  alarm_count;
    int16_t alarms[12];

    Sprite displayed_sprite;
} Instance;


//#[ASM_EXPOSED]
typedef struct {
    Instance* instance;
    Instance* other;
} GamemakerCTX;


extern GamemakerCTX gmctx;



#ifdef ROOM
// This stuff is common setup done for each room. 

#ifndef ROOMID
#error Something went wrong, ROOMID is NOT defined
#endif

#define room_entry RM_entrypoint_##ROOMID


#endif
