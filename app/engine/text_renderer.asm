SECTION code_engine

INCLUDE "core/asm_globals.def"
INCLUDE "core/Ti83p.def"
PUBLIC write_ti_large
PUBLIC write_ti_small

; Write a small font char to the screen at location de
; Inputs:
;  hl = input font code (see appendix of https://dn710703.ca.archive.org/0/items/83psdk/sdk83pguide.pdf)
;  de = output location in screen buffer
; Destroys: Bc
write_ti_small:
; hl *= 8
  add hl, hl
  add hl, hl
  add hl, hl

  push de
  bcall _Load_SFont ; input=hl, output=hl
  pop de


  REPT 8
    ldi
    dec hl
    ldi
  ENDR
  ret

DEFC _Load_LFontV2	=		806Ch
DEFC _Load_LFontV		=  	806Fh

; Write a large font char to the screen at location de
; Inputs:
;  hl = input font code (see appendix of https://dn710703.ca.archive.org/0/items/83psdk/sdk83pguide.pdf)
;  de = output location in screen buffer
; Destroys: Bc
write_ti_large:
; hl *= 8
  add hl, hl
  add hl, hl
  add hl, hl

  push de
  bcall _Load_LFontV ; input=hl, output=hl
  pop de

  REPT 8
    ldi
    dec hl
    ldi
  ENDR
  ret
