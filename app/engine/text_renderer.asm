SECTION code_engine
;
; INCLUDE "core/asm_globals.def"
; INCLUDE "core/Ti83p.def"
;
; PUBLIC write_ti_large
; PUBLIC write_ti_small
;
; PUBLIC _write_ti_large
; PUBLIC _write_ti_small
;
;
;
; ; ----======================----
; ;   Assorted font copy routines
; ; ----======================----
;
; ; Inputs:
; ; hl = source
; ; de = destination on screen
; ; hl' = variable shift amount (shift_var is enabled)
; MACRO text8x do_3x, do_cpl 
;   ld c, a
;
;   ; First byte is the width
;   ld a, (hl)
;   ex af, af'
;   ld a, (hl)
;   inc hl
;
;   IF shift_var
;     ; we need to shift by: 8-c-w = -c-w + 8
;     cpl
;     sub c
;     add $8
;     ld c, a
;   ENDIF
;
;
;   REPT 7
;     ld a, (hl)
;     inc hl
;
;
;     rlca
;     rlca
;     rlca
;     rlca
;     rlca
;     rlca
;     rlca
;
;     IF 1==do_3x
;       ld (de), a
;       inc de
;     endif
;
;     ; Done after the trans byte, this way it is unmolested
;     IF 1==do_cpl
;       cpl
;     endif
;
;     ld (de), a
;     inc de
;     ld (de), a
;     inc de
;   endr
; endm
;
;
;
; copy_8x2_bytes:
;   ld a, c
;   exx
;   text8x 0, 0, 0
;   ret
; copy_8x2_bytes_cpl:
;   ld a, c
;   exx
;   text8x 0, 1, 0
;   ret
;
; copy_8x3_bytes:
;   ld a, c
;   exx
;   text8x 1, 0, 0
;   ret
; copy_8x3_bytes_cpl:
;   ld a, c
;   exx
;   text8x 1, 1, 0
;   ret
;
; copy_8x2_bytes_shifted:
;   ld a, c
;   exx
;   text8x 0, 0, 1
;   ret
; copy_8x2_bytes_cpl_shifted:
;   ld a, c
;   exx
;   text8x 0, 1, 1
;   ret
;
; copy_8x3_bytes_shifted:
;   ld a, c
;   exx
;   text8x 1, 0, 1
;   ret
; copy_8x3_bytes_cpl_shifted:
;   ld a, c
;   exx
;   text8x 1, 1, 1
;   ret
;
;
;
; copy_8x_table: 
;   jp copy_8x2_bytes \ jp copy_8x2_bytes_cpl \ jp copy_8x3_bytes \ jp copy_8x3_bytes_cpl
;   jp copy_8x2_bytes_shifted \ jp copy_8x2_bytes_cpl_shifted \ jp copy_8x3_bytes_shifted \ jp copy_8x3_bytes_cpl_shifted
;
;
; MACRO load_font_viahl call_routine
; ; hl *= 8
;   add hl, hl
;   add hl, hl
;   add hl, hl
;
;   push de
;   bcall call_routine ; input=hl, output=hl
;   pop de
; endm
;
;
; ; extern char write_ti_small(void* screen_loc, int font_code, int copy_mode) __z88dk_sdccdecl __z88dk_callee;
; _write_ti_small:
;   pop af
;   pop de ; screen loc
;   pop hl ; font code 
;
;   exx \ pop hl \ ld c, h \ ld h, $0 \ exx ; copy mode
;   push af
;
;
; ; Write a small font char to the screen at location de
; ; Inputs:
; ;  hl  = input font code (see appendix of https://dn710703.ca.archive.org/0/items/83psdk/sdk83pguide.pdf)
; ;  de  = output location in screen buffer
; ;  hl` = copy mode, index*3 into copy_8x_table
; ; Output:
; ;  de = location on screen after the char
; ;  l = char width
; ; Destroys: Bc
; write_ti_small:
;   load_font_viahl _Load_SFont
;
;   exx
;
;   ld de, copy_8x_table
;   add hl, de
;
;   jp (hl) ; tail call
;
; DEFC _Load_LFontV2	=		806Ch
; DEFC _Load_LFontV		=  	806Fh
;
;
;
; ; extern char write_ti_large(void* screen_loc, int font_code, int copy_mode) __z88dk_sdccdecl __z88dk_callee;
; _write_ti_large:
;   pop af
;   pop de ; screen loc
;   pop hl ; font code 
;
;   exx \ pop hl \ ld c, h \ ld h, $0 \ exx ; copy mode
;   push af
; ; Write a large font char to the screen at location de, inverting the color
; ; Inputs:
; ;  hl = input font code (see appendix of https://dn710703.ca.archive.org/0/items/83psdk/sdk83pguide.pdf)
; ;  de = output location in screen buffer
; ;  hl` = copy mode, index*2 into copy_8x_table
; ; Output:
; ;  de = location on screen after the char
; ;  l = char width
; ; Destroys: Bc
; write_ti_large:
;   load_font_viahl _Load_LFontV
;
;   exx
;   ld de, copy_8x_table
;   add hl, de
;
;   jp (hl) ; tail call
;

