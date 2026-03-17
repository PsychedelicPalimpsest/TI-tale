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
    rra

    jp c, dark_gray

    ld hl, (_current_light_buff)
    jp after_dark
dark_gray:
    ld hl, (_current_dark_buff)
after_dark:

    ld a, $1 ; 8bit mode
    out (10h), a

    ld a, $7 ; Move right
    out (10h), a


    
    ld d, 80h  ; d = row + 80h

    ld c, 11h  ; Port to write to (for outi),  
row_loop:
    ld a, d ; Set col
    out (10h), a ;


    ld a, 20h ; Go to beginning of col
    out (10h), a

; Unrolled write loop (12 entries)
    outi
    outi ; out (c), (hl) \ inc (hl)
    outi
    outi


    outi
    outi
    outi
    outi

    outi
    outi
    outi
    outi


    inc d
    ld a, 80h + ymax -1
    sub a, d
    jp nc, row_loop






    jp after_masks

grey_mask: defb %01101101;1
grey_carry: defb 1
after_masks:
