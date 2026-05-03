; A heap created with a fixed sized object
;  The process of creating a heap is broken up into two steps, `fheap_def` and `fheap_init*`.
;  A heap must be defined with a maximum amount of items reserved to it, this means undershooting
;  creates a situation where the next heap is corrupted! And overshooted wastes ram. 
;

MACRO fheap_def arena, name, reservation, obj_size
; Comptime constants
  DEFC fh_reservation_##name = reservation
  DEFC fh_obj_size_##name    = obj_size 
  DEFC fh_origin_##name = arena

; Header
  RDEF arena, fh_freehead_##name, 2   ; ptr to first freed object (or null)
  RDEF arena, fh_tailplus_##name, 2    ; ptr to the first UNALLOCATED object

  RDEF arena, fh_heap_##name, ((reservation) * (obj_size+1))
  ; How this structure work:
  ; When an object is freed, we store the ptr to the 'next' free
  ; object there, this creates a stack for freed object.
  ; Each object has a single metadata byte, where it is null if
  ; it is allocated
endm

#define fheap_addr(name) fh_origin_##name



MACRO fheap_init_inline name
  ld hl, 0
  ld (fh_freehead_##name), hl

  ld hl, fh_heap_##name
  ld (fh_tailplus_##name), hl
  
  ld a, 1 ; Mark as free
  ld (fh_heap_##name), a
endm

; Inputs:
; hl = heap origin
MACRO fheap_init
  xor a, a

  ld (hl), a
  inc hl
  ld (hl), a
  inc hl

  ld de, hl
  inc de \ inc de

  ld (hl), e
  inc hl
  ld (hl), d
  inc hl

  ld (hl), d ; Since we are not allowed in the bootcode, d must be non-zero!
endm

; NOTE: Is create a procedure, do not inline
;
; Inputs: 
; hl = heap ptr
; Outputs:
; hl = allocation
; Registers: af, bc, de, hl modified
MACRO fheap_alloc obj_size
  ; Psudocode:
  ; IF freehead == 0
  ;    node = tailplus
  ;    tailplus += obj_size + 1
  ; ELSE
  ;    node = freehead
  ;    freehead = *freehead
  ; ENDIF
  ; return(node)
  LOCAL not_null
  
  ; de = *hl, hl++, set flags from d
  ld e, (hl)
  inc hl
  ld a, (hl)
  and a
  ld d, a

  jp nz, not_null
; freehead == 0
  inc hl 

  ; hl = *tailplus (node ptr), de = &tailplus+1
  ld e, (hl)
  inc hl
  ld d, (hl)
  ex de, hl

  push hl

  ; hl += obj_size
  ld bc, obj_size+1
  add hl, bc

  ; hl = &tailplus+1, de=node ptr
  ex de, hl

  ld (hl), d
  dec hl
  ld (hl), e

  pop hl ; node ptr

  ; Mark as not free
  xor a, a
  ld (hl), a
  inc hl

  ret
not_null:
  ex de, hl
  ; now hl = *freehead, de = &freehead+1
  dec de
  ldi \ ldi

  ; Undo incs from ldi, and go metadata byte
  dec hl \ dec hl \ dec hl

  xor a, a
  ld (hl), a
  inc hl

  ret
endm

; Inputs:
; hl = heap to free on
; de = ptr to free
; Outputs:
; bc--
; hl=hl
; de=de
MACRO fheap_free
  ; Psudocode:
  ; *ptr = freehead
  ; freehead = ptr

  ; Mark as free
  dec de
  ld a, 1
  ld (de), a
  inc de

  ldi ; Copy first byte of old heap head

  ld a, (hl) ; Copy secound byte
  ld (de), a

  dec hl \ dec de ; Restore ptrs

  ld (hl), e
  inc hl

  ld (hl), d
  dec hl
endm


; Iterates over each non-freed element in the heap.
; Set hl initially to the heap ptr, then with each iteration hl
; will be set to the element ptr. When no other elements exists,
; jumps to @end_of_loop. All loop state is kept in the shadow registers,
; feel free to use everything else (including hl).
MACRO fheap_foreach obj_size
  push hl \ exx \ pop hl

  inc hl \ inc hl
  ld e, (hl)
  inc hl
  ld d, (hl)
  inc hl

  dec de ; This way comparing to it will cause a carry iff we go out of bounds

  ; This is used in the loop
  ld bc, obj_size+1

; Now:
; hl = the heap object
; de = the heap object cap

@loop_outer:
  CpHLDE
  ; The sign flag if HL > DE

  jp p, @pre_end_of_loop ; 'p' check if it is reset, therefore jumping if it is out of bounds

  ld a, (hl)
  and a
  jp nz, @inc_hl


  push hl
  exx \ ex af, af'
  pop hl

  jp @user_code
  @loop:
; User jumps back here
  exx \ ex af, af'
@inc_hl:
  add hl, bc
  jp @loop_outer
@pre_end_of_loop:
  exx \ ex af, af'
  jp @end_of_loop

@user_code:
endm

