INCLUDE "core/includes/utils.inc"

; Each tree element has two element:
; 1. A 16-bit SIGNED key
; 2. A ptr (we do nothing with it)
MACRO bh_def arena, name, reservation
    DEFC bh_reservation_##name = reservation

    RDEF arena, bh_tail_##name, 2
    RDEF arena, bh_base_##name, reservation*4
endm

MACRO bh_init name
    ld hl, bh_base_##name
    ld (bh_tail_##name), hl
endm


MACRO _swap_hl_de
    REPT 4
        ld a,(de)
        ldi
        dec hl
        ld (hl),a
        inc hl
    endr
endm


; MUST GO IN RAM
; Inputs:
; hl = A valid ptr in the heap
MACRO bh_siftup name
@loop:
    ld (@first_ptr+1), hl ; With smc it simplifies logic
    ld e, (hl) \ inc hl
    ld d, (hl) \ dec hl
        
; Is there a parent to test with?
    ld bc,  4+bh_base_##name
    or a \ sbc hl, bc
    ret m ; It can only go negative from the subtraction, not division 

    ld a, l
    srl h \ rra
    and ~3
    ld l, a 

    ld bc,  bh_base_##name
    add hl, bc

    ld c, (hl) \ inc hl
    ld b, (hl) \ dec hl

    ex de, hl
        ; We want the child to be BIGGER then the parent
        ; child - parent
        sbc hl, bc
        ret p
        add hl, bc
    ex de, hl
@first_ptr:
    ld de, 0000h ; SMC: First ptr
    push hl
        _swap_hl_de
    pop hl
    jp @loop
endm



; Takes a heap ptr, checks if that is the new smallest, if so sets is as such, and returns with hl
; not being modified
; Conventions:
; de   = Last smallest value
; hl   = Current ptr
; (sp) = Last smallest ptr
; Going in carry should be RESET!
;
; is_too_small should what happens when the INDEX is too small
macro _do_smallest name, is_too_small
    LOCAL @hl_still_smallest

    ; bc should be BIGGER then hl
    ld bc, (bh_tail_##name)
    sbc hl, bc
    add hl, bc

    jp p, is_too_small

    ld c, (hl) \ inc hl
    ld b, (hl) \ dec hl

    ex de, hl
        or a
        sbc hl, bc
        add hl, bc
    ex de, hl
    jp m, @hl_still_smallest
        pop af
        push hl
        ld de, bc
@hl_still_smallest:
endm



; Inputs:
; hl = a valid ptr in the heap
MACRO bh_siftdown name
    ; We keep the current smallest key value in de,
    ; with the ptr to that heap entry in (sp). 
@loop:
    push hl \ push hl
    ld e, (hl) \ inc hl
    ld d, (hl) \ dec hl

    ld bc, -bh_base_##name
    add hl, bc


    ; left = 2*i+1
    sla l \ rl h
    ld bc, 4 + bh_base_##name
    add hl, bc

    _do_smallest name, @finished

    ld bc, 4
    add hl, bc

    _do_smallest name, @do_smallest
@do_smallest:
    pop hl ; last smallest ptr
    pop de ; original ptr

    or a
    sbc hl, de
        ret z ; Safe since stack is reset
    add hl, de

    push hl
        _swap_hl_de
    pop hl

    jp @loop


@finished:
    pop af \ pop af
    ret
endm


; Inputs:
; bc = key
; de = ptr
MACRO bh_insert name

    ld hl, (bh_tail_##name)
    push hl
        ld (hl), c \ inc hl
        ld (hl), b \ inc hl

        ld (hl), e \ inc hl
        ld (hl), d \ inc hl
        ld (bh_tail_##name), hl
    pop hl

    bh_siftup name
ENDM



; Output:
; hl' = key
; de' = ptr
MACRO bh_pop name
    LOCAL sift_down

    ld hl, (bh_base_##name)
    ld de, (2+bh_base_##name)
    exx

        ld hl, (bh_tail_##name)
            ld bc, -4
            add hl, bc
        ld (bh_tail_##name), hl

        ld de, bh_base_##name
            ldi \ ldi \ ldi \ ldi

    ld hl, bh_base_##name
    bh_siftdown name
endm

