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



MACRO GREY_ACK_TIMER
	ld	a, 3 ; Interrupt mode (to bit 5 of port 4h), and loop
	out	($31), 	a
ENDM

MACRO SETUP_GREY_TIMER
	ld	a, $40
	out	($30), a	;10922 Hz

	GREY_ACK_TIMER

	ld	a, (_grey_timing)
	out	($32), a
ENDM

MACRO GAME_ACK_TIMER
	ld	a, 3 ; Interrupt mode (to bit 5 of port 4h), and loop
	out	($34), 	a
ENDM

MACRO SETUP_GAME_TIMER
	ld	a, $46
	out	($33), a	; 128 Hz

	GAME_ACK_TIMER

	ld	a, 4
	out	($35), a ; 128/4 = 32Hz
ENDM

MACRO AUDIO_ACK_TIMER
	ld	a, 3 ; Interrupt mode (to bit 6 of port 4h), and loop
	out	($37), 	a
ENDM

MACRO SETUP_AUDIO_TIMER
	ld	a, $44
	out	($36), a	; 32768 Hz

	AUDIO_ACK_TIMER

	ld	a, 24*8
	out	($38), a ; 32768/41 = 800Hz
ENDM


interupt:
PHASE interupt_vector
    di
    push	af

    in a, (4) ; Get interrupt cause 
    
    rlca
    jr c, audio_case
after_audio_case:
    rlca
    jr c, game_case
after_game_case:
    rlca 
    jr c, grey_case
after_grey_case:
    bit 3, a ; Originally bit 0, gets rotated to bit 3
    jr nz, on_case
after_cases:
    xor a, a ; Ack interrupts
    out	(03), a

    ld a, interupt_mask
    out (3), a

    pop af
    ei
    ret

game_case:
    push af
    GAME_ACK_TIMER

    ; Note: Self modifying code!
    _gametick_call: call 0000h
    pop af
    jp after_game_case
grey_case:
    push af
    GREY_ACK_TIMER

    ; Note: Self modifying code!
    _greyscale_call: call 0000h
    pop af
    jp after_grey_case
on_case:
    ; Load in the first rom page of app
    ld a, (_first_rom_page)
    out (6), a

    ; Ensure TiOS has regular interrupts
    ld a, %00001011
    out (3), a

    ; Note: TiOS fixes the stack for us
    jp __Exit
audio_case:

  push af
  AUDIO_ACK_TIMER

  extern audio_tick
  call audio_tick
  pop af

; Optimization:
; Since the audio is ran so often, it is likely it is the only one
; being fired. And so the only bit being set would be #3 and #7 (itself), the on button.
; which is shifted to bit 4, and the audio is shifted to 0. 
  cp %10001
  jr z, after_cases

  jp after_audio_case
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

    ld a, %11000000 ; Disable link assist
    out (8), a
    

    ; Enable interrupts
    im 2
    di
    ; It is NOT safe to enable interupts until greyscale_addr and gametick_addr have been set!

    ; Note here the race condition :<

    ; SETUP_GREY_TIMER
    ; SETUP_GAME_TIMER
    SETUP_AUDIO_TIMER


    ret
