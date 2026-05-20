; Audio format:
; There are two 'speed modes' the audio engine supports:
;  - The fast mode: Here, the timer is set to cpu_freq/64, this allows
;    'higher' quality output, at the cost of cpu.
;  - The slow mode: Where the timer is 32768 Hz, this is best for retro
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



; Public pointers used to control the current sound
PUBLIC audio_state
PUBLIC audio_ptr
defc audio_state = audio_tick+1
defc audio_ptr   = astate_next_note+1 



PUBLIC set_song
set_song:
    ld (audio_ptr), hl

    ld hl, astate_next_note
    ld (audio_state), hl
    ret




; Speed modes:
ch1_speed: DEFB 44h
ch2_speed: DEFB 44h

; Determines if you are permitted to sweep the additive constant. Bit 1 for channel 1, 2 for channel 2
can_sweep_saw_const: DEFB 0h


; Table for the note bytecode 
note_lookup:
    defw note_stop_song ; 00
    defw note_wait      ; 01 nn : wait ticks

; Speed options: Sets the speed for the next note
    defw note_ch1_fast  ; 02
    defw note_ch1_slow  ; 03

    defw note_ch2_fast  ; 04
    defw note_ch2_slow  ; 05

    defw note_ch1_stop  ; 06
    defw note_ch2_stop  ; 07

; Square wave
    defw note_ch1_square ; 08 n n : ticks high, ticks low
    defw note_ch2_square ; 09 n n

; Additive saw mode. Given an addative constant K, and desired freq F:
; max=1+sqrt(32768K / F)

    defw saw_ch1@saw1   ; 0a n n : additive constant, maximum
    defw saw_ch2@saw1   ; 0b n n

; Exponential saw mode
    defw saw_ch1@saw2  ; 0c n : maximum ticks
    defw saw_ch2@saw2  ; 0d n

; Exponential+1 saw mode
    defw saw_ch1@saw3 ; 0e n : maximum ticks
    defw saw_ch2@saw3 ; 0f n

; Square pitch sweeping. Activates whenever the grey counter & activation mask is zero
    defw note_ch1_square_sweep ; 10 n n n : activation mask, high ticks added, low ticks added
    defw note_ch2_square_sweep ; 11 n n n

; Saw pitch sweeping, Activates whenever the grey counter & activation mask is zero
    defw note_ch1_saw_sweep ; 12 n n n  : activation mask, maximum ticks added, addative constant added (ignored if in anything other then saw mode 1)
    defw note_ch2_saw_sweep ; 13 n n n



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
    EXTERN ch1_jp, ch2_jp
    EXTERN ch1@state, ch1@state

    EXTERN ch##channel##_##state

; No di is needed since it is an atomic operation
    ld a, ch##channel##_##state & 0xff
    ld (channel == 1 ? ch1_jp+1 : ch2_jp+1), a
endm

; Sets the timer for a channel
; Outputs: a=speed
MACRO set_timer channel, speed
    defl timer_ = (channel == 1 ? ch1_timer : ch2_timer)

    ld a, (channel == 1 ? ch1_speed : ch2_speed)
    out (timer_), a
    ld a, 3 ; loop + interrupt 
    out (1+timer_), a

    ld a, speed
    out (2+timer_), a
endm





; ---======Channel cleanup hook======---

macro _reset_cleanup channel
    ld hl, _no_cleanup
    ld (channel == 1 ? ch1_cleanup_hook: ch2_cleanup_hook), hl
endm
macro set_cleanup_nohook channel 
    ld hl, channel == 1 ? cleanup_ch1_nohook : cleanup_ch2_nohook
    ld (channel == 1 ? ch1_cleanup_hook : ch2_cleanup_hook), hl
endm

defc ch1_cleanup_hook = cleanup_ch1+1
defc ch2_cleanup_hook = cleanup_ch2+1

; These get called whenever a channels tone is changed
cleanup_ch1: 
    jp _no_cleanup
cleanup_ch2: 
    jp _no_cleanup


