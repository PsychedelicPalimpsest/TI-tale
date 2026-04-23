; Takes the greyscale screen bufer, and converts them into optimized phased buffers
; for the greyscale IRQ. Then, swaps the buffer used by the greyscale IRQ
;
; NOTE: Although designed for mode 7 lcd drawing (left to right), mode 5
;       works perfectly fine! (Although the dirty col system gets weird)
;
; T-State Analysis:
;   T_total = 416 + 7502*D + 3395*C + 122*S
;   where D+C+S = 12 columns
;
;   Min  (D=0,  C=0,  S=12): 1,880   T-states (Static screen)
;   Max  (D=12, C=0,  S=0):  90,440  T-states (Full redraw)
;   Mean (D=4,  C=4,  S=4):  44,076  T-states (Average motion)

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
  ; Register allocation:
  ; hl' = dirty cols
  ; de' = prev dirty cosl
  ; b'  = col loop counter 
  ; 
  ; hl = input buffer
  ; de = first output phase buffer

  ; bc under copy = cell loop counters
  ; 
MACRO end_loop
  exx
  dec b
  jp nz, @col_loop
  ret
endm

  exx
  ld hl, (previous_dirty_cols)
  ex de, hl
  ld hl, (dirty_cols)

  ld b, 12
@col_loop:
; Advance the diry bitset, if the carry is set,
; we know that col is dirty
  add hl, hl
  jp nc, @non_diry_copy

; Advance the last frames dirty bitset, carry is not used
  ex de, hl
  add hl, hl
  ex de, hl
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


@dirty_cell_loop:
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
  jp nz, @dirty_cell_loop

  ld hl, sp ; Note: z88dk macro

  ; Self modifying code
@sp_restore: ld sp, 0000h
  ei

@post_pixels:
  end_loop ; handles dec and ret

@non_diry_copy: 

; Advance last frame's dirty bitset
  ex de, hl
  add hl, hl
  ex de, hl
  exx

; If the col is was dirty last frame, no need to copy it, as
; it is still in this buffer. 
  jp nc, @nondirty_end_of_loop
  
  push hl

; hl = the phase buffer currently being displayed
; de = the alt buffer we are copying too

; Flip the bit required to get to and from the alt buffers.
; They are exactly $1000 bytes apart, so this works

  ld a, d
  xor (grey_phase1_buff^grey_phase1_altbuff) >> 8  

  ld h, a
  ld l, e

  ld bc, 64
@nondirty_copy_loop1:
  ldi \ ldi \ ldi \ ldi
  ldi \ ldi \ ldi \ ldi
  ldi \ ldi \ ldi \ ldi
  ldi \ ldi \ ldi \ ldi

  ; The P/V flag is reset (PO) if BC == 0 
  jp pe, @nondirty_copy_loop1

; Get to next phase (phase 2)
  inc h \ inc h \ inc h
  inc d \ inc d \ inc d

; Now, we are at the next phase + 64, to save cycles, we can use the ldd
; instruction, which copies backward (decs de, hl, bc)

  ld bc, 64
@nondirty_copy_loop2:
  ldd \ ldd \ ldd \ ldd
  ldd \ ldd \ ldd \ ldd
  ldd \ ldd \ ldd \ ldd
  ldd \ ldd \ ldd \ ldd

  jp pe, @nondirty_copy_loop2

; Get to next phase (phase 3)
  inc h \ inc h \ inc h
  inc d \ inc d \ inc d

  ld bc, 64
@nondirty_copy_loop3:
  ldi \ ldi \ ldi \ ldi
  ldi \ ldi \ ldi \ ldi
  ldi \ ldi \ ldi \ ldi
  ldi \ ldi \ ldi \ ldi

  ; The P/V flag is reset (PO) if BC == 0 
  jp pe, @nondirty_copy_loop3

; Get d back to the correct phase. 
; NOTE: due to the last round of LDIs, it is +64 already
  ld a, -6
  add d
  ld d, a

  pop hl

; bc = 128 (b = 0 from ldi loop)
  ld c, 128
  add hl, bc
  end_loop ; Handles jp and ret
@nondirty_end_of_loop:
  ld bc, 128
  add hl, bc

  ex de, hl

  ld bc, 64
  add hl, bc

  ex de, hl
  end_loop ; Handles jp and ret






_greyscale_swap:
; =========Convert the individual buffers=========
  ld hl, _screen_buffer
  ld de, (alt_phase1)
  call phase_component

; Save old dirty cols
  ld hl, (dirty_cols)
  ld (previous_dirty_cols), hl

; Mark entire frame non-dirty
  ld hl, 0
  ld (dirty_cols), hl


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
