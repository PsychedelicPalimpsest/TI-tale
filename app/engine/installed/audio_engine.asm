; Audio format:
; There are two 'speed modes' the audio engine supports:
;  - The fast mode: Here, the timer is set to cpu_freq/64, this allows
;    'higher' quality output, at the cost of cpu.
;  - The slow mode: Where the timer is 32678 Hz, this is best for retro
;    style chiptune audio. 
;
; In the fast mode, everything sounds higher pitched. As such, this is mostly
; used for the custom instrument.
;
; And four `voices` are also supported:
;  - The 'additive saw' voice: 
;  - The 'multiplicative saw' voice
;  - The 'square wave' voice
;  - The custom instrument. 
;
;
;
; This file directs core/audio.inc, 


; Speed modes:
ch1_speed: DEFB 44h
ch2_speed: DEFB 44h




defc audio_state = audio_tick+1
defc audio_ptr = audio_tick@next_note_state+1

EXTERN ch1_timer
EXTERN ch2_timer



MACRO set_ch_state channel, state
    extern ch1_jp
    extern ch2_jp
    extern ch1@state
    extern ch2@state

    extern ch##channel##_##state

    ld a, ch##channel##_##state & 0xff
    ld (channel == 1 ? ch1_jp+1 : ch2_jp+1), a

endm

; Sets the timer for a channel, 
; Outputs: a=speed
MACRO set_timer channel, speed
    local timer_
    defc timer_ = channel == 1 ? ch1_timer : ch2_timer

    ld a, (channel == 1 ? ch1_speed : ch2_speed)
    out (timer_), a
    ld a, 3 ; loop + interupt 
    out (timer_ + 1), a

    ld a, speed
    out (timer_ + 2), a
endm

; Inputs: d = high timing, e = low timing
; channel should be 1 or 2
MACRO setup_square channel
    EXTERN ch1_square_down_ptr, ch1_square_up_ptr
    EXTERN ch2_square_down_ptr, ch2_square_up_ptr

    di
    set_timer channel, e ; Low ptr

    ; Set the square down value
    ; a is still the low timing
    ld (channel == 1 ? ch1_square_down_ptr : ch2_square_down_ptr), a

    ; Set the square up value
    ld a, d
    ld (channel == 1 ? ch1_square_up_ptr : ch2_square_up_ptr), a

    set_ch_state channel, square_state 
    ei
endm


; Opcodes for the note language
note_lookup:
    defw audio_tick@stop_song ; 00
    defw audio_tick@wait      ; 01 nn : wait ticks

; Speed options: Sets the speed for the next note
    defw audio_tick@ch1_fast  ; 02
    defw audio_tick@ch1_slow  ; 03

    defw audio_tick@ch2_fast  ; 04
    defw audio_tick@ch2_slow  ; 05

    defw audio_tick@ch1_stop  ; 06
    defw audio_tick@ch2_stop  ; 07

; Square wave
    defw audio_tick@ch1_square ; 08 n n : ticks high, ticks low
    defw audio_tick@ch2_square ; 09 n n

; Adative saw mode
    defw saw_ch1@saw1   ; 0a n n : addative constant, maximum
    defw saw_ch2@saw1   ; 0b n n

; Exponential saw mode
    defw saw_ch1@saw2  ; 0c n : maximum ticks
    defw saw_ch2@saw2  ; 0d n

; Exponential+1 saw mode
    defw saw_ch1@saw3 ; 0e n : maximum ticks
    defw saw_ch2@saw3 ; 0f n

; Square pitch sweeping. Activates whenever the game counter & activation mask is zero
    defw audio_tick@ch1_square_sweep ; 10 n n n : activation mask, high ticks added, low ticks added
    defw audio_tick@ch2_square_sweep ; 11 n n n



; This runs at ~60 hz before the greyscale tick, this does mean
; the audio changes based on user input, but this is a price I
; am willing to pay. 
; 
; This controls the audio
audio_tick:
    ; Self modifying code state machine
    jp @nothing


@nothing: ret
    

@next_note_state:
    ; Self modifying code: Music ptr
    ld de, $0000
@_next_note:

    ld a, (de)
    inc de

    add a, a

    ; hl = a + note_lookup
    add_nn_a_hl note_lookup

    ; hl = (hl)
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a

    jp (hl)


@wait_state:
    ld de, 0000
    ld hl, (_gray_count)

    or a \ sbc hl, de

    jr nc, @wait_expired

@wait_ch1_hook:
    jp @wait_ch2_hook
@wait_ch2_hook:
    jp @after_wait_ch2_hook
@after_wait_ch2_hook:
    ret

@wait_expired:
    ld hl, @next_note_state
    ld (audio_state), hl
    jp (hl)
    

@stop_song:
    ; No need to save audio ptr, since we are stoping the song
    ld hl, @nothing
    ld (audio_state), hl

    ; Reset speed
    ld a, $44 ; 32768 Hz
    ld (ch1_speed), a
    ld (ch2_speed), a

    ; Reset timers
    xor a
    out (ch1_timer), a
    out (ch2_timer), a

    ret


@wait:
    ex de, hl

    ld e, (hl)
    inc hl
    ld d, (hl)
    inc hl

    ld (audio_ptr), hl
    ld hl, (_gray_count)
    add hl, de
    ld (@wait_state+1), hl
    ret

@ch1_fast:
    ld a, $A0 ; cpu_freq/64
    ld (ch2_speed), a
    jp @_next_note
@ch1_slow:
    ld a, $44 ; 32768 Hz
    ld (ch2_speed), a
    jp @_next_note


@ch2_fast:
    ld a, $A0 ; cpu_freq/64
    ld (ch2_speed), a
    jp @_next_note
@ch2_slow:
    ld a, $44 ; 32768 Hz
    ld (ch2_speed), a
    jp @_next_note


audio_tick@ch1_stop:
    ; Turn the timer off
    xor a
    out (ch1_timer), a
    jp @_next_note

audio_tick@ch2_stop:
    ; Turn the timer off
    xor a
    out (ch2_timer), a
    jp @_next_note



macro _square channel
    ex de, hl
    
    ld d, (hl) \ inc hl
    ld e, (hl) \ inc hl

    setup_square channel

    ex de, hl
    jp @_next_note
endm


@ch1_square: _square 1 
@ch2_square: _square 2 


macro _square_sweep channel

endm

@ch1_square_sweep: 
@ch1_square_sweep: 

macro _saw style, max_ptr, chan
@saw1:
    di
    ld a, $C6 ; add a, n
    ld (style), a

    ld a, (de)  \ inc de
    ld (style+1), a
    jp @setup

@saw2: 
    di
    ld a, $B7 ; or a
    ld (style), a

    ld a, $17 ; rla
    ld (style+1), a
    jp @setup

@saw3:  
    di
    ld a, $00 ; nop
    ld (style), a

    ld a, $17 ; rla
    ld (style+1), a
    ; fall through
@setup:
    set_timer chan, 2 ; Set later by the saw wave

    ld a, (de) \ inc de
    ld (max_ptr), a

    set_ch_state chan, saw_state 
    jp audio_tick@_next_note
endm

extern ch1_saw_style, ch1_saw_maximum_ptr
saw_ch1: _saw ch1_saw_style, ch1_saw_maximum_ptr, 1

extern ch2_saw_style, ch2_saw_maximum_ptr
saw_ch2: _saw ch2_saw_style, ch2_saw_maximum_ptr,  2

