SECTION code_core

PUBLIC setup_interrupts
PUBLIC greyscale_addr
PUBLIC gametick_addr

INCLUDE "common.inc"
EXTERN __Exit


defc interupt_vector = 8181h
defc interupt_mask = %00001001

; Adresses of greyscale and gametick hooks
defc greyscale_addr = _greyscale_call + 1
defc gametick_addr =  _gametick_call + 1


MACRO SETUP_GREY_TIMER
	ld	a, $40
	out	($30), a	;10922 Hz

	ld	a, 2 ; Interrupt mode (to bit 5 of port 4h)
	out	($31), 	a

	ld	a, (_grey_timing)
	out	($32), a
ENDM

MACRO SETUP_GAME_TIMER
	ld	a, $46
	out	($33), a	; 128 Hz

	ld	a, 2 ; Interrupt mode (to bit 6 of port 4h)
	out	($34), 	a

	ld	a, 4
	out	($35), a ; 128/4 = 32Hz
ENDM



interupt:
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
    jp z, after_exit 

; If so, exit
    ; Load in the first rom page of app
    ld a, (_first_rom_page)
    out (6), a

    ; Ensure TiOS has regular interrupts
    ld a, %00001011
    out (3), a

    ; Note: TiOS fixes the stack for us
    jp __Exit
after_exit:
    bit 5, b
    jp z, after_grey

    push bc

    SETUP_GREY_TIMER

    ; Note: Self modifying code!
    _greyscale_call: call 0000h

    pop bc
after_grey:
    bit 6, b
    jp z, after_game_tick

    SETUP_GAME_TIMER

    ; Note: Self modifying code!
    _gametick_call: call 0000h
after_game_tick:


    ld a, interupt_mask
    out (3), a

    pop	hl
    pop	de
    pop	bc
    pop	af
    ei
    ret
after_interrupt_code:
DEPHASE
end_of_interupts:


setup_interrupts:
    ld hl, interupt
    ld de, interupt_vector
    ld bc, end_of_interupts - interupt
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
    di
    ; It is NOT safe to enable interupts until greyscale_addr and gametick_addr have been set!

    ; Note here the race condition :<
    SETUP_GREY_TIMER
    SETUP_GAME_TIMER

    ret
