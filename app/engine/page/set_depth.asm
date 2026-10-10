SECTION code_engine
INCLUDE "engine/engine_globals.inc"
EXTERN __change_render_queue

; void set_depth(Instance* ins, int16_t depth) __z88dk_callee;
PUBLIC _set_depth
_set_depth:
    pop de ; New depth

    pop ix ; Instance

    ld hl, (ix+Instance_depth)
    ld (ix+Instance_depth), de

    push ix
    pop bc
    jp __change_render_queue
