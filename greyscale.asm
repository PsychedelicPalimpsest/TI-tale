; Greyscale system. This code runs from interrupt.asm at approx 60 Hz, but
; is adjustable by the user to adjust flickering issues. 

defc xmax = 96d
defc ymax = 64d
    ld hl, (_gray_count)
    inc hl
    ld (_gray_count), hl


    
    ld   a, (grey_carry) 
    rra                 ; Put carry in carry bit
    ld   a, (grey_mask)
    rla
    ld   (grey_mask), a

    jp   c, use_dark ; If carry is set, we know it is a dark pixel

    xor  a
    ld   (grey_carry), a
    ld   hl, _working_light
    jp  after_dark

use_dark:
    ld   a, 1 ; Since carry is set, just save a one
    ld   (grey_carry), a
    ld   hl, _working_dark
after_dark:
    ld a, $1 ; 8bit mode
    out (10h), a

    ld a, $7 ; Move right
    out (10h), a


    
    ld d, 80h  ; d = row + 80h

    ld c, 11h  ; Port to write to (for outi),  
row_loop:
    ld a, d ; Set col (saved in d)
    out (10h), a


    ld a, 20h ; Go to beginning of col
    out (10h), a

; Unrolled write loop (12 entries)
    outi
    outi ; out (c), (hl) \ inc (hl), dec b
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
