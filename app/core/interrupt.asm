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


MACRO SETUP_GAME_TIMER
	ld	a, $46
	out	($30), a	; 128 Hz

	GAME_ACK_TIMER

	ld	a, 4
	out	($32), a ; 128/4 = 32Hz
ENDM

  MACRO GAME_ACK_TIMER
    ld	a, 3 ; Interrupt mode (to bit 6 of port 4h), and loop
    out	($31), 	a
  ENDM



MACRO SETUP_GREY_TIMER
	ld	a, $40
	out	($33), a	;10922 Hz

	GREY_ACK_TIMER

	ld	a, (_grey_timing)
	out	($35), a
ENDM

  MACRO GREY_ACK_TIMER
    ld	a, 3 ; Interrupt mode (to bit 5 of port 4h), and loop
    out	($34), 	a
  ENDM


MACRO SETUP_AUDIO_TIMER
	ld	a, $44
	out	($36), a	; 32768 Hz

	AUDIO_ACK_TIMER

	ld	a, 24*8
	out	($38), a ; 32768/41 = 800Hz
ENDM
  MACRO AUDIO_ACK_TIMER
    ld	a, 3 ; Interrupt mode (to bit 7 of port 4h), and loop
    out	($37), 	a
  ENDM




MACRO interupt_cleanup
    pop af ; Note: This is the user af, not other af interupt usage.
    ei
    ret
ENDM



; Interupt preformence: 
;  Interupts are called a LOT, every cycle matters! As such, I
;  do the following:
;   - To keep other routines fast (and make z88dk happy), the typical shadow register tick will not work. 
;     so, any register you use in an interupt _must_ be preserved! 
;   - `jr X, label` has a 7 cycle fall-through, so that is what I prefer. 
;      Just remember at all times what is the 'fast path'
;   - 
;  The crystal timers are assigned by calling frequency
;    #3 - Audio, can get up to 1000+ Hz depending on the tone
;    #2 - Greyscale, ~60 Hz
;    #1 - Gametick, 32 Hz (TODO, might change)
;  In addition: timer 3 is bit 7, 2 is bit 6, 1 is bit 5 of port 4. 
;  This means, a simple rlca will reveal if a timer is set. 
;
;  In addition, I am assuming one interupt cause per interupt,
;  and the only possible sources are: 1. Crystal timers 2. On button
;
;  Keep in mind: this is the single hottest path of this codebase. (espicially audio)
interupt:
PHASE interupt_vector
    di       ;  4
    push	af ;  11

    in a, (4) ; 11- Get interrupt cause 
    
    rlca      ; 4
    jp nc, non_audio_case  ; 10
      ; Do audio logic
      INCLUDE "audio.asm" ; Taken out for simplicity
     
non_audio_case:
    rlca                  ; 4
    jr nc, non_grey_case  ; 12/7
      ; Do greyscale logic
      GREY_ACK_TIMER

      ; Note: Self modifying code! (hook)
      _greyscale_call: call 0000h
      interupt_cleanup 

non_grey_case:
    rlca
    jr nc, non_game_case
      ; Do gametick logic
       GAME_ACK_TIMER

      ; Note: Self modifying code!
      _gametick_call: call 0000h
      interupt_cleanup 
non_game_case:
; Assume any other interupt is caused by the on button
; note: It needs acked by ports 2 & 3
    ; Ack interupt
    xor a
    out ($02), a
    out ($03), a

    ; Load in the first rom page of app
    ld a, (_first_rom_page)
    out (6), a


    ; Note: TiOS fixes the stack for us (no interupt cleanup needed)
    ;       __Exit also does interupt mask cleanup
    jp __Exit



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

    SETUP_GREY_TIMER
    ; SETUP_GAME_TIMER


    SETUP_AUDIO_TIMER


    ret
