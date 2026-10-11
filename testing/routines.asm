SECTION code
INCLUDE "struct_offsets.inc"

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
EXTERN _event_perform_user
EXTERN _instance_create_depth
EXTERN _set_depth
EXTERN __change_render_queue
EXTERN _instance_destroy
EXTERN _instance_find_id
EXTERN _gmctx
EXTERN instance_sweep
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

PUBLIC _test_event_perform_user
_test_event_perform_user:
    jp _event_perform_user

PUBLIC _test_instance_create_depth
_test_instance_create_depth:
    jp _instance_create_depth

PUBLIC _test_instance_destroy
_test_instance_destroy:
    jp _instance_destroy

PUBLIC _test_instance_find_id
_test_instance_find_id:
    jp _instance_find_id

PUBLIC _test_change_render_queue
_test_change_render_queue:
    jp __change_render_queue

PUBLIC _test_instance_sweep
_test_instance_sweep:
    jp instance_sweep

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

PUBLIC _test_destroy_callback
_test_destroy_callback:
    ld hl, $A900
    inc (hl)
    ret

PUBLIC _test_clean_up_callback
_test_clean_up_callback:
    ld hl, $A901
    inc (hl)
    ret

PUBLIC _test_destroy_target_callback
_test_destroy_target_callback:
    ld hl, ($A902)
    call _instance_destroy
    ret

PUBLIC _test_record_step_callback
_test_record_step_callback:
    ld hl, $A904
    inc (hl)
    ret

PUBLIC _test_user_callback
_test_user_callback:
    ld hl, $A905
    inc (hl)
    ret

PUBLIC _test_draw_begin_callback
_test_draw_begin_callback:
    ld hl, $A906
    inc (hl)
    ld a, (hl)
    ld ($A907), a
    ret

PUBLIC _test_draw_callback
_test_draw_callback:
    ld hl, $A906
    inc (hl)
    ld a, (hl)
    ld ($A908), a
    ret

PUBLIC _test_draw_end_callback
_test_draw_end_callback:
    ld hl, $A906
    inc (hl)
    ld a, (hl)
    ld ($A909), a
    ret

PUBLIC _test_clean_up_creates_callback
_test_clean_up_creates_callback:
    ld hl, $B600
    push hl ; obj
    ld hl, 0
    push hl ; y
    push hl ; x
    push hl ; depth
    call _instance_create_depth
    ld ($A90C), hl
    ret

PUBLIC _test_draw_destroy_self_callback
_test_draw_destroy_self_callback:
    ld hl, (_gmctx)
    ld de, Instance_id
    add hl, de
    ld e, (hl) \ inc hl
    ld d, (hl)
    ex de, hl
    call _instance_destroy
    ret

PUBLIC _test_draw_creates_callback
_test_draw_creates_callback:
    ld a, ($A910)
    or a
    ret nz
    ld a, 1
    ld ($A910), a
    ld hl, $B700
    push hl ; obj
    ld hl, 0
    push hl ; y
    push hl ; x
    push hl ; depth
    call _instance_create_depth
    ld ($A90E), hl
    ret

PUBLIC _test_draw_set_depth_callback
_test_draw_set_depth_callback:
    ld hl, (_gmctx)
    push hl ; instance
    ld hl, 5
    push hl ; new depth
    call _set_depth
    ret
