


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




defc audio_channel_usage = audio_tick+1

; This runs at ~60 hz before the greyscale tick, this does mean
; the audio changes based on user input, but this is a price I
; am willing to pay. 
; 
; This controls the audio
audio_tick:
    ld a, 0

    ; No channels in use, move along
    or a \ ret z

