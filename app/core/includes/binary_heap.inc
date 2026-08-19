
; Each tree element has two element:
; 1. A 16-bit SIGNED key
; 2. A ptr (we do nothing with it)
MACRO bh_def arena, name, reservation
    DEFC bh_reservation_##name = reservation

    RDEF arena, bh_tail_##name, 2
    RDEF arena, bh_base_##name, reservation*4

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



; Inputs:
; hl = index*4 in heap
MACRO bh_siftup name
    ld bc, bh_base_##name
@loop:
    add hl, bc ; Should never cause a carry
        ld (@ld_hl+1), hl
    sbc hl, bc

    ld bc, -4
    add hl, bc
    ret nc

    srl h \ rr l
    srl h \ rr l
    srl h \ rr l
    add hl, hl
    add hl, hl

    ld bc, bh_base_##name
    add hl, bc ; Should never cause a carry
        ld (@ld_bc+2), hl
    sbc hl, bc

    exx
    @ld_hl:
        ld hl, (0000h) ; child
    @ld_bc:
        ld bc, (0000h) ; parent
        ; child - parent
        ld a, h
        xor b
        jp p, @same_sign
        bit 7, h
        jp nz, @swap
        ret
    @same_sign:
        or a \ sbc hl, bc
        ret nc

    @swap:
        ld hl, (@ld_hl+1)
        ld de, (@ld_bc+2)

        _swap_hl_de
    exx
    jp @loop
endm



MACRO _bh_lookup_and_set_smallest name
    LOCAL @still_smallest, @still_after_compare, @new_smallest, @same_sign, @rejoin
    ; Loop up the key
    ld bc, bh_base_##name
    add hl, bc ; Should never carry
    ld c, (hl) \ inc hl
    ld b, (hl) \ dec hl

    ; If the key is the new smallest, swap it out
    ex de, hl
        ld a, h
        xor b
        jp p, @same_sign
        bit 7, h
        jp z, @new_smallest
        jp @still_smallest
    @same_sign:
        or a
        sbc hl, bc
        jp c, @still_after_compare
        jp z, @still_after_compare
    @new_smallest:
        ld hl, bc
        ex de, hl

        ld bc, -bh_base_##name
        add hl, bc ; Should carry
        pop af \ push hl
        jp @rejoin
    @still_smallest:
        ex de, hl
        ld bc, -bh_base_##name
        add hl, bc ; Should carry
        jp @rejoin
    @still_after_compare:
        add hl, bc
        ex de, hl
        ld bc, -bh_base_##name
        add hl, bc ; Should carry
    @rejoin:
endm


; Inputs:
; hl = index*4 in heap
MACRO bh_siftdown name
    @loop:
    push hl ; Bottom will be the original index

    ; We keep the smallests index on the stack
    push hl

    ; And it's value in de
    ld bc, bh_base_##name
    add hl, bc
    ld e, (hl) \ inc hl
    ld d, (hl) \ dec hl
    or a
    sbc hl, bc


    ; *= 2
    sla l \ rl h

;;;; Left
    ld bc, 4
    add hl, bc ; Should never carry

    ; if the left is out of bounds, nothing left to do
    ld bc, 4*bh_reservation_##name
    or a
    sbc hl, bc
        jp nc, @maybe_swap
    add hl, bc

    _bh_lookup_and_set_smallest name
;;;; Right
    ld bc, 4
    add hl, bc

    ld bc, 4*bh_reservation_##name
    or a
    sbc hl, bc
        jp nc, @maybe_swap
    add hl, bc

    _bh_lookup_and_set_smallest name
@maybe_swap:
    pop hl ; Smallest index
    pop de ; Original index

    or a
    sbc hl, de
    ret z
    add hl, de

    push hl
        ld bc, bh_base_##name
        add hl, bc
        ex de, hl
        add hl, bc
        _swap_hl_de
    pop hl

    jp @loop
endm
