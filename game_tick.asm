; This code runs at 32 Hz, and is run by interrupt.asm
    

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

    ld (_keymap + 0h), a


    ld a, $FD ;Select group 1.
    out (1), a
    in a, (1)

    ld (_keymap + 1h), a


    ld a, $FB ;Select group 2.
    out (1), a
    in a, (1)

    ld (_keymap + 2h), a


    ld a, $F7 ;Select group 3.
    out (1), a
    in a, (1)

    ld (_keymap + 3h), a


    ld a, $EF ;Select group 4.
    out (1), a
    in a, (1)

    ld (_keymap + 4h), a


    ld a, $DF ;Select group 5.
    out (1), a
    in a, (1)

    ld (_keymap + 5h), a



    ld a, $BF ;Select group 6.
    out (1), a
    in a, (1)

    ld (_keymap + 6h), a



    ld a, $7F ;Select group 7.
    out (1), a
    in a, (1)

    ld (_keymap + 7h), a


    ld a, 0FFh ;Reset the keypad.
    out (1), a    



    ld a, 0F7h ;Select group 3.
    out (1), a
    in a, (1)

    ld (_keymap + 3h), a




