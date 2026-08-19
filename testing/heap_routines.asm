SECTION code

INCLUDE "core/includes/utils.inc"
INCLUDE "core/includes/fixed_heap.inc"
INCLUDE "core/includes/binary_heap.inc"

; Keep this heap outside the app's code and fixed global regions.
DEFL test_heap_arena = $B000
fheap_def test_heap_arena, testing, 4, 3

; A one-slot heap exercises the smallest useful reservation and object size.
DEFL single_heap_arena = $B200
fheap_def single_heap_arena, single, 1, 2

; The header ends at a page boundary, exercising 16-bit pointer carry.
DEFL boundary_heap_arena = $B0FC
fheap_def boundary_heap_arena, boundary, 3, 2

DEFL binary_heap_arena = $B300
bh_def binary_heap_arena, binary_testing, 7

DEFC test_heap_origin = fheap_addr(testing)
DEFC test_foreach_count = $B020
DEFC test_foreach_seen = $B030

PUBLIC _test_fheap_init_inline
_test_fheap_init_inline:
    fheap_init_inline testing
    ret

PUBLIC _test_fheap_init_inline_single
_test_fheap_init_inline_single:
    fheap_init_inline single
    ret

PUBLIC _test_fheap_init_inline_boundary
_test_fheap_init_inline_boundary:
    fheap_init_inline boundary
    ret

PUBLIC _test_fheap_init
_test_fheap_init:
    fheap_init
    ret

PUBLIC _test_fheap_alloc
_test_fheap_alloc:
    fheap_alloc fh_obj_size_testing

PUBLIC _test_fheap_alloc_small
_test_fheap_alloc_small:
    fheap_alloc fh_obj_size_single

PUBLIC _test_fheap_free
_test_fheap_free:
    fheap_free
    ret

PUBLIC _test_fheap_foreach
_test_fheap_foreach:
    ld bc, 0
    fheap_foreach fh_obj_size_testing
        inc c
        jp @loop
    @end_of_loop:
    ld a, c
    ld (test_foreach_count), a
    ret

PUBLIC _test_fheap_foreach_small
_test_fheap_foreach_small:
    ld bc, 0
    fheap_foreach fh_obj_size_single
        inc c
        jp @loop
    @end_of_loop:
    ld a, c
    ld (test_foreach_count), a
    ret

PUBLIC _test_fheap_foreach_record
_test_fheap_foreach_record:
    ld bc, 0
    ld de, test_foreach_seen
    fheap_foreach fh_obj_size_testing
        ld (de), l
        inc de
        ld (de), h
        inc de
        inc c
        jp @loop
    @end_of_loop:
    ld a, c
    ld (test_foreach_count), a
    ret

PUBLIC _test_fheap_foreach_clobber
_test_fheap_foreach_clobber:
    ld bc, 0
    fheap_foreach fh_obj_size_testing
        inc c
        ld hl, $1234
        ld de, $5678
        ld a, $A5
        jp @loop
    @end_of_loop:
    ld a, c
    ld (test_foreach_count), a
    ret

PUBLIC _test_bh_siftup
_test_bh_siftup:
    bh_siftup binary_testing
    ret

PUBLIC _test_bh_siftdown
_test_bh_siftdown:
    bh_siftdown binary_testing
    ret
