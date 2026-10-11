SECTION code_engine
INCLUDE "engine/engine_globals.inc"
INCLUDE "engine/gamemaker_register.inc"
EXTERN __insert_render_queue

; Allocate a new instance
; Output: hl = allocated object
_allocate_instance:
    ld hl, fheap_addr(instances)
    fheap_alloc Instance_size


; Arguments should be on the stack in the z88dk order,
; then the return values are put on the stack. On create is NOT called
; They are push in order:
; * Depth
; * Sprite
;
; _instance_create_unsafe_without_render(int16_t depth, uint16_t x, uint16_t y, Object* obj) __z88dk_callee;
MACRO _instance_create_unsafe_without_render
    call _allocate_instance

    pop bc ; obj

    ld (hl), c \ inc hl
    ld (hl), b \ inc hl

    push hl
        ld hl, Object_initial_flags
        add hl, bc
        ld a, (hl)
        or a
        jr nz, @has_defaults
            ld a, 3 ; Legacy object tables default to active and visible
    @has_defaults:
        or 4 ; Needs render-list setup
    pop hl
    ld (hl), a \ inc hl

    push hl ; Save ptr
        ld de, Instance_alarm_count-3
        add hl, de

        ; No active alarms
        ld (hl), 0 \ inc hl

        ; Set all alarms to -1 (disabled)
        REPT 12*2
            ld (hl), $FF \ inc hl
        endr

        ex de, hl ; hl = *object, de=Instance as sprite_index_max
        
        ld hl, Object_sprite_count
        add hl, bc
        
        ld a, (hl)
        push af
        ldi ; Copy sprite count to instance        

        ; Zero out sprite_index and last_sprite_index
        xor a
        ld (de), a \ inc de
        ld (de), a \ inc de

        ; Deref the first sprite
        pop af
        or a
        jr z, @no_sprite

        ld a, (hl) \ inc hl
        ld h, (hl)
        ld l, a

        ; Copy the displayed sprite into place
        ; TODO: This is of known size, should it be optimized?
        ld bc, Sprite_size
        ldir
        jr @sprite_done

    @no_sprite:
        ; Controllers can have no sprite. Clear the displayed sprite so
        ; draw_self has nothing to render.
        ex de, hl
        ld b, Sprite_size
        xor a
    @clear_sprite:
        ld (hl), a \ inc hl
        djnz @clear_sprite
    @sprite_done:
    pop hl  ; Restore ptr at depth
    

    pop bc ; y
    pop de ; x

    push hl ; Save *depth
    inc hl \ inc hl ; Skip depth
        ; X
        ld (hl), e \ inc hl
        ld (hl), d \ inc hl

        ; Y
        ld (hl), c \ inc hl
        ld (hl), b \ inc hl


        ; xprev
        ld (hl), e \ inc hl
        ld (hl), d \ inc hl

        ; yprev
        ld (hl), c \ inc hl
        ld (hl), b \ inc hl

        ; hspeed
        ld (hl), 0 \ inc hl 
        ld (hl), 0 \ inc hl 

        ; vspeed
        ld (hl), 0 \ inc hl 
        ld (hl), 0 \ inc hl 
    pop hl ; *depth
    pop de ; Depth

    ld (hl), e \ inc hl
    ld (hl), d 

        ; The ROM sprite template starts at (0,0). Match its copy to the
        ; instance coordinates before the first draw.
        push de                         ; Preserve depth for render queue insertion
        push hl                         ; instance + Instance_depth + 1
        inc hl                          ; source: instance x
        push hl
        ld de, Instance_displayed_sprite+Sprite_x_pos-Instance_x
        add hl, de
        ex de, hl                       ; destination: displayed sprite x
        pop hl
        ldi \ ldi
        inc de \ inc de \ inc de        ; destination: displayed sprite y
        ldi \ ldi
        pop hl
        pop de

    ; Get back to start
    REPT 4
        dec hl
    endr

    push de
    push hl
        _register_instance
endm

; Instance* instance_create_depth(int16_t depth, uint16_t x, uint16_t y, Object* obj) __z88dk_callee;
PUBLIC _instance_create_depth
;#[PROFILE_ROUTINE]
_instance_create_depth:
    ; The heap is fixed-size. Never let fheap_alloc run past its reservation.
    ld hl, (fh_freehead_instances)
    ld a, h \ or l
    jr nz, @has_slot
    ld hl, (fh_tailplus_instances)
    ld de, fh_heap_instances + fh_reservation_instances*(Instance_size+1)
    or a \ sbc hl, de
    jr c, @has_slot
        pop de ; Return address
        pop bc ; obj
        pop bc ; y
        pop bc ; x
        pop bc ; depth
        push de
        ld hl, 0
        ret
@has_slot:
    pop de ; Return ptr
    exx
        _instance_create_unsafe_without_render
    exx

    pop bc ; Sprite
    pop hl ; Depth

    push de ; Return ptr

    ld a, (draw_in_progress)
    or a
    jr z, @insert_render
        push bc \ pop ix
        set 6, (ix+Instance_flags)
        ld a, 1
        ld (render_queue_pending), a
        jr @after_render
@insert_render:
    push bc
        call __insert_render_queue
    pop bc
@after_render:
    push bc
    pop hl \ push hl ; Instance*

    ; Assign an ID before Create so code in that event can pass it around.
    push hl
        EXTERN __allocate_instance_id
        call __allocate_instance_id
    pop ix
    ld (ix+Instance_id), l
    ld (ix+Instance_id+1), h
    ld a, (ix+Instance_depth)
    ld (ix+Instance_queued_depth), a
    ld a, (ix+Instance_depth+1)
    ld (ix+Instance_queued_depth+1), a
    push ix \ pop hl

    ld de, (_gmctx + GamemakerCTX_instance)
    ld (_gmctx + GamemakerCTX_instance), hl
    push de
        ; hl = Object*
        ld a, (hl) \ inc hl
        ld h, (hl)
        ld l, a

        ld de, Object_create
        add hl, de

        ld a, (hl) \ inc hl
        ld h, (hl)
        ld l, a

        EXTERN __hl

        or h
        call nz, __hl
    pop hl ; Old current instance
    ld (_gmctx + GamemakerCTX_instance), hl

    pop hl ; Instance*
    

    ret
