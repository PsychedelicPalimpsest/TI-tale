SECTION code_engine
INCLUDE "engine/engine_globals.inc"
INCLUDE "engine/gamemaker_register.inc"
EXTERN __insert_render_queue

; Allocate a new instance
; Output: hl = allocated object
_allocate_instance:
    ld hl, fheap_addr(instances)
    fheap_alloc Instance_size


; Arguments should be on the stack in the z88dk order,
; then the return values are put on the stack. On create is NOT called
; They are push in order:
; * Depth
; * Sprite
;
; _instance_create_unsafe_without_render(int16_t depth, uint16_t x, uint16_t y, Object* obj) __z88dk_callee;
MACRO _instance_create_unsafe_without_render
    call _allocate_instance

    pop bc ; obj

    ld (hl), c \ inc hl
    ld (hl), b \ inc hl

    ; TODO: Where do flags come from?
    ld (hl), 7 \ inc hl ; Active, visible, needs rl

    push hl ; Save ptr
        ld de, Instance_alarm_count-3
        add hl, de

        ; No active alarms
        ld (hl), 0 \ inc hl

        ; Set all alarms to -1 (disabled)
        REPT 12*2
            ld (hl), $FF \ inc hl
        endr

        ex de, hl ; hl = *object, de=Instance as sprite_index_max
        
        ld hl, Object_sprite_count
        add hl, bc
        
        ldi ; Copy sprite count to instance        

        ; Zero out sprite_index and last_sprite_index
        xor a
        ld (de), a \ inc de
        ld (de), a \ inc de

        ; Deref the first sprite
        ld a, (hl) \ inc hl
        ld h, (hl)
        ld l, a

        ; Copy the displayed sprite into place
        ; TODO: This is of known size, should it be optimized?
        ld bc, Sprite_size
        ldir
    pop hl  ; Restore ptr at depth
    

    pop bc ; y
    pop de ; x

    push hl ; Save *depth
    inc hl \ inc hl ; Skip depth
        ; X
        ld (hl), e \ inc hl
        ld (hl), d \ inc hl

        ; Y
        ld (hl), c \ inc hl
        ld (hl), b \ inc hl


        ; xprev
        ld (hl), e \ inc hl
        ld (hl), d \ inc hl

        ; yprev
        ld (hl), c \ inc hl
        ld (hl), b \ inc hl

        ; hspeed
        ld (hl), 0 \ inc hl 
        ld (hl), 0 \ inc hl 

        ; vspeed
        ld (hl), 0 \ inc hl 
        ld (hl), 0 \ inc hl 
    pop hl ; *depth
    pop de ; Depth

    ld (hl), e \ inc hl
    ld (hl), d 

        ; The ROM sprite template starts at (0,0). Match its copy to the
        ; instance coordinates before the first draw.
        push de                         ; Preserve depth for render queue insertion
        push hl                         ; instance + Instance_depth + 1
        inc hl                          ; source: instance x
        push hl
        ld de, Instance_displayed_sprite+Sprite_x_pos-Instance_x
        add hl, de
        ex de, hl                       ; destination: displayed sprite x
        pop hl
        ld bc, 2
        ldir
        inc de \ inc de \ inc de        ; destination: displayed sprite y
        ld bc, 2
        ldir
        pop hl
        pop de

    ; Get back to start
    REPT 4
        dec hl
    endr

    push de
    push hl
        _register_instance
endm

; Instance* instance_create_depth(int16_t depth, uint16_t x, uint16_t y, Object* obj) __z88dk_callee;
PUBLIC _instance_create_depth
;#[PROFILE_ROUTINE]
_instance_create_depth:
    pop de ; Return ptr
    exx
        _instance_create_unsafe_without_render
    exx

    pop bc ; Sprite
    pop hl ; Depth

    push de ; Return ptr

    push bc
        call __insert_render_queue
    pop hl \ push hl ; Instance*

    ld de, (_gmctx + GamemakerCTX_instance)
    ld (_gmctx + GamemakerCTX_instance), hl
    push de
        ; hl = Object*
        ld a, (hl) \ inc hl
        ld h, (hl)
        ld l, a

        ld de, Object_create
        add hl, de

        ld a, (hl) \ inc hl
        ld h, (hl)
        ld l, a

        EXTERN __hl

        or h
        call nz, __hl
    pop hl ; Old current instance
    ld (_gmctx + GamemakerCTX_instance), hl

    pop hl ; Instance*
    

    ret
