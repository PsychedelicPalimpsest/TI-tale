; Takes the greyscale screen bufer, and converts them into optimized phased buffers
; for the greyscale IRQ. Then, swaps the buffer used by the greyscale IRQ
; ~122,858 t-states


PUBLIC _greyscale_swap
SECTION code_engine

INCLUDE "core/asm_globals.def"

M1 EQU %01101101
M2 EQU %11011011
M3 EQU %10110110


; Input: hl = buffer with light, dark bytes inter leaved
; Output: (bc)
; 53 t-states
; 
; P'*L + P * D = D ^ (P; & (L ^ D))
MACRO PIXEL mask 
  ld a, (hl)      ; 7
  inc hl          ; 6

  xor (hl)        ; 7
  and 0xFF ^ mask ; 7
  xor (hl)        ; 7

  ld (bc), a       ; 7


  inc hl      ; 6
  inc bc      ; 6
endm

; 159 t-states
MACRO PIXELS_3 N1, N2, N3
  PIXEL N1
  PIXEL N2
  PIXEL N3
endm

; 636 t-states
MACRO PIXELS_12 N1, N2, N3
  PIXELS_3 N1, N2, N3
  PIXELS_3 N1, N2, N3

  PIXELS_3 N1, N2, N3
  PIXELS_3 N1, N2, N3
endm

MACRO PRE_SINGLE_SWAP
  ld hl, _screen_buffer ; 10
  ld d, $7              ; 7
endm


_greyscale_swap:
  ; Convert the individual buffers

  ; Phase 1: 40,866 t-states
  ld bc, (alt_phase1) ; 20
  PRE_SINGLE_SWAP     ; 17
  call grey_loop      ; 17 + 40,812


  ; Phase 2: 40,866 t-states
  ld bc, (alt_phase2) ; 20
  PRE_SINGLE_SWAP     ; 17
  call grey_loop231   ; 17 + 40,176
  PIXELS_12 M2, M3, M1; 636

; Phase 3: 40,866 t-states
  ld bc, (alt_phase3) ; 20
  PRE_SINGLE_SWAP     ; 17

  call grey_loop312   ; 17 + 39,540
  PIXELS_12 M2, M3, M1; 636
  PIXELS_12 M3, M1, M2; 636



  ; Swap the buffer ptrs
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


; Inputs:
; Expects PRE_SINGLE_SWAP to be set
; Caller is expected to do one PIXELS_12
;
; T-states: 40,812 (including ret)

  ; 
grey_loop:
  PIXELS_12 M1, M2, M3
grey_loop231:
  PIXELS_12 M2, M3, M1
grey_loop312:
  PIXELS_12 M3, M1, M2

  PIXELS_12 M1, M2, M3
  PIXELS_12 M2, M3, M1
  PIXELS_12 M3, M1, M2

  PIXELS_12 M1, M2, M3
  PIXELS_12 M2, M3, M1
  PIXELS_12 M3, M1, M2
 
  dec d              ; 4 t-states
  jp nz, grey_loop   ; 10 t-states

  PIXELS_12 M1, M2, M3
  ret
