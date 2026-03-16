;	Stub for the TI 83+ calculator for building as an app. Required for appmake when using "+ti83papp"
;   Modified for this project to remove bloat we do not need
;
;
    MODULE  Ti83plus_App_crt0

    DEFINE DEFINED_basegraphics
    DEFINE TI83PLUSAPP  ;Used by grayscale interrupt and the such


    EXTERN  _main		; No matter what set up we have, main is
                        ;  always, always external to this file.
    GLOBAL  __Exit





;-------------------------
; Begin of (shell) headers
;-------------------------

    INCLUDE "Ti83p.def"	; ROM / RAM adresses on Ti83+[SE]
    defc    crt0 = 1
    INCLUDE	"zcc_opt.def"	; Receive all compiler-defines


    INCLUDE "asm_globals.def"

    defc	CONSOLE_ROWS = 8
    defc    TAR__clib_exit_stack_size = 3
    defc    TAR__register_sp = -1
    defc	__CPU_CLOCK = 6000000


    PUBLIC  __crt_org_bss
    defc __crt_org_bss = c_bss


    ; Header data
    DEFINE ASM
    DEFINE NOT_DEFAULT_SHELL

    org $4000


; No header or main is needed for anything other than the first page. (Or a single page apps)
IF (startup=0 || startup=1)


 ;   PUBLIC	crt0_exit		; used by exit()


    PUBLIC	tidi		;
    PUBLIC	tiei		;


    IF !DEFINED_CRT_MODEL
        defc CRT_MODEL = 1
        defc DEFINED_CRT_MODEL = 1
    ENDIF


    INCLUDE "crt/classic/crt_rules.inc"

HEADER_START:


    DEFB $80,$0F		;Field: Program length
    DEFB $00,$00,$00,$00	;Length=0 (N/A for unsigned apps)

    DEFB $80,$12		;Field: Program type
    DEFB $01,$04		;Type = Freeware, 0104

    DEFB $80,$21		;Field: App ID
    DEFB $01		;Id = 1

    DEFB $80,$31		;Field: App Build
    DEFB $01		;Build = 1


    DEFB $80,$40 + endname_true-beginname		;Field: App Name

beginname:
    DEFINE NEED_name
    INCLUDE	"zcc_opt.def"		; Get namestring from zcc_opt.def
    UNDEFINE NEED_name
    IF !DEFINED_NEED_name
        DEFM	"TI83+APP"
    ENDIF
endname:
    defc NameLength = (endname-beginname)
IF NameLength < 2	; Padd spaces if not 8 bytes... (horrible)
    defm ' '
ENDIF
IF NameLength < 3
    defm ' '
ENDIF
IF NameLength < 4
    defm ' '
ENDIF
IF NameLength < 5
    defm ' '
ENDIF
IF NameLength < 6
    defm ' '
ENDIF
IF NameLength < 7
    defm ' '
ENDIF
IF NameLength < 8
    defm ' '
    ENDIF
endname_true:



    DEFB $80,$81		;Field: App Pages
    DEFB $01		;App Pages = 1

    DEFB $80,$90		;No default splash screen

    DEFB $03,$26,$09,$04	;Field: Date stamp =
    DEFB $04,$6f,$1b,$80	;5/12/1999

    DEFB $02, $0d, $40	;Dummy encrypted TI date stamp signature
    DEFB $a1, $6b, $99, $f6
    DEFB $59, $bc, $67, $f5
    DEFB $85, $9c, $09, $6c
    DEFB $0f, $b4, $03, $9b
    DEFB $c9, $03, $32, $2c
    DEFB $e0, $03, $20, $e3
    DEFB $2c, $f4, $2d, $73
    DEFB $b4, $27, $c4, $a0
    DEFB $72, $54, $b9, $ea
    DEFB $7c, $3b, $aa, $16
    DEFB $f6, $77, $83, $7a
    DEFB $ee, $1a, $d4, $42
    DEFB $4c, $6b, $8b, $13
    DEFB $1f, $bb, $93, $8b
    DEFB $fc, $19, $1c, $3c
    DEFB $ec, $4d, $e5, $75

    DEFB $80,$7F		;Field: Program Image length
    DEFB 0,0,0,0		;Length=0, N/A
    DEFB 0,0,0,0		;Reserved
    DEFB 0,0,0,0		;Reserved
    DEFB 0,0,0,0		;Reserved
    DEFB 0,0,0,0		;Reserved

    ;--------------------------------------------
    ; End of header, begin of branch table stuff
    ;--------------------------------------------
    jp start    ; Skips branch table (if present) and by testing if followed by zero alerts appmake to a present branch table


IF DEFINED_MULTI_PAGE_CALLS
END_OF_HEADER:
    ; Pad Header until it is divisable by 3
    defc header_mod = (END_OF_HEADER-HEADER_START)%3
    IF header_mod = 2
        DEFB 0
    ENDIF
    IF header_mod = 1
        DEFB 0
        DEFB 0
    ENDIF

start_branch_table:

    DEFS MULTI_PAGE_CALLS*3, 0

    ; Appmake will fill this area

ENDIF
    ;--------------------------------------------
    ; End of branch table, begin of startup stuff
    ;--------------------------------------------

start:
    rst     0x28 ; bcall(_ForceFullScreen)
    DEFW    0x508F
    rst     0x28 ; bcall(_ClrLCDFull)
    DEFW    0x4540

    di ; Disable interupts to prevent any issues during setup

    ld a, $1 ; Set 15Mz
    out (20h), a

    ; Give us more ram. After this point NO BCALLS SHOULD BE MADE
    ld a, $83
    out (7), a

    in a, (6)
    ld (_first_rom_page), a

    ; Printf stuff
    INCLUDE "crt/classic/crt_init_sp.inc"
    call    crt0_init


     EXTERN __setup_interrupts
     call __setup_interrupts



    call    _main		; call main()
__Exit:     ; exit() jumps to this point
    di

    ld      iy,_IY_TABLE	; Restore flag pointer
    im      1		;


    ld a, 81h ; Restore normal ram size. After this point BCALLS will work again
    out (7), a


    xor	    a		; Switch to 6MHz (normal speed)
    out (20h), a

    defw	SetExSpeed	;

__restore_sp_onexit:
    ;ld	sp,0		; Restore SP
    di
    im 1
    ei      ;
    call    $50		; B_JUMP(_jforcecmdnochar)
    DEFW    4027h;
    ret     ;

tiei:   ei
tidi:	ret			;

ENDIF
    ;----------------------------------------
    ; End of startup part, routines following
    ;----------------------------------------

    l_dcal:
        jp	(hl)		; used as "call (hl)"







    defc ansipixels = 96
    IF !DEFINED_ansicolumns
        defc DEFINED_ansicolumns = 1
        defc ansicolumns = 32
    ENDIF

    IF DEFINED_CRT_MODEL
        defc    __crt_model = CRT_MODEL
    ELSE
        defc    __crt_model = 1
    ENDIF

    #include "interrupt.asm"


    ; Needed for printf

    INCLUDE "crt/classic/crt_runtime_selection.inc"
    INCLUDE	"crt/classic/crt_section.inc"

base_graphics: DEFW $8800
