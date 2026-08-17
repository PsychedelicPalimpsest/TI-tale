SECTION code

INCLUDE "core/includes/utils.inc"

PUBLIC _test_utils_compare_hlde
_test_utils_compare_hlde:
    CpHLDE
    ret

PUBLIC _test_utils_compare_hlbc
_test_utils_compare_hlbc:
    CpHLBC
    ret

PUBLIC _test_utils_msb_maska
_test_utils_msb_maska:
    msb_maska
    ret

PUBLIC _test_utils_ld_bc_a
_test_utils_ld_bc_a:
    ld_bc_a
    ret

PUBLIC _test_utils_ld_de_a
_test_utils_ld_de_a:
    ld_de_a
    ret

PUBLIC _test_utils_ld_hl_a
_test_utils_ld_hl_a:
    ld_hl_a
    ret

PUBLIC _test_utils_add_hl_a
_test_utils_add_hl_a:
    add_hl_a
    ret

PUBLIC _test_utils_sub_hl_a
_test_utils_sub_hl_a:
    sub_hl_a
    ret

PUBLIC _test_utils_add_hl_a_bc
_test_utils_add_hl_a_bc:
    add_hl_a_bc
    ret

PUBLIC _test_utils_add_hl_a_de
_test_utils_add_hl_a_de:
    add_hl_a_de
    ret

PUBLIC _test_utils_neghl
_test_utils_neghl:
    neghl
    ret

PUBLIC _test_utils_add_nn_a_hl
_test_utils_add_nn_a_hl:
    add_nn_a_hl $12F0
    ret

PUBLIC _test_utils_add_nn_2a_hl
_test_utils_add_nn_2a_hl:
    add_nn_2a_hl $B800
    ret

PUBLIC _test_utils_add_bc_a_signed
_test_utils_add_bc_a_signed:
    add_bc_a_signed
    ret

PUBLIC _test_utils_add_de_a_signed
_test_utils_add_de_a_signed:
    add_de_a_signed
    ret

PUBLIC _test_utils_add_hl_a_signed
_test_utils_add_hl_a_signed:
    add_hl_a_signed
    ret

PUBLIC _test_utils_add_nn_a_bc
_test_utils_add_nn_a_bc:
    add_nn_a_bc $1200
    ret
