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


        inc b ; build_cache extends by one col
        ld l, b ; Width *=8
        REPT 3
            sla l
            rla
        endr

        ex de, hl
            ; Width in cols
            ld (hl), b
            inc hl
            
            ; Width in pixels
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
            ld (hl), a ; A is still zero
            inc hl
            ld (hl), a
            inc hl
        ex de, hl
    push de 
        ld l, b
        ld d, $0
        ld e, c

        dec l ; Remove the extra col (this width is needed for sprite gen)

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
    ld iyh, 0 ; Set zero so we can put in sp easily
    ld iyl, a
        
    push de
        ld c, a
        dec c
        
        ld (hl), 0
        ld de, hl
        inc de

        ldir
        ex de, hl
    pop de
    ; Now hl is at the end of the zero extended buffer


    ld (@reset_sp+1), sp
    ld sp, iy

    add hl, sp ; This is for the _do_col convention (also resets cary on valid inputs)


    ; Convention:
    ; hl  = sp+operating cell aka one cell over
    ; de  = copy from cell
    ; iyl = height*3
    ;
    ; hl is assumed to never be able to overflow by adding sp
    ;
    ; **CARRY IS RESET**
    MACRO _do_col is_first, is_last
        LOCAL @cell_loop
        ld b, iyl

        ; Since the last col does NOT need to carry out, save time by pre-subing
        ; hl

        if 1==is_last
            sbc hl, sp
        endif

        @cell_loop:
            ld a, (de)
            rra

            ; Copy carry flag into bit zero of (hl)
            if 0==is_last
                ld (hl), 0
                rr (hl)
            endif

            if 0==is_last
                sbc hl, sp
            endif
            if 0==is_first
                or (hl)
            endif
            ld (hl), a
            
            if 0==is_last
                add hl, sp
            endif


            inc hl
            inc de
            djnz @cell_loop

        if 1==is_last
            add hl, sp
        endif
    endm


    ld ixh, 7
    @rotation_loop:
        _do_col 1, 0 

        ld c, ixl

        dec c ; First col
        jr z, @do_last_col ; Last col is implicit (always done)

        @middle_loop:
            _do_col 0, 0


            dec c
            jp nz, @middle_loop
        
    @do_last_col:        
        _do_col 0, 1

        dec ixh
        jp nz, @rotation_loop
    
    
    
    
@reset_sp:
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
; de' = 7
; Output:
; hl' = Next RL entry
;
; All shadow registers perserved
PUBLIC blit_rl_entry
blit_rl_entry:
    ld (@restore_sp+1), sp

    di
    exx
        bit 0, (hl)
        inc hl

        jr z, no_render ; Likely to fall through
        
        ld sp, hl
        add hl, de
    exx

    pop de
    pop hl
    pop ix
        ld a, ixh
    pop bc ; B is a trash byte
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

    ld c, a
    add a

    cpl
    add 128+1
    ld (@advance_col+1), a

    ld a, b
    add a    
    add b
    ld (@adj_ptr+1), a

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


; Sprite Math Master Equations:
; ----=====================----
;
; global_x     = sprite_x - cam_x
; global_y     = sprite_y - cam_y
; global_x_ext = global_x + sprite_w
; global_y_ext = global_y + sprite_h
;
; left_truncation   = global_x     >= 0     ? 0 : -global_x
; top_truncation    = global_y     >= 0     ? 0 : -global_y
; right_truncation  = global_x_ext <= cam_w ? 0 :  global_x_ext - cam_w
; bottom_truncation = global_y_ext <= cam_h ? 0 :  global_y_ext - cam_h
;
; is_on_screen = global_x < cam_w && global_x_ext > 0
;                     && global_y < cam_h && global_y_ext > 0    
; 
; is_off_screen = global_x >= cam_w || global_x_ext <= 0
;                      || global_y >= cam_h || global_y_ext <= 0



    

; Inputs:
; hl - Sprite Address + 1 (Flags skipped)
; Ouputs:
; ixl - left_truncation
; ixh - top_truncation
; iyl - right_truncation
; iyh - bottom_truncation
; a   - Rotation (based on position)
sprite_truncation:
    ; inc hl (sprite addr skipped)

    ; First load in the X position (pixels)
    ld e, (hl) \ inc hl
    ld d, (hl) \ inc hl
                 inc hl ; Skip col width
    ld bc, (cur_camx)

; left_truncation   = global_x     >= 0     ? 0 : -global_x
    ex de, hl
        xor a ; Reset carry, and zero out a!
        sbc hl, bc
        

        ; Handle bit rotation
        ex af, af'
            ld a, 7 ; magically, this works for both positive and negative values!!!
            and l
        ex af, af'
        
        jp p, @positive_globalx
            sub l ; a = -global_x (truncated)
        @positive_globalx:
        ld ixl, a
    ex de, hl

; right_truncation  = global_x_ext <= cam_w ? 0 :  global_x_ext - cam_w
    ; Pixel width
    ld c, (hl) \ inc hl
    ld b, (hl) \ inc hl
    ex de, hl
        ; hl comes from global_x (above)
         
        add hl, bc ; global_x_ext
        ld bc, 96 ; 96 pixel wide: TODO: THIS MIGHT NEED ABSTRACTED OUT

        xor a \ sbc hl, bc
        jp m, @no_right_trunc
            ld a, l
        @no_right_trunc:
        ld iyl, a
    ex de, hl

