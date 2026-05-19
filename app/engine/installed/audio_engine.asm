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
; This file directs core/audio.inc, ie the tone currently being produced. 





; Speed modes:
ch1_speed: DEFB 44h
ch2_speed: DEFB 44h

; Determines if you are permitted to sweep the adative constant. Bit 0 for channel 1, 1 for channel 2
can_sweep_saw_const: DEFB 0h

; Public pointers used to control the current sound
PUBLIC audio_state
PUBLIC audio_ptr
defc audio_state = audio_tick+1
defc audio_ptr = audio_tick@next_note_state+1



; The on/off port for timer for each channel.
; See: https://web.archive.org/web/20200804061732/https://wikiti.brandonw.net/index.php?title=83Plus:Ports:30
; +0 is on/off, with the value set determining the timer used
; +1 is the loop control port, should only be set to $3
; +2 is the loop counter
EXTERN ch1_timer
EXTERN ch2_timer



; Sets the value of the audio.inc state machine for a given channel. 
; channel should be 1 or 2, and state is the symbol after the 
; chN_ part
; EX: 
;   set_ch_state 1, square_state
MACRO set_ch_state channel, state
    extern ch1_jp
    extern ch2_jp
    extern ch1@state
    extern ch2@state

    extern ch##channel##_##state

; No di is needed since it is an atomic operation
    ld a, ch##channel##_##state & 0xff
    ld (channel == 1 ? ch1_jp+1 : ch2_jp+1), a

endm

; Sets the timer for a channel
; Outputs: a=speed, enables interupts
MACRO set_timer channel, speed
    defl timer_ = channel == 1 ? ch1_timer : ch2_timer

    di

    ld a, (channel == 1 ? ch1_speed : ch2_speed)
    out (timer_), a
    ld a, 3 ; loop + interupt 
    out (timer_ + 1), a

    ld a, speed
    out (timer_ + 2), a

    ei
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

    set_ch_state channel, square_state  ; Enables interupts
endm


; Opcodes for the note bytecode 
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

; Square pitch sweeping. Activates whenever the grey counter & activation mask is zero
    defw audio_tick@ch1_square_sweep ; 10 n n n : activation mask, high ticks added, low ticks added
    defw audio_tick@ch2_square_sweep ; 11 n n n

; Saw pitch sweeping, Activates whenever the grey counter & activation mask is zero
    defw audio_tick@ch1_saw_sweep ; 10 n n n  : activation mask, maximum ticks added, addative constant added (ignored if in anything other then saw mode 1)
    defw audio_tick@ch2_saw_sweep ; 11 n n n




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


; Channel cleanup hooks:
macro _reset_cleanup channel
    ld hl, audio_tick@_no_cleanup
    ld (channel == 1 ? ch1_cleanup_hook: ch2_cleanup_hook), hl
endm

defc ch1_cleanup_hook = @cleanup_ch1+1
defc ch2_cleanup_hook = @cleanup_ch2+1

; These get called whenever a channels tone is changed
@cleanup_ch1: 
    jp @_no_cleanup
@cleanup_ch2: 
    jp @_no_cleanup

@cleanup_ch1_nohook:
    _reset_cleanup 1
    ld hl, @wait_ch2_hook
    ld (@wait_ch1_hook+1), hl
    ret
@cleanup_ch2_nohook:
    _reset_cleanup 2
    ld hl, @after_wait_ch2_hook
    ld (@wait_ch2_hook+1), hl
    ret


@_no_cleanup: ret

@wait_state:
    ; Self modifying code: gray count target value
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

    call @cleanup_ch1
    jp   @cleanup_ch2


@wait:
    ex de, hl

    ld e, (hl)
    inc hl
    ld d, (hl)
    inc hl

    ; Save updated audio ptr
    ld (audio_ptr), hl

    ld hl, (_gray_count)
    add hl, de
    ld (@wait_state+1), hl
    ret

@ch1_fast:
    ld a, $A0 ; cpu_freq/64
    ld (ch1_speed), a

    call @cleanup_ch1
    jp @_next_note
@ch1_slow:
    ld a, $44 ; 32768 Hz
    ld (ch1_speed), a

    call @cleanup_ch1
    jp @_next_note


@ch2_fast:
    ld a, $A0 ; cpu_freq/64
    ld (ch2_speed), a

    call @cleanup_ch2
    jp @_next_note
@ch2_slow:
    ld a, $44 ; 32768 Hz
    ld (ch2_speed), a

    call @cleanup_ch2
    jp @_next_note


@ch1_stop:
    call @cleanup_ch1

    ; Turn the timer off
    xor a
    out (ch1_timer), a
    jp @_next_note

@ch2_stop:
    call @cleanup_ch2

    ; Turn the timer off
    xor a
    out (ch2_timer), a
    jp @_next_note



