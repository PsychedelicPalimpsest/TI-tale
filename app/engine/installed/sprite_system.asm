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

PUBLIC mark_col_dirty
mark_col_dirty:
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


; Inputs: 
; hl = Sprite cache size
PUBLIC setup_sprite_system
setup_sprite_system:
    ld (sprite_cache_size), hl

    ld hl, sprite_cache_head
    ld (sprite_cache_tail), hl

    ret


; Takes a sprite, and generates the sprite rotation cache.
; Inputs:
;  de =  Input location
;  ix =  Output location
;  hl = Width*height
;  c = Width (bytes)
;  a  = Height 
build_cache:
    ld (@reset_height+1), a
    ld (@restore_sp+1), sp
    ld sp, hl



; hl = 8*width*height - 1
    add hl, hl
    add hl, hl
    add hl, hl
    dec hl
    ld (@next_outputline+1), hl
    
@reset_height:
    ld b, 00
@loop:
    ld a, (de)
    exx

; Use register pair ac, where a is the high byte
    ld c, a
    xor a

    REPT 4
        ld (hl), c
        add hl, sp

        ex de, hl

        ld (hl), a
        add hl, sp ; Carry flag is assemed to be reset!

        rl c
        rla

        ld (hl), a
        add hl, sp

        ex de, hl
        ld (hl), c
        add hl, sp

        rl c
        rla
    ENDR

@next_outputline: ld bc, 0000
    
    or a ; Reset carry
    sbc hl, bc
    ex de, hl

    sbc hl, bc ; Carry flag assumed reset 
    ex de, hl

    exx
    inc de

    djnz @loop
    dec c
    jp nz, @reset_height
    
@restore_sp: ld sp, 0000
    ret
