; Convert the full interleaved screen into all three grayscale phases, then
; swap the buffers used by the grayscale IRQ.

PUBLIC _greyscale_swap

; Old, simple pattern:
; M1 EQU 0xFF ^ %01101101
; M2 EQU 0xFF ^ %11011011
; M3 EQU 0xFF ^ %10110110

; More complex pattern:
M1 EQU %10010100   ; bits 7, 4, 2
M2 EQU %01001001   ; bits 6, 3, 0
M3 EQU %00100010   ; bits 5, 1




; Input: hl = buffer with light, dark bytes inter leaved
; Output: (de), de += 768*2*sign(instr) + 1
; P'*L + P * D = D ^ (P' & (L ^ D))
; 114 t-states
MACRO PIXEL_BASE mask1, mask2, mask3, instr
; b = D (dark pixel)
; c = L (light pixel)
    pop bc

; a = D (dark pixel)
    ld a, b

    ; b = L ^ D (shared across all three phases)
    xor c           ; 4
    ld b, a         ; 4

; Phase 1: apply mask1
    and 0xff^mask1   ; 7
    xor c            ; 4
    ld (de), a       ; 7


    ; Each phase buffer is 768 bytes apart, or 3*256
    ; As such, inc/dec x3 gets you to and thro
    instr d \ instr d \ instr d

    ld a, b
    and 0xff^mask2
    xor c
    ld (de), a


    instr d \ instr d \ instr d

    ld a, b
    and 0xff^mask3
    xor c
    ld (de), a

    inc de
endm


; These two macros should be used in pairs, as they cleanup
; after the other

; Ascending through phases (phase1 → phase2 → phase3)
MACRO PIXEL_UP mask1, mask2, mask3
    PIXEL_BASE mask1, mask2, mask3, inc
endm

; Mask args are reversed: decrementing through phases visits
; phase3→phase2→phase1, so mask3 applies first.
MACRO PIXEL_DOWN  mask1, mask2, mask3
    PIXEL_BASE mask3, mask2, mask1, dec
endm


; Inputs:
; hl = input buffer
; de = alt phase buffer 1
phase_component:
    ; PIXEL_BASE consumes BC, so keep the column counter in the shadow bank.
    exx
    ld b, 12
@col_loop:
    exx

    di
    ld (@sp_restore+1), sp
    ld sp, hl

; Phase generation goal: for each phase, we want a patern of
; Phase 1: 1 2 3
; Phase 2: 2 3 1
; Phase 3: 3 1 2

    PIXEL_UP M1, M2, M3
    PIXEL_DOWN M2, M3, M1
    PIXEL_UP M3, M1, M2
    PIXEL_DOWN M1, M2, M3


@cell_loop:
; Big code size, but this code is so hot it is needed
    REPT 2
        PIXEL_UP M2, M3, M1
        PIXEL_DOWN M3, M1, M2
        PIXEL_UP M1, M2, M3

        PIXEL_DOWN M2, M3, M1
        PIXEL_UP M3, M1, M2
        PIXEL_DOWN M1, M2, M3
    ENDR
    ; Check if the phase buffer%64 is zero, if so, we have looped
    ; back around to the next col
    ld a, 63
    and e
    jp nz, @cell_loop

    ld hl, sp ; Note: z88dk macro

    ; Self modifying code
@sp_restore: ld sp, 0000h
    ei

    exx
    dec b
    jp nz, @col_loop
    ret





;#[PROFILE_ROUTINE]
_greyscale_swap:
; =========Convert the individual buffers=========
    ld hl, _screen_buffer
    ld de, (alt_phase1)
    call phase_component

; =========Swap the buffer ptrs=========
    ; Total Swap: 236 t-states
    di ; Prevent potential race conditions
    ld hl, (alt_phase1)
    ld de, (current_phase1)
    ex de, hl
    ld (alt_phase1), hl
    ld (current_phase1), de
    ;
    ld hl, (alt_phase2)
    ld de, (current_phase2)
    ex de, hl
    ld (alt_phase2), hl
    ld (current_phase2), de

    ld hl, (alt_phase3)
    ld de, (current_phase3)
    ex de, hl
    ld (alt_phase3), hl
    ld (current_phase3), de
    ei

    ret
