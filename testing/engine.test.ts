import { describe, expect, it } from 'vitest'
import { address, machine, mapAddress } from './test_machine.js'

describe('linked engine routines', () => {
  it('keeps frame dispatch and self-modifying queue code in RAM, with instance APIs in ROM', () => {
    const installedStart = mapAddress('install_location')
    const installedEnd = mapAddress('end_of_install')
    for (const name of ['gml_step', '_draw_self', '__insert_render_queue', '__change_render_queue']) {
      expect(mapAddress(name), name).toBeGreaterThanOrEqual(installedStart)
      expect(mapAddress(name), name).toBeLessThan(installedEnd)
    }
    for (const name of ['_inst_update_alarms', '_instance_create_depth', '_set_depth']) {
      expect(mapAddress(name), name).toBeGreaterThanOrEqual(0x4000)
      expect(mapAddress(name), name).toBeLessThan(0x8000)
    }
  })

  it('boots the resident engine and initializes the first room', () => {
    const m = machine()
    const installStart = mapAddress('install_location')
    const installEnd = mapAddress('end_of_install')
    const installSource = mapAddress('install_origin')
    const globalsStart = mapAddress('_globals_start')
    const buffersStart = mapAddress('buffers_start')
    const buffersEnd = mapAddress('buffers_end')

    // Start with dirty RAM so the test exercises the real install and clear paths.
    for (let i = installStart; i < installEnd; i++) m.writeByte(i, 0xA5)
    for (let i = globalsStart + 2; i < globalsStart + 0x73; i++) m.writeByte(i, 0xA5)
    for (let i = buffersStart; i < buffersEnd; i++) m.writeByte(i, 0xA5)
    m.writeByte(mapAddress('_base_rom_page'), 7)
    m.writeByte(mapAddress('_ram_restore_page'), 3)
    m.writeByte(buffersEnd, 0x5A)

    m.runFrom(address('test_setup_interrupts'))
    m.runFrom(address('test_engine_init'), 500_000)

    expect(m.readByte(0x8000)).toBe(0x81)
    expect(m.readByte(0x8100)).toBe(0x81)
    for (let i = installStart; i < installEnd; i++) {
      if (i === mapAddress('grey_timingX6') || i === mapAddress('grey_timingX6') + 1) continue
      expect(m.readByte(i), `installed byte at ${i.toString(16)}`).toBe(m.readByte(installSource + i - installStart))
    }
    expect(m.readWord(mapAddress('greyscale_addr'))).toBe(mapAddress('greyscale_tick'))
    expect(m.readByte(mapAddress('_base_rom_page'))).toBe(7)
    expect(m.readByte(mapAddress('_ram_restore_page'))).toBe(3)
    expect(m.readByte(mapAddress('room_init_done'))).toBe(0)
    expect(m.readByte(mapAddress('_grey_timing'))).toBe(0xA0)
    expect(m.readWord(mapAddress('grey_timingX6'))).toBe(0x03C0)
    expect(m.readWord(mapAddress('dirty_cols'))).toBe(0xFFFF)
    expect(m.readWord(mapAddress('previous_dirty_cols'))).toBe(0xFFFF)
    for (const [current, buffer] of [
      ['current_phase1', 'grey_phase1_buff'],
      ['current_phase2', 'grey_phase2_buff'],
      ['current_phase3', 'grey_phase3_buff'],
      ['alt_phase1', 'grey_phase1_altbuff'],
      ['alt_phase2', 'grey_phase2_altbuff'],
      ['alt_phase3', 'grey_phase3_altbuff'],
    ]) {
      expect(m.readWord(mapAddress(current))).toBe(mapAddress(buffer))
    }
    for (let i = buffersStart; i < buffersEnd; i++) expect(m.readByte(i)).toBe(0)
    expect(m.readByte(buffersEnd)).toBe(0x5A)

    m.runFrom(address('test_room_init'))

    expect(m.readByte(mapAddress('room_init_done'))).toBe(1)
    expect(m.readWord(mapAddress('fh_freehead_instances'))).toBe(0)
    expect(m.readWord(mapAddress('fh_tailplus_instances'))).toBe(mapAddress('fh_heap_instances'))
    expect(m.readWord(mapAddress('object_render_queue_tail'))).toBe(mapAddress('object_render_queue'))
    expect(m.readWord(mapAddress('scl_tail_begin_step'))).toBe(mapAddress('scl_head_begin_step'))
    expect(m.readWord(mapAddress('scl_tail_alarm'))).toBe(mapAddress('scl_head_alarm'))
  })

  it('initializes the instance heap once without modifying ROM code', () => {
    const m = machine()
    const codeStart = mapAddress('room_init')
    const codeEnd = mapAddress('__code_engine_tail')
    const originalCode = Array.from(
      { length: codeEnd - codeStart },
      (_, offset) => m.readByte(codeStart + offset),
    )
    const freeHead = mapAddress('fh_freehead_instances')
    const tail = mapAddress('fh_tailplus_instances')
    const heap = mapAddress('fh_heap_instances')

    m.runFrom(address('test_room_init'))
    expect(m.readByte(mapAddress('room_init_done'))).toBe(1)
    expect(m.readWord(freeHead)).toBe(0)
    expect(m.readWord(tail)).toBe(heap)

    m.writeWord(freeHead, 0xA123)
    m.runFrom(address('test_room_init'))
    expect(m.readWord(freeHead)).toBe(0xA123)
    expect(Array.from(
      { length: codeEnd - codeStart },
      (_, offset) => m.readByte(codeStart + offset),
    )).toEqual(originalCode)
  })

  it('multiplies a 16-bit value by an 8-bit value', () => {
    const m = machine()
    m.regs.de = 0x1234
    m.regs.l = 7

    m.runFrom(address('test_mul_16_16x8_fast'))

    expect(m.regs.hl).toBe((0x1234 * 7) & 0xFFFF)
  })

  it('multiplies by the low nibble of an 8-bit value', () => {
    const m = machine()
    m.regs.de = 0x1234
    m.regs.l = 0xF7

    m.runFrom(address('test_mul_16_16x4_fast'))

    expect(m.regs.hl).toBe((0x1234 * 7) & 0xFFFF)
  })

  it('advances the self-modifying random seed', () => {
    const m = machine()
    const wrapperAddress = address('test_rand16')
    const seedAddress = m.readWord(wrapperAddress + 1) + 1
    m.writeWord(seedAddress, 0)

    m.runFrom(wrapperAddress)
    const first = m.regs.hl
    m.runFrom(wrapperAddress)
    const second = m.regs.hl

    expect(first).not.toBe(second)
    expect(m.readWord(seedAddress)).toBe(second)
  })

  it('updates the greyscale timing state', () => {
    const m = machine()
    m.regs.l = 0xA0

    m.runFrom(address('test_set_grey_timing'))

    expect(m.readByte(mapAddress('_grey_timing'))).toBe(0xA0)
    expect(m.readWord(mapAddress('grey_timingX6'))).toBe(0x03C0)
  })

  it('marks a region idempotently and preserves overlapping dirty columns', () => {
    const m = machine()
    const dirtyCols = mapAddress('dirty_cols')
    const sprite = 0xA000
    const calculateRenderList = () => m.runFrom(address('test_calculate_rl'))

    m.writeByte(sprite, 1)
    m.writeWord(sprite + 1, 16)
    m.writeByte(sprite + 3, 3)
    m.writeWord(sprite + 4, 24)
    m.writeWord(sprite + 6, 0)
    m.writeByte(sprite + 8, 8)
    m.writeWord(sprite + 17, 0xB000)
    m.writeWord(mapAddress('cur_camx'), 0)
    m.writeWord(mapAddress('cur_camy'), 0)
    m.writeWord(mapAddress('calculate_rl_screen'), 0xC000)
    m.writeWord(mapAddress('st_camera_width'), 96)
    m.writeWord(mapAddress('st_camera_height'), 64)

    m.regs.hl = sprite
    calculateRenderList()
    expect(m.readWord(dirtyCols)).toBe(0x3800)

    m.regs.hl = sprite
    calculateRenderList()
    expect(m.readWord(dirtyCols)).toBe(0x3800)

    m.writeWord(dirtyCols, 0x8000)
    m.regs.hl = sprite
    calculateRenderList()
    expect(m.readWord(dirtyCols)).toBe(0xB800)

    m.writeWord(dirtyCols, 0)
    m.writeWord(sprite + 1, 72)
    m.regs.hl = sprite
    calculateRenderList()
    expect(m.readWord(dirtyCols)).toBe(0x0070)
  })
})
