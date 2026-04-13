; This file contains MAN assorted LCD blit tools. Each one
; is designed for a specific situation. 

PUBLIC blit_solid
PUBLIC _blit_solid

PUBLIC _blit_sprite
PUBLIC blit_sprite

; extern void blit_solid(void* dst, void* src, char width, char height_times2) __z88dk_sdccdecl __z88dk_callee;
; T-states: 120WH + 61W + 137
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
;
; T-states: 120WH + 61W + 82
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
  ; Set the iyh (height) restore point via EVIL self modifying code 
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
  ld b, (hl)    ; b = light screen byte (I)

  ex de, hl
  ld c, (hl)    ; c = sprite trans byte (T)
  inc hl
  ld a, (hl)    ; a = sprite light byte (S)
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
  ld b, (hl)    ; b = dark screen byte (I)

  ex de, hl
  ld a, (hl)    ; a = sprite dark byte (S)  [trans byte already consumed above]
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
  ; Note: Stack is slow, but this is _as_ hot as the inner loop
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



; Self modifying code note: 
; This is intended to be modified by the callee. 
; @rot_instr should be set to 8-rotation_amount
;
; Clobbers: a, hl
;
; Inputs:
; hl = byte to rot and blit
; iy = screen buffer
MACRO apply_hl_to_sprite has_mod, default_method
  ; Self modifying code: the jr is replaced before this is run
  @rot_instr: jr $
  REPT 7
    add hl, hl ; 1 byte, acts as a left rot
  endr

  ld a, l

  IF do_cpl
    cpl
  endif
  
  @apply_iy1: default_method (iy)
  IF has_mod
   @mod_a1: nop
  endif

  ld (iy), a 

  ld a, h

  @apply_iy2: default_method (iy-128)

  IF has_mod
    @mod_a2: nop
  endif
  ld (iy-128), a 
endm



; Take a monochrome sprite column, and blit it to the screen buffer
; with a rotation
; Inputs:
; iy=screen buffer
; de=sprite
; a=8-rotation (0-7)
; ixh=height
PUBLIC mono_screen_rot_blit
mono_screen_rot_blit:
  ld (light@rot_instr+1), a
  ld (dark@rot_instr+1), a
  ; Does not modify anything else
  ld b, $0 ; Set b to zero for later

rot_loop:
  ld a, (de)
  ld (restore_a+1), a
  inc de 

  ld h, b
  ld l, a

  light: apply_hl_to_sprite 0, or

; Evil micro optimization: Alignment means no carry across bytes is possible >:}
  inc iyl

  restore_a: ld a, 0

  ld h, b
  ld l, a

  dark: apply_hl_to_sprite 0, or
  inc iyl 


  dec ixh
  jp nz, rot_loop 
  ret



; Specific routine for drawing text. 
; Inputs:
; iy=screen buffer
; a=8-rotation (0-7)
; hl=text (AFTER THE WIDTH PREFIX)
; ixh=height
; b=Text color: 00, 01, 10, 11
; c=Background assumption: 00 for white bg, etc
PUBLIC text_screen_rot_blit
text_screen_rot_blit:
; Patch rotation jr
  ld (light_loop@rot_instr+1), a
  ld (dark_loop@rot_instr+1), a

; c = text color XOR background color
  ld a, b
  xor c
  ld c, a

; Set b=0 for the rest of routine
  ld b, $0 

; ixl=ixh=height
  ld ixl, ixh

; Now de is the text sprite
  ex de, hl
  push de 
  push iy

; If the bit in c is *reset*, the bg is the same as the sprite. 
  bit 0, c
; If they are the same, there is nothing to do! (for this color)
  jp z, dark_setup 

light_loop:
  ld a, (de)
  inc de 

; hl = 00 + color
  ld h, b
  ld l, a

  apply_hl_to_sprite 0, xor
  inc iyl
  inc iyl

  dec ixl
  jp nz, light_loop

dark_setup:
  pop iy
  pop de

; Return if there is nothing to do
  bit 1, c
  ret z

  inc iyl
dark_loop: 
  ld a, (de)
  inc de 

  ld h, b
  ld l, a

  apply_hl_to_sprite 0, xor
  inc iyl
  inc iyl

  dec ixh
  jp nz, dark_loop
  ret
  
