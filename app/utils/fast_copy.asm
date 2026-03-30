PUBLIC fastcpy_16
EXTERN fast_copy_counter
EXTERN fast_copy_sp_restore


; Inputs:
; ix=from address
; iy=to address + 16
;
; Destroys everything except ix, iy
fastcpy_16:
  ld (fast_copy_sp_restore), sp

; 204 T-states (~13 per byte)
MACRO fastcpy_16_m
  ld sp, ix

  pop bc
  pop de
  pop hl
  pop af

  exx
  ex af, af'

  pop bc
  pop de
  pop hl
  pop af


  ld sp, iy

  push af
  push hl
  push de
  push bc

  exx
  ex af, af'

  push af
  push hl
  push de
  push bc
ENDM
  fastcpy_16_m

  ld sp, (fast_copy_sp_restore)
  ret


; Entry point C function.
; __z88dk_callee
_fastcpy_1536:
  pop af ; Ret ptr
  pop ix ; src ptr
  pop iy ; dst ptr
  push af
  ; fall through to fastcpy_1536


; Inputs:
; ix=from address
; iy=to address + 16
fastcpy_1536:
  ld a, -96 ; 1536/16=96
  ld (fast_copy_counter), a
  ; Fall through to fastcpy_NN


; Inputs:
; ix=from address
; iy=to address + 16
; (fast_copy_counter) = NEGATIVE amount of 16 byte chunks to write
fastcpy_NN:
  ld (fast_copy_sp_restore), sp

loop:
  fastcpy_16_m
  ld de, 16  ; 10 
  add ix, de ; 15 
  add iy, de ; 15 

  ld hl, fast_copy_counter ; 10
  inc (hl) ; 11
  jp nz, loop ; 10

  ld sp, (fast_copy_sp_restore)
  ret







