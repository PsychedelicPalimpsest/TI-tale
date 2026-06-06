SECTION CODE_ENGINE
; PREFACE: THIS FILE IS TAKEN: the_mad_joob @
; https://www.omnimaga.org/asm-language/flash-snacks/msg407110/#msg407110
;
; He is a wizard, and I am proud to borrow from him
; 
; Notes: This for use to get all the ram pages


;#####

;flashunlock - fast variant

;DESCRIPTION
;Unlocks the flash chip.
;Inspired by thepenguin77's code.

;WARNINGS
;UNLOCKING FLASH OPENS A DOOR TO SOME DANGEROUS THINGS.
;DON'T IF YOU'RE A BEGINNER.
;IT'S HIGHLY RECOMMENDED TO CALL flashlock WHEN YOU'RE DONE.

;IN
;interrupts : disabled
;bank 2 : RAM page $01 (system default)
;code location : anywhere (see NOTES)
;stack location : bank 3
;free stack space : 40+ bytes (call included)

;OUT
;interrupt mode : 1
;b = $40
;hl = $0007
;sp = unchanged
;all other registers = ?

;NOTES
;The following addresses are written to, don't have your code there :
;   $8100>$817B
;   $81D4>$81FE
;   $82A2
;   $83E8>$83E9
;   $83EB
;   $83EE
;   $84DB>$84DC
;   $9834
;   $9836>$9837
;   $983A
;If you want their content preserved, use the non-destructive variant instead.
PUBLIC flashunlock
flashunlock:

	ld a,$14
	ld bc,flashunlock_ram_end-flashunlock_ram_start
	ld de,flashunlock_ram_start-flashunlock_return+$81E3
	ld hl,$8167
	ld iy,$0031 ; must be $0031
	ld ($83EE),a ; must be $08>$15
	ld ($84DB),hl ; must be $8167
	ld ($9834),a ; must be $03>$FF
	add a,l
	ld ($983A),a ; must be close enough to but under $80
	ld hl,flashunlock_ram_start
	ldir

	in a,($06)
	push af

	in a,($02)
	rra
	or %10111111
	ld d,a
	and $7B

	jp flashunlock_ram_start-flashunlock_return+$81E3

flashunlock_ram_start:

	out ($06),a

	ld hl,($5092)

	ld a,d
	and $7C
	out ($06),a

	ld a,$10
	cpir

	jp (hl)

flashunlock_return:

	ld hl,24
	add hl,sp
	ld sp,hl
	ld hl,$0007
	ld (hl),$FF
	ld b,%01000000

	pop af
	out ($06),a

flashunlock_wait:

	ld a,(hl)

	rla
	ret c

	and b
	jp z,flashunlock_wait-flashunlock_return+$81E3

	ld a,(hl)

	rla
	ret c

	ld (hl),$F0

	ret

flashunlock_ram_end:



;flashlock - app variant

;DESCRIPTION
;Locks the flash chip.

;IN
;interrupts : disabled
;code location : bank 1|3
;stack location : bank 1|3
;free stack space : 6 bytes (call included)

;OUT
;interrupt mode : 1
;a = page in bank 2
;f = %???????0
;b = a
;c = ?
;hl = ?

PUBLIC flashlock
flashlock:

	in a,($07)
	ld b,a

	in a,($02)
	rra
	or %10111111
	ld c,a
	and $7B
	out ($07),a

	ld hl,($8F3C)
	ld a,h
	xor %11000000
	ld h,a

	ld a,c
	and $7C
	out ($07),a

	call flashlock_jump

	ld a,b
	out ($07),a

	ret

flashlock_jump:
	jp (hl)


