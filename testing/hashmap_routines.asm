SECTION code

INCLUDE "core/includes/utils.inc"
INCLUDE "core/includes/hashmap.inc"

DEFC test_hmap_base = $B400
DEFC test_hmap_tail_storage = $B3F0
DEFC test_hmap_pool = $B500
DEFC test_hmap_key_a = $B600
DEFC test_hmap_key_b = $B603
DEFC test_hmap_key_c = $B606
DEFC test_hmap_key_empty = $B609
DEFC test_hmap_key_d = $B60C

hmap_def testing, test_hmap_base, 8, 3, test_hmap_tail_storage

PUBLIC _test_hash_func1
_test_hash_func1:
    hash_func1
    ret

PUBLIC _test_hash_func2
_test_hash_func2:
    hash_func2
    ret

PUBLIC _test_xhash1
_test_xhash1:
    xhash hash_func1, 3
    ret

PUBLIC _test_xhash2
_test_xhash2:
    xhash hash_func2, 3
    ret

PUBLIC _test_hmap_init
_test_hmap_init:
    ; Deliberately dirty every bucket byte so initialization must clear the
    ; complete two-byte bucket table, not only the first half.
    ld hl, hm_base_testing
    ld b, hm_buckets_testing * 2
    ld a, $FF
    @fill:
    ld (hl), a
    inc hl
    djnz @fill

    hmap_init testing

    ld hl, test_hmap_pool
    ld (test_hmap_tail_storage), hl

    xor a
    ld (test_hmap_key_a), a
    ld (test_hmap_key_a + 1), a
    ld (test_hmap_key_a + 2), a
    ld (test_hmap_key_b), a
    ld (test_hmap_key_b + 1), a
    ld (test_hmap_key_b + 2), a
    ld (test_hmap_key_c), a
    ld (test_hmap_key_c + 1), a
    ld (test_hmap_key_c + 2), a
    ld (test_hmap_key_empty), a
    ld (test_hmap_key_empty + 1), a
    ld (test_hmap_key_empty + 2), a
    ld (test_hmap_key_d), a
    ld (test_hmap_key_d + 1), a
    ld (test_hmap_key_d + 2), a
    ret

PUBLIC _test_hmap_alloc
_test_hmap_alloc:
    xhash hash_func1, 3
    hmap_alloc testing, 5

PUBLIC _test_hmap_lookup
_test_hmap_lookup:
    xhash hash_func1, 3
    hmap_lookup testing