cleanup_ch1_nohook:
    _reset_cleanup 1

    ld hl, no_wait_hook
    ld (ch1_hook+1), hl
    ret
cleanup_ch2_nohook:
    _reset_cleanup 2
    ld hl, no_wait_hook
    ld (ch2_hook+1), hl
    ; Fall through for ret

_no_cleanup: ret




PUBLIC audio_tick
; This runs at ~60 hz before the greyscale tick, this does mean
; the audio changes based on user input, but this is a price I
; am willing to pay. 
; 
; This controls the audio, andis the main entry point for audio
audio_tick:
    ; Self modifying code state machine
    jp astate_nothing


;---===== Audio States====---

astate_nothing: ret

; This is where the next note is processed. A lot of things will jump to @after, which
; allows them to set their own de. 
astate_next_note:
    ; Self modifying code: Music ptr
    ld de, $0000
@after:

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

    ; Jp to the note
    jp (hl)

; Note calling conventions:
; Input: de is set to the audio pointer. 
; Output: Every note MUST do one of two things:
;         1. Jump to astate_next_note@after with de=the next note ptr
;            this is done when a note does not need to wait until the next state
;         2. Write the new audio ptr to astate_next_note+1, before returning


    no_wait_hook: ret

astate_wait:
    ; Self modifying code: gray count target value
    ld de, 0000
    ld hl, (_gray_count)

    ; sub hl, de
    or a \ sbc hl, de

    jr nc, wait_expired

    ch1_hook:
        call no_wait_hook

    ch2_hook:
        jp no_wait_hook

    wait_expired:
        ld hl, astate_next_note
        ld (audio_state), hl
        jp (hl)
    

;---======Note bytecode implmentations=====--- 

note_stop_song:
    ; No need to save audio ptr, since we are stoping the song
    ld hl, astate_nothing
    ld (audio_state), hl

    ; Reset speed
    ld a, $44 ; 32768 Hz
    ld (ch1_speed), a
    ld (ch2_speed), a

    ; Reset timers
    xor a
    out (ch1_timer), a
    out (ch2_timer), a
    ld (can_sweep_saw_const), a

    call cleanup_ch1
    jp   cleanup_ch2 ; Tail call


note_wait:
    ex de, hl

    ld e, (hl)
    inc hl
    ld d, (hl)
    inc hl

    ; Save updated audio ptr
    ld (audio_ptr), hl

    ld hl, astate_wait
    ld (audio_state), hl

    ld hl, (_gray_count)
    add hl, de
    ld (astate_wait+1), hl
    ret

note_ch1_fast:
    ld a, $A0 ; cpu_freq/64
    ld (ch1_speed), a

    jp astate_next_note@after
note_ch1_slow:
    ld a, $44 ; 32768 Hz
    ld (ch1_speed), a

    jp astate_next_note@after


note_ch2_fast:
    ld a, $A0 ; cpu_freq/64
    ld (ch2_speed), a

    jp astate_next_note@after
note_ch2_slow:
    ld a, $44 ; 32768 Hz
    ld (ch2_speed), a

    jp astate_next_note@after


note_ch1_stop:
    call cleanup_ch1

    ; Turn the timer off
    xor a
    out (ch1_timer), a
    jp astate_next_note@after

note_ch2_stop:
    call cleanup_ch2

    ; Turn the timer off
    xor a
    out (ch2_timer), a
    jp astate_next_note@after


; Inputs: d = high timing, e = low timing
; channel should be 1 or 2
MACRO setup_square channel
    EXTERN ch1_square_down_ptr, ch1_square_up_ptr
    EXTERN ch2_square_down_ptr, ch2_square_up_ptr

    di
    set_timer channel, e ; Low period

    ; Set the square down value
    ; a is still the low timing
    ld (channel == 1 ? ch1_square_down_ptr : ch2_square_down_ptr), a

    ; Set the square up value
    ld a, d
    ld (channel == 1 ? ch1_square_up_ptr : ch2_square_up_ptr), a

    set_ch_state channel, square_state

    ei
endm


