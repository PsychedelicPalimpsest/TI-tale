SECTION code_engine
INCLUDE "engine/engine_globals.inc"

; void event_perform_user(uint8_t index) __z88dk_fastcall;
PUBLIC _event_perform_user
_event_perform_user:
    ld a, l
    cp 16
    ret nc
    ld c, l

    ld hl, (_gmctx + GamemakerCTX_instance)
    ld a, h \ or l
    ret z
    push hl

    ld e, (hl) \ inc hl
    ld d, (hl)
    ex de, hl
    ld de, Object_user_events
    add hl, de

    ; The event table contains two-byte callback pointers.
    ld a, c
    add a, a
    ld c, a
    ld b, 0
    add hl, bc
    ld e, (hl) \ inc hl
    ld d, (hl)
    ld a, d \ or e
    jr z, @no_callback
        ex de, hl
        EXTERN __hl
        call __hl
@no_callback:
    pop hl
    ld (_gmctx + GamemakerCTX_instance), hl
    ret