; top_truncation    = global_y     >= 0     ? 0 : -global_y
    ; Y position
    ld e, (hl) \ inc hl
    ld d, (hl) \ inc hl

    ld bc, (cur_camy)
    ex de, hl
        xor a
        sbc hl, bc

        jp p, @positive_global_y
            sub l
        @positive_global_y:
        ld ixh, a
    ex de, hl

; bottom_truncation = global_y_ext <= cam_h ? 0 :  global_y_ext - cam_h
    ld b, 0    ; Height is only 8-bit (we only need 64 rows after all)
    ld c, (hl) \ inc hl
    ex de, hl
        add hl, bc ; global_y_ext
        ld c, 64

        xor a
        sbc hl, bc
        jp m, @no_bottom_trunc
            ld a, l
        @no_bottom_trunc:
        ld iyh, a
    
    ; ex de, hl ; Not needed
    ex af, af'
    ret



; Calculate the renderlist entry for a sprite, it updates a sprites exiting entry
; if one is found, otherise it uses the provided one
; Inputs:
; hl = Sprite list entry
; de = Render list entry
; bc = Screen to place the sprite on
; ; Outputs:
; Zero is set iff renderlist was incremented
; de - Possibly incremented render list entry
; bc - Restored
PUBLIC calculate_rl
calculate_rl:
    ld a, (hl)

    rra    
    ret nc ; Sprite is disabled
    inc hl

    ld (@screen_placed_on+1), bc

    push hl
        inc hl \ inc hl ; Skip X
        ld a, (hl)
        ld (@col_width+1), a

        ; Advance, skip width, and Y
        ld bc, 5        
        add hl, bc
        
        ld a, (hl)
        ld (@height+1), a
        inc hl
           
        ld a, (hl)
        or a

        inc hl
        jr z, @zero ; Likely to fall through
            ; Endianess hack: This is correct
            ld d, (hl)
            dec hl
            ld e, (hl)
            inc hl
        @zero:
        inc hl
        ld (@sprite_table+1), hl
        

    ex af, af' ; Send the zero flag to the shadow realm

    
    pop hl
    

    ; Set the render flag
    ld a, 1
    ld (de), a
    inc de

@req_trunc:
    ld iy, de ; Z88DK macro
    call required_truncation


    ; Outputs:
    ; ixl - Width truncation
    ; ixh - Height truncation
    ; hl - Offset in screen [0, 768*2)
    ; b  - x truncation
    ; c  - y truncation
    ; a  - Rotation [0, 7]

    ; BaseSprite = *(after_rl_ptr + a*2)
    ; SpriteAddr = BaseSprite + y_trunc + x_trunc*3*col_width 
@screen_placed_on:
    ld de, 0000h ; SMC: Screen we are placing it on
    add hl, de
    ld (iy+2), l
    ld (iy+3), h



@sprite_table:
    ld hl, 0000h ; SMC: The sprite table
    add a ; a *= 2 for ptr offset in the rotation table

    add_hl_a
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a

    ; Add in the y truncation
    ld d, $0
    ld e, a

    ; *3 for pixel size
    add hl, de
    add hl, de
    add hl, de
    


    ; X truncation amount
    ld a, 12 ; Bytes needed to totally skip the addition
    sub b
    ld (@col_mult+1), a 


    ; Width - x_truncation - width_truncation
@col_width:
    ld a, 00h ; SMC: set to the width
    sub b
    sub ixl
    ld (iy+4), a

   
; Add the y and height truncation (one should be zero, but this works)
    ld a, ixh
    add c
    ld (iy+6), a

    ; A single col is of size 3*h, therefore when adjusting for x truncation,
    ; we need to add 3*h
@height:
    ld a, 00h ; SMC: Height
    ld (iy+5), a ; Full height

    ld d, $0
    ld e, a

    add a ; This is safe since the screen is 96 pixels tall
    ld b, d
    ld c, a

    ex de, hl \ add hl, bc \ ex de, hl


    ; I know this looks slow, but mul_16_16x8_fast uses 240 cycles in the BEST case,
    ; and we know the col truncation amount is going to be mostly small (mostly 0-2 cols)
    ; values, so this beats real multiplication in ALL (valid) cases!
@col_mult:
    jr $+2 ; SMC: Set to the amount to truncate
    REPT 12 ; Maximum (supported) col truncation amount
        add hl, de
    endr
    ld (iy+0), l
    ld (iy+1), h


    ex af, af' ; Send the zero flag to the shadow realm

    ld bc, (@screen_placed_on+1) ; Restore screen
    ret nz ; Unlikely to fall through

    ld hl, 6
    ld bc, iy

    add hl, bc
    ex de, hl
    ret
   
   
    ; Inputs:
    ; de = Input sprite
    ; hl = Output location on screen
    ; ixl  = Width in cols (can be truncated)
    ; a  = Full Height (what the sprite actually is)
    ; b  = Height truncation (cols to remove from bottom)
    
    

    
        

    

