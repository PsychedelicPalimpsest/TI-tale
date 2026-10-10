#pragma once
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
                // Bit 2: Needs new RL
                // Bit 3: Is persistent
                // Bit 4: Is solid (tbd) 
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
    uint8_t sprite_index;    // An index into the sprite_cache_entries in obj
    Sprite displayed_sprite;
} Instance;


//#[ASM_EXPOSED]
typedef struct {
    Instance* instance;
    Instance* other;
    
    Instance** old_history; // A pointer WITHIN with_history

    
    Instance* with_history[8];
} GamemakerCTX;


extern GamemakerCTX gmctx;


extern Instance* instance_create_depth(int16_t depth, uint16_t x, uint16_t y, Object* obj) __z88dk_callee;

#define instance_create(x, y, obj) \
    instance_create_depth(gmctx.instance->depth, (x), (y), (obj))

#define BEGIN_WITH(obj) \
    *(gmctc.old_history++) = gmctx.instance; \
    gmctx.instance = obj;

#define END_WITH() \
    gmctx.instance = *(--gmctx.old_history)


#define set_x(__OBJ, __X) \
    __OBJ->x = __X; \
    __OBJ->displayed_sprite->x = __X;     

#define set_y(__OBJ, __Y) \
    __OBJ->y = __Y; \
    __OBJ->displayed_sprite->y = __Y;     
extern void set_depth(Instance* ins, int16_t depth) __z88dk_callee;


#ifdef ROOM
// This stuff is common setup done for each room. 

#ifndef ROOMID
#error Something went wrong, ROOMID is NOT defined
#endif

#define room_entry RM_entrypoint_##ROOMID


#endif


#ifdef OBJECT

#ifndef OBJECTID
#error Something went wrong, OBJECTID is NOT defined
#endif

// Regular events
#define object_create               OBJ_create_##OBJECTID
    #define object_create_inherited     OBJ_inherited_create_##OBJECTID
#define object_begin_step           OBJ_begin_step_##OBJECTID
    #define object_begin_step_inherited OBJ_inherited_begin_step_##OBJECTID
#define object_step                 OBJ_step_##OBJECTID
    #define object_step_inherited       OBJ_inherited_step_##OBJECTID
#define object_end_step             OBJ_end_step_##OBJECTID
    #define object_end_step_inherited   OBJ_inherited_end_step_##OBJECTID
#define object_draw                 OBJ_draw_##OBJECTID
    #define object_draw_inherited       OBJ_inherited_draw_##OBJECTID
#define object_pre_draw             OBJ_pre_draw_##OBJECTID
    #define object_pre_draw_inherited   OBJ_inherited_pre_draw_##OBJECTID
#define object_post_draw            OBJ_post_draw_##OBJECTID
    #define object_post_draw_inherited  OBJ_inherited_post_draw_##OBJECTID
#define object_draw_begin           OBJ_draw_begin_##OBJECTID
    #define object_draw_begin_inherited OBJ_inherited_draw_begin_##OBJECTID
#define object_draw_end             OBJ_draw_end_##OBJECTID
    #define object_draw_end_inherited   OBJ_inherited_draw_end_##OBJECTID
#define object_draw_gui             OBJ_draw_gui_##OBJECTID
    #define object_draw_gui_inherited   OBJ_inherited_draw_gui_##OBJECTID
    
// "User events"
#define object_user_0 OBJ_user_0_##OBJECTID
    #define object_user_0_inherited OBJ_inherited_user_0_##OBJECTID

#define object_user_1 OBJ_user_1_##OBJECTID
    #define object_user_1_inherited OBJ_inherited_user_1_##OBJECTID

#define object_user_2 OBJ_user_2_##OBJECTID
    #define object_user_2_inherited OBJ_inherited_user_2_##OBJECTID

#define object_user_3 OBJ_user_3_##OBJECTID
    #define object_user_3_inherited OBJ_inherited_user_3_##OBJECTID

#define object_user_4 OBJ_user_4_##OBJECTID
    #define object_user_4_inherited OBJ_inherited_user_4_##OBJECTID

#define object_user_5 OBJ_user_5_##OBJECTID
    #define object_user_5_inherited OBJ_inherited_user_5_##OBJECTID

#define object_user_6 OBJ_user_6_##OBJECTID
    #define object_user_6_inherited OBJ_inherited_user_6_##OBJECTID

#define object_user_7 OBJ_user_7_##OBJECTID
    #define object_user_7_inherited OBJ_inherited_user_7_##OBJECTID

#define object_user_8 OBJ_user_8_##OBJECTID
    #define object_user_8_inherited OBJ_inherited_user_8_##OBJECTID

#define object_user_9 OBJ_user_9_##OBJECTID
    #define object_user_9_inherited OBJ_inherited_user_9_##OBJECTID

#define object_user_10 OBJ_user_10_##OBJECTID
    #define object_user_10_inherited OBJ_inherited_user_10_##OBJECTID

#define object_user_11 OBJ_user_11_##OBJECTID
    #define object_user_11_inherited OBJ_inherited_user_11_##OBJECTID

#define object_user_12 OBJ_user_12_##OBJECTID
    #define object_user_12_inherited OBJ_inherited_user_12_##OBJECTID

#define object_user_13 OBJ_user_13_##OBJECTID
    #define object_user_13_inherited OBJ_inherited_user_13_##OBJECTID

#define object_user_14 OBJ_user_14_##OBJECTID
    #define object_user_14_inherited OBJ_inherited_user_14_##OBJECTID

#define object_user_15 OBJ_user_15_##OBJECTID
    #define object_user_15_inherited OBJ_inherited_user_15_##OBJECTID

// Alarm events
#define object_alarm_0 OBJ_alarm_0_##OBJECTID
    #define object_alarm_0_inherited OBJ_inherited_alarm_0_##OBJECTID

#define object_alarm_1 OBJ_alarm_1_##OBJECTID
    #define object_alarm_1_inherited OBJ_inherited_alarm_1_##OBJECTID

#define object_alarm_2 OBJ_alarm_2_##OBJECTID
    #define object_alarm_2_inherited OBJ_inherited_alarm_2_##OBJECTID

#define object_alarm_3 OBJ_alarm_3_##OBJECTID
    #define object_alarm_3_inherited OBJ_inherited_alarm_3_##OBJECTID

#define object_alarm_4 OBJ_alarm_4_##OBJECTID
    #define object_alarm_4_inherited OBJ_inherited_alarm_4_##OBJECTID

#define object_alarm_5 OBJ_alarm_5_##OBJECTID
    #define object_alarm_5_inherited OBJ_inherited_alarm_5_##OBJECTID

#define object_alarm_6 OBJ_alarm_6_##OBJECTID
    #define object_alarm_6_inherited OBJ_inherited_alarm_6_##OBJECTID

#define object_alarm_7 OBJ_alarm_7_##OBJECTID
    #define object_alarm_7_inherited OBJ_inherited_alarm_7_##OBJECTID

#define object_alarm_8 OBJ_alarm_8_##OBJECTID
    #define object_alarm_8_inherited OBJ_inherited_alarm_8_##OBJECTID

#define object_alarm_9 OBJ_alarm_9_##OBJECTID
    #define object_alarm_9_inherited OBJ_inherited_alarm_9_##OBJECTID

#define object_alarm_10 OBJ_alarm_10_##OBJECTID
    #define object_alarm_10_inherited OBJ_inherited_alarm_10_##OBJECTID

#define object_alarm_11 OBJ_alarm_11_##OBJECTID
    #define object_alarm_11_inherited OBJ_inherited_alarm_11_##OBJECTID


#endif
