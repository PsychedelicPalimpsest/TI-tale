; A simplistic hashmap system. It requires the user to bring their own allocator,
; and to add the following to their object definition:
; struct { void* next; char[] key }
; 

; There are TWO hash functions to chose form. 
; The first is faster, but does not cascade. 


; Input:    DE = 16-bit key, A = D
; Output:   A  = 8-bit hash
; Clobbers: A
MACRO hash_func1
;    ld   a, d       ; A = high byte
    xor  e          ; fold in low byte
    add  a, d       ; add D again to break XOR symmetry
endm


; Input:    DE = 16-bit key, A=D
; Output:   A  = 8-bit hash
; Clobbers: A
macro hash_func2
;    ld   a, d       ; A = high byte
    rlca            ; \
    rlca            ;  > rotate D left by 3 bits
    rlca            ; /
    xor  e          ; mix in low byte
    xor  d          ; fold in original D  
endm


; Calulates the hash of a region of memory. 
; Inputs:
; HL = memory addr
; A = hash seed
; Output:
; a = hash
MACRO xhash func, keysize
    ld d, a
    ld e, (hl)  \ inc hl
    
    func

    IF 0<(keysize-1)
        xhash func, (keysize-1)
    ENDIF
endm

; LIMITATIONS:
; buckets must be a power of two
MACRO hmap_def hmap, base_addr, buckets, keysize, stack_tail_ptr_ptr
    defc hm_base_##hmap = base_addr
    defc hm_buckets_##hmap = buckets
    defc hm_keysize_##hmap = keysize
    defc hm_tail_##hmap = stack_tail_ptr_ptr
endm


; Can be used inline
MACRO hmap_init hmap
    ld hl, hm_base_##hmap
    ld de, 1+hm_base_##hmap
    ld bc, hm_buckets_##hmap

    xor a
    ld (hl), a
    ldir
endm

# Note: This generates a routine
# run xhash, and then this.
# Inputs:
# A = hash (see xhash), (hl)=key 
# Outputs:
# hl = newly allocated object
MACRO hmap_alloc hmap, obj_size
; Since the bucket count MUST be a power of two, this masks the lower bits
    and (hm_buckets_##hmap) - 1

    push hl ; Key ptr
    add_nn_2a_hl hm_base_##hmap
@loop:
; Get the high byte
    inc hl 
    ld a, (hl)
; If zero, it is not a valid ptr 
    or a
    jp z, @found_space

    dec hl

    ld l, (hl)
    ld h, a

    jp @loop


@found_space:
    dec hl
; Now hl is the place to put the new ptr

    ex de, hl
    ld hl, (hm_tail_##hmap)
    push hl ; Allocated area
    ld bc, obj_size
    add hl, bc
    ld (hm_tail_##hmap), hl

    ex de, hl
    pop de ; Allocated area

    ld (hl), e \ inc hl
    ld (hl), d

    pop de  ; Key ptr
    push hl ; Allocated area
; Zero out the next ptr
    xor a
    ld (hl), a \ inc hl
    ld (hl), a \ inc hl

    ex de, hl

    REPT hm_keysize_##hmap
        ldi
    endr
    pop hl
    ret
endm

; Note: This generates a routine
; Inputs:
; A = hash (see xhash), (hl)=key
; Outputs:
; Zero flag indicates if it is NOT found (reset if found)
; Hl = The found item, bc=its parent ptr
MACRO hmap_lookup hmap
    and (hm_buckets_##hmap) - 1

    push hl ; key
    add_nn_2a_hl hm_base_##hmap

@loop:
    inc hl
    ld a, (hl)
    dec hl

    or a \ ret z

    ld bc, hl

    ld l, (hl)
    ld h, a

    pop de  ; key
    push hl ; Current base

    inc hl \ inc hl


    push bc
    REPT hm_keysize_##hmap
        ld a, (de)
        cp (hl)
        
        jr nz, @not_found
        inc de \ inc hl   ; Only expend 12 cycles when needed
    ENDR
    pop bc ; Parent
    pop hl ; Found item
    

    or d ; Reset the zero flag (high ptr must be non zero)
    ret

@not_found:
    pop af ; Discard parent
    pop hl

    ld a, (hl) \ inc hl
    ld h, (hl)
    ld l, a

    jp @loop
endm



