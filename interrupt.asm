defc interupt_vector = 8A8Ah

__interupt:
    di
    push	af
    push	bc
    push	de
    push	hl

    ; Todo interupt

    pop	hl
    pop	de
    pop	bc
    pop	af
    ei
    ret
__end_of_interupts:



__setup_interrupts:
    ld hl, __interupt
    ld de, interupt_vector
    ld bc, __end_of_interupts - __interupt
    ldir

; Vector table is based at $8B00
    ld a, $8b
    ld i, a
; Fill the vector table with $8A so interrupts always jump to $8A8A,
; no matter the value of the low byte.
    ld hl, $8b00
    ld (hl), $8a
    ld de, $8b01
    ld bc, 256
    ldir

    im 2
    ei


    ret
