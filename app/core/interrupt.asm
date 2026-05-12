SECTION code_core

PUBLIC setup_interrupts
PUBLIC greyscale_addr

INCLUDE "common.inc"
EXTERN __Exit


defc interupt_vector = 8181h
defc interupt_mask = %00001001

; Adresses of greyscale and gametick hooks
defc greyscale_addr = _greyscale_call + 1


defc ch1_timer = $36
defc ch2_timer = $33



MACRO SETUP_GREY_TIMER
	ld	a, $40
	out	($30), a	;10922 Hz

	GREY_ACK_TIMER

	ld	a, (_grey_timing)
	out	($32), a
ENDM

  MACRO GREY_ACK_TIMER
    ld	a, 3 ; Interrupt mode (to bit 5 of port 4h), and loop
    out	($31), 	a
  ENDM



MACRO interupt_cleanup
    pop af ; Note: This is the user af, not other af interupt usage.
    ei
    ret
ENDM



; Get audio macros
INCLUDE "audio.inc"


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
ch1_jp: 
    jp c, ch1@saw_double ; 10
     
    rlca                  ; 4
ch2_jp: 
    jp c, ch2@saw_double ; 10
    rlca
    jr nc, non_grey_case
      GREY_ACK_TIMER




; This hack allows the audio to still work, it may cause issues ¯\_(ツ)_/¯
;
; Ex: if audio takes up too much cpu, greyscale might not run in 60hz, and
;     will interupt this interupt, not good. 
      ei 

      ; Note: Self modifying code! (hook)
      _greyscale_call: call 0000h
      interupt_cleanup 

non_grey_case:
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


ch1: AUDIO_CHANNEL 1, ch1_timer, ch1_jp, ch1_instrument_val_ptr, ch1_instrument_low_ptr, ch1_saw_style
ch2: AUDIO_CHANNEL 2, ch2_timer, ch2_jp, ch2_instrument_val_ptr, ch2_instrument_low_ptr, ch2_saw_style

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
    ; Fun fact: This is _not_ a race condition, as interupts are disabled, if the timer expires nothing happens!


    SETUP_GREY_TIMER
; Disable audio timers (re-enabled in engine)
    xor a
    out (ch1_timer), a
    out (ch2_timer), a

    ret
