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

  RDEF arena, fh_heap_##name, ((reservation) * (obj_size))
  ; How this structure work:
  ; When an object is freed, we store the ptr to the 'next' free
  ; object there, this creates a stack for freed object.
endm

MACRO fheap_init_inline name
  ld hl, 0
  ld (fh_freehead_##name), hl

  ld hl, fh_heap_##name
  ld (fh_tailplus_##name), hl
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
endm

; NOTE: Is create a procedure, do not inline
;
; Inputs: 
; hl = heap ptr
; Outputs:
; hl = allocation
MACRO fheap_alloc obj_size
  ; Psudocode:
  ; IF freehead == 0
  ;    node = tailplus
  ;    tailplus += obj_size
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
  ld bc, obj_size
  add hl, bc

  ; hl = &tailplus+1, de=node ptr
  ex de, hl

  ld (hl), d
  dec hl
  ld (hl), e

  pop hl ; node ptr
  ret
not_null:
  ex de, hl
  ; now hl = *freehead, de = &freehead+1
  dec de
  ldi \ ldi
  dec hl \ dec hl

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

  ldi ; Copy first byte of old heap head

  ld a, (hl) ; Copy secound byte
  ld (de), a

  dec hl \ dec de ; Restore ptrs

  ld (hl), e
  inc hl

  ld (hl), d
  dec hl
endm

