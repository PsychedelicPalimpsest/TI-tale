; KEEP ME FIRST
ALIGN 256
bitset_lookup:
REPTI val, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
    ; When the 0-ith col is dirty, the highest bit is set
    DEFW (1 << (15-val + 1)) - 1
ENDR
    DEFW 0

bitset_lookup2:
REPTI val, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
    ; When the 0-ith col is dirty, the highest bit is set
    DEFW 1 << (15-val)
ENDR




; Takes a location on the screen buffer, and marks that col as dirty.
; Inputs: hl = Location on screen
; Clobbers: hl, a
; T-states: 131

PUBLIC mark_col_dirty
mark_col_dirty:
; a=2*col number
  add hl, hl ; Get col bits into high byte
  ld a, h
  sub (_screen_buffer*2) >> 8
  add a
  add bitset_lookup2 & 0xFF ; Get to the second table

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

;Inputs: 
; hl = location on screen
; a  = height

PUBLIC mark_region_dirty
mark_region_dirty:
; 4 rows to one bitset item
    rrca
    and %01111110
    ld b, a
    

    add hl, hl
    ld a, h
    sub ((_screen_buffer*2) >> 8) & 0xFF
    add a
    ld c, a

    add b  

    ld l, a

    ld h, bitset_lookup >> 8
    ld b, h

    ld a, (dirty_cols)
    ld e, a
    ld a, (bc)
    xor (hl)
    or e
    ld (dirty_cols), a
    
    inc c \ inc l ; Due to alignment no overflow is possible
    
    ld a, (dirty_cols+1)
    ld e, a
    ld a, (bc)
    xor (hl)
    or e
    ld (dirty_cols+1), a

    ret



; Takes an object, and generates the sprite rotation cache.
; NOTE: Disabling interrupts is a MUST
; Inputs:
;  de =  Input location
;  hl =  Pixel width (1 for monochrome, 2 for opaque greyscale, 3 for greyscale with transparency)
;  hl'=  Output location
;  de'=  (Width + Pixel Width)*height - Pixel Width 
;  a  =  Width (bytes, not pixels)
;  c  =  Height (typically 8 for tiles)
PUBLIC gen_cache
gen_cache:
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




; Inputs:
; hl = Tile addr
; de = Screen location
tile_cpy:
    ld (@sp_restore+1), sp   
    ld sp, hl
    ex hl, de
; sp is now the tile addr
; hl is now the screen addr

REPT 8
    pop de
    ld (hl), e \ inc l ; Due to alignment, no overflows should occur within a col
    ld (hl), d \ inc l ; and if your tile is between two cols, thats a bug!
ENDR


@sp_restore:
    ld sp, $0000
    ret

; Inputs:
; hl = Screen location
; de = Tile addr
; Outputs:
; hl = Screen location 
tile_blend:
REPT 8
    ld a, (de) ; Transparency byte 
    ld c, a

    inc de

; shuffle in light byte
    ld a, (de)
    xor (hl)
    and c
    xor (hl)
    ld (hl), a
   
    ; Micro optimization: HL has alignment garentees
    inc l \ inc de 

; shuffle in dark byte
    ld a, (de)
    xor (hl)
    and c
    xor (hl)
    ld (hl), a


    inc l \ inc de
ENDR
    ret




; Copies 768*2 bytes QUICKLY. 
; Inputs: 
;  iy = source
;  ix = destination
; T-states: 23,769, or 15.47 per byte
PUBLIC scrcpy
scrcpy:
    ld (@sp_restore+1), sp

    ld d, ixh
    ld e, ixl
    ld hl, 108 * 14 ; 768 + 744, leaving 24 (12*2) left over
    add hl, de

    ld a, l
    ld (@chk_low+1), a
    ld a, h
    ld (@chk_high+1), a

    ld de, 14 ; Stride

    di
    @loop:
        REPT 12
            fastcpy_14s_stride
        ENDR

    @chk_low:
        ld a, $00
        cp ixl
        jp nz, @loop ; Unlikely to fall through

    @chk_high:
        ld a, $00
        cp ixh
        jp nz, @loop

        ld de, 12
        fastcpy_12s_stride \ fastcpy_12s_stride

@sp_restore: ld sp, 0000h
    ei
    ret

