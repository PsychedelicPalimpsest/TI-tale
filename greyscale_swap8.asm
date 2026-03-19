PUBLIC _greyscale_swap

extern _working_w4          ; weight-4 source buffer
extern _working_w2          ; weight-2 source buffer
extern _working_w1          ; weight-1 source buffer

extern current_phase1
extern current_phase2
extern current_phase3
extern current_phase4
extern current_phase5
extern current_phase6
extern current_phase7

extern alt_phase1
extern alt_phase2
extern alt_phase3
extern alt_phase4
extern alt_phase5
extern alt_phase6
extern alt_phase7

; ============================================================
; Shade encoding:
;   shade = 4*(W4 bit) + 2*(W2 bit) + 1*(W1 bit)  =>  0..7
;
; Shade 0 = white (pixel never lit)
; Shade 7 = black (pixel lit in all 7 phases)
; ============================================================

P0_M4 EQU %00011110
P0_M2 EQU %01100000
P0_M1 EQU %10000001

P1_M4 EQU %00111100
P1_M2 EQU %11000001
P1_M1 EQU %00000010

P2_M4 EQU %01111000
P2_M2 EQU %10000011
P2_M1 EQU %00000100

P3_M4 EQU %11110001
P3_M2 EQU %00000110
P3_M1 EQU %00001000

P4_M4 EQU %11100011
P4_M2 EQU %00001100
P4_M1 EQU %00010000

P5_M4 EQU %11000111
P5_M2 EQU %00011000
P5_M1 EQU %00100000

P6_M4 EQU %10001111
P6_M2 EQU %00110000
P6_M1 EQU %01000000

; ============================================================
; PIXEL3 mask4, mask2, mask1
;   out = (W4 & mask4) | (W2 & mask2) | (W1 & mask1)
;   Writes one output byte and advances all four pointers.
;
; Register contract (set up by PRE_PHASE / caller):
;   DE   = W4 source ptr  (main)
;   HL   = W2 source ptr  (main)
;   HL'  = W1 source ptr  (shadow)
;   IY   = output ptr
;   B'   = row counter    (shadow, untouched here)
;   C    = scratch
;
; Clobbers: A, C, F, DE, HL, HL', IY
; T-states: 121
; ============================================================
MACRO PIXEL3 mask4, mask2, mask1
  ld a, (de)          ; 7
  and mask4           ; 7
  ld c, a             ; 4
  ld a, (hl)          ; 7
  and mask2           ; 7
  or c                ; 4
  ld c, a             ; 4
  exx                 ; 4   -- HL now points to W1
  ld a, (hl)          ; 7
  exx                 ; 4   -- HL back to W2
  and mask1           ; 7
  or c                ; 4
  ld (iy+0), a        ; 19
  inc de              ; 6
  inc hl              ; 6
  exx                 ; 4
  inc hl              ; 6   -- advance W1 ptr
  exx                 ; 4
  inc iy              ; 10
endm                  ; Total: 121 T-states

; ============================================================
; PIXELS_ROW m4, m2, m1
;   One full 12-byte screen row.
;   T-states: 12 * 121 = 1452
; ============================================================
MACRO PIXELS_ROW m4, m2, m1
  PIXEL3 m4, m2, m1
  PIXEL3 m4, m2, m1
  PIXEL3 m4, m2, m1
  PIXEL3 m4, m2, m1
  PIXEL3 m4, m2, m1
  PIXEL3 m4, m2, m1
  PIXEL3 m4, m2, m1
  PIXEL3 m4, m2, m1
  PIXEL3 m4, m2, m1
  PIXEL3 m4, m2, m1
  PIXEL3 m4, m2, m1
  PIXEL3 m4, m2, m1
endm

; ============================================================
; PRE_PHASE
;   Loads source pointers and arms the row counter.
;   IY (output ptr) must be loaded by the caller first.
;
;   After macro: DE=_working_w4, HL=_working_w2,
;                HL'=_working_w1, B'=64
;   T-states: 45
; ============================================================
MACRO PRE_PHASE
  ld hl, _working_w2  ; 10
  ld de, _working_w4  ; 10
  exx                 ; 4
  ld hl, _working_w1  ; 10
  ld b, 64            ; 7   -- 64 rows * 12 bytes = 768 bytes
  exx                 ; 4
endm                  ; Total: 45 T-states

