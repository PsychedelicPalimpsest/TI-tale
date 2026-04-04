; This file contains MAN assorted LCD blit tools. Each one
; is designed for a specific situation. 

PUBLIC blit_solid
PUBLIC _blit_solid

SECTION code_engine

; extern void blit_solid(void* dst, void* src, char width, char height_times2) __z88dk_sdccdecl __z88dk_callee;
_blit_solid:
  pop af
  pop de ; dst
  pop hl ; src
  pop ix
  push af
  ; fall through to blit_solid

  
; Writes a sprite who has not support for transparency (or transparent bytes)
; Inputs:
;  hl = Sprite source
;  de = Destination addr
;  ixl = width
;  ixh = height 
blit_solid:
; a is the amount needed to go to the next col in dst
  ld a, 64*2 
  sub ixh
 
  ld b, $0
loop:
  ld c, ixh

; hl = sprite
; de = screen
; bc = height
  ldir

; 
  ex de, hl
  
  ; bc = 96-height
  ld c, a
  add hl, bc


  ex de, hl
  dec ixl
  jp nz, loop
  ret




  
  



