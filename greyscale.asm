; Greyscale system. This code runs from interrupt.asm at approx 60 Hz, but
; is adjustable by the user to adjust flickering issues. 

defc xmax = 96d
defc ymax = 64d
    ld hl, (_gray_count)
    inc hl
    ld (_gray_count), hl


    ld   a, (grey_carry)    ; load stored carry bit (0 or 1)
    rra                     ; shift bit 0 into CF

    ld   a, (grey_mask)
    rla   ; grey_carry goes to lsb, and msb goes to carry
    
    ld (grey_mask), a

    ld a, $0
    rla ; Set carry to a

    ld (grey_carry), a

    dec a ; 1=>0, 0=>0xff

    ld b, a ; Save to b


    ld a, 1h ; 8bit mode
    out (10h), a


    ld a, 25h
    out (10h), a


    ld a, 85h
    out (10h), a

    ld a, b ; restore a from b
    out (11h), a
    out (11h), a
    out (11h), a

    ld a, (_grey_timing)
    out (11h), a
    out (11h), a
    out (11h), a


    jp after_masks

grey_mask: defb %01101101;1
grey_carry: defb 1
after_masks:
