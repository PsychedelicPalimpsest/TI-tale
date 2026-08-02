; This file contains some of the ugliest code ever written. 

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



; Take a sprite from the disk format and generate the sprite cache data entry 
; Input:
; hl = Input sprite
; Output:
; de = Sprite cache entry
MACRO _new_sprite_cache_entry N
    ld de, (sprite_pool_head)
    push de ; Old sprite cache head

    ld b, (hl) ; Width (cols)
    inc hl
    ld c, (hl) ; Height
    dec hl

    ld ixl, b ; Save width for build_cache
    ld a,   c ; Save height for build_cache
    ex af, af'

    push hl ; Input sprite
        ; Flags entry (default to not being displayed)
        xor a
        ld (de), a
        inc de
        
        ; Init X, Width, Y, Height fields
        ld (de), a
        inc de
        ld (de), a
        inc de

        ld l, b ; Width *=8
        inc l ; build_cache extends by one col
        REPT 3
            sla l
            rla
        endr

        ex de, hl
            ; Width in pixel
            ld (hl), e
            inc hl
            ld (hl), a
            inc hl

            ; Y 
            xor a
            ld (hl), a
            inc hl
            ld (hl), a
            inc hl

            ; Height
            ld (hl), c
            inc hl

            ; RL entry
            ld (hl), a
            inc hl
            ld (hl), a
            inc hl
        ex de, hl
    push de 
        ld l, b
        ld d, $0
        ld e, c

        ; Width*height
        call mul_16_16x8_fast
        ld (@reset_bc+1), hl
        
        add hl, de ; Add in another copy of the height (to account for the extra col)
        ld de, hl
        ; *=3
        add hl, hl
        add hl, de
        ld bc, hl
    pop de

    ; Ptr for each sprite entry
    ld hl, 8*2
    add hl, de

    ld ixh, 8
    @loop:
        ld a, l
        ld (de), a
        inc de

        ld a, h
        ld (de), a
        inc de    

        add hl, bc

        dec ixh
        jp nz, @loop 
    
    pop hl ; Input sprite
    inc hl \ inc hl ; Skip width and height bytes

    ex af, af'
@reset_bc:
    ld bc, 0000h
    
    call build_cache##N##x
    ld (sprite_pool_head), de
    pop de ; Old head
    ret
endm


PUBLIC new_sprite_cache_entry2x
new_sprite_cache_entry2x:_new_sprite_cache_entry 2

PUBLIC new_sprite_cache_entry3x
new_sprite_cache_entry3x:_new_sprite_cache_entry 3



; Add alpha channel to a sprite
; Inputs:
; hl = Input
; de = Output
; bc = Length
MACRO norot2x3_cpy
    LOCAL @loop2x3
    ex af, af'
        ; bc *= 2
        sla c
        rl b    

        ld a, 0xFF
    @loop2x3:
        ld (de), a
        inc de
        ldi \ ldi
        jp pe, @loop2x3
    ex af, af'
endm

; Inputs:
; hl = Input
; de = Output
; bc = Length
MACRO norot3x3_cpy
    push bc
    push bc
    ldir
    pop bc
    ldir
    pop bc
    ldir
endm






; Build the cache contents for a spritex2.
; This extends the buffer by one col for rotation carry out
; Please note this should NOT be used directly
; Inputs:
; hl = Input
; de = Output
; bc = Width*Height
; a  = Height
; ixl = Width in cols
; Interupts must be disabled
;
; Outputs:
;  de  = End of cache entry 
;  hl  = One sprite rotation before de
;  ixl = Zero
build_cache2x:
    push de
        norot2x3_cpy
        ex de, hl

        ; A*=3 (pixel width)
        ld d, a
        add a
        add d
    pop de
    jp build_cache_rejoin

; Build the cache contents for a spritex3.
; This extends the buffer by one col for rotation carry out
; Please note this should NOT be used directly
; Inputs:
; hl = Input
; de = Output
; bc = Width*Height
; a  = Height
; ixl = Width in cols
; Interupts must be disabled
;
; Outputs:
;  de  = End of cache entry 
;  hl  = One sprite rotation before de
;  ixl = Zero
build_cache3x:
    push de ; Original output
        norot3x3_cpy
        ex de, hl

        ; A*=3 aka pixel width
        ld d, a
        add a
        add d
    pop de

    ; Coming in:
    ; hl = after the first rotation buffer
    ; de = first rotation buffer
    ; bc = zero
    ; a = height*3
    ; ixl = width in cols

build_cache_rejoin:
    ld (@restore_sp+1), sp
    ld (@height_reset1+1), a
    ld (@height_reset2+1), a
    ld (@set_sp+1), a


    ; Extend the rotation buffer with a blank col
    push de
        ld c, a
        ld de, hl
        ld (hl), 0

        dec c ; First byte is already written
        inc de
        ldir
        ex de, hl
    pop de

    
@set_sp: ld sp, 0000h



    MACRO _cell is_first
        ld a, (de)
        ld c, 0

        rra
        rr c

        ; Don't take a carry on the first col 
        if 0=is_first
            or (hl)
        endif
        ld (hl), a
        add hl, sp
            ld (hl), c
        sbc hl, sp ; Carry flag will never be set with valid args

        inc hl
        inc de
    endm


    ld a, ixl
    dec a ; Account for the first col being done outside of the loop
    ld (@width_reset+2), a

    ld ixh, 7 ; 7 Rotations 

@height_reset1:
    ld b, 00h

    @loop1:
        _cell 1
        djnz @loop1

@width_reset:
    ld ixl, 00h

    @height_reset2:
        ld b, 00h

        @loop2:
            _cell 0
            djnz @loop2

        dec ixl
        jp nz, @height_reset2

    ; Skip the last col
    add hl, sp
    ex de, hl
        add hl, sp
    ex de, hl

    dec ixh
    jp nz, @height_reset1

@restore_sp:
    ld sp, 0000h
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


no_render:
    add hl, de
    exx
    ret

; Input:
; hl' = Render list entry
; de' = 6
; Output:
; hl' = Next RL entry
;
; All shadow registers perserved
PUBLIC blit_rl_entry
blit_rl_entry:
    ld (@restore_sp+1), sp

    di
    exx
        xor a
        or (hl)
        jr z, no_render ; Likely to fall through
        
        ld sp, hl
        add hl, de
    exx
    inc sp

    pop de
    pop hl
    pop ix
        ld a, ixh
    pop bc
        ld b, c
@restore_sp:
    ld sp, 0000h
    ei
    ; Fall through to norot3x2_blit    

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


; Copy a screen who needs a custom height stride
; iy = source
; ix = destination
; hl = stride
PUBLIC scrcpy_stride
scrcpy_stride:
    ld (@stride+1), hl

    ld a, 12
    ld (@loop_counter+1), a
    ld (@sp_restore+1), sp
    di

@loop:
    ld de, 14
    REPT 7
        fastcpy_14s_stride_backwards
    endr

    fastcpy_14s_stridenuke_backwards

    ld de, 16
    fastcpy_16s_stridenuke_backwards

@stride: ld de, 0000h ; Stride
    add iy, de
    add ix, de
    

@loop_counter:
    ld a, $0
    dec a
    ld (@loop_counter+1), a
    jp nz, @loop

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
    ; X
    ld c, (hl)
    inc hl
    ld b, (hl)
    inc hl
    push bc ; Save X

    ; Width
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

    ; Y
    ld c, (hl)
    inc hl
    ld b, (hl)
    inc hl
    push bc ; Save Y


    ; Height
    ld d, $0
    ld e, (hl)
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
PUBLIC calculate_rl
calculate_rl:
    ld a, (hl)

    rra    
    ret nc ; Sprite is disabled
    inc hl

    push de ; Save render list entry for later
        call is_sprite_on_screen
        jp nc, reset_carry_retpop

    push hl
        inc hl \ inc hl ; Skip X

        ; Width for later
        ld de, @add_in_width+1
        ldi \ ldi

        
        inc hl \ inc hl ; Skip Y

        ; Height for later
        ld a, (hl)
        ld (@true_height+1), a
        inc hl       

          
        ; Get the base sprite data table
        ld de, @sprite_rot_table+1
        ldi \ ldi

        ld b, (hl)
        inc hl
        ld c, (hl)
    pop hl
    pop de

; A sprites cached list entry trumps all else
    ld a, c
    or c
    jp z, @after_de_set
        ld bc, de
@after_de_set:
    ld a, 1 ; Mark as render-able
    ld (bc), a
    inc bc
    
    ld iy, bc

    ; hl from pop
    call required_truncation
; ixl - Width truncation
; ixh - Height truncation
; hl - Offset in screen [0, 768*2)
; b  - x truncation
; c  - y truncation
; a  - Rotation [0, 7]

    ld (iy+2), l ; Screen offset can be passed in
    ld (iy+3), h

    ex af, af' ; Rotation
        ; Combine the y truncation together
        ld a, ixh  ; Height truncation
        add c      ; Presprite y truncation  
        ld (iy+6), a
    
    ex af, af' ; Rotation

        exx

    ; Get the sprites location (via lookup table) from rotation
    @sprite_rot_table:
        ld hl, 0000h ; Rotation table
        add a ; *2 for ptr size
        add_hl_a 

        ; Lookup sprite entry
        ld a, (hl)
        inc hl
        ld h, (hl)
        ld l, a
        

        ld d, $0
        ld e, c

        add hl, bc ; Add in the Y truncation

    @add_in_width:
        ld de, 0000h ; SMC: Width stored from earlier

        ; *=3 for pixel size (alph, light, dark)
        push hl
            ld hl, de
            add hl, hl
            add hl, de
            ex de, hl
        pop hl

        ld a, 12 ; Bytes needed to skip loop
        sub b
        ld (@x_truncation_jr+1), a

    @x_truncation_jr:
        jr $+2

        REPT 12 ; Max truncation amount (size of screen)
            add hl, de
        endr

        ld (iy+0), l ; Input sprite
        ld (iy+1), h

        ; Divid width by 8 to get col width
        ld hl, (@add_in_width+1)
        ld a, l
        REPT 3
            srl h
            rra
        endr

        sub ixl ; Subtract width truncation
        ld (iy+4), a

    @true_height:
        ld c, 00h
        ld (iy+5), c ; Pass in full height (This can safely be truncated to a byte)

    ret
