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

    ld hl, (ix+Instance_queued_depth)
    ld (ix+Instance_depth), de

    bit 5, (ix+Instance_flags)
    ret nz ; Destruction will remove the old queue entry
    bit 6, (ix+Instance_flags)
    ret nz ; The pending insertion will use the new depth

    ld a, (draw_in_progress)
    or a
    jr z, @change_now
        set 7, (ix+Instance_flags)
        ret

@change_now:
    ld (ix+Instance_queued_depth), de

    push ix
    pop bc
    jp __change_render_queue
