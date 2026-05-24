#include <stdbool.h>
#include <stdint.h>

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


typedef struct {
    void*   rot_cache; // Location in the sprite cache table
    uint8_t width; // Pixel width
    uint8_t height;
    
    void* tileset;
    uint8_t tileset_width;
    uint8_t tileset_height;
} Tile;


typedef struct {
    void* rot_cache;
    void* data;

    // Flags:
    // bit 0: Do rot cache
    // ...todo
    uint8_t flags;
    uint8_t width;
    uint8_t height;
} Sprite;




#ifdef ROOM
// This stuff is common setup done for each room. 

#ifndef ROOMID
#error Something went wrong, ROOMID is NOT defined
#endif

#define room_entry RM_entrypoint_##ROOMID


#endif
