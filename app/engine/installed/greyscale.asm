; Greyscale system. This code runs from interrupt.asm at approx 60 Hz, but
; is adjustable by the user to adjust flickering issues. 
; 
; This code is highly optimized, and will only run on post ~2007 calculators
; due to the lack of delay between LCD writes. 



PUBLIC xmax, ymax

defc xmax = 96d
defc ymax = 64d


PUBLIC clock_count_1, clock_count_2, clock_count_3, clock_count_4


; This is the main counter for the game. It is measured in 2X the ticks of the 32768Hz clock, or 2**16.
; this means that count_3 is the number of secounds since the game has started! And you can use 
; the pair (count_2, count_3) as a 16 bit fixed point number of secounds. This has a maximum of 
; 194 days of range.
;
; Please note: count_1 is not very percise!
defc clock_count_1 = greyc_12+1
defc clock_count_2 = greyc_12+2
defc clock_count_3 = greyc_3 +1
defc clock_count_4 = greyc_4 +1
defc clock_count_5 = greyc_5 +1

PUBLIC _grey_count, grey_timingX6

defc grey_timingX6 = greyc_x6+1

defc _grey_count=greyscale_tick+1

; The long count, this is only rarly hit (once per secound). 
    greyc_3: 
        ld a, 00h
        add 1
        ld (greyc_3+1), a
        ld (_scount+1), a  ; High byte of secounds counter

        jp nc, after_grey_count

; Every 256 secounds
    greyc_4: 
        ld a, 00h
        add 1
        ld (greyc_4+1), a

        jp nc, after_grey_count

; Every 256*256 secounds
    greyc_5: 
        ld a, 00h
        add 1
        ld (greyc_5+1), a

        jp after_grey_count

; GREYSCALE ENTRY POINT:
greyscale_tick:
    ld hl, 0
    inc hl
    ld (_grey_count), hl

    ; Call only on even ticks, so ~60/2 Hz
    bit 0, l
    call nz, engine_tick

greyc_12: ld de, 0000h  ; High percision timer
greyc_x6: ld hl, 0000h  ; How much ticks as passed in a hypothetical 64KHz clock since the last greyscale tick

    add hl, de

    ld (greyc_12+1), hl

    ld a, h
    ld (_scount), a     ; Low byte of secounds counter

    jr c, greyc_3         ; Only happens once per secound
after_grey_count:



    ld a, (phase)
    or a
    jp z, phase0

    dec a
    jp z, phase1

    ; a=2
    xor a
    ld (phase), a
    ld hl, (current_phase1)
    jp after_phases
phase1:
    ; a=1
    ld a, $2
    ld (phase), a
    ld hl, (current_phase2)
    jp after_phases
phase0:
    ; a=0
    inc a
    ld (phase), a
    ld hl, (current_phase3)
    ; Fall through
  
after_phases:
    
    ld a, $1 ; 8bit mode
    out (10h), a

    ld a, $5 ; Move up to down 
    out (10h), a

    
    ld d, 20h  ; d = row + 20h

    ld c, 11h  ; Port to write to (for outi),  
row_loop:
    ld a, d ; Set col (saved in d)
    out (10h), a


    ld a, 80h ; Go to beginning of row
    out (10h), a

; Unrolled write loop (64 entries)
REPT ymax
    outi ; out (c), (hl) \ inc (hl), dec b
endr



    inc d
    ld a, 20h + 12 -1
    sub a, d
    jp nc, row_loop

    ret


phase: DEFB 0
