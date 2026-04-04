
; Copies 12 bytes with the stack.
; 
; Inputs: 
;  iy = source
;  ix = destination
;  de = destination offset (typically 12)
;  de' = source offset (or sride)
; Outputs:
;  iy += de'
;  iy += de
;  sp = ix + 12
; 
; Clobbers: af, bc, hl, af', bc', hl'
; Perserves: de, de`
; t-states: 192
MACRO fastcpy_12
    ld sp, iy

    pop af
    pop bc
    pop hl
    
    ex af, af' ; flags free to clobber 
    add ix, de ; dst += dst_offset (12)
    exx
    add iy, de ; src += stride

    pop af
    pop bc
    pop hl

    ld sp, ix

    push hl
    push bc
    push af

    exx
    ex af, af'

    push hl
    push bc
    push af
  ENDM



; Copies 14 bytes with the stack. Used de
; for the stride for BOTH dst and src
; 
; Inputs: 
;  iy = source
;  ix = destination
;  de = source and destination stride
; Outputs:
;  iy += de
;  iy += de
;  sp = ix + 14
; 
; Clobbers: af, bc, hl, af', bc', hl', de'
; Perserves: de, de`
; t-states: 213 
MACRO fastcpy_14s_stride
    ld sp, iy

    pop af
    pop bc
    pop hl
    
    ex af, af' ; flags free to clobber 
    add ix, de ; dst += stride
    add iy, de ; src += stride
    exx

    pop af
    pop bc
    pop hl
    pop de

    ld sp, ix

    push de 
    push hl
    push bc
    push af

    exx
    ex af, af'

    push hl
    push bc
    push af
  ENDM
