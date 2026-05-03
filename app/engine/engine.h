#include <stdbool.h>

enum event_t{
  ev_create,
  ev_destroy,
  ev_cleanup,

  ev_step, ev_step_normal, ev_step_begin, ev_step_end,
};




typedef struct {
} Object;

typedef struct {
} Instance;




#ifdef ROOM
// This stuff is common setup done for each room. 

#ifndef ROOMID
#error Something went wrong, ROOMID is NOT defined
#endif

#define room_entry RM_entrypoint_##ROOMID


#endif
