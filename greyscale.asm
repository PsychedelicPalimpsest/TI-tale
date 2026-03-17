defc xmax = 96d
defc ymax = 64d


    ld hl, (_current_light_buff)

    ld a, 1h  ; 8bit mode
    out (10h), a

    ld a, 7h  ; inc right
    out (10h), a


    ld c, 80h ; Set top row
row_loop:
    ld a, c
    out (10h), a

    ld a, $20 ; Set left column
    out (10h), a

    ld b, xmax/8h
cell_loop:
    ld a, (hl)
    inc hl
    out (11h), a
    djnz cell_loop

    inc c
    ld a, ymax + 80h
    sub a, c
    jp nz, row_loop



    jp after_masks




grey_mask: defb %01101101
grey_carry: defb 1

after_masks:
