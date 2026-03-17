; Zero out global vars for safety
    ld hl, _globals_start
    ld (hl), $00
    ld de, _globals_start + 1
    ld bc, $1000 ; 4kb
    ldir

    ld a, $A0
    ld (_grey_timing), a

; Init buffers
    ld hl, _light_buff_1
    ld (_current_light_buff), hl

    ld hl, _grey_buff_1
    ld (_current_dark_buff), hl

 
