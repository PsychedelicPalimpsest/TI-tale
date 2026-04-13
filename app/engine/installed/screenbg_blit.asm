PUBLIC _screenbg_blit
PUBLIC screenbg_blit


; C entry point for screenbg_blit. It is:
; void screenbg_blit(char* dst, char* src, int stride) __z88dk_callee;
_screenbg_blit:
  pop af ; ret ptr
  pop de ; stride
  pop iy ; src
  pop ix ; dst
  push af

  ; Fall through

; Copies the background to the screen buffer.
; Screen buffer is defined as a 768*2 size buffer
;
; NOTE:  Although designed for mode 7 lcd drawing (left to right), mode 5
;        works perfectly fine!
; NOTE2: The screen buffer has amble space after is, so this stack trickery
;        is not horrible. 
;
; Inputs:
; ix=dst
; iy=src
; de=stride src diff
screenbg_blit:
  ld (fast_copy_sp_restore), sp
  ld a, 12 ; 96/16*2=12
  ld (fast_copy_counter), a

  ; Now de` is the stride 
  exx
  ld de, 12 ; de = dst len

  ; Now:
  ; de`  = stride
  ; de = 12
  


@loop:
  fastcpy_12 \ fastcpy_12 \ fastcpy_12 \ fastcpy_12
  fastcpy_12 \ fastcpy_12 \ fastcpy_12 \ fastcpy_12
  fastcpy_12 \ fastcpy_12 \ fastcpy_12 \ fastcpy_12
  fastcpy_12 \ fastcpy_12 \ fastcpy_12 \ fastcpy_12
  ld hl, fast_copy_counter
  dec (hl)

  jp nz, @loop


  ld sp, (fast_copy_sp_restore)
  ret
