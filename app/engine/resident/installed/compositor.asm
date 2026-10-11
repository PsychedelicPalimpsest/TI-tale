INCLUDE "engine/engine_globals.inc"

PUBLIC frame_pending
DEFC frame_pending = compositor_loop+1

EXTERN yield, yield_raw

; When this happens, it is best to assume a frame will be dropped
;#[PROFILE_START render_background]
render_background:
    EXTERN calculate_rl_screen

    ld hl, (cur_camx)
    ld (cur_camprevx), hl
    ld hl, (cur_camy)
    ld (cur_camprevy), hl

    ; Everything is likely fucked
    ld hl, -1
    ld (dirty_cols), hl

    ; TODO: Can we expand the screen size, and then simply move
    ;       the background instead of a complete redraw?

    ; Fill the background
    ld hl, layer_background + 768*2
    ld de, (bg_fill_color)
    call scrset


    ld hl, layer_background
    ld (render_sprite_screen), hl

    ld bc, (tile_render_queue_tail)
    ld hl, tile_render_queue


    @loop:
        CpHLBC
        jr z, @end_of_loop

        inc hl \ inc hl ; We don't care about the depth

        ld e, (hl) \ inc hl
        ld d, (hl) \ inc hl

        push hl
        push bc
            ex de, hl
            call render_sprite
        pop bc
        pop hl
        jp @loop

;#[PROFILE_STOP render_background]
@end_of_loop:
    ;  Backgrounds can take a LONG time, so lets give the main loop a chance
    ;  to fire (but only if that much time has passed)

    call yield_raw ; We don't have any registers we care about, trash them!

    jp compositor_loop@rejoin



PUBLIC compositor_loop
compositor_loop:
    ld a, 0
    rra
    jp nc, @yield_and_loop

;#[PROFILE_START compose]
@compose_start:
    xor a
    ld (frame_pending), a

    ; We only re-render the background if the camera moves
    ld hl, (cur_camx)
    ld de, (cur_camprevx)
    CpHLDE
    jr nz, render_background

    ld hl, (cur_camy)
    ld de, (cur_camprevy)
    CpHLDE
    jr nz, render_background

;#[PROFILE_START compose_core]
@rejoin:
    ld iy, layer_background ; Src
    ld ix, layer_foreground   ; Dst
    call scrcpy


    EXTERN calculate_rl_screen

    ; Set the current display layer to the foreground
    ld hl, layer_foreground
    ld (calculate_rl_screen), hl

    
    ; Note: This is after the background to save a bit of time (move the big stuff down to use jr)
    ;       since tiles can have not callbacks, this is valid
    ld a, 1
    ld (draw_in_progress), a
    for_each_and_call pre_draw, Object_pre_draw, 3 ; Does NOT need any order

    MACRO _event_until_tail tail_ptr, head, event, do_self
        LOCAL @loop, @no_draw_event, @skip_entry, @end_of_loop

        ld bc, (tail_ptr)
        ld hl, head
        @loop:
            CpHLBC
            jr z, @end_of_loop
            inc hl \ inc hl ; Skip depth
            ld e, (hl) \ inc hl
            ld d, (hl) \ inc hl

            push hl
            push bc
                ex de, hl
                push hl
                ld de, Instance_flags
                add hl, de
                ld a, (hl)
                and %00100011 ; Active, visible, and not pending destruction
                cp 3
                pop hl
                jr nz, @skip_entry
                ld (_gmctx + GamemakerCTX_instance), hl ; Set the context for the callback
                ld e, (hl) \ inc hl
                ld d, (hl)


                ld hl, event
                add hl, de

                ld e, (hl) \ inc hl
                ld d, (hl)

                ld a, d
                or e
                jr z, @no_draw_event

                ex de, hl
                call __hl
            pop bc
            pop hl
            jp @loop

    @no_draw_event:
        IF 1=do_self
            EXTERN _draw_self
            call _draw_self ; Handles sprite blitting
        endif
    @skip_entry:
        pop bc
        pop hl
        jp @loop

@end_of_loop:
    ENDM

    _event_until_tail object_render_queue_tail, object_render_queue, Object_draw_begin, 0
    _event_until_tail object_render_queue_tail, object_render_queue, Object_draw, 1
    _event_until_tail object_render_queue_tail, object_render_queue, Object_draw_end, 0


    for_each_and_call post_draw, Object_post_draw, 3 ; Does NOT need any order


    _event_until_tail gui_render_queue_tail, gui_render_queue, Object_draw_gui, 0

    ; Draw callbacks can request destruction. Remove those instances only
    ; after all draw queues have finished iterating.
    xor a
    ld (draw_in_progress), a
    call instance_sweep
    call instance_flush_render_queue

    ; Full column conversion keeps the previous sprite footprint clean while
    ; the position-based dirty region API is still being developed.
    ld hl, $ffff
    ld (dirty_cols), hl
    call _greyscale_swap



;#[PROFILE_STOP compose_core]
;#[PROFILE_STOP compose]
@yield_and_loop:
    call yield_raw ; No registers betweem loops
    jp compositor_loop
