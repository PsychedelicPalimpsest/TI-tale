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


; Build the cache contents for a sprite. Please note this should NOT be used directly
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

    ld (@sp_set+1), a ; Set low byte of sp
@sp_set: 
    ld sp, 0000h  ; SMC

    or a ; Reset carry
@reset_height:
    ld b, 00h ; SMC
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


@sp_restore:    ld sp, 0000h ; SMC
    ret


; Copies a sprite based on width and height
; Inputs:
; hl = Ouput buffer
; de = Input buffer
; ixl = Width
; b = Height*Pixel Width
;
; Outputs:
; bc = zero
; de = end of output buffer
PUBLIC wh_copy_sprite
wh_copy_sprite:
    ex de, hl

    ld ixh, b
    ld b, $0
@width_loop:
    ld c, ixh
    ldir

    dec ixl
    jp nz, @width_loop
    ret


; Inputs: 
; hl = Ouput buffer
; de = Input buffer
; a  = Rotation amount, must be [0, 7]
; ixl = Width
; b = Height*Pixel Width
;
; Outputs:
; bc = zero
; a  = unchanged

PUBLIC rotate_plane
rotate_plane:
    or a ; Test a, reset carry going in
    jr z, wh_copy_sprite ; Micro opt: Mostly falls through, so jr is used


    ld (@rot_amount+1), a
    ld (@restore_sp+1), sp


    ld a, b
    ld (@height_reset+2), a
    ld (@set_sp+1), a ; Set low byte of sp

@set_sp:       ld sp,  0000h 
@height_reset: ld ixh, 00h 

@height_loop:
@rot_amount:   ld b, 00h

        ld a, (de) ; Main pixel
        ld c, 0    ; Carry out pixel

        @rot_loop:
            rra 
            rr c
        djnz @rot_loop

        or (hl)
        ld (hl), a
        
        add hl, sp
            ld (hl), c
        sbc hl, sp ; The carry flag _should_ never be set

        inc hl
        inc de
    dec ixh
    jp nz, @height_loop

    dec ixl
    jp nz, @height_reset

@restore_sp: ld sp, 0000h

    ld a, (@rot_amount+1) ; Restore a
    ret



; Blits a sprite to the screen
; Inputs:
; de = Input sprite
; hl = Output location on screen
; ixl  = Width in cols (can be truncated)
; a  = Full Height (what the sprite actually is)
; b  = Height truncation (cols to remove from bottom)
public norot3x2_blit
norot3x2_blit:
    sub b
    ld (@reset_height+1), a

    ld a, b
    add a
    add b
    ld (@adj_ptr), a

    ; Calculate the diff to get to the next col
    ; The screen is 64 pixel tall, *2 for the grayscale
    ; 128-2a = 2(-a + 64)

    cpl ; Saves 4 cycles by using cpl instead of neg, needing me to add on to 64
@height_adj:
    add 64+1
    add a
    ld (@advance_col+1), a


@reset_height:
    ld b, 00h ; SMC
@height_loop:
        ld a, (de)
        ld c, a
        inc de

        ; shuffle in light byte
        ld a, (de)
        xor (hl)
        and c
        xor (hl)
        ld (hl), a

        inc de \ inc hl ; No alignment garentees

        ; shuffle in dark byte
        ld a, (de)
        xor (hl)
        and c
        xor (hl)
        ld (hl), a

        inc de ; No alignment garentees
        inc l  ; Micro optimization: This is safe due to alignment. Screens start aligned to 256 bytes. 
               ; Overflow happens when the low byte is 1111 1111, an odd byte, meaning from going from 
               ; a light pixel to a dark pixel.
    djnz @height_loop

    ex de, hl
    @adj_ptr:
        ld c, 00h ; SMC
        add hl, bc
    ex de, hl

@advance_col: 
    ld c, 00h ; SMC
    add hl, bc

    dec ixl
    jp nz, @reset_height
    ret

; Inputs:
; hl' = Ouput buffer
; de' = Input buffer
; HL  = Pixel mode. H for light byte, L for dark byte. If the byte is 00h, xors input on,
;       if 2Fh will xor by ~input, if AFh will do nothing. Do not use anything else
; ixl= Input width in cols
; a  = Input Height 
; c  = Ouput Height*PixelWidth
; N  = Pixel Width, MUST be 2 or 3 
;
; Outputs:
; hl' = Output buffer AFTER last written pixel
; de' = Input buffer AFTER last read pixel
; hl  = Untouched
MACRO _norot1xN_xorblit N
    ld (@height_reset+1), a

    REPT N-1
        add a
    endr
    ; Calculate the stride
    ; H-h = -h + H
    neg
    add c
    ld (@output_stride+1), a

    
    ld a, h
    ld (@lo), a

    ld a, l
    ld (@do), a

    exx

