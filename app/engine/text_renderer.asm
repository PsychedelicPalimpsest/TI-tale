SECTION code_engine

INCLUDE "core/asm_globals.def"
INCLUDE "core/Ti83p.def"

EXTERN mono_screen_rot_blit

; Inputs:
; ixl  = x
; ixh  = y
; a = char
; Outputs:
; a = next bit pos
blit_char_small_:
  exx
; hl = idx * 8
  ld h, $0
  ld l, a

  add hl, hl
  add hl, hl
  add hl, hl

  ; Does NOT change shadow registers >:}
  bcall _Load_SFont
  ld a, (hl)
  inc hl

; Apply the offset to the x
  add ixl
  ld ixl, a

; store sprite for later
  push hl
  exx

  ld l, $0
; Byte offset
  ld a, %11111000 
  and ixl

  ; Get byte offset, reset carry
  rrca \ rrca \ rrca

  ; hl = x * 128
  rra
  rr l
  ld h, a

; iy = screen buffer ptr
  ld de, _screen_buffer
  add hl, de
  
  ; Apply height
  ld d, $0

  ld a, ixh
  ld e, a

  add hl, de
  ld iy, hl ; Beware: z88dk pseudo instruction

  ld a, 7
  and ixl

  ld c, a
  pop hl

  push ix
  ld ixh, 7

  ; iy=screen buffer
  ; hl=sprite
  ; c=rotation (0-7)
  ; ixh=height
  call mono_screen_rot_blit
  pop ix
  

  ret


PUBLIC blit_char_small
; Inputs:
; hl= screen_buffer
; c = bit position (init with 8)
; a = char
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

  ; Does NOT change shadow registers >:}
  bcall _Load_SFont
  ld a, (hl)
  inc hl

  push hl
  exx

  add a, c
  cp 8

  jp c, after_next_row
  sub a, 8

; Go to next col
  ld de, 128
  add hl, de

; hl -= _screen_buffer + 768*2
  ld de, -( _screen_buffer + 768*2)
  add hl, de

; If there is a carry out, sign change occured,
; meaning hl >  _screen_buffer + 768
  jp nc, no_overflow

; Handle overflow
  ld de, _screen_buffer
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

  pop hl ; Restore sprite buffer
  ; iy=screen buffer
  ; hl=sprite
  ; c=rotation (0-7)
  ; ixh=height
  ld ixh, 7
  call mono_screen_rot_blit
  exx

  ret






  





