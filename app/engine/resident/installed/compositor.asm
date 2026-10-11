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

    call invalidate_all_renderlists

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
        ; The low-byte mismatch is the common case. This costs 20 T-states
        ; per entry instead of 37 for CpHLBC plus the branch.
        ld a, l
        cp c
        jr nz, @tile_entry
        ld a, h
        cp b
        jr z, @end_of_loop
    @tile_entry:

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

    


    MACRO _event_until_tail tail_ptr, head, event, do_self
        LOCAL @loop, @queue_entry, @no_draw_event, @skip_entry, @end_of_loop

        ld bc, (tail_ptr)
        ld hl, head
        @loop:
            ld a, l
            cp c
            jr nz, @queue_entry
            ld a, h
            cp b
            jr z, @end_of_loop
        @queue_entry:
            inc hl \ inc hl ; Skip depth
            ld e, (hl) \ inc hl
            ld d, (hl) \ inc hl

            push hl
            push bc
                ex de, hl
                inc hl \ inc hl
                ld a, (hl)
                dec hl \ dec hl
                and %00100011 ; Active, visible, and not pending destruction
                cp 3
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



;#[PROFILE_START compose_pre_draw]
@__1:
    ; Note: This is after the background to save a bit of time (move the big stuff down to use jr)
    ;       since tiles can have not callbacks, this is valid
    ld a, 1
    ld (draw_in_progress), a
    for_each_and_call pre_draw, Object_pre_draw, 3 ; Does NOT need any order

;#[PROFILE_START compose_draw_begin]
;#[PROFILE_STOP compose_pre_draw]
@__2:
    _event_until_tail object_render_queue_tail, object_render_queue, Object_draw_begin, 0

;#[PROFILE_START compose_draw]
;#[PROFILE_STOP compose_draw_begin]
@__3:

    _event_until_tail object_render_queue_tail, object_render_queue, Object_draw, 1

;#[PROFILE_START compose_draw_end]
;#[PROFILE_STOP compose_draw]
@__4:
    _event_until_tail object_render_queue_tail, object_render_queue, Object_draw_end, 0


;#[PROFILE_START compose_post_draw]
;#[PROFILE_STOP compose_draw_end]
@__5:
    for_each_and_call post_draw, Object_post_draw, 3 ; Does NOT need any order

;#[PROFILE_START compose_draw_gui]
;#[PROFILE_STOP compose_post_draw]
@__6:
    _event_until_tail gui_render_queue_tail, gui_render_queue, Object_draw_gui, 0


;#[PROFILE_STOP compose_draw_gui]
@__7:


    ; Draw callbacks can request destruction. Queue changes wait until all
    ; draw callbacks have finished iterating.
    xor a
    ld (draw_in_progress), a

    call _greyscale_swap

    ; Run deferred changes after the swap. Any invalidation they request now
    ; belongs to the next composed frame.
    ld a, (instances_pending_destroy)
    or a
    call nz, instance_sweep
    ld a, (render_queue_pending)
    or a
    call nz, instance_flush_render_queue

;#[PROFILE_STOP compose_core]
;#[PROFILE_STOP compose]
@yield_and_loop:
    call yield_raw ; No registers betweem loops
    jp compositor_loop

; The camera position is part of every cached render-list entry. Include
; invisible and disabled sprites so a later draw cannot use an old location.
invalidate_all_renderlists:
    ld a, (room_init_done)
    or a
    ret z
    ld hl, fheap_addr(instances)
    fheap_foreach Instance_size
        inc hl \ inc hl \ inc hl
        set 2, (hl)
        jp @loop
    @end_of_loop:
        ret
