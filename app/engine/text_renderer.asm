SECTION code_engine

INCLUDE "core/asm_globals.def"
INCLUDE "core/Ti83p.def"

EXTERN mono_screen_NNrot_blit
PUBLIC blit_char_small


DEFC _Load_LFontV = 806Fh


Load_LFontV: bcall _Load_LFontV \ ret
Load_SFont: bcall _Load_SFont \ ret

font_select:
  exx
  bit 2, b
  exx

  jp z, Load_SFont
  jp Load_LFontV

; Inputs:
; hl= screen_buffer
; c = bit position (init with 8)
; a = char
; b = bit 3 is the color font select, bits 1 and 2 are color select. 
;     bit 3 is set if large font is used
; Outputs:
; c = next bit position
; hl = next screen position
blit_char_small:
  exx
; hl = idx * 8
  ld h, $0
  ld l, a

  add hl, hl
  add hl, hl
  add hl, hl

  ; _Load_*Font does NOT change shadow registers >:}
  call font_select

  ld a, (hl)
  inc hl

  push hl
  exx

  add a, c
  cp 8

  jp c, after_next_row
  sub a, 8


; hl += 128
; hl -= _screen_buffer + 768*2
  ld de, 128-( _screen_buffer + 768*2)
  add hl, de

; If there is a carry out, sign change occured,
; meaning hl >  _screen_buffer + 768
  jp nc, no_overflow

; Handle overflow
  ld de, _screen_buffer + 12
  add hl, de
  jp after_next_row

no_overflow:

  ld de,  _screen_buffer + 768*2
  add hl, de
after_next_row:
  ld c, a

  ld iy, hl ; Beware: z88dk pseudo instruction

  exx
  ld c, a
  exx
  ld a, b
  exx


  pop hl ; Restore sprite buffer

  ; iy=screen buffer
  ; hl=sprite
  ; c=rotation (0-7)
  ; a=color select
  ; ixh=height
  ld ixh, 7
  call mono_screen_NNrot_blit
  exx

  ret


