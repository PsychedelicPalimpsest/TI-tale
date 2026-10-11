SECTION code_engine
INCLUDE "engine/engine_globals.inc"
EXTERN __change_render_queue

; void set_depth(Instance* ins, int16_t depth) __z88dk_callee;
PUBLIC _set_depth
_set_depth:
    pop bc ; Return address
    pop de ; New depth

    pop ix ; Instance
    push bc

    ld a, (ix+Instance_depth)
    cp e
    jr nz, @changed
    ld a, (ix+Instance_depth+1)
    cp d
    ret z
@changed:
    ld (ix+Instance_depth), de

    ; Neither a destroyed instance nor a pending insertion needs a queue
    ; change. One indexed read is cheaper than two indexed BIT tests.
    ld a, (ix+Instance_flags)
    and %01100000
    ret nz

    ld a, (draw_in_progress)
    or a
    jr z, @change_now
        set 7, (ix+Instance_flags)
        ld a, 1
        ld (render_queue_pending), a
        ret

@change_now:
    ld hl, (ix+Instance_queued_depth)
    ld (ix+Instance_queued_depth), de

    push ix
    pop bc
    jp __change_render_queue
