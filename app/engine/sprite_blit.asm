

; Blits a sprite to the screen, overwriting everything, with no support for transparency or non %8 x positions.
; Inputs:
; Hl = destination addr
; De = sprite location
; a = width*2
; ixh = 24-(width*2)
; ixl = height

blit_solid_sprite:
  ld b, $0
sprite_loop:
  ld c, a
  ldir
  ld c, ixh
  add hl, bc

  dec ixl
  jp nz sprite_loop
  ret





  



