SECTION code

INCLUDE "core/includes/utils.inc"
INCLUDE "core/includes/binary_insert.asm"

DEFC binary_insert_head = $C100
DEFC binary_insert_tail_ptr = $B380
DEFC binary_insert_capacity = 16
DEFC binary_insert_end = binary_insert_head + binary_insert_capacity * 4

PUBLIC _test_binary_insert
_test_binary_insert:
    sorted_array_insert binary_insert_head, binary_insert_tail_ptr
