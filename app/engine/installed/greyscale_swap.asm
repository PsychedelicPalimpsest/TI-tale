; Takes the greyscale screen bufer, and converts them into optimized phased buffers
; for the greyscale IRQ. Then, swaps the buffer used by the greyscale IRQ
; ~122,858 t-states
;
; NOTE: Although designed for mode 7 lcd drawing (left to right), mode 5
;       works perfectly fine! (Although the dirty col system gets weird)


PUBLIC _greyscale_swap

; Xor'd to simplify bit shuffle logic
M1 EQU 0xFF ^ %01101101
M2 EQU 0xFF ^ %11011011
M3 EQU 0xFF ^ %10110110

; Input: hl = buffer with light, dark bytes inter leaved
; Output: (de)
; 53 t-states
; 
; P'*L + P * D = D ^ (P' & (L ^ D))
MACRO PIXEL mask 
  ld a, (hl)      ; 7
  inc hl          ; 6

  xor (hl)        ; 7
  and mask        ; 7
  xor (hl)        ; 7

  ld (de), a       ; 7


  inc hl      ; 6
  inc de      ; 6
endm





MACRO init_phase known_current_buff, known_alt_buff, phase_mode
  ld a, (known_current_buff >> 8) ^ (known_alt_buff >> 8)
  ld (phase_component@phase_swap_xor + 1), a

  if 1==phase_mode
    ; do not do any pre pixels
    ld hl, phase_component@dirty_cell_loop
    ld (phase_component@pre_pixel_jp + 1), hl

    ; Do a full set of post pixels
    REPTI jp_label, phase_component@post_pix1_jp, phase_component@post_pix2_jp
      ld hl, jp_label+3
      ld (jp_label+1), hl
    endr
  endif
  if 2==phase_mode
    ; Do a single pre pixel, making the pattern 3 - 1 2 3
    ld hl, phase_component@pre_pix3
    ld (phase_component@pre_pixel_jp + 1), hl

    ; Do the first two post pixels making the pattern ... 1 2 3 - 2 3
    ld hl, phase_component@post_pix1_jp + 3
    ld (phase_component@post_pix1_jp+1), hl

    ld hl, phase_component@post_pixels
    ld (phase_component@post_pix2_jp+1), hl
  endif

  if 3==phase_mode
    ; Do two pre pixels, making the pattern 2 3 - 1 2 3
    ld hl, phase_component@pre_pix2
    ld (phase_component@pre_pixel_jp + 1), hl

    ; Do only one more pixel, making the pattern ... 1 2 3 - 1
    ld hl, phase_component@post_pixels
    ld (phase_component@post_pix1_jp+1), hl
  endif
endm


; Inputs:
; hl = input buffer
; de = alt phase buffer
phase_component:
  ; Register allocation:
  ; hl' = dirty cols
  ; b'  = col loop counter 
  ; 
  ; hl = input buffer
  ; de = output phase buffer
  ; bc = cell loop counters



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

  ; todo: old dirty
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

 ; The screen is 64 tall. (64-3) / 12 = 5, r=1
  ld b, 5

; Phase generation goal: for each phase, we want a patern of
; Phase 1: 1 2 3
; Phase 2: 3 1 2
; Phase 3: 2 3 1
; So, we leave 4 pixels to be done outside of the loop, and patch
; the jumps to adjust which ones we are doing at a given phase.


  ; Self modifying code: Patches what offset is used into the phase pattern
  @pre_pixel_jp: jp 0000h
; @pre_pix1:
;  PIXEL M1 
@pre_pix2:
  PIXEL M2 
@pre_pix3:
  PIXEL M3 
@dirty_cell_loop:
REPT 4
  PIXEL M1 
  PIXEL M2 
  PIXEL M3 
endr
  djnz @dirty_cell_loop



; Post pixels, each one of these jumps is modified before being ran
  PIXEL M1 
@post_pix1_jp: jp @post_pixels

  PIXEL M2 
@post_pix2_jp: jp @post_pixels

  PIXEL M3 
@post_pixels:
  end_loop ; handles dec and ret

@non_diry_copy: 
  push hl

; Advance last frame's dirty bitset
  ex de, hl
  add hl, hl
  ex de, hl
; If the col is not dirty last frame, no need to copy it, as
; it is still in this buffer. 
  jp nc, @nondirty_end_of_loop


; hl = current phase buffer (in use)
  ld a, d
  ; Self modifying code:
@phase_swap_xor:  xor 00h
  ld h, a
  ld l, e

  ld bc, 64
@nondirty_copy_loop:
  ldi \ ldi \ ldi \ ldi
  ldi \ ldi \ ldi \ ldi
  ldi \ ldi \ ldi \ ldi
  ldi \ ldi \ ldi \ ldi

  ; The P/V flag is reset (PO) if BC == 0 
  jp pe, @nondirty_copy_loop

  pop hl
  ld bc, 128
  add hl, bc

@nondirty_end_of_loop:
  end_loop ; Handles jp and ret



_greyscale_swap:
  init_phase grey_phase1_buff, grey_phase1_altbuff, 1 

  ; Convert the individual buffers
  ld hl, _screen_buffer
  ld de, (alt_phase1)
  p1: call phase_component


  init_phase grey_phase2_buff, grey_phase2_altbuff, 2 
  ld hl, _screen_buffer
  ld de, (alt_phase2)
  p2: call phase_component 


  init_phase grey_phase3_buff, grey_phase3_altbuff, 3 
  ld hl, _screen_buffer
  ld de, (alt_phase3)
  p3: call phase_component


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
