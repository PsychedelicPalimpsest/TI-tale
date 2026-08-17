SECTION code

; These aliases are the roots that pull selected routines out of the app
; archives. Add another alias here when a routine becomes a test target.
EXTERN mul_16_16x8_fast
EXTERN mul_16_16x4_fast
EXTERN rand16
EXTERN _set_grey_timing
EXTERN setup_interrupts
EXTERN install_hooks

PUBLIC _test_mul_16_16x8_fast
_test_mul_16_16x8_fast:
    jp mul_16_16x8_fast

PUBLIC _test_mul_16_16x4_fast
_test_mul_16_16x4_fast:
    jp mul_16_16x4_fast

PUBLIC _test_rand16
_test_rand16:
    jp rand16

PUBLIC _test_set_grey_timing
_test_set_grey_timing:
    jp _set_grey_timing

PUBLIC _test_setup_interrupts
_test_setup_interrupts:
    jp setup_interrupts

PUBLIC _test_install_hooks
_test_install_hooks:
    jp install_hooks
