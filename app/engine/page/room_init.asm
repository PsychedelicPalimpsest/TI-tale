SECTION code_engine
INCLUDE "engine/engine_globals.inc"
INCLUDE "engine/gamemaker_register.inc"

PUBLIC room_init
PUBLIC _room_init
DEFC _room_init = room_init
;#[PROFILE_ROUTINE]
room_init:
    ld hl, 0
    ld (_gmctx + GamemakerCTX_instance), hl
    ld (_gmctx + GamemakerCTX_other), hl
    xor a
    ld (draw_in_progress), a
    ld (instances_pending_destroy), a
    ld (render_queue_pending), a
    ; A new room needs a fresh background even when its camera position matches.
    ld hl, $ffff
    ld (cur_camprevx), hl
    ld (cur_camprevy), hl

    ; Cleanup the callback lists
    REPTI name, begin_step, step, end_step, draw, pre_draw, post_draw, draw_begin, draw_end, draw_gui
        scl_init name
    endr

    scl_init alarm

    ld hl, _gmctx + GamemakerCTX_old_history
    ld (_gmctx+GamemakerCTX_old_history), hl


    ; TODO: Does this need moved out?
    ld hl, object_render_queue
    ld (object_render_queue_tail), hl

    ld hl, tile_render_queue
    ld (tile_render_queue_tail), hl

    ld hl, gui_render_queue
    ld (gui_render_queue_tail), hl


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
        inc hl ; Skip heap metadata before accessing Instance fields
        inc hl \ inc hl
            bit 3, (hl) ; Is persistant
        dec hl \ dec hl
        jr nz, @setup

        ; Cleanup
            ex de, hl
            fheap_free instances
            jp @loop


        @setup:
            push hl \ pop ix
            _register_instance
            ; The callback lists and render queue were reset above. Restore
            ; both for instances carried into this room.
            ld (ix+Instance__alarms), 0
            ld (ix+Instance__alarms+1), 0
            push ix \ pop de
            ld hl, Instance_alarms+1
            add hl, de
            ld b, 12
        @alarm_scan:
            bit 7, (hl)
            jr z, @has_alarm
            inc hl \ inc hl
            djnz @alarm_scan
            jr @no_alarm
        @has_alarm:
            push ix \ pop hl
            scl_append alarm
        @no_alarm:
            ld l, (ix+Instance_depth)
            ld h, (ix+Instance_depth+1)
            ld (ix+Instance_queued_depth), l
            ld (ix+Instance_queued_depth+1), h
            push ix \ pop bc
            EXTERN __insert_render_queue
            call __insert_render_queue
            jp @loop

    @end_of_loop:
        ret
