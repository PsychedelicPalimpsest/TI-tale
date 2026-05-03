PUBLIC rand16




; Input: none
; Output: HL = pseudo-random number, period 65536
;
; Taken from https://web.archive.org/web/20150225121110/http://baze.au.com/misc/z80bits.html#4.1
; This lives in ram for self modifying code 

rand16:
	ld	de, $0		; Seed: default to zero
	ld	a,d
	ld	h,e
	ld	l,253
	or	a
	sbc	hl,de
	sbc	a,0
	sbc	hl,de
	ld	d,0
	sbc	a,d
	ld	e,a
	sbc	hl,de
	jp	nc,@rand
	inc	hl
@rand:
  ld	(rand16+1),hl
	ret