macro _square channel
    call channel == 1 ? @cleanup_ch1 : @cleanup_ch1

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
    local @wait_hook, @wait_hook_mask
    local @wait_hook_up_mod, @wait_hook_down_mod

; Set the cleanup code
    ld hl, channel == 1 ? @cleanup_ch1_nohook  : @cleanup_ch2_nohook
    ld (channel == 1 ? ch1_cleanup_hook : ch2_cleanup_hook), hl

; Set the activation mask
    ld a, (de) \ inc de
    ld (@wait_hook_mask+1), a

; High ticks added
    ld a, (de) \ inc de
    ld (@wait_hook_up_mod+1), a

; Low ticks added
    ld a, (de) \ inc de
    ld (@wait_hook_down_mod+1), a

    jp @_next_note


    defl return_jp = channel == 1 ? @wait_ch2_hook : @after_wait_ch2_hook
@wait_hook:
    ld a, (_gray_count) ; Low byte of grey count

    ; Self modifying code
@wait_hook_mask: cp 00h
    jp nz, return_jp

    defl up_ptr = channel == 1 ? ch1_square_up_ptr : ch2_square_up_ptr
    ld a, (up_ptr)
@wait_hook_up_mod: add 00h
    ld (up_ptr), a



    defl down_ptr = channel == 1 ? ch1_square_down_ptr : ch2_square_down_ptr
    ld a, (down_ptr)
@wait_hook_down_mod: add 00h
    ld (down_ptr), a


    jp return_jp
endm

@ch1_square_sweep: _square_sweep 1
@ch2_square_sweep: _square_sweep 2




macro _saw style, max_ptr, chan
@saw1:
    di
    ld a, $C6 ; add a, n
    ld (style), a

    ld a, (de)  \ inc de
    ld (style+1), a

; Set the sweep enable bit
    ld a, (can_sweep_saw_const)
    or 1 << chan
    ld (can_sweep_saw_const), a


    jp @setup

@saw2: 
    di
    ld a, $B7 ; or a
    ld (style), a

    ld a, $17 ; rla
    ld (style+1), a

; Reset the sweep enable bit
    ld a, (can_sweep_saw_const)
    and ~(1 << chan)
    ld (can_sweep_saw_const), a

    jp @setup

@saw3:  
    di
    ld a, $00 ; nop
    ld (style), a

    ld a, $17 ; rla
    ld (style+1), a

; Reset the sweep enable bit
    ld a, (can_sweep_saw_const)
    and ~(1 << chan)
    ld (can_sweep_saw_const), a

    ; fall through
@setup:
    call chan == 1 ? audio_tick@cleanup_ch1 : audio_tick@cleanup_ch2
    set_timer chan, 2 ; Set later by the saw wave

    ld a, (de) \ inc de
    ld (max_ptr), a

    set_ch_state chan, saw_state 

    ei
    jp audio_tick@_next_note
endm

extern ch1_saw_style, ch1_saw_maximum_ptr
saw_ch1: _saw ch1_saw_style, ch1_saw_maximum_ptr, 1

extern ch2_saw_style, ch2_saw_maximum_ptr
saw_ch2: _saw ch2_saw_style, ch2_saw_maximum_ptr,  2


macro _saw_sweep channel
    local @wait_hook, @wait_hook_mask
    local @wait_hook_max_mod, @wait_hook_const_mod

; Set the cleanup code
    ld hl, channel == 1 ? audio_tick@cleanup_ch1_nohook  : audio_tick@cleanup_ch2_nohook
    ld (channel == 1 ? ch1_cleanup_hook : ch2_cleanup_hook), hl

; Set the activation mask
    ld a, (de) \ inc de
    ld (@wait_hook_mask+1), a

; Maximum ticks added
    ld a, (de) \ inc de
    ld (@wait_hook_max_mod+1), a

; Addative const ticks added
    ld a, (de) \ inc de
    ld (@wait_hook_const_mod+1), a

    jp audio_tick@_next_note


    defl return_jp = channel == 1 ? audio_tick@wait_ch2_hook : audio_tick@after_wait_ch2_hook
@wait_hook:
    ld a, (_gray_count) ; Low byte of grey count

    ; Self modifying code
@wait_hook_mask: cp 00h
    jp nz, return_jp

    defl max_ptr = channel == 1 ? ch1_saw_maximum_ptr : ch2_saw_maximum_ptr
    ld a, (max_ptr)
@wait_hook_max_mod: add 00h
    ld (max_ptr), a

    ld a, (can_sweep_saw_const)
    and 1 << channel

; If the saw style is anything other then style 1, do not modifying the addative constant
    jp z, return_jp

    defl style_ptr = channel == 1 ? ch1_saw_style : ch2_saw_style
    ld a, (style_ptr+1)
@wait_hook_const_mod: add 00h
    ld (style_ptr+1), a


    jp return_jp
   

endm

audio_tick@ch1_saw_sweep: _saw_sweep 1
audio_tick@ch2_saw_sweep: _saw_sweep 2
