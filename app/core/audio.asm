; This is raw included into the interupt routine to save cycles (being run so often, it must be BLAZINGLY FAST)

; Audio subsytem notes:
; - The 32768 hz timer is GOD. All must be designed around it. 
;    - The loop counter will be modified on the fly
; - Due the the extreme nature of this code, every cycle matters. As such, optimization
;   trumps all else. Inlining is essential. 
; 

MACRO audio_cleanup
	AUDIO_ACK_TIMER
  interupt_cleanup
endm

; max=1+sqrt(32768K / F)
DEFC saw_maximum = 45
DEFC saw_constant = 2

DEFC instrument_val = lookup_instrument+1       ; 16 bit
DEFC instrument_low = lookup_instrument@reset+1 ; 8 bit


audio_tick:
; Cary flag always set (due to interupt code)
; NOTE: Self modifying code for the audio state
  jp lookup_instrument 

;---======= Saw wave=======---
saw_double:
  ld a, $1
@style: ; Next two bytes may be patched
  ; or a \ rla ; may become add a, saw_constant
add a, saw_constant
  cp saw_maximum
  jp nc, @cleanup

  ld (saw_double+1), a
@saw_output:
  out	($38), a

  xor a
  out (0), a

  ld a, saw_double_rest & 0xFF
  ld (audio_tick+1), a

  audio_cleanup
@cleanup:
  ld a, $1
  ld (saw_double+1), a
  jp @saw_output

saw_double_rest:
  ld a, (saw_double+1)

  cpl
  add saw_maximum

  out ($38), a
  ld a, $1
  out (0), a

  ld a, saw_double & 0xFF
  ld (audio_tick+1), a
  audio_cleanup

square_up:
  ld a, $1
  out (0), a
  
  ld a, 46
  out ($38), a

  ld a, square_down&0xFF
  ld (audio_tick+1), a
  audio_cleanup

square_down:
  xor a, a
  out (0), a

  ld a, 46
  out ($38), a

  ld a, square_up&0xFF
  ld (audio_tick+1), a

  audio_cleanup

EXTERN test_instrument
;---======= Custom instrument=======---
lookup_instrument:
  ld a, (test_instrument) 
  or a
  jr z, @reset
  out ($38), a

@oscilator:
  ld a, $3
  cpl
  ld (@oscilator+1), a
  and 1
  out (0), a

  ld a, (lookup_instrument+1)
  inc a
  ld (lookup_instrument+1), a
  audio_cleanup

@reset:
  ld a, test_instrument & 0xFF
  ld (lookup_instrument+1), a

  ld a, $3
  out (0), a
  ld (@oscilator+1), a
  jp lookup_instrument


