
#define __scl_off(XXXX) scl_iso_##XXXX

; Sprite callback list:
; tail  = the next free space
; 
; *tail = 0x00??  - allows for quick iteration (high byte zero)
MACRO scl_define arena, name, reservation, in_sprite_offset
    DEFC __scl_off(name) = in_sprite_offset
    RDEF arena, scl_tail_##name, 2 ; ptr to the last element+2

    RDEF arena, scl_head_##name, ((reservation) * 2)
endm

MACRO scl_init name
    ld hl, scl_head_##name
    ld (scl_tail_##name), hl 

    ld hl, 0
    ld (scl_head_##name), hl
endm

; Appends a sprite to the end of the list
; Inputs:
;   HL = Address of the sprite struct
; Clobbers:
;   DE, HL, AF
MACRO scl_append name
    LOCAL @no_append

    ld de, __scl_off(name) + 1
    add hl, de

    ld a, (hl) 
    or a \ jr nz, @no_append
    
    ld de, (scl_tail_##name) ; Get the high byte of the tail

    ; Set the sprites location to the tail (the first empty element)
        ld (hl), d \ dec hl
        ld (hl), e

    ; Set the tail value
        ex de, hl
        ld (hl), e \ inc hl
        ld (hl), d \ inc hl
    ; Set the new tail
        ld (scl_tail_##name), hl
        
        inc hl \ ld (hl), 0
    @no_append:
endm

; Removes a sprite from the list
;
; Inputs:
;   HL = Address of the sprite struct
; Clobbers:
;   AF, BC, DE, HL
MACRO scl_pop name
    LOCAL @nope_out, @not_equal

    ld de, __scl_off(name)
    add hl, de

    ; Get the location ptr from the sprite, set it to zero
    ld e, (hl) \ ld (hl), 0 \ inc hl
    ld d, (hl) \ ld (hl), 0

    ; Don't continue if the entry is invalid
    ld a, d \ or a
    jr z, @nope_out
        ld hl, (scl_tail_##name)    
        dec hl
        ld b, (hl) \ ld (hl), 0 \ dec hl
        ld c, (hl) \ ld (hl), 0

        
        ld (scl_tail_##name), hl ; Set the new tail 

        sbc hl, de ; carry is still reset from `or a`
        add hl, de
        jr z, @nope_out

        ex de, hl

        ; Move old tail to the newly opened ptr
        ld (hl), c \ inc hl
        ld (hl), b \ dec hl


        ; Update the back pointer
        ld a, l
        ld (bc), a \ inc bc

        ld a, h
        ld (bc), a
        
    @nope_out:
endm



; Loop over the list backwards.
;
; KNOWN BUG: If an item is removed, and we are not currently on that item, the tail will apear TWICE. 
;            Meaning it is only `safe` to remove the current item
; 
; During each loop:
; hl is set to the instance location. You can clobber anything but sp.
; 
; clobbers with each loop: de
MACRO SCL_FOR name
    ld hl, (scl_tail_##name)

@scl_loop:
    dec hl
    ld de, scl_head_##name

    CpHLDE
    jp m, @scl_loopend
    


    push hl
    ld a, (hl) \ dec hl
    ld l, (hl)
    ld h, a

    ld de, -__scl_off(name)
    add hl, de
    
endm


MACRO SCL_ENDFOR name
    pop hl
    dec hl
    jp @scl_loop
@scl_loopend:
endm

