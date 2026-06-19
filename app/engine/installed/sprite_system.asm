; KEEP ME FIRST
ALIGN 256

to_run:
macro _gen x
    DEFB ((x)/3*2) + (runs&0xFF)

    IF x+1 != 48
        _gen x+1
    ENDIF
endm
_gen 0

runs:
macro _gen2 x
    DEFW (1<<(x))-1
    IF x != 0
        _gen2 x-1
    ENDIF
endm
_gen2 16


; We split the screen into 16 different segments. Laid out as groups of 4 rows. 
; Since rows are 12 bytes, we need a small lookup sable to divide by 3 quickly,
; and another is used to quickly compute byte runs
;

MACRO hl_to_run
    add hl, hl
    add hl, hl
    add hl, hl

    ld a, -((_screen_buffer>>8) *8) & 0xFF
    add h
    ld h, to_run>>8
    ld l, a

    ld l, (hl)
endm


; Takes a location on the screen buffer, and marks that col as dirty.
; Inputs: hl = Location on screen

PUBLIC mark_col_dirty
mark_col_dirty:
    ld b, 0

;Inputs: 
; hl = location on screen
; b  = height

PUBLIC mark_region_dirty
mark_region_dirty:
    hl_to_run
    ex hl, de

    ld a, b

    and 3^0xFF
    rrca

    add e
    add 2

    ld h, d
    ld l, a

    ld bc, (dirty_cols)
    
    ld a, (de)
    xor (hl)
    or b
    ld (dirty_cols), a

    inc e \ inc l

    ld a, (de)
    xor (hl)
    or c
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

; Copies 768*2 bytes QUICKLY. Assumes interupts are disabled
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
    ret


; Rotating blit into the 96x64 screen buffer layout.
;
; Inputs:
;   HL = output buffer + 768*2
;   DE = end of input display region
;        (= input buffer + 64*(stride-14))
;   BC = input buffer stride
;   A  = rotate count in bits (0..7)
;
; Outputs:
;   Writes 64 rows × 12 bytes to the output buffer, backwards from HL.
;
; Clobbers:
;   AF, BC, DE, HL, IX, IY
PUBLIC scrot_blit
scrot_blit:
    ; Rotation=0 means we can quickly copy it into place via stack
    or a \ jr z, @fast_path

    ; Rotation greater 4 can be optimized by using a different shift method
    cp 5 \ jp c, @lessthen_5
        add -5
        jp _using_right

@lessthen_5:
    neg
    add 4
    jp _using_left



@fast_path:
    push bc
    exx
        pop de
        ld hl, -14
        add hl, de
        ex de, hl
    exx

    ; Z88dk macros
    ld ix, hl ; output into dst
    ld iy, de ; input into src


    ld de, -12

    di ; This needs interupts disabled
    ld (@sp_restore+1), sp

@copy_loop:
REPT 8
    fastcpy_12_samestridebackwards
    fastcpy_12backwards
ENDR
    ld a, _screen_buffer >> 8
    cp ixh
    jp nz, @copy_loop
    ld a, _screen_buffer & 0xFF
    cp ixl
    jp nz, @copy_loop

@sp_restore: ld sp, 0000h
    ei
    ret


    


macro _leftmethod label
    ld e, $0
    ld a, (hl)
    label: jr $+2 ; SMC: Rot amount
    REPT 4   ; This method uses an extra layer to allow rot by a nibble
        rla
        rl e
    endr
endm
macro _rightmethod label
    ld e, (hl)
    xor a
    label: jr $+2 ; SMC: Rot amount
    REPT 3
        rr e
        rra
    endr
endm

macro _rot_scr method
; If you thing about it, why disable interupts, most likely it will just be
; overwritten by the next iteration, hopefully ¯\(°_o)/¯
    ld (@restore_sp+1), sp
    ld sp, hl
    ld (@do_stride+1), bc

; a *= 3
    ld b, a
    add a
    add b

    ld (@cin_rot1+1), a
    ld (@cin_rot2+1), a
    ld (@rot1+1), a
    ld (@rot2+1), a

    ; Input is now in hl
    ex de, hl


    ld ixl, 64
@outer_loop:
; Build initial carry in
    dec hl
    method @cin_rot1
    ld b, e

    dec hl
    method @cin_rot2
    ld c, e

    ld iyl, 12
    @row_loop:
        dec hl
        method @rot1
        or b
        ld b, e
        ld d, a

        dec hl
        method @rot2
        or c
        ld c, e
        ld e, a

        push de

        dec iyl
        jp nz, @row_loop

@do_stride: ld bc, 0000h ; SMC: Input stride
    add hl, bc
    
    dec ixl
    jp nz, @outer_loop

@restore_sp: ld sp, 0000h
    ret
endm

_using_left:  _rot_scr _leftmethod
_using_right: _rot_scr _rightmethod




; inputs:
; hl = output location
; de = input location
; a = width (pixels/8)
; ixh = height
; outputs:
; hl = the output location advanced to the next row, directly under the placed sprite
public norot3x2_blit
norot3x2_blit:
    push hl
    ld (@height_loop+1),           a
    ld (@height_pre_mark_dirty+1), a

; this is the amount of bytes needed to get to the next row.
; 24 - 2*w = 2*(-w + 12)
    neg
    add 12
    add a
    ld (@advance_row +1), a


@height_loop:
    ld b, 0
@width_loop:
; mask to b
    ld a, (de)
    ld c, a
    inc de

; shuffle in light byte
    ld a, (de)
    xor (hl)
    and c
    xor (hl)
    ld (hl), a
    
    inc hl \ inc de

; shuffle in dark byte
    ld a, (de)
    xor (hl)
    and c
    xor (hl)
    ld (hl), a


    inc hl \ inc de

    djnz @width_loop

; b is already zero
@advance_row:
    ld c, $0
    add hl, bc

    dec ixh
    jp nz, @height_loop

    pop hl ; Restore height
@height_pre_mark_dirty:
    ld a, 00h ; SMC: restore height

    jp mark_region_dirty ; Tail call

; Inputs:
; hl = Input location
; de = Output location
; a = Width   (Pixels/8)
; ixh = Height
public norot2x2_blit
norot2x2_blit:
    push hl
    ld ixl, ixh

    add a
    ld (@height_loop+1), a

; This is the amount of bytes needed to get to the next row.
; 24 - 2*w = 2*(-w + 12)
    neg
    add 12
    add a
    ld (@advance_row +1), a   


@height_loop:
    ld bc, 0000h
    ldir    ; Just copy the bytes over

; B is already zero
@advance_row:
    ld c, $0
    add hl, bc

    dec ixh
    jp nz, @height_loop

    pop hl ; restore old start loc
    ld a, ixl ; Restore height
    jp mark_region_dirty ; Tail call



