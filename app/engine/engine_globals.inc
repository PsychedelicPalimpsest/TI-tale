#IFNDEF ENGINE_GLOBALS
#DEFINE ENGINE_GLOBALS


INCLUDE "core/includes/globals.inc"


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
;   DE, HL
MACRO scl_append name
    ld de, __scl_off(name)
    add hl, de
    ld de, (scl_tail_##name) ; Get the hight byte of the tail

    ; Set the sprites location to the tail (the first empty element)
        ld (hl), e \ inc hl
        ld (hl), d \ dec hl
    ; Set the tail value
        ex de, hl
        ld (hl), e \ inc hl
        ld (hl), d \ inc hl
    ; Set the new tail
        ld (scl_tail_##name), hl
        
        inc hl \ ld (hl), 0
endm

; Removes a sprite from the list
;
; Inputs:
;   HL = Address of the sprite struct
; Clobbers:
;   AF, BC, DE, HL
MACRO scl_pop name
    LOCAL @nope_out

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
        ld c, (hl) 

        ld (scl_tail_##name), hl ; Set the new tail 
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




; During each loop:
; hl is set to the instance location. You can clobber anything but sp
; clobbers: de, af
MACRO SCL_FOR name
    ld hl, scl_head_##name

@scl_loop:

    ld e, (hl) \ inc hl
    ld d, (hl) \ inc hl

    ld a, d \ or a 
    jp z, @scl_loopend
    
    push hl

    ld hl, -__scl_off(name)
    add hl, de
endm



MACRO SCL_ENDFOR name
    pop hl
    jp @scl_loop

@scl_loopend:
endm



EXTERN end_of_install

; START: Statically sized engine globals
DEFC engine_globals_start = end_of_install
DEFL engine_globals       = engine_globals_start


; DEFC loaded_sprite_size

RDEF engine_globals,    cur_room_page,      1
RDEF engine_globals,    cur_room_addr,      2


RDEF engine_globals,    cur_camx,           2
RDEF engine_globals,    cur_camy,           2

RDEF engine_globals,    cur_camx_plusw,           2
RDEF engine_globals,    cur_camy_plush,           2

; Dynamically sized elements
; bg_sprites  - comes first, after engine globals

RDEF engine_globals, bg_fill_color,   2 

RDEF engine_globals, sprite_pool_head, 2

; The sprite callback lists. This is where the canonical callbacks live!
scl_define engine_globals, begin_steps, 64,  2 
scl_define engine_globals, steps,       64,  4 
scl_define engine_globals, end_steps,   64,  6 
scl_define engine_globals, draws,       64,  8
scl_define engine_globals, alarms,      64,  10



; The core renderlists
RDEF engine_globals, bg_renderlist, 8*64 ; 64 max sprites
RDEF engine_globals, fg_renderlist, 8*64 



; TODO: PUT MORE CRAP HERE TO WASTE LESS SPACE
RALIGN engine_globals, 256

RDEF engine_globals,    layer_background, 768*2
RDEF engine_globals,    layer_foregound,  768*2


DEFC engine_globals_end = engine_globals


#ENDIF
