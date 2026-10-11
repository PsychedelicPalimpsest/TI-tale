SECTION code

; These aliases are the roots that pull selected routines out of the app
; archives. Add another alias here when a routine becomes a test target.
EXTERN mul_16_16x8_fast
EXTERN mul_16_16x4_fast
EXTERN rand16
EXTERN _set_grey_timing
EXTERN setup_interrupts
EXTERN install_hooks
EXTERN calculate_rl
EXTERN room_init
EXTERN engine_init
EXTERN _inst_update_alarms
EXTERN _instance_create_depth
EXTERN _set_depth
EXTERN _draw_self
EXTERN compositor_loop
EXTERN _game_loop
EXTERN check_frame
EXTERN _return_to_loop

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

PUBLIC _test_calculate_rl
_test_calculate_rl:
    jp calculate_rl

PUBLIC _test_room_init
_test_room_init:
    jp room_init

PUBLIC _test_engine_init
_test_engine_init:
    jp engine_init

PUBLIC _test_inst_update_alarms
_test_inst_update_alarms:
    jp _inst_update_alarms

PUBLIC _test_instance_create_depth
_test_instance_create_depth:
    jp _instance_create_depth

PUBLIC _test_set_depth
_test_set_depth:
    jp _set_depth

PUBLIC _test_draw_self
_test_draw_self:
    jp _draw_self

PUBLIC _test_compositor_loop
_test_compositor_loop:
    jp compositor_loop

PUBLIC _test_game_loop
_test_game_loop:
    jp _game_loop

PUBLIC _test_check_frame
_test_check_frame:
    jp check_frame

PUBLIC _test_return_to_loop
_test_return_to_loop:
    jp _return_to_loop

PUBLIC _test_alarm_callback
_test_alarm_callback:
    ld a, 42
    ld ($A900), a
    ret
