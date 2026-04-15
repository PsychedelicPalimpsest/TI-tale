SECTION code_engine

INCLUDE "core/common.inc"

EXTERN text_screen_rot_blit
PUBLIC blit_char


DEFC _Load_LFontV = 806Fh
font_select:
  exx
  bit 2, c
  exx


; HACK: The os uses iy+$35 for temp state. This ensures is has a byte to write to. 
;       This is only 'safe' because I have verified that whith *this* TI-OS version
;       *this* routine only uses this flag
  ld iy, free_trash_byte - $35

  jp z, Load_SFont
  bcall _Load_LFontV 
  ret


Load_SFont: bcall _Load_SFont \ ret


; Inputs:
; hl= screen_buffer
; b = bit position (init with 8)
; a = char
; c = bit 3 is the color font select, bits 1 and 2 are the color modes. See: text_screen_rot_blit
;     bit 3 is set if large font is used
; Outputs:
; b = next bit position
; c = same as input
; hl = next screen position
blit_char:
  exx
; hl = idx * 8
  ld h, $0
  ld l, a

  add hl, hl
  add hl, hl
  add hl, hl

; hl=sprite data, prefixed with width
; _Load_*Font does NOT change shadow registers >:}
  call font_select

  ld a, (hl)
  inc hl

  push hl
  exx

  add a, b
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
  ld b, a

  pop de ; Restore sprite buffer

  push bc
  push hl

  push hl
  pop iy ; iy = screen buffer

  ex de, hl ; Sprite buffer in hl

; Clobbers: iy, a, ix*, hl, de, b
;
; Inputs:
; iy=screen buffer
; a=8-rotation (0-7)
; hl=text (AFTER THE WIDTH PREFIX)
; ixh=height
; c=Text mode. 0-3. You should calculate this by XORing a the desired color by the
;                   assumed background. Ex: %00 ^ %10 = %10

  ld ixh, 7
  call text_screen_rot_blit

  pop hl
  pop bc

  ret


