; This code runs at 32 Hz, and is run by interrupt.asm

; Copy current keymap to last keymap
    ld hl, (_current_keymap)
    ld (_last_keymap), hl
    ld hl, (_current_keymap + 2)
    ld (_last_keymap + 2), hl

    ld hl, (_current_keymap + 4)
    ld (_last_keymap + 4), hl
    ld hl, (_current_keymap + 6)
    ld (_last_keymap + 6), hl


; Game counter
    ld hl, (_game_count)
    inc hl
    ld (_game_count), hl



; Keyboard scanning
    ld a, $FF ;Reset the keypad.
    out (1), a


    ld a, $FE ;Select group 0.
    out (1), a
    in a, (1)

    ld (_current_keymap + 0h), a


    ld a, $FD ;Select group 1.
    out (1), a
    in a, (1)

    ld (_current_keymap + 1h), a


    ld a, $FB ;Select group 2.
    out (1), a
    in a, (1)

    ld (_current_keymap + 2h), a


    ld a, $F7 ;Select group 3.
    out (1), a
    in a, (1)

    ld (_current_keymap + 3h), a


    ld a, $EF ;Select group 4.
    out (1), a
    in a, (1)

    ld (_current_keymap + 4h), a


    ld a, $DF ;Select group 5.
    out (1), a
    in a, (1)

    ld (_current_keymap + 5h), a



    ld a, $BF ;Select group 6.
    out (1), a
    in a, (1)

    ld (_current_keymap + 6h), a



    ld a, $7F ;Select group 7.
    out (1), a
    in a, (1)

    ld (_current_keymap + 7h), a


    ld a, 0FFh ;Reset the keypad.
    out (1), a    


; We want to activate when it goes from unpressed, to pressed.
; 1 is for unpressed. So, 10

    ld a, (_current_keymap)
    ld b, a

    ld a, (_last_keymap)

    cpl a
    and a, b
    and %1111 ; Potential ghosting

    ld (_nav_key_change), a

; Temp tuning stuff

    ; Nope out early if nothing is newly pressed
    jp z, after_tuning 


    bit 3, a
    jp nz, UP
    bit 0, a
    jp nz, DOWN

    bit 1, a
    jp nz, LEFT
    bit 2, a
    jp nz, RIGHT

LEFT:
    jp after_tuning
RIGHT:
    jp after_tuning

UP:
    ld a, (_grey_timing)
    inc a
    ld (_grey_timing), a
    jp after_tuning
DOWN:
    ld a, (_grey_timing)
    dec a
    ld (_grey_timing), a
    ; Fall through

after_tuning:
