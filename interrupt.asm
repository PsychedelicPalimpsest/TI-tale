defc interupt_vector = 8181h

defc interupt_mask = %00001011


__interupt:
PHASE interupt_vector
    di
    push	af
    push	bc
    push	de
    push	hl


    
    in a, (4) ; Get interrupt cause 
    ld b, a   ; Save cause to b

    xor a, a ; Ack interrupts
    out	(03), a


    bit 0, b ; Test if on button is pressed
    jp z, _after_exit ; If so, exit


    ; Load in the first rom page of app
    ld a, (_first_rom_page)
    out (6), a

    ; Ensure TiOS has interrupts
    ld a, interupt_mask
    out (3), a

    ; Note: TiOS fixes the stack for us
    jp __Exit
_after_exit:

    ld a, interupt_mask
    out (3), a

    pop	hl
    pop	de
    pop	bc
    pop	af
    ei
    ret
DEPHASE
__end_of_interupts:


__setup_interrupts:
    ld hl, __interupt
    ld de, interupt_vector
    ld bc, __end_of_interupts - __interupt
    ldir

; Vector table is based at $8000
    ld a, $80
    ld i, a
; Fill the vector table with $81 so interrupts always jump to $8181,
; no matter the value of the low byte.
    ld hl, $8000
    ld (hl), $81
    ld de, $8001
    ld bc, 256
    ldir

    xor a, a
    out	(03), a

    ld a, interupt_mask
    out (3),a

    ; Enable interrupts
    im 2
    ei

    ret

