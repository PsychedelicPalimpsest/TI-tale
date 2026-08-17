SECTION CODE_ENGINE


room_init:


    

	

; void set_alarm(uint16_t alarm_idx, int16_t value) __z88dk_callee 
PUBLIC  _inst_update_alarms
_inst_update_alarms:
    ld hl, (_gmctx + GamemakerCTX_instance) ; Current sprite instance
    ld bc, Instance_alarms
    add hl, bc

    pop bc ; value
    pop de ; alarm index

    ; Seek to that current alarm
    add hl, de ; *2 for uint16_t
    add hl, de

    ld (hl), c \ inc hl
    ld (hl), b

    ; Negative numbers do not tick
    bit 7, b    
    ret nz

        ld hl, (_gmctx + GamemakerCTX_instance) ; Current sprite instance
        scl_append alarms ; Handles for us alarms what are already set 


    ret
