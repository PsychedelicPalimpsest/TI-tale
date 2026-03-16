defc interupt_vector = 8181h

__interupt:
PHASE interupt_vector

    di
    push	af
    push	bc
    push	de
    push	hl

    ; Interupt status
    in a, (4)

    xor a, a
    ; Acknowledge interrupt
    out (2), a

    ; Exit if on button is pressed
    bit 0, a
    jr z, __after_exit

    ld a, (_first_rom_page)
    out (6), a ; Set first page to be loaded

    jp __Exit ; Nope out (exists on first page)
__after_exit:
    bit 1, a
    jp z, __after_gray

    INCLUDE "greyscale.asm"
__after_gray:



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

    ; Set interupt mask
    ; Bit 0: On button press
    ; Bit 1: Hardware time 1
    ; Bit 2: Hardware time 2
    ld a, %111
    out (3), a


    ; Enable interrupts
    im 2
    ei


set_timers:
	ld	a, $40
	out	($30), a	;10922 Hz

	ld	a, 2
	out	($31), 	a ; Interupt

    ; TODO: Should this be 183?
	ld	a, 178	;<- this is the number you change for delay.  10922 / 178 = 61.359550561797754
	out	($32), a

    ret
