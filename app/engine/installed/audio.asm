PUBLIC audio_tick



audio_tick:
  ld a, 00h
  cpl
  ld (audio_tick+1), a

  and 1
  out (0), a


  ret
