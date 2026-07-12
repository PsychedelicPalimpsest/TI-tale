SECTION code_engine

INCLUDE "core/common.inc"

EXTERN blit_sprite_masked
PUBLIC blit_char


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