@height_reset: ld b, $0
@height_loop:
    IF 3=N
        inc hl 
    endif
    
; Light pixel
    ld a, (de)
@lo:nop ; nop or cpl, patched on the fly
    xor (hl)
    ld (hl), a
    inc hl

; Dark pixel
    ld a, (de)
@do:nop 
    xor (hl)
    ld (hl), a
    inc hl

    inc de
    djnz @height_loop
    
@output_stride:
    ld bc, 0000h
    add hl, bc

    dec ixl
    jp nz, @height_reset
    ret
endm



PUBLIC norot1x2_xorblit
norot1x2_xorblit: _norot1xN_xorblit 2

PUBLIC norot1x3_xorblit
norot1x3_xorblit: _norot1xN_xorblit 3





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

; Fill a 768*2 screen quickly
; Input:
; hl = screen buffer + 768*2 (after the screen in question)
; de = Fill color
;
; T-states: 8,660
PUBLIC scrset
scrset:
    ld (@sp_restore+1), sp
    di
    ld sp, hl

    ld b, 768*2 /64/2
    @loop:
        REPT 64
            push de
        ENDR
        djnz @loop



@sp_restore: ld sp, 0000h
    ei
    ret



        
; Inputs:
; hl - sprite entry
; Outputs:
; ixl - Width truncation
; ixh - Height truncation
; hl - Offset in screen [0, 768*2)
; b  - x truncation
; c  - y truncation
; a  - Rotation [0, 7]
required_truncation:
    ld c, (hl)
    inc hl
    ld b, (hl)
    inc hl
    push bc ; Save X

    ld e, (hl)
    inc hl
    ld d, (hl)
    inc hl    

    ex de, hl
        add hl, bc
        ld bc, (cur_camx_plusw)
        sub hl, bc
        ld ixl, $0
        jp p,@after_width_truncation 

        ld a, l
        ld ixl, a
@after_width_truncation:
    ex de, hl

    ld c, (hl)
    inc hl
    ld b, (hl)
    inc hl
    push bc ; Save Y

    ld e, (hl)
    inc hl
    ld d, (hl)
    inc hl        
       

    ex de, hl
        add hl, bc
        ld bc, (cur_camy_plush)
        sub hl, bc
        ld ixh, $0
        jp p,@after_height_truncation 

        ld a, l
        ld ixh, a

@after_height_truncation:
    pop bc ; Y
    pop hl ; X

    ; Fall through into coords_to_screen_offsets with:
    ;   hl = X position
    ;   bc = Y position





; Take coords (two signed 16-bit ints) and calculate the offset
; within a screen. This assumes the sprite is on the screen
; Inputs:
; hl - X position
; bc - Y position
; 
; Outputs:
; hl - Offset in screen [0, 768*2)
; b  - x truncation
; c  - y truncation
; a  - Rotation [0, 7]
coords_to_screen_offsets:
    ld de, (cur_camx)
    sub hl, de

    
    ex af, af' ; Store flags
        ; Bit offset (magically works with negatives)
        ld a, 7
        and l ; Stored lower byte
    ex af, af' ; Save for later; restore flags

    jp p, @positive_diff
    ; diff = (-diff + 7) = (7 - diff)
        ld a, 7
        sub l
        ld l, a

        sbc  a, a
        sub  h
        ld   h, a
        
        REPT 3
            srl h
            rr  l
        endr
        ld d, l ; x-truncation 

        ld h, 0 ; x-offset
        ld l, h
        jp @handle_y
@positive_diff:
    ld a, 7 ^ 0xFF
    and l
    ld l, a


    REPT 4
        add hl, hl
    endr


    ld d, $0 ; X-truncation
@handle_y:
    push de ; Save x truncation
    push hl  ; Save x offset

    ld hl, bc
    ld de, (cur_camy)
    sub hl, de

    jp p, @positive_ydiff
        ld bc, $0

        ld a, l
        neg
        ld d, a
        jp @cleanup
@positive_ydiff:
    ld b, $0 
    ld c, l
    
    ld d, $0

@cleanup:
    pop hl     ; x_offset * 128
    add hl, bc ; + y_offset

    pop bc
    ld c, d
    ex af, af' ; bit rotation
    ret




    
