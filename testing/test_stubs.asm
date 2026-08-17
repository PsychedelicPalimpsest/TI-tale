SECTION code

; The routines under test can refer to these TI-OS exit points. The test
; machine never enters them, but defining them keeps the app libraries
; linkable without a TI-OS CRT.
PUBLIC __Exit
__Exit:
    ret

PUBLIC __Early_Exit
__Early_Exit:
    ret
