INCLUDE "core/includes/utils.inc"




; Upper bound into an already sorted array
; BC - key
; OUT: DE - first record with key > BC
MACRO sorted_array_bsearch head, tail_ptr
    ld de, head
    ld hl, (tail_ptr)
    ld (@end_ptr+1), hl


    ; hl = end
    ; de = start
    ; bc = key we are looking for (for the entire loop)
    @loop:
        ; hl = end-start
        or a \ sbc hl, de
        ret z

        ; hl /= 2
        srl h
        ld a, l
        rra
        and ~3 ; Round down (alignment)
        ld l, a

        ; Add the start back in to get the pointer back
        add hl, de

    ; if array[midpoint] > key:
        ; bc - (hl)
        CpBC_PHL
        jp pe, @overflow ; Rare: signed overflow
        jp m, @key_is_smaller
@key_is_bigger:
            ; start = midpoint+1
            ex de, hl ; midpoint to start
            inc de \ inc de \ inc de
        @end_ptr:
            ld hl, 0000h ; End ptr
            jp @loop

@overflow:
        jp m, @key_is_bigger
        @key_is_smaller:
            ; end = midpoint
            dec hl
            ld (@end_ptr+1), hl
            jp @loop
endm


; Scan backwards from DE for a matching key+value
; DE - one past the last candidate (upper bound)
; BC - key
; HL - value
; OUT: DE - matching record, or RET if not found
MACRO _sorted_array_scan_eq head
    LOCAL @scan, @go, @nomatch, @found
@scan:
    ld a, e
    cp head & 0xFF
    jr nz, @go
    ld a, d
    cp head >> 8
    ret z
@go:
    dec de \ dec de \ dec de \ dec de

    ld a, (de)
    cp c
    ret nz
    inc de
    ld a, (de)
    cp b
    ret nz
    inc de
    ld a, (de)
    cp l
    jr nz, @nomatch
    inc de
    ld a, (de)
    cp h
    jr z, @found
    dec de
@nomatch:
    dec de \ dec de
    jp @scan
@found:
    dec de \ dec de \ dec de
endm


; Insert into an already sorted array
; HL - key
; BC - value
MACRO sorted_array_insert head, tail_ptr, bsearch
    push bc
    ld bc, hl
    call bsearch

    push bc ; Key
        ; de = start ptr
        ld hl, (tail_ptr)

        sbc hl, de
            ld bc, hl
        add hl, de

        ld de, hl

        inc de \ inc de \ inc de \ inc de
            ld (tail_ptr), de
        dec de
        dec hl


        ld a, b \ or c
        jr z, @no_cpy

        ; Copy BACKWORDS, from tail -> tail+4, this means nothing gets corrupted
        @cpy_loop:
            ldd \ ldd \ ldd \ ldd
            jp pe, @cpy_loop
@no_cpy:
        ex de, hl

    pop bc ; Key
    pop de ; Ptr
    ld (hl), d \ dec hl
    ld (hl), e \ dec hl

    ld (hl), b \ dec hl
    ld (hl), c
    ret
endm


; Remove from an already sorted array
; HL - key
; BC - value
MACRO sorted_array_remove head, tail_ptr, bsearch
    push bc
    ld bc, hl
    call bsearch
    pop hl

    _sorted_array_scan_eq head

    ld hl, (tail_ptr)
    ld bc, -4
    add hl, bc
        ld (tail_ptr), hl
    or a
    sbc hl, de
    ret z

        ld bc, hl
    ld hl, de
    inc hl \ inc hl \ inc hl \ inc hl

    ; Copy FORWARDS, from found+4 -> found
    @cpy_loop:
        ldi \ ldi \ ldi \ ldi
        jp pe, @cpy_loop
    ret
endm


; Change the depth of an item in an already sorted array
; HL - old key
; DE - new key
; BC - value
MACRO sorted_array_change_depth head, tail_ptr, bsearch
    ld a, l
    cp e
    jr nz, @go
    ld a, h
    cp d
    ret z
@go:
    push bc
    ld (@new_key+1), de
    ld bc, hl
    call bsearch
    pop hl

    _sorted_array_scan_eq head

    push hl ; Value
    ld (@old_pos+1), de
@new_key:
    ld bc, 0000h ; New key
    call bsearch
@old_pos:
    ld hl, 0000h ; Old pos


    ; Same slot if new == old or new == old+4
    ld a, e
    cp l
    jr nz, @not_eq
    ld a, d
    cp h
    jp z, @in_place
@not_eq:
    ld a, l
    add a, 4
    cp e
    jr nz, @move
    ld a, h
    adc a, 0
    cp d
    jp z, @in_place
@move:
    push bc ; Key
        ld bc, 4
        add hl, bc
        or a
        sbc hl, de
        jr c, @right

            ; Shift [new, old) right
            sbc hl, bc
                ld bc, hl
            add hl, de
            inc hl \ inc hl \ inc hl
            ex de, hl
            ld hl, de
            dec hl \ dec hl \ dec hl \ dec hl
            @left_loop:
                ldd \ ldd \ ldd \ ldd
                jp pe, @left_loop
            ex de, hl
            pop bc
            pop de
            jp @write

@right:
            ; Shift [old+4, new) left
            add hl, de
            ex de, hl
            or a
            sbc hl, de
                ld bc, hl
            ld hl, de
            dec de \ dec de \ dec de \ dec de
            @right_loop:
                ldi \ ldi \ ldi \ ldi
                jp pe, @right_loop
            ex de, hl
            inc hl \ inc hl \ inc hl
            pop bc
            pop de
@write:
    ld (hl), d \ dec hl
    ld (hl), e \ dec hl

    ld (hl), b \ dec hl
    ld (hl), c
    ret

@in_place:
    pop de ; Value
    ld (hl), c \ inc hl
    ld (hl), b
    ret
endm
