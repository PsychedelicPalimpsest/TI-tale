INCLUDE "core/includes/utils.inc"

; Insert into an already sorted array
; HL - key
; BC - value
MACRO sorted_array_insert head, tail_ptr
    push bc
    ld bc, hl


    ld hl, (tail_ptr)
    ld de, head

    CpHLDE
    jr c, @end_of_loop


    ; hl = end    
    ; de = start
    ; bc = key we are looking for (for the entire loop)
    @loop:
        ld (@end_ptr+1), hl 
        
        ; hl = end-start
        or a \ sbc hl, de
        jr z, @end_of_loop 
        ; jr c, @end_of_loop ; Theoretically, should never happen
       
        ; hl /= 2
        srl h 
        ld a, l
        rra
        and ~3 ; Round down (alignment)
        ld l, a

        ; Add the start back in to get the pointer back
        add hl, de

        ; array[midpoint] - key <= 0
        ; bc - (hl)
        CpBC_PHL
    ; if array[midpoint] > key:
        jp m, @key_is_smaller
            ; start = midpoint+1
            ex de, hl ; midpoint to start
            inc de \ inc de \ inc de
            
        @end_ptr:
            ld hl, 0000h ; End ptr
            jp @loop


        
        @key_is_smaller:
            ; end = midpoint
            dec hl

            jp @loop
              

@end_of_loop:
    push bc ; Key
        ; de = start ptr
        ld hl, (tail_ptr)

        or a
        sbc hl, de
            ld bc, hl
        add hl, de


        ld de, hl
        dec hl ; The tail ptr is the NEXT empty space, we don't need to copy that
        inc de \ inc de \ inc de ; inc de
        ld (tail_ptr), de

        ; Copy BACKWORDS, from tail -> tail+4, this means nothing gets corrupted
        @cpy_loop:
            ldd \ ldd \ ldd \ ldd
            jp pe, @cpy_loop
    ; De = where it was copied to, so that is where we start writing our insertion
    ex de, hl

    pop bc ; Key
    pop de ; Ptr
    ld (hl), d \ dec hl
    ld (hl), e \ dec hl

    ld (hl), b \ dec hl
    ld (hl), c
    ret
endm



