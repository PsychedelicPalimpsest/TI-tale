; Inputs:
; hl = src
; de = dest
; bc = stride

  ld iyl, 12 ; 96/16*2=12
  ; ix = bc
  ld ixh, b
  ld ixl, c

loop:
MACRO copy_block_m
  ldi \ ldi \ ldi
  ldi \ ldi \ ldi
  ldi \ ldi \ ldi
  ldi \ ldi \ ldi
endm
  copy_block_m  \  copy_block_m \ copy_block_m \ copy_block_m
  copy_block_m  \  copy_block_m \ copy_block_m \ copy_block_m

  copy_block_m  \  copy_block_m \ copy_block_m \ copy_block_m
  copy_block_m  \  copy_block_m \ copy_block_m \ copy_block_m

  ld b, ixh
  ld c, ixl
  add hl, bc
  dec iyl
  jp nz, loop
  ret


