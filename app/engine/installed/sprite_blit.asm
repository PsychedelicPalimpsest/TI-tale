; This file contains MAN assorted LCD blit tools. Each one
; is designed for a specific situation. 

PUBLIC blit_solid
PUBLIC _blit_solid

PUBLIC _blit_sprite
PUBLIC blit_sprite
PUBLIC mark_hl_dirty


; KEEP ME FIRST
ALIGN 256
bitset_lookup:
REPTI val, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
  ; When the 0-ith col is dirty, the highest bit is set
 DEFW 1 << (15-val)
ENDR

; Takes a location on the screen buffer, and marks that col as dirty.
; Inputs: hl = Location on screen
; Clobbers: hl, a
; T-states: 124
mark_hl_dirty:
; a=2*col number
  add hl, hl ; Get col bits into high byte
  ld a, h
  sub ((_screen_buffer*2) >> 8) & 0xFF
  and %1111 ; Stupid bounds checking, just keeps the input within the lookup table
  add a

;hl = Location in lookup table
  ld h, bitset_lookup >> 8
  ld l, a

; Do the high byte
  ld a, (dirty_cols)
  or (hl)
  ld (dirty_cols), a

; Do the low byte
  inc l ; Due to alignment cannot carry
  ld a, (dirty_cols+1)
  or (hl)
  ld (dirty_cols+1), a 

  ret






; extern void blit_solid(void* dst, void* src, char width, char height_times2) __z88dk_sdccdecl __z88dk_callee;
; T-states: 120WH + 61W + 137
_blit_solid:
  pop af
  pop de ; dst
  pop hl ; src
  pop ix ; high byte goes to height, low byte goes width. Little endianness is fun
  push af
  ; fall through to blit_solid

  
; Writes a sprite who has no support for transparency (or transparent bytes)
; Inputs:
;  hl = Sprite source
;  de = Destination addr
;  ixl = width
;  ixh = height 
;
; T-states: 120WH + 61W + 82
blit_solid:
; a is the amount needed to go to the next col in dst
; use some self modifying code to restore
  ld a, 64*2 
  sub ixh
  ld (c_load_point+1), a
 
  ld b, $0
loop:
  ld c, ixh

  ex de, hl
  push hl
  call mark_hl_dirty
  pop hl
  ex de, hl

; hl = sprite
; de = screen
; bc = height
  ldir

  ex de, hl
  
; bc = 2*(64-height)
  c_load_point: ld c, 00h
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
  push hl
  call mark_hl_dirty
  pop hl

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
  push iy

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

  pop hl
  jp mark_hl_dirty ; Tail call



; This is designed for text bliting, however can be useful for more complex
; situations when the sprite needs xor'd on. 
; Clobbers: iy, a, ix*, hl, de, b
;
; Inputs:
; iy=screen buffer
; a=8-rotation (0-7)
; hl=text (AFTER THE WIDTH PREFIX)
; ixh=height
; c=Text mode. 0-3. You should calculate this by XORing a the desired color by the
;                   assumed background. Ex: %00 ^ %10 = %10
PUBLIC apply_sprite_rot_blit
apply_sprite_rot_blit:
; Patch rotation jr
  ld (light_loop@rot_instr+1), a
  ld (dark_loop@rot_instr+1), a

  push iy

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

  pop de ; Screen buffer

; Note: This can go outside the valid range, but that is ok
;       as that will just got to the unused bits in the bitset
  ld hl, -128 
  add hl, de
  
  call mark_hl_dirty
  ex de, hl
  jp mark_hl_dirty ; tail call

