; This is raw included into the interupt routine to save cycles (being run so often, it must be BLAZINGLY FAST)
; NOTE: **Must perseve all registers used!**

; Audio subsytem notes:
; - The 32768 hz timer is GOD. All must be designed around it. 
;    - The loop counter will be modified on the fly
; - Due the the extreme nature of this code, every cycle matters. As such, optimization
;   trumps all else. Inlining is essential. 
; 

MACRO audio_cleanup
	AUDIO_ACK_TIMER
  pop af

; Optimization:
; Since the audio is ran so often, it is likely it is the only one
; being fired. And so the only bit being set would be #3 and #7 (itself), the on button.
; which is shifted to bit 4, and the audio is shifted to 0. 
  cp $11
  jp z, after_cases

  jp after_audio_case
endm


audio_tick:
; NOTE: Self modifying code for the audio state
  jp aud_low

; ====A the low sequence of a square wave===
aud_low:
  push af

; NOTE: Patch this puppy
low_count: ld a, 0
  out ($38), a

  xor a, a
  out ($0), a

  ld a, aud_high & 0xFF
  ld (audio_tick + 1), a
  audio_cleanup


; ====A the high sequence of a square wave===
aud_high:
  push af

; NOTE: Patch this puppy
high_count: ld a, 0
  out ($38), a

  ld a, $1
  out ($0), a

  ld a, aud_low & 0xFF
  ld (audio_tick + 1), a
  audio_cleanup





  



