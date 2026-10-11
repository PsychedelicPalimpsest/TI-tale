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
    ld (hl), 3 \ inc hl ; Active and visible

    inc hl \ inc hl ; Skip depth

    pop bc ; y
    pop de ; x

    ld (hl), e \ inc hl
    ld (hl), d \ inc hl

    ld (hl), c \ inc hl
    ld (hl), b

    dec hl \ dec hl \ dec hl

    pop de ; Depth

    ld (hl), d \ dec hl
    ld (hl), e \ dec hl

    ; Get back to start
    dec hl \ dec hl \ dec hl

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
