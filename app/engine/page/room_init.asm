SECTION code_engine
INCLUDE "engine/engine_globals.inc"
INCLUDE "engine/gamemaker_register.inc"

PUBLIC room_init
PUBLIC _room_init
DEFC _room_init = room_init
;#[PROFILE_ROUTINE]
room_init:
    ; Cleanup the callback lists
    REPTI name, begin_step, step, end_step, draw, pre_draw, post_draw, draw_end, draw_gui
        scl_init name
    endr

    scl_init alarm

    ld hl, _gmctx + GamemakerCTX_old_history
    ld (_gmctx+GamemakerCTX_old_history), hl


    ; TODO: Does this need moved out?
    ld hl, object_render_queue
    ld (object_render_queue_tail), hl


    ld a, (room_init_done)
    or a
    jr nz, @is_initialized

    ; Init the instance heap allocator once per app run
    fheap_init_inline instances
    ld a, 1
    ld (room_init_done), a

@is_initialized:

    ld hl, fheap_addr(instances)
    fheap_foreach Instance_size
        inc hl \ inc hl
            bit 3, (hl) ; Is persistant
        dec hl \ dec hl
        jr nz, @setup

        ; Cleanup
            fheap_free instances
            jp @loop


        @setup:
            _register_instance
            jp @loop

    @end_of_loop:
        ret
