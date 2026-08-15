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


; ==============================================================================
; DATA STRUCTURE: Sprite Cache Entry (Runtime Sprite Instance)
; ==============================================================================
; Description:
;   Dynamic runtime sprite instance allocated within the sprite cache pool.
;   Contains bounding/coordinate metadata, a pointer back to its Render List entry,
;   a lookup table of 8 pre-rotated frame pointers, and the cached pixel buffers.
;
; Offset | Size | Field Name     | Description
; -------+------+----------------+----------------------------------------------
;  +00h  |   1  | flags          | Bit 0: Active / Render enabled flag (0=off, 1=on)
;  +01h  |   2  | x_pos          | Global X coordinate in pixels (16-bit word, LE)
;  +03h  |   1  | width_cols     | Width in columns (includes +1 rotation carry col)
;  +04h  |   2  | width_px       | Width in pixels = (width_cols * 8) (16-bit word, LE)
;  +06h  |   2  | y_pos          | Global Y coordinate in pixels (16-bit word, LE)
;  +08h  |   1  | height_px      | Full height in pixels / scanlines (8-bit)
;  +09h  |   2  | rl_entry_ptr   | Pointer to active Render List entry (0 = none)
;  +0Bh  |  16  | rot_ptrs[8]    | Table of 8 word pointers (rot 0..7) to pre-rotated
;        |      |                | cache frame buffers below (+0Bh to +1Ah)
;  +1Bh  |  var | cache_data     | 8 consecutive pre-rotated sprite buffers.
;        |      |                | Size per frame = (width_cols * height * 3) bytes
; -------+------+----------------+----------------------------------------------
; Header Size: 27 bytes (+00h through +1Ah)
; Total Size : 27 + (8 * width_cols * height_px * 3) bytes
; ==============================================================================



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


; ==============================================================================
; DATA STRUCTURE: Render List Entry (Blit Command Queue)
; ==============================================================================
; Description:
;   An 8-byte command record generated by `calculate_rl` and consumed by
;   `blit_rl_entry`. Designed to be read directly using stack pops (SP manipulation).
;
; Offset | Size | Reg (Pop) | Field Name     | Description
; -------+------+-----------+----------------+----------------------------------
;  +00h  |   1  | c         | flags          | Bit 0: 1 = blit entry, 0 = skip
;  +01h  |   1  | b         | vert_trunc     | Total vertical rows to clip (top + btm)
;  +02h  |   1  | ixl       | vis_width_cols | Visible / clipped width in 8-px cols
;  +03h  |   1  | ixh / a   | full_height    | Unclipped sprite height in pixels
;  +04h  |   2  | de        | data_ptr       | Pointer to pre-rotated & clipped
;        |      |           |                | sprite pixel buffer in cache
;  +06h  |   2  | hl        | screen_dest    | Destination VRAM/buffer address
; -------+------+-----------+----------------+----------------------------------
; Total Size: Exactly 8 bytes
; ==============================================================================