; Based on a sprite at HL, checks if it is on screen. 
; Setting the carry flag if so
;
; Restores: HL
; Clobbers: BC, AF, DE
PUBLIC is_sprite_on_screen
is_sprite_on_screen:
    ; Sprite placement possibilites:
    ; 1. The sprite is too far X to be seen (sx > cx+cw)
    ; 2. The sprite is too far the other X direction to be seen
    ;    (cx > sx + sw)
    ; 3. The sprite is too far Y to be seen (sy > cy+ch)
    ; 4. The sprite is too far the other Y direction to be seen
    ;    (cy > sy+sh)
    push hl

    ; Check 1:
    
        ; X
        ld c, (hl)
        inc hl
        ld b, (hl)
        inc hl
        ex de, hl
            ld hl, (cur_camx_plusw)
            or a \ sbc hl, bc
            jp c, @no
        ex de, hl
   
    ; Check 2:
        ; X : comes from check 1
        ; 
        ; Width
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl

        ex de, hl
            add hl, bc ; Assume no carry
 
            ld bc, (cur_camx)
            sbc hl, bc
            jp c, @no
        ex de, hl

    ; Check 3:
        ; Y
        ld c, (hl)
        inc hl
        ld b, (hl)
        inc hl
        ex de, hl
            ld hl, (cur_camy_plush)
            or a \ sbc hl, bc
            jp c, @no
        ex de, hl       
    ; Check 4:
        ; Height
        ld e, (hl)
        inc hl
        ld d, (hl)

        ex de, hl
            add hl, bc ; Assume no carry

            ld bc, (cur_camy)
            sbc hl, bc
            jp c, @no
    scf

    pop hl
    ret

@no:
    or a

    pop hl
    ret




reset_carry_retpop:
    pop af
reset_carry_ret:
    or a
    ret

; Calculate the renderlist entry for a sprite, it updates a sprites exiting entry
; if one is found, otherise it uses the provided one
; Inputs:
; hl = Sprite list entry
; de = Render list entry
; ; Outputs:
; Carry flag is set iff renderlist was incremented
; de = possibly advanced entry list
calculate_rl:
    ld a, (hl)

    rra    
    ret nc ; Sprite is disabled
    inc hl
    push de ; Save render list entry for later
        call is_sprite_on_screen
        jp nc, reset_carry_retpop

    push hl
        inc hl \ inc hl
        ; Width for later
            ld a, (hl)
            ld (@add_in_width+1), a
            inc hl

            ld a, (hl)
            ld (@add_in_width+2), a
            inc hl
        
        inc hl \ inc hl
        ; Height for later
             ld a, (hl)
            ld (@true_height+1), a
            inc hl

            ld a, (hl)
            ld (@true_height+2), a
            inc hl       


        ; Load in the full sprite size for later
            ld a, (hl)
            ld (@sprite_size+1), a
            inc hl

            ld a, (hl)
            ld (@sprite_size+2), a
            inc hl

        ld (@base_sprite_location+1), hl
        
    pop hl
    pop de

; A sprites cached list entry trumps all else
    ld a, c
    or c
    jp z, @after_de_set
        ld bc, de
@after_de_set:
    ld iy, bc

    ; hl from pop
    call required_truncation
; Outputs:
; ixl - Width truncation
; ixh - Height truncation
; hl - Offset in screen [0, 768*2)
; b  - x truncation
; c  - y truncation
; a  - Rotation [0, 7]

    ld (iy+2), l ; Screen offset can be passed in
    ld (iy+3), h

    ; Combine the y truncation together
    ld a, ixh  ; Height truncation
    add c      ; Presprite y truncation  
    ld (iy+6), a
    
    push bc ; X-y truncation
        exx

        ; Calculate the full sprites location in the cache
    @base_sprite_location:
        ld hl, 0000h ; Sprite locationi
    @sprite_size:
        ld de, 0000h ; Full sprite size

        ; Add de a times to hl
        cpl
        add 7+1 ; 1 is added to use cpl instead of neg
        ld (@loop_jr+1), a

    @loop_jr:
        jr $+2 ; SMC: Patched jump amount
        REPT 7
            add hl, de
        endr


    pop bc ; X-Y truncation
        ld d, $0
        ld e, c

        add hl, bc ; Add in the Y truncation

    @add_in_width:
        ld de, 0000h ; SMC: Width stored from earlier

        ld a, 24 ; Bytes needed to skip add loop
        sub b
        ld (@x_truncation_jr+1), a

    @x_truncation_jr:
        jr $+2

        REPT 24
            add hl, de
        endr

        ld (iy+0), l ; Input sprite
        ld (iy+1), h

        ; Divide width by 8 to get col width
        ld a, e
        REPT 3
            srl d
            rra
        endr
        sub ixl ; Subtract width truncation
        ld (iy+4), a

    @true_height:
        ld bc, 0000h
        ld (iy+5), c ; Pass in full height (This can safely be truncated)

    ret

; de = Input sprite
; hl = Output location on screen
; ixl  = Width in cols (can be truncated)
; a  = Full Height (what the sprite actually is)
; b  = Height truncation (cols to remove from bottom)


    
    
