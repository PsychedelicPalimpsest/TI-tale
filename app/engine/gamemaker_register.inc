; de - Object callback ptr +1
; hl - back ptr +1
macro _maybe_register _name
    LOCAL @next
    ld a, (de)
    inc de \ inc de ; Move until next

    ; or a ; Test the high byte of the callback
    jp z, @next ; Highly unlikely to fall through
        push de
        push hl
            scl_append_from_scloff _name
        pop hl
        pop de
    @next:
        inc hl \ inc hl
endm

MACRO _register_instance
    ex de, hl
        ld hl, Instance__begin_step
        add hl, de

        ; Zero out the callback back ptrs
        ; TODO: Optimize
        REPT Instance__alarms-Instance__begin_step
            ld (hl), 0 \ inc hl
        endr
    ex de, hl
    ; Get the object ptr
    ld e, (hl) \ inc hl
    ld d, (hl)
    inc de

    ld bc, Instance__begin_step-1+1
    add hl, bc

    REPTI _name, begin_step, step, end_step, draw, pre_draw, post_draw, draw_end, draw_gui
        _maybe_register _name
    endr
endm
