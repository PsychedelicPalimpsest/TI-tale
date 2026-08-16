; This code runs at ~30 Hz, and is run by greyscale.asm
; Please note: This is NOT the game loop, this handles key scanning


PUBLIC engine_tick
engine_tick:

; Copy current keymap to last keymap
    ld hl, (_current_keymap)
    ld (_last_keymap), hl
    ld hl, (_current_keymap + 2)
    ld (_last_keymap + 2), hl

    ld hl, (_current_keymap + 4)
    ld (_last_keymap + 4), hl
    ld hl, (_current_keymap + 6)
    ld (_last_keymap + 6), hl


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

  ret