; ============================================================
; _greyscale_swap
;   Builds 7 phase buffers from the three 8-shade working
;   buffers, then atomically swaps the alt/current pointers.
;
;   Clobbers: AF, AF', BC, BC', DE, DE', HL, HL', IY
;   Preserves: IX (saved/restored for ABI compatibility)
;   T-states: ~661,500
; ============================================================
_greyscale_swap:
  push iy
  push ix

  ; Phase 0 -- 94,353 T-states
  ld iy, (alt_phase1)  ; 20
  PRE_PHASE            ; 45
  call grey_loop_p0    ; 17 + 94,326

  ; Phase 1
  ld iy, (alt_phase2)
  PRE_PHASE
  call grey_loop_p1

  ; Phase 2
  ld iy, (alt_phase3)
  PRE_PHASE
  call grey_loop_p2

  ; Phase 3
  ld iy, (alt_phase4)
  PRE_PHASE
  call grey_loop_p3

  ; Phase 4
  ld iy, (alt_phase5)
  PRE_PHASE
  call grey_loop_p4

  ; Phase 5
  ld iy, (alt_phase6)
  PRE_PHASE
  call grey_loop_p5

  ; Phase 6
  ld iy, (alt_phase7)
  PRE_PHASE
  call grey_loop_p6

  ; --- Atomically swap all 7 alt/current pointer pairs ---
  ; ~392 T-states (7 * 56)
  di

  ld hl, (alt_phase1)
  ld de, (current_phase1)
  ex de, hl
  ld (alt_phase1), hl
  ld (current_phase1), de

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

  ld hl, (alt_phase4)
  ld de, (current_phase4)
  ex de, hl
  ld (alt_phase4), hl
  ld (current_phase4), de

  ld hl, (alt_phase5)
  ld de, (current_phase5)
  ex de, hl
  ld (alt_phase5), hl
  ld (current_phase5), de

  ld hl, (alt_phase6)
  ld de, (current_phase6)
  ex de, hl
  ld (alt_phase6), hl
  ld (current_phase6), de

  ld hl, (alt_phase7)
  ld de, (current_phase7)
  ex de, hl
  ld (alt_phase7), hl
  ld (current_phase7), de

  ei

  pop ix
  pop iy
  ret

; ============================================================
; Phase loop subroutines
;
;   Inputs:  IY=output ptr, HL=W2, DE=W4, HL'=W1, B'=64
;
;   Each PIXEL3 issues two balanced exx's, so PIXELS_ROW
;   always returns in main-register mode, leaving B' safely
;   accessible for the dec/jp overhead.
;
;   T-states per subroutine:
;     64 * (1452 + 4 + 4 + 4 + 10) + 10 = 94,346
; ============================================================

grey_loop_p0:
grey_loop_p0_row:
  PIXELS_ROW P0_M4, P0_M2, P0_M1
  exx                       ; 4  -- expose B'
  dec b                     ; 4
  exx                       ; 4  -- restore main regs
  jp nz, grey_loop_p0_row   ; 10
  ret                       ; 10

grey_loop_p1:
grey_loop_p1_row:
  PIXELS_ROW P1_M4, P1_M2, P1_M1
  exx
  dec b
  exx
  jp nz, grey_loop_p1_row
  ret

grey_loop_p2:
grey_loop_p2_row:
  PIXELS_ROW P2_M4, P2_M2, P2_M1
  exx
  dec b
  exx
  jp nz, grey_loop_p2_row
  ret

grey_loop_p3:
grey_loop_p3_row:
  PIXELS_ROW P3_M4, P3_M2, P3_M1
  exx
  dec b
  exx
  jp nz, grey_loop_p3_row
  ret

grey_loop_p4:
grey_loop_p4_row:
  PIXELS_ROW P4_M4, P4_M2, P4_M1
  exx
  dec b
  exx
  jp nz, grey_loop_p4_row
  ret

grey_loop_p5:
grey_loop_p5_row:
  PIXELS_ROW P5_M4, P5_M2, P5_M1
  exx
  dec b
  exx
  jp nz, grey_loop_p5_row
  ret

grey_loop_p6:
grey_loop_p6_row:
  PIXELS_ROW P6_M4, P6_M2, P6_M1
  exx
  dec b
  exx
  jp nz, grey_loop_p6_row
  ret
