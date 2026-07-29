SECTION code_engine

INCLUDE "core/common.inc"

DEFC _Load_LFontV = 806Fh
font_select:
  exx
      bit 2, c
  exx


; HACK: The os uses iy+$35 for temp state. This ensures is has a byte to write to. 
;       This is only 'safe' because I have verified that with *this* TI-OS version
;       *this* routine only uses this flag
  ld iy, free_trash_byte - $35

  jp z, @Load_SFont
  bcall _Load_LFontV 
  ret


@Load_SFont: bcall _Load_SFont \ ret




EXTERN rotate_plane
EXTERN restore_sp_and_ret

; Inputs:
; hl' = Ouput buffer
; hl  = character * 8 
; e'  = Output buffer height (*2 for greyscale)
; c'   = Color mode
; 
; b'   = Base rotation amount (default to 8)
;
; Output:
; b'  = Next rotation amount (b` - width % 8)
; hl' = new output buffer location (does NOT wrap around at end of buffer)
MACRO _char_blit N
    ld (restore_sp_and_ret+1), sp

; Allocate temp space (two cols of 7 cells each)
    ld de, $0
    REPT 7
        push de
    endr

    ; Get the sprite
    call font_select
    ex de, hl
    ld a, (de) ; Width of char, less then 8 
    inc de

    ; Handle char positioning (we need to do this here since ti right aligned them)
    exx
        add b
        cp 8
        jp c, @not_negative ; Jump is sign bit RESET 

        ; Handle negative Rotation
        sub 8
        ld d, $0
        add hl, de ; Go to the next col (no end of buffer handling)
        @not_negative:    
    exx
   
    

    ; Ouput location
    ld hl, $0
    add hl, sp

    ld ixl, $1 ; Width
    ld b, 7    ; Height
               ; rotation comes from a from above


    call rotate_plane
    ex af, af' ; Save rot amount to shadow a

    exx
        push hl
    exx
    pop de

    ld hl, $0
    add hl, sp
    ex de, hl

    push hl ; Save output location for final restore
    exx

    ; Set the color mode based on c
        ld hl, $0000

        push bc ; Save color mode

            ld a, c    ; Color mode
            rra        ; Get bit 0 (dark color) 
            jp c, @after_dark
                ld l, $af ; Do nothing to that bit
    @after_dark:
            rra        ; Get bit 1 (light color)
            jp c, @after_light
                ld h, $af ; Do nothing to that bit
    @after_light:

            ld ixl, 2 ; Width (cols)
            ld a, 7   ; Height
            ld c, e   ; Output height
        
            EXTERN norot1x##N##_xorblit
            call norot1x##N##_xorblit


        
    ; Set new output buffer, color mode, and rotation amount
    exx
        pop bc ; Restore color mode
        pop hl  ; Restore output buff
        ex af, af'
        ld b, a
    exx

    jp restore_sp_and_ret ; Tail call out and restore sp
endm

PUBLIC char_x2blit
char_x2blit:_char_blit 2
PUBLIC char_x3blit
char_x3blit:_char_blit 3


