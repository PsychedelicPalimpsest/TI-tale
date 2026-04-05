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
  pop af        ; Save return address
  pop hl        ; dst: pointer into screen buffer
  pop de        ; src: sprite data (format per row: trans_byte, light_byte, dark_byte)
  pop iy        ; iyl = width (columns), iyh = height (rows) — packed via little-endian push
  push af       ; Restore return address
  ; Fall through to blit_sprite

; Blits a masked sprite onto a light/dark interleaved screen buffer.
; Each screen row occupies 2 bytes: one light byte followed by one dark byte.
; Each sprite row occupies 3 bytes: trans_byte, light_byte, dark_byte.
;
; Inputs:
;   hl  = screen pointer (dst)
;   de  = sprite pointer (src)
;   iyl = width  (columns)
;   iyh = height (rows)
blit_sprite:
  ; Save the initial height into the self-modifying reset instruction below,
  ; so iyh can be restored after each column is drawn.
  ld a, iyh
  ld (_iyh_reset + 2), a  ; Patch operand of: ld iyh, 00h  (encoding: FD 26 XX)

  ; Compute the byte stride needed to advance hl to the next column after
  ; drawing. Each row is 2 bytes (light + dark), screen is 64 rows tall,
  ; so the remaining rows after the sprite = 64 - height, giving a stride
  ; of 2*(64 - height).
  ld a, 64
  sub iyh
  add a, a      ; a = 2 * (64 - height)

  ld b, $0
  ld c, a
  push bc       ; Push stride onto stack for reuse each column

; Shared loop entry for both the inner (row) and outer (column) loops.
sprite_col_loop:
  ; --- Blend light plane ---
  ld a, (hl)    ; a = light screen byte (I)

  ex de, hl
  ld c, (hl)    ; c = sprite trans byte (T)
  inc hl
  ld b, (hl)    ; b = sprite light byte (S)
  inc hl
  ex de, hl

  ; Transparent blit: keep screen pixel where T=1, use sprite pixel where T=0
  ; Formula: TI + T'S  ==>  S ^ (T & (I ^ S))
  xor b
  and c
  xor b

  ld (hl), a    ; Write blended light byte to screen
  inc hl

  ; --- Blend dark plane ---
  ld a, (hl)    ; a = dark screen byte (I)

  ex de, hl
  ld b, (hl)    ; b = sprite dark byte (S)  [trans byte already consumed above]
  inc hl
  ex de, hl

  ; Same transparent blit formula (reuses c = trans byte from above)
  xor b
  and c
  xor b

  ld (hl), a    ; Write blended dark byte to screen
  inc hl

  ; Inner loop: iterate over all rows of this column
  dec iyh
  jp nz, sprite_col_loop

  ; Advance screen pointer past the undrawn rows to reach the next column
  pop bc
  add hl, bc
  push bc

  ; Restore iyh for the next column (self-modifying: patches the immediate above)
_iyh_reset: ld iyh, 00h

  ; Outer loop: iterate over all columns
  dec iyl
  jp nz, sprite_col_loop

  ; Clean up stride from stack
  pop af

  ret
