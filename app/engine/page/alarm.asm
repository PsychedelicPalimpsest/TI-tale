SECTION code_engine
INCLUDE "engine/engine_globals.inc"

; void set_alarm(uint16_t alarm_idx, int16_t value) __z88dk_callee
PUBLIC  _set_alarm
;#[PROFILE_ROUTINE]
_set_alarm:
    pop hl ; Return address
        pop bc ; value
        pop de ; alarm index
    push hl

    ; Alarm slots are 0..11. Reject invalid indices before seeking into
    ; the instance, including a null current instance.
    ld a, d
    or a
    ret nz
    ld a, e
    cp 12
    ret nc
    ld hl, (_gmctx + GamemakerCTX_instance)
    ld a, h \ or l
    ret z

    ; Current sprite instance
    push de
        ld de, Instance_alarms
        add hl, de
    pop de

    ; Seek to that current alarm
    add hl, de ; *2 for uint16_t
    add hl, de

    ld (hl), c \ inc hl
    ld (hl), b

    ; Negative numbers do not tick
    bit 7, b
    ret nz
        ld hl, (_gmctx + GamemakerCTX_instance) ; Current sprite instance
        scl_append alarm ; Handles for us alarms what are already set
    ret
