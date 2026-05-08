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
DEFC saw_maximum = 15
DEFC saw_constant = 3

audio_tick:
; Cary flag always set (due to interupt code)
; NOTE: Self modifying code for the audio state
  jp saw_double

;---======= Saw wave wave=======---
saw_double:
  ld a, $1
saw_style: ; Next two bytes may be patched
  add a, saw_constant
  cp saw_maximum
  jp nc, double_cleanup

  ld (saw_double+1), a
saw_output:
  out	($38), a

  ld a, $1
  out (0), a

  ld a, saw_double_rest & 0xFF
  ld (audio_tick+1), a

  audio_cleanup
double_cleanup:
  ld a, $1
  ld (saw_double+1), a
  jp saw_output

saw_double_rest:
  ld a, (saw_double+1)

  cpl
  add saw_maximum

  out ($38), a
  ld a, $0
  out (0), a

  ld a, saw_double & 0xFF
  ld (audio_tick+1), a
  audio_cleanup

  
  
  


