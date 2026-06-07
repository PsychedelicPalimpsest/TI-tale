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
;  hl =  Pixel width (1 for monochrome, 2 for opaque greyscale, 3 for greyscale with transparency)
;  hl'=  Output location
;  de'=  (Width + Pixel Width)*height - Pixel Width 
;  a  =  Width (bytes, not pixels)
;  c  =  Height
PUBLIC build_cache
build_cache:
    ld (@height_loop+1), a
    ld (@restore_sp+1),  sp
    ld sp, hl

@height_loop: ld b, $00
@width_loop:
    ld a, (de)
    inc de
    exx
        ld (@reset_hl+1), hl

        ld b, $0
        ld c, a
        REPT 7
            ld a, (hl)
            or c
            ld (hl),a 

            add hl, sp 

            ld (hl), b
            
            add hl, de

            srl c
            rr  b
        endr
@reset_hl: ld hl, 0000
    inc hl
    exx
    djnz @width_loop

    ; This adds in an extra padding byte to the end of each row
    exx \ add hl, sp \ exx


    dec c
    jp nz, @height_loop
    
@restore_sp: ld sp, 0000h
    ret
