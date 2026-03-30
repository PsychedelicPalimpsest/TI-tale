EXTERN fast_copy_counter
EXTERN fast_copy_sp_restore


; C entry point for screenbg_blit. It is:
; screenbg_blit(char* dst_plus_12, char* src, int stride) __z88dk_callee;
_screenbg_blit:
  pop af ; ret ptr
  pop de ; stride
  pop iy ; src
  pop ix ; dst+12
  push af

  ; Fall through

; Copies the background to the screen buffer.
; Screen buffer is defined as a 768*2 size buffer
; ix=dst+12
; iy=src
; de=stride src diff
screenbg_blit:
  ld (fast_copy_sp_restore), sp
  ld a, -12 ; 96/16*2=12
  ld (fast_copy_counter), a

  ; Now de` is the stride 
  exx
  ld de, 12 ; de = dst len
  exx

  ; Now:
  ; de  = stride
  ; de` = 12
  
  MACRO fastcpy_12
    ld sp, iy
    add iy, de ; src += stride

    pop af
    pop bc
    pop hl
    
    exx
    ex af, af'
    add ix, de ; dst += 12

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

loop:
  fastcpy_12 \ fastcpy_12 \ fastcpy_12 \ fastcpy_12
  fastcpy_12 \ fastcpy_12 \ fastcpy_12 \ fastcpy_12
  fastcpy_12 \ fastcpy_12 \ fastcpy_12 \ fastcpy_12
  fastcpy_12 \ fastcpy_12 \ fastcpy_12 \ fastcpy_12
  ld hl, fast_copy_counter
  dec (hl)
  jp nz, loop


  ld sp, (fast_copy_sp_restore)
  ret
