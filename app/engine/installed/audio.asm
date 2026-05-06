PUBLIC audio_tick

; NOTE: **Must perseve all registers but af**



audio_tick:
  ld a, 00h
  cpl
  ld (audio_tick+1), a

  and 1
  out (0), a


  ret
