#include <stdbool.h>
#include <stdint.h>

enum event_t{
  ev_create,
  ev_destroy,
  ev_cleanup,

  ev_step, ev_step_normal, ev_step_begin, ev_step_end,
};




typedef struct {

    
    void* user_events[16];
    void* alarm_callbacks[12];
} Object;

typedef struct {
    Object*  obj;
    
    uint8_t  alarm_count;
    int16_t alarms[12];
} Instance;







#ifdef ROOM
// This stuff is common setup done for each room. 

#ifndef ROOMID
#error Something went wrong, ROOMID is NOT defined
#endif

#define room_entry RM_entrypoint_##ROOMID


#endif
