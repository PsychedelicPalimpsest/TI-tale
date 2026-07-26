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




; Inputs:
; hl = Input
; de = Output
; bc = Width*Height*Pixel Width aka total sprite size
; a  = Height*Pixel Width 
; ixl = Width in cols
; Interupts must be disabled
;
; Outputs:
;  de  = End of cache entry 
;  hl  = One sprite rotation before de
;  ixl = Zero
PUBLIC build_cache_for
build_cache_for:
    push de
        ldir ; Copy in the first sprite rotation
        ex de, hl
    pop de


    ld (@sp_restore+1),   sp
    ld (@reset_height+1),  a

    ld ($+3+1), a ; Set low byte of sp
    ld sp, 0000h

    or a ; Reset carry
@reset_height:
    ld b, 0
    @height_loop:
        REPT 7 
            ; Inner loop runs: 7*Width*Height*Pixel Width times
            
            ld a, (de) ; Main pixel
            ld c, 0    ; Carry out pixel

            rra 
            rr c

            or (hl)
            ld (hl), a
            
            add hl, sp
                ld (hl), c
            sbc hl, sp ; The carry flag _should_ never be set

            inc hl
            inc de
        endr
    djnz @height_loop   

    dec ixl
    jp nz, @reset_height


@sp_restore:    ld sp, 0000h
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

