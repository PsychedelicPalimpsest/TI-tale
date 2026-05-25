
; Rotates an input buffer into an output buffer. Simply reset bc,
; to run one after another. The first column needs zero'd!
; Inputs:
;  de = Input location
;  ix = Ouput location
;  bc  = Height (CANNOT BE MORE THEN 127)
;  a  = 7-rot
;
; Clobbers: hl, a
; Outputs: ix += height, de += height, bc=0
bitro:
    ld (@rot_pt+1), a

    ld a, c
; DD 74 N where N is the +d part
    ld (@stride_out+2), a

@loop:
    ld a, (de)

    ld l, a
    ld h, b ; b is assumed to be zero

@rot_pt:
    jr $+2
    REPT 7
        add hl, hl
    endr

; Combine with the previous value which could be here
    ld a, (ix) \ or l
    ld (ix),   a

@stride_out:
    ld (ix+0), h

    inc ix
    inc de

    dec c
    jp nz, @loop






