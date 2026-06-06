SECTION CODE_ENGINE
INCLUDE "core/common.inc"



PUBLIC init_ram
init_ram:

    in a, (2)
    ld hl, err_unsuported

    bit 7, a ; Reset for a TI-83+ Basic and TI-73. Set for everything else. 
    call z, on_error


; Find the required amount of ram to copy
    ld hl, (tempMem) ; End of user variables
    ex de, hl
    ld hl, $C000
    or a \ sbc hl, de
    ex de, hl
    jp nc, @no_carry

    ld hl, $C000
@no_carry:
    ld de, -$8000
    add hl, de
    ; now hl is the amount of bytes needed

    push hl


    
    



;    Make all ram executable
    EXTERN flashunlock
    call flashunlock
        xor a      ; Set lower ram execution limit to zero
        out ($25),a

        cpl        ; Set highest ram execution limit to MAX
        out ($26),a


        xor a
        ld ($8E29), a ; numLastEntries, this makes page 83 FREE

    ; Backup 8000h to swap sector
        ld a, $F0     ; Mark page as ready to delete, this is a safty for
        ld ($8000), a ; if the calc is reset


        bcall $5095 ; _findSwapSector, goes into a

        pop bc  ; User memory usage
        push af ; Save the sector
        

        ld de, $4000
        ld hl, $8000
        bcall $80C9 ; WriteFlash

    EXTERN flashlock
    call flashlock

    pop bc
    pop hl ; Get the ret ptr

; See: https://wikiti.brandonw.net/index.php?title=83Plus:OS:Ram_Pages
    ld a, $83
    out (7), a

    ld a, 1   ; Default 8000h ram page to C000
    out (5), a

    ld a, b
    ld (_ram_restore_page), a


    jp (hl)   ; Return (evil hack)

PUBLIC cleanup_ram
cleanup_ram:
    di
    pop hl   ; Save the ret ptr in the shadow realm

    ld a, (_ram_restore_page)
    ld b, a ; Save to b

    exx
    out (7), a                  ; Set the restore page to $8000

    ld a, 1
    out (5), a ; Set $C000 to the regular $8000 page

    ld hl, $8000
    ld de, $C000
    ld bc, $4000
    ldir
    
    ld a, $81   ; Restore regular $8000 page
    out (7), a 
    xor a      ; Restore regular $C000 page
    out (5), a



;    Make all ram executable
    EXTERN flashunlock
    call flashunlock
        exx
        push hl

; Cleanup the swap
        ld a, b ; Restore ram page
        ld hl, $4000

        bcall $8024 ; EraseFlash 
    EXTERN flashlock
    call flashlock


    ret




    

    
; Does NOT return. 
; Inputs: HL=error message (only the options bellow)
on_error:
    ld de, $8000 ; Unused ram area (pre ram install)
    ld bc, end_of_errs-err_unsuported
    ldir


    ld hl, $8000 ; Unused ram area (pre ram install)
    bcall _PutS
    bcall _GetKey

EXTERN __Early_Exit
    jp __Early_Exit



err_unsuported:
    DEFM "ERR: UNSUPPORTED CALC"
    nop
end_of_errs:
