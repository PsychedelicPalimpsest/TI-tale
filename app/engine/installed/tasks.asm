; We use a simplified Cooperative Multitasking system*. Since we do not have many tasks,
; the logic becomes quite simple. Maximum of 4 tasks (not all used), of two types:
;
; * Interupts still exist, pre-empting all else
;
;
; We split it up into 4 task slots:
; 1. The game loop (conditional task, framerate based)
; 2. Unused
; 3. The compositor (unconditional task)
; 4. Unused


#define _raw(XXXX) XXXX
#define _label(YYYY) task##_raw(YYYY)##_raw(:)

REPTI NUM, 1, 2, 3, 4
_label(NUM)
	db $00     ; Type: 0 for unused, 1 for conditional, 2 for unconditional
	dw $0000   ; Condition (a routine that is called, carry=time to run). All registers may
	           ; be clobbered but sp. 
	dw $0000   ; Stack location
endr


DEFC __current_task = __next_task+1





__restore_shadow:
	pop hl \ pop de \ pop bc \ pop af
	exx \ ex af, af'
		pop hl \ pop de \ pop bc \ pop af

	exx \ ex af, af'
	ret

__restore:
	pop hl \ pop de \ pop bc \ pop af
	ret

yield_shadow:
	exx \ ex af, af'
		push af \ push bc \ push de \ push hl
	exx \ ex af, af'

	push af \ push bc \ push de \ push hl

	ld hl, __restore_shadow
	push hl
	jp yield_raw
yield:
	push af \ push bc \ push de \ push hl

	ld hl, __restore
	push hl
	; Fall through
	

; yield control of the current thread without perserving anything
yield_raw:
	ld hl, 0
	add hl, sp

	ex de, hl
	
	ld hl, (__current_task)
	inc hl \ inc hl \ inc hl

	ld (hl), e
	inc hl
	ld (hl), d
	; Fall through

	
__next_task:
	ld de, 0h  ; The current task ptr or null
@redo_loop:
	ld b, 4
	ld hl, task1
@loop:
	push hl
	CpHLDE ; Exclude last task

	jp z, @next ; Skip the current task
 	
	ld a, (hl)
	or a
	jp z, @next ; Skip unused tasks 

	inc hl

	dec a
	jp nz, @unconditional_task 

	push hl
		ld a, (hl)
		inc hl
		ld h, (hl)
		ld l, a

		; Assume the condition clobbers both
		push de
		push bc
			EXTERN __hl
			call __hl
		pop bc
		pop de
	pop hl
	jp nc, @next
	; Fall through
@unconditional_task:
	; Always run unconditional tasks 
	dec hl
		ld (__current_task), hl
	inc hl \ inc hl \ inc hl

	ld a, (hl)
	inc hl
	ld h, (hl)
	ld l, a 

	ld sp, hl
	ret

@next:
	pop hl
	ld a, 5
	add_hl_a

	djnz @loop
	ld de, 0 ; Don't exclude the last task
	jp @redo_loop