; Input:
; hl' = Render list entry
; de' = 8
; Output:
; hl' = Next RL entry
;
; All shadow registers perserved
PUBLIC blit_rl_entry
blit_rl_entry:
    exx
        bit 0, (hl)
        jr z, no_render     ; Likely to fall through
        
        ld (@restore_sp+1), sp
        di

        ld sp, hl           ; SP = entry + 0 (aligned to entry boundary)
        add hl, de          ; hl' = entry + 1 + 7 = entry + 8 (next entry)
    exx

    ; Memory Layout:
    ; +0: flags          +1: vert_trunc
    ; +2: vis_width_cols +3: full_height
    ; +4: data_ptr (word)
    ; +6: screen_dest (word)

    pop bc                  ; c = flags, b = vert_trunc (Height truncation)
    pop ix                  ; ixl = vis_width_cols, ixh = full_height
    ld a, ixh               ; a = full_height
    pop de                  ; de = data_ptr (Input sprite pointer)
    pop hl                  ; hl = screen_dest (Output screen location)

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
;
; screen_location = (global_x > 0 ? global_x//8*cam_h*2: 0) + (global_y >= 0 ? global_y : 0)
; sprite_offset   = sprite_h*left_truncation + top_truncation


pop3x_scf_ret:
    pop af
pop2x_scf_ret:
    pop af
pop_scf_ret:
    pop af
    pop af
    scf 
    ret
    

defc st_camera_width = (sprite_truncation@cam_width + 1)
defc st_camera_height = (sprite_truncation@cam_height + 1)

; Inputs:
; hl - Sprite Address + 1 (Flags skipped)
; st_camera_width, st_camera_height MUST be set
; Ouputs:
; Carry flag is reset iff the sprite is on the screen, otherwise NO OTHER
; OUTPUTS ARE VALID. 
; 
; ixl - left_truncation
; ixh - top_truncation
; iyl - right_truncation
; iyh - bottom_truncation
; hl  - Screen X position
; de  - Screen Y position 
; bc  - Sprite height
; c'  - Sprite Width in cols
; a   - Rotation (based on position)
PUBLIC sprite_truncation, st_camera_height, st_camera_width
sprite_truncation:
    ; inc hl (sprite addr skipped)

    ; First load in the X position (pixels)
    ld e, (hl) \ inc hl
    ld d, (hl) \ inc hl

    ; Save col width for ret (b is trash)
    ld c, (hl) \ inc hl
    push bc
    
    ld bc, (cur_camx)

; left_truncation   = global_x     >= 0     ? 0 : -global_x
    ex de, hl
        xor a ; Reset carry, and zero out a!
        sbc hl, bc
        push hl
        

        ; Handle bit rotation
        ex af, af'
            ld a, 7 ; magically, this works for both positive and negative values!!!
            and l   ; Also resets carry!
        ex af, af'  ; Send rotation and reset carry flag to the shadow realm for ret!
        
        jp p, @positive_globalx
            sub l ; a = -global_x (truncated)
        @positive_globalx:
        ld ixl, a

        ; Is on screen test:
        ; global_x >= cam_w 
@cam_width:
        ld bc, 0000h ; SMC: Camera width
        CpHLBC        
        jp p, pop_scf_ret ; Likely to fall throught (but no jr p exists)

        ld a, c ; Save width later (safe to truncate)
        
    ex de, hl

; right_truncation  = global_x_ext <= cam_w ? 0 :  global_x_ext - cam_w
    ; Pixel width
    ld c, (hl) \ inc hl
    ld b, (hl) \ inc hl
    ex de, hl
        ; hl comes from global_x (above)
         
        add hl, bc ; global_x_ext
        
        ld b, 0 \ ld c, a ; Restore width 
        
        ; Is on screen test:
        ; global_x_ext <= 0
        ld a, l \ or h
        jp z, pop_scf_ret

        bit 7, h            ; Sign bit
        jr nz, pop_scf_ret ; Likely to fall throught
        

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
        xor a \ sbc hl, bc ; global_y
        push hl

        jp p, @positive_global_y
            sub l
        @positive_global_y:
        ld ixh, a

        ; Is on screen test: 
        ; global_y >= cam_h
@cam_height:
        ld bc, 0000h ; SMC: Camera height
        CpHLBC
        jp p, pop2x_scf_ret
        ld a, c ; Store for later
    ex de, hl

; bottom_truncation = global_y_ext <= cam_h ? 0 :  global_y_ext - cam_h
    ld b, 0    ; Height is only 8-bit (we only need 64 rows after all)
    ld c, (hl) \ inc hl
    push bc
    ex de, hl
        add hl, bc ; global_y_ext
        ld b, 0 \ ld c, a ; Camera height

        ; Is on screen test: 
        ; global_y_ext <= 0
        ld a, h \ or l
        jr z, pop3x_scf_ret

        bit 7, h
        jr nz, pop3x_scf_ret

        xor a
        sbc hl, bc
        jp m, @no_bottom_trunc
            ld a, l
        @no_bottom_trunc:
        ld iyh, a
    
    ex af, af' ; Rotation + reset carry flag
    pop bc
    pop de
    pop hl
    exx \ pop bc \ exx
    ret


not_on_screen:
    pop af ; Trash sprite ptr
    pop de ; Restore RL entry
    ld a, 1
    or a ; reset zero flag
    ret

; Calculate the renderlist entry for a sprite, it updates a sprites exiting entry
; if one is found, otherise it uses the provided one
; Inputs:
; hl = Sprite list entry
; de = Render list entry
; bc = Screen to place the sprite on
; st_camera_width, st_camera_height MUST be set correctly
; 
; Outputs:
;  Zero flag is set iff renderlist was incremented
;  de = renderlist entry, possibly incremented
;
;  Only valid if on screen (not reliable):
;   ixl - left_truncation
;   ixh - top_truncation
;   iyl - right_truncation
;   iyh - bottom_truncation
;
; Clobbers: bc', ix, iy, hl, bc, af, af'
; Perserves: hl', de'
PUBLIC calculate_rl
calculate_rl:
    ld a, (hl)

    rra    
    ret nc ; Sprite is disabled

    ld (@screen+1), bc

    inc hl
    push de ; Save for return
    push hl ; Save for later

    ; Skip to rl entry
    ld bc, 9+1-1 ; Plus high byte, minus the flag byte
    add hl, bc

    ld a, (hl) 
    or a   ; A valid rl entry CANNOT have a zero high byte
    jp nz, @has_rl_entry
    ; Has no rl entry
        ld (hl), d
        dec hl
        ld (hl), e
        inc hl \ inc hl
        jp @de_set
    @has_rl_entry:
        ld d, a
        dec hl
        ld e, (hl)
        inc hl \ inc hl
@de_set:
    ld (@sprite_table+1), hl

    ld hl, 8 ; RL entry size
    add hl, de
    ld (@set_sp+1), hl
    
    pop hl  ; Start of sprite
    push af ; Save zero flag for later (not clobbered by add)

    call sprite_truncation

    ; Ouputs:
    ; Carry flag is reset iff the sprite is on the screen, otherwise NO OTHER
    ; OUTPUTS ARE VALID. 
    ; 
    ; ixl - left_truncation
    ; ixh - top_truncation
    ; iyl - right_truncation
    ; iyh - bottom_truncation
    ; hl  - Screen X position
    ; de  - Screen Y position 
    ; bc  - Sprite height
    ; c'  - Sprite Width in cols
    ; a   - Rotation (based on position)
    
    jr c, not_on_screen ; Likely to fall through
    ex af, af' ; Save rotation for later

    ld a, c
    ld (@full_height+1), a


    ld (@restore_sp+1), sp
@set_sp: ld sp, 0000h
    ; Now the stack is our output
    push bc ; Save for later

    bit 7, h
    
    @style: ; SMC point for switching screen size 
    jp z, @positive_globalx_style64
        ld hl, 0
        jp @after_mult

    @positive_globalx_style64:
        ; Here, we are using a variation of the formula for the typical 64px tall screen
        ; global_x /8 * 64 * 2 = global_x * 16 

        ; Remove pesky inter col crap
        ld a, ~7
        and l
        ld l, a

        REPT 4
            add hl, hl
        endr
        jp @after_mult

    @positive_globalx_style128:
        ; Here, we are using a variation of the formula for the background 128px tall screen
        ; global_x /8 * 128 * 2 = global_x * 32

        ; Remove pesky inter col crap
        ld a, ~7
        and l
        ld l, a

        REPT 5
            add hl, hl
        endr
@after_mult:

    bit 7, d
    jr nz, @screen
        ; *2 for the screen size
        add hl, de
        add hl, de
@screen:
    ld bc, 0000h ; SMC: Screen location
    add hl, bc

    ; Put: screen location
    ; Get: Sprite height
    ex (sp), hl 
    ld a, ixh
    or ixl
    jr nz, @with_tl_truncation ; Likely hot path
        ld de, 0
        jp @sprite_table
@with_tl_truncation:    
    ; c = sprite height *3
       ; Note: We only allow sprites as big as the screen, and since 64*3 < 256, this is safe
        ld a, l
        add a
        add l
        ld b, $0
        ld c, a

    ; hl = 3*top truncation
    ld h, b ; Zero high byte
    ld a, ixh \ add a \ add ixh \ ld l, a 

    ; A = left truncation / 8
    ld a, ixl ; left truncation

    ; Pixel to col:
        add 7 ; Round up
        rrca \ rrca \ rrca \ and 31 ; >>3

    cpl \ add 12+1
    ld (@left_trunc_loop+1), a

    ; This looks slow, but when you consider that truncations values must be lower
    ; then 12, this always is better then mul_16_16x8_fast, and usually faster then
    ; mul_16_16x4_fast (since zero truncation is the norm)
    @left_trunc_loop:
    jr $+2
    REPT 12
        add hl, bc
    endr
    ex de, hl

; Re-entry point for no truncation path
@sprite_table:
    ld hl, 0000h 

    ex af, af'
    add a
    add_hl_a

    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a
    
    add hl, de ; Add in the offset
    push hl

    exx ; To get access to the width in cols


    ld a, ixl  ; Left truncation    
    add iyl    ; Right truncation

    jp z, @full_height ; No lr truncation = no need to change width 

    ; Pixel to col:
        add 7 ; Round up
        rrca \ rrca \ rrca \ and 31 ; >>3

    neg \ add c
    ld c, a   ; Little endian: First byte is little
@full_height:
    ld b, 00h ; SMC: Full height 
    push bc

    ld a, ixh ; Top trunc
    add iyh   ; Bottom trunc
    
    ld b, a
    ld c, 1   ; Set the do-display flag

    push bc

    @restore_sp: ld sp, 0000h
    exx ; Round amount of shadow reg switches (minimize nuked shadows to bc)

    pop af ; Zero flag from earlier
    pop de
    
    ret nz ; Return if rl does not need incremented (most common)

    ; Increment de:
        ld hl, 8
        add hl, de
        ex de, hl
    
    ret