; Generic for both channels
macro _square channel
    call channel == 1 ? cleanup_ch1 : cleanup_ch2

    ex de, hl
    
    ld d, (hl) \ inc hl
    ld e, (hl) \ inc hl

    setup_square channel

    ex de, hl
    jp astate_next_note@after
endm


note_ch1_square: _square 1 
note_ch2_square: _square 2 

macro _square_sweep channel
; Set the cleanup code
    set_cleanup_nohook channel

    ld hl, @wait_hook
    ld (channel == 1 ? ch1_hook+1 : ch2_hook+1), hl

; Set the activation mask
    ld a, (de) \ inc de
    ld (@wait_hook_mask+1), a

; High ticks added
    ld a, (de) \ inc de
    ld (@wait_hook_up_mod+1), a

; Low ticks added
    ld a, (de) \ inc de
    ld (@wait_hook_down_mod+1), a



    jp astate_next_note@after


@wait_hook:
    ld a, (_gray_count) ; Low byte of grey count

    ; Self modifying code
@wait_hook_mask: and 00h
    ret nz

    defl up_ptr = channel == 1 ? ch1_square_up_ptr : ch2_square_up_ptr
    ld a, (up_ptr)
@wait_hook_up_mod: add 00h
    ld (up_ptr), a



    defl down_ptr = channel == 1 ? ch1_square_down_ptr : ch2_square_down_ptr
    ld a, (down_ptr)
@wait_hook_down_mod: add 00h
    ld (down_ptr), a


    ret
endm

note_ch1_square_sweep: _square_sweep 1
note_ch2_square_sweep: _square_sweep 2


macro _saw style, max_ptr1, max_ptr2, chan
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
; Currently interupts are disabled

    set_timer chan, 2 ; Set later by the saw wave

    call chan == 1 ? cleanup_ch1 : cleanup_ch2

    ld a, (de) \ inc de
    ld (max_ptr1), a
    ld (max_ptr2), a

    set_ch_state chan, saw_state 

    ei

    jp astate_next_note@after
endm

EXTERN ch1_saw_style, ch1_saw_maximum_ptr1, ch1_saw_maximum_ptr2
saw_ch1: _saw ch1_saw_style, ch1_saw_maximum_ptr1, ch1_saw_maximum_ptr2, 1

EXTERN ch2_saw_style, ch2_saw_maximum_ptr1, ch2_saw_maximum_ptr2
saw_ch2: _saw ch2_saw_style, ch2_saw_maximum_ptr1, ch2_saw_maximum_ptr2,  2


macro _saw_sweep channel
; Set the cleanup code
    set_cleanup_nohook channel

    ld hl, @wait_hook
    ld (channel == 1 ? ch1_hook+1 : ch2_hook+1), hl

; Set the activation mask
    ld a, (de) \ inc de
    ld (@wait_hook_mask+1), a

; Maximum ticks added
    ld a, (de) \ inc de
    ld (@wait_hook_max_mod+1), a

; Additive const ticks added
    ld a, (de) \ inc de
    ld (@wait_hook_const_mod+1), a



    jp astate_next_note@after

@wait_hook:
    ld a, (_gray_count) ; Low byte of grey count

    ; Self modifying code
@wait_hook_mask: and 00h
    ret nz 

    defl max_ptr1 = channel == 1 ? ch1_saw_maximum_ptr1 : ch2_saw_maximum_ptr1
    defl max_ptr2 = channel == 1 ? ch1_saw_maximum_ptr2 : ch2_saw_maximum_ptr2
    ld a, (max_ptr1)
@wait_hook_max_mod: add 00h
    ld (max_ptr1), a
    ld (max_ptr2), a

    ld a, (can_sweep_saw_const)
    and 1 << channel

; If the saw style is anything other then style 1, do not modify the addative constant
    ret z

    defl style_ptr = (channel == 1 ? ch1_saw_style : ch2_saw_style)
    ld a, (style_ptr+1)
@wait_hook_const_mod: add 00h
    ld (style_ptr+1), a

    ret
endm

note_ch1_saw_sweep: _saw_sweep 1
note_ch2_saw_sweep: _saw_sweep 2
