; This file contains MAN assorted LCD blit tools. Each one
; is designed for a specific situation. 

PUBLIC blit_solid
PUBLIC _blit_solid

PUBLIC _blit_sprite
PUBLIC blit_sprite

SECTION code_engine



; extern void blit_solid(void* dst, void* src, char width, char height_times2) __z88dk_sdccdecl __z88dk_callee;
_blit_solid:
  pop af
  pop de ; dst
  pop hl ; src
  pop ix ; high byte goes to height, low byte goes width. Little endianness is fun
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

  ex de, hl
  
; bc = 2*(64-height)
  ld c, a
  add hl, bc


  ex de, hl

; Use the width as the loop counter
  dec ixl
  jp nz, loop

  ret

  
; extern void blit_sprite(void* dst, void* src, char width, char height) __z88dk_sdccdecl __z88dk_callee;
_blit_sprite:
  pop af
  pop hl ; screen
  pop de ; sprite
  pop iy ; high byte goes to height, low byte goes width. Little endianness is fun
  push af
  ; fall through to blit_sprite

; Inputs:
; hl  = screen 
; de  = sprite (format: transparent_byte light_byte dark_byte)
; iyl = Width
; iyh = height
blit_sprite:
; Set width restore point
  ld a, iyh
  ld (_iyh_reset + 2), a ; Self modifying code: ld iyh, 00h => FD 26 00

; a = 2*(64-height)
; push the height diff onto the stack
; this is the amount needed to advance
; to the next col. 
  ld a, 64
  sub iyh
  add a, a

  ld b, $0
  ld c, a
  push bc

; Loop point for both x and y
sprite_col_loop:
  ld a, (hl) ; Load a from light screen byte
  
  ex de, hl
  ld c, (hl) ; c is the sprite trans byte
  inc hl     

  ld b, (hl)   ; b is the sprite light byte
  inc hl 
  ex de, hl

; a = Dark screen byte
; c = trans byte
; b = Dark sprite byte
  
; Select the screen byte if transparent bit is set
; TI + T'S = S ^ (T & (I ^ S))
  xor b
  and c
  xor b

  ld (hl), a ; Write to screen
  inc hl
  ld a, (hl) ; a is the dark screen byte


  ex de, hl
  ld b, (hl) ; b is the dark sprite byte
  inc hl 
  ex de, hl

; a = Dark screen byte
; c = trans byte
; b = Dark sprite byte

; Select the screen byte if transparent bit is set
; TI + T'S = S ^ (T & (I ^ S))
  xor b
  and c
  xor b

  ld (hl), a
  inc hl

  dec iyh
  jp nz, sprite_col_loop
  

; screen_ptr += 2*(64-height)
  pop bc
  add hl, bc
  push bc

; EVIL: Self modifying code
  _iyh_reset: ld iyh, 00h

; width--
  dec iyl
  jp nz, sprite_col_loop

; Pop the screen ptr diff
  pop af


  ret

