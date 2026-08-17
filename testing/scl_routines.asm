SECTION code

INCLUDE "core/includes/utils.inc"
INCLUDE "engine/scl.inc"

DEFL test_scl_arena = $BA00
scl_define test_scl_arena, testing, 4, 2

DEFC test_scl_sprite_a = $BC00
DEFC test_scl_sprite_b = $BC20
DEFC test_scl_sprite_c = $BC40
DEFC test_scl_sprite_d = $BC60
DEFC test_scl_count = $BB00
DEFC test_scl_seen = $BB10

PUBLIC _test_scl_init
_test_scl_init:
    scl_init testing
    xor a
    ld (test_scl_sprite_a + 2), a
    ld (test_scl_sprite_a + 3), a
    ld (test_scl_sprite_b + 2), a
    ld (test_scl_sprite_b + 3), a
    ld (test_scl_sprite_c + 2), a
    ld (test_scl_sprite_c + 3), a
    ld (test_scl_sprite_d + 2), a
    ld (test_scl_sprite_d + 3), a
    ret

PUBLIC _test_scl_append
_test_scl_append:
    scl_append testing
    ret

PUBLIC _test_scl_pop
_test_scl_pop:
    scl_pop testing
    ret

MACRO test_scl_iterate_record_body
    LOCAL @scl_loop, @scl_loopend
    SCL_FOR testing
        ld (ix + 0), l
        ld (ix + 1), h
        inc ix
        inc ix
        inc c
    SCL_ENDFOR testing
ENDM

PUBLIC _test_scl_iterate_record
_test_scl_iterate_record:
    ld bc, 0
    ld ix, test_scl_seen
    test_scl_iterate_record_body
    ld a, c
    ld (test_scl_count), a
    ret

MACRO test_scl_iterate_clobber_body
    LOCAL @scl_loop, @scl_loopend
    SCL_FOR testing
        inc c
        ld hl, $1234
        ld de, $5678
        ld a, $A5
    SCL_ENDFOR testing
ENDM

PUBLIC _test_scl_iterate_clobber
_test_scl_iterate_clobber:
    ld bc, 0
    test_scl_iterate_clobber_body
    ld a, c
    ld (test_scl_count), a
    ret

MACRO test_scl_remove_all_body
    LOCAL @scl_loop, @scl_loopend
    SCL_FOR testing
        scl_pop_current_element testing
        inc c
    SCL_ENDFOR testing
ENDM

PUBLIC _test_scl_remove_all
_test_scl_remove_all:
    ld bc, 0
    test_scl_remove_all_body
    ld a, c
    ld (test_scl_count), a
    ret
