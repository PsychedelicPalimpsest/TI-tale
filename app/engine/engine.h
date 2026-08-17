#include <stdbool.h>
#include <stdint.h>


enum event_t{
  ev_create,
  ev_destroy,
  ev_cleanup,

  ev_step, ev_step_normal, ev_step_begin, ev_step_end,
};

// NOTE: DO NOT CHANGE THESE STRUCTS ORDER, THEY THE OFFSETS ARE USED IN ASM



//#[ASM_EXPOSED]
typedef struct {
    void* begin_step;
    void* step;
    void* end_step;
    void* draw;
    void* render;

    


    void* user_events[16];
    void* alarm_callbacks[12];
} Object;


//#[ASM_EXPOSED]
typedef struct {
    Object*  obj;

    // These are the 'back points' used for callback book
    // keeping, NEVER touch these yourself! Only init to null
    void* _begin_step;
    void* _step;
    void* _end_step;
    void* _draw;
    void* _render;


    

    uint8_t  alarm_count;
    int16_t alarms[12];

} Instance;


//#[ASM_EXPOSED]
typedef struct {
    Instance* instance;
    Instance* other;
} GamemakerCTX;;

extern GamemakerCTX gmctx;


#ifdef ROOM
// This stuff is common setup done for each room. 

#ifndef ROOMID
#error Something went wrong, ROOMID is NOT defined
#endif

#define room_entry RM_entrypoint_##ROOMID


#endif
