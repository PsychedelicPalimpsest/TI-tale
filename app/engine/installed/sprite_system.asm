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
; NOTE: Disabling interupts is a MUST
; Inputs:
;  de =  Input location
;  hl'=  Output location
;  hl = (Width+1)*height
;  c = Width (bytes)
;  a  = Height 
PUBLIC build_cache
build_cache:
    ld (@reset_height+1), a
    ld (@restore_sp+1), sp
    ld sp, hl

    
    exx
        ; de = output location + height
        add_hl_a_de
    exx

; Register allocation:
; sp = stride between rotations (width*heigh)
; b  = height loop counter
; c  = width  loop counter (input)
; de = input ptr
; hl'= regular output ptr
; de'= output ptr + height


; hl = -(8*width*height - 1)
    add hl, hl
    add hl, hl
    add hl, hl

    ld a, l
    cpl
    ld l, a

    ld a, h
    cpl
    ld h, a
    inc hl \ inc hl
    ld (@next_outputline+1), hl
    
@reset_height:
    ld b, 00
@loop:
    ld a, (de)
    exx

; Use register pair ac, where a is the high byte
    ld b, a
    ld c, $0

    REPT 4
        ld a, b
        or (hl)
        ld (hl), a
        add hl, sp
    
        ex de, hl

        ld (hl), c
        add hl, sp

        srl b
        rr c

        ld (hl), c
        add hl, sp

        ex de, hl
        ld a, b
        or (hl)
        ld (hl), a
        add hl, sp

        srl b
        rr c
    ENDR

@next_outputline: ld bc, 0000
    add hl, bc
    ex de, hl

    add hl, bc 
    ex de, hl

    exx
    inc de

    djnz @loop
    dec c
    jp nz, @reset_height
    
@restore_sp: ld sp, 0000
    ret
