

DEFC frame_pending = compositor_loop+1

; When this happens, it is best to assume a frame will be dropped
render_background:
    ld hl, (cur_camx)
    ld (cur_camprevx), hl
    ld hl, (cur_camy)
    ld (cur_camprevy), hl

    ; Everything is likely fucked
    ld hl, -1
    ld (dirty_cols), hl
    ; TODO: Background tiles


    jp compositor_loop@rejoin


PUBLIC compositor_loop
compositor_loop:
    ld a, 0
    rra
    jp nc, @yield_and_loop

    xor a
    ld (frame_pending), a

    for_each_and_call pre_draw, Object_pre_draw ; Dows NOT need any order

    ; We only re-render the background if the camera moves
    ld hl, (cur_camx)
    ld de, (cur_camprevx)
    CpHLDE
    jr nz, render_background

    ld hl, (cur_camy)
    ld de, (cur_camprevy)
    CpHLDE
    jr nz, render_background

@rejoin:
    




@yield_and_loop:
    EXTERN yield
    call yield
    jp compositor_loop
