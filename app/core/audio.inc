; This file handles the fast, almost instantanious, audio outputs. It only cares about tones. 
; See core/installed/audio_engine.asm for actually using it.
;
; Audio subsytem notes:
; - The timer is GOD. All must be designed around it. 
;        - The loop counter will be modified on the fly
; - Due the the extreme nature of this code, every cycle matters. As such, optimization
;     trumps all else. Inlining is essential. 
; 



; max=1+sqrt(32768K / F)
DEFC saw_maximum = 45
DEFC saw_constant = 2

MACRO audio_cleanup timer
   ld a, $3         ;  Loop + interupt
    out (1+timer), a
    interupt_cleanup
endm


; This macro is used twice, one for each channel (left and right)
MACRO AUDIO_CHANNEL mask, timer, audio_jp, instrument_val_ptr, instrument_low_ptr, saw_style
    DEFC instrument_val_ptr = @lookup_instrument+1    ; 16 bit
    DEFC instrument_low_ptr = @lookup_reset+1             ; 8 bit
    DEFC saw_style                    = @saw_style                        ; 2 bytes of opcodes

; This lets us only set the low byte of the jp instruction
; (this also means no more then 256 bytes can be used here)
ALIGN 256

;---======= Saw wave =======---
@saw_double:
    ld a, $1
@saw_style: ; Next two bytes may be patched
    ; or a \ rla ; may become add a, saw_constant
        add a, saw_constant
    cp saw_maximum
    jr nc, @saw_cleanup 

    ld (@saw_double+1), a
@saw_output:
    out	($38), a

; Reset the bit to pull it high
    ld a, (sound_state)
    and ~mask
    ld (sound_state), a

    out (0), a

    ld a, @saw_double_rest & 0xFF
    ld (audio_jp+1), a

    audio_cleanup timer
@saw_cleanup:
    ld a, $1
    ld (@saw_double+1), a
    jp @saw_output

@saw_double_rest:
    ld a, (@saw_double+1)

; low_ticks = maximum - high_ticks ~= -high_ticks + maximum -1
    cpl
    add saw_maximum

    out ($38), a

; Set the bit to pull low
    ld a, (sound_state)
    or mask
    out (0), a
    ld (sound_state), a

    ld a, @saw_double & 0xFF
    ld (audio_jp+1), a
    audio_cleanup timer

;---======= Pure square wave =======---
@square_up:
; Reset bit to pull high
    ld a, (sound_state)
    and ~mask
    out (0), a
    ld (sound_state), a

 
@square_uptime:
    ld a, 46
    out ($38), a

    ld a, @square_down&0xFF
    ld (audio_jp+1), a
    audio_cleanup timer

@square_down:
    ld a, (sound_state)
    or mask
    ld (sound_state), a
    out (0), a

    ld a, 46
    out ($38), a

    ld a, @square_up&0xFF
    ld (audio_jp+1), a

    audio_cleanup timer

EXTERN test_instrument
;---======= Custom instrument =======---
@lookup_instrument:
    ld a, (0000) ; (test_instrument) 
    or a
    jr z, @lookup_reset
    out ($38), a

@oscilator:
    ld a, (sound_state)
    xor mask ; flip the bit
    out (0), a
    ld (sound_state), a

    ; Only the low byte is incremented! This means you MUST align to 256 (or end before the boundry)
    ld a, (@lookup_instrument+1)
    inc a
    ld (@lookup_instrument+1), a
    audio_cleanup timer

@lookup_reset:
    ld a, 0 ; test_instrument & 0xFF
    ld (@lookup_instrument+1), a

    ld a, (sound_state)
    and ~mask
    out (0), a
    ld (sound_state), a

    jp @lookup_instrument

endm

