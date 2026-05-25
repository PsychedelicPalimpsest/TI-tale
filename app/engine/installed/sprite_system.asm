; KEEP ME FIRST
ALIGN 256
bitset_lookup:
REPTI val, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
  ; When the 0-ith col is dirty, the highest bit is set
 DEFW 1 << (15-val)
ENDR

; Takes a location on the screen buffer, and marks that col as dirty.
; Inputs: hl = Location on screen
; Clobbers: hl, a
; T-states: 124

PUBLIC mark_col_dirty
mark_col_dirty:
; a=2*col number
  add hl, hl ; Get col bits into high byte
  ld a, h
  sub ((_screen_buffer*2) >> 8) & 0xFF
  and %1111 ; Stupid bounds checking, just keeps the input within the lookup table
  add a

;hl = Location in lookup table
  ld h, bitset_lookup >> 8
  ld l, a

; Do the high byte
  ld a, (dirty_cols)
  or (hl)
  ld (dirty_cols), a

; Do the low byte
  inc l ; Due to alignment cannot carry
  ld a, (dirty_cols+1)
  or (hl)
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



; Rotates an input buffer into an output buffer. Simply reset bc,
; to run one after another. The first column needs zero'd!
; Inputs:
;  de =  Input location
;  ix =  Output location + height
;  b  =  Height (Height cannot be more then 128)
;  c  =  0 
;  a  =  7-rot
;
; Clobbers: hl, a
; Outputs: ix += height, de += height
;
; Optimal usage: Only call bitro on the first col, after that call bitro_subsequent

PUBLIC bitro, bitro_subsequent
DEFC bitro_subsequent = bitro@loop

bitro:
    ld (@rot_pt+1), a

    ld a, b \ neg
; DD XX N where N is the +d part (this is why height is limited)
    ld (@set_curr1+2), a
    ld (@set_curr2+2), a

@loop:
    ld a, (de)

    ld l, a
    ld h, c ; C is assumed to be zero (3 cycle savings per loop!)

@rot_pt:
    jr $+2
    REPT 7
        add hl, hl
    endr

; Combine with the previous value which could be here
@set_curr1: ld a, (ix+0) \ or l
@set_curr2: ld (ix+0),  a

    ld (ix), h

    inc ix
    inc de

    djnz bitro
    ret




; Inputs:
; de = sprite
; ix = output
; bc  = height (cannot be more then 128)
; iyl = width
;
; WARNING: Please zero the first output column
PUBLIC bitro_full
bitro_full:
    add ix, bc

    ld a, c
    ld c, b
    ld b, a

    ld (@loop+1), a

    call bitro

    dec iyl
    ret z ; One col sprites

@loop:
    ld b, 00h ; Restore height (smc)
    call bitro_subsequent

    dec iyl
    jp nz, @loop

    ret

