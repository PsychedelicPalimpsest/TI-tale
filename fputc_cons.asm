;   fputc_cons.asm
;   Override of fputc_cons_native from ti83p_clib.lib
;
;   The C library calls fputc_cons_native to emit a single character to the
;   console.  By defining it here (in an object file that is linked before the
;   library is searched) the linker uses this copy and ignores the library copy.
;
;   Calling convention (classic C lib / sccz80 __smallc):
;       The character to print is passed on the stack.
;       [sp+2] = character (pushed as a word; only the low byte matters)
;       Return value is not used by the library wrapper, but HL = char is safe.
;
;   Registers you may freely clobber: AF, BC, DE, HL
;   Registers you must preserve:      IX, IY
;

    SECTION code_clib
    PUBLIC  fputc_cons_native
    PUBLIC  _reset_pen
; ─────────────────────────────────────────────────────────────────────────────


defc penCol = 86D7h
defc penRow	 = 86D8h

fputc_cons_native:
    ld      hl, 2
    add     hl, sp
    ld      a, (hl)             ; A = character to print

    ld h, $0
    ld l, a
    push hl


    cp '\n'
    jp z, new_line

    push ix
    rst 28h
    defw 455Eh
    pop ix

    pop hl

    ld a, (penCol)
    inc a
    ld (penCol), a
    ret

new_line:
    ld a, (penRow)
    add $6
    ld (penRow), a

    xor a, a
    ld (penCol), a
    ret


_reset_pen:
    ld hl, $0
    ld (penCol), hl
    ld (penRow), hl
    ret
