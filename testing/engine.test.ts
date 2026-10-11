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
    const mutableInstalledWords = new Set([
      'grey_timingX6', 'st_camera_width', 'st_camera_height',
    ].flatMap(name => [mapAddress(name), mapAddress(name) + 1]))

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
      if (mutableInstalledWords.has(i)) continue
      expect(m.readByte(i), `installed byte at ${i.toString(16)}`).toBe(m.readByte(installSource + i - installStart))
    }
    expect(m.readWord(mapAddress('greyscale_addr'))).toBe(mapAddress('greyscale_tick'))
    expect(m.readByte(mapAddress('_base_rom_page'))).toBe(7)
    expect(m.readByte(mapAddress('_ram_restore_page'))).toBe(3)
    expect(m.readByte(mapAddress('room_init_done'))).toBe(0)
    expect(m.readByte(mapAddress('_grey_timing'))).toBe(0xA0)
    expect(m.readWord(mapAddress('grey_timingX6'))).toBe(0x03C0)
    expect(m.readWord(mapAddress('st_camera_width'))).toBe(96)
    expect(m.readWord(mapAddress('st_camera_height'))).toBe(64)
    expect(m.readWord(mapAddress('cur_camx'))).toBe(0)
    expect(m.readWord(mapAddress('cur_camy'))).toBe(0)
    expect(m.readWord(mapAddress('cur_camprevx'))).toBe(0xFFFF)
    expect(m.readWord(mapAddress('cur_camprevy'))).toBe(0xFFFF)
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

  it('draw_self uses instance visibility rather than the object address byte', () => {
    const m = machine()
    const instance = 0xA000
    const entry = instance + 65 + 9
    const screen = 0xC000
    m.writeWord(mapAddress('_gmctx'), instance)
    m.writeWord(instance, 0x0002) // Object pointer low byte has visibility bit set.
    m.writeByte(entry, 1)
    m.writeByte(entry + 1, 0)
    m.writeByte(entry + 2, 1)
    m.writeByte(entry + 3, 1)
    m.writeWord(entry + 4, 0xB000)
    m.writeWord(entry + 6, screen)
    m.writeBlock(0xB000, [0xFF, 0xAA, 0x55])
    m.writeByte(instance + 2, 0)
    m.runFrom(address('test_draw_self'))
    expect(m.readWord(screen)).toBe(0)

    m.writeWord(instance, 0x0000) // Object pointer low byte has visibility bit clear.
    m.writeByte(instance + 2, 2)
    m.runFrom(address('test_draw_self'))
    expect(m.readWord(screen)).not.toBe(0)
  })

  it('creates an instance with its sprite at the room coordinates', () => {
    const m = machine()
    const object = 0xA300
    const sprite = 0xA500
    m.runFrom(address('test_room_init'))
    m.writeByte(object + 20, 1)
    m.writeWord(object + 21, sprite)
    m.writeByte(sprite, 1)
    m.writeByte(sprite + 3, 2)
    m.writeWord(sprite + 4, 16)
    m.writeByte(sprite + 8, 8)
    m.regs.sp = 0xE000
    m.writeWord(0xE000, object)
    m.writeWord(0xE002, 24)
    m.writeWord(0xE004, 40)
    m.writeWord(0xE006, 7)
    m.runFrom(address('test_instance_create_depth'), 200_000)
    const instance = m.regs.hl
    expect(instance).toBe(mapAddress('fh_heap_instances') + 1)
    expect(m.readWord(instance)).toBe(object)
    expect(m.readByte(instance + 62)).toBe(1)
    expect(m.readWord(instance + 3)).toBe(7)
    expect(m.readWord(instance + 5)).toBe(40)
    expect(m.readWord(instance + 7)).toBe(24)
    expect(m.readWord(instance + 65 + 1)).toBe(40)
    expect(m.readWord(instance + 65 + 6)).toBe(24)
  })

  it('composes a moving instance and clears its old screen position', () => {
    const m = machine()
    m.runFrom(address('test_engine_init'), 500_000)
    m.runFrom(address('test_room_init'))
    const instance = 0xA000
    const object = 0xA300
    const pixels = 0xB000
    const screen = mapAddress('layer_foreground')
    const queue = mapAddress('object_render_queue')
    m.writeWord(mapAddress('cur_camprevx'), 0)
    m.writeWord(mapAddress('cur_camprevy'), 0)
    m.writeWord(instance, object)
    m.writeByte(instance + 2, 7)
    m.writeWord(queue, 0)
    m.writeWord(queue + 2, instance)
    m.writeWord(mapAddress('object_render_queue_tail'), queue + 4)
    m.writeByte(instance + 65, 1)
    m.writeWord(instance + 65 + 1, 16)
    m.writeByte(instance + 65 + 3, 2)
    m.writeWord(instance + 65 + 4, 16)
    m.writeWord(instance + 65 + 6, 8)
    m.writeByte(instance + 65 + 8, 8)
    for (let i = 0; i < 8; i++) m.writeWord(instance + 65 + 17 + i * 2, pixels)
    for (let i = 0; i < 16; i++) m.writeBlock(pixels + i * 3, [0xFF, 0xFF, 0xFF])
    const oldPixel = screen + 16 / 8 * 128 + 8 * 2
    const newPixel = screen + 24 / 8 * 128 + 8 * 2
    m.writeByte(mapAddress('yield_raw'), 0x76) // Stop after one composition.
    m.writeByte(mapAddress('frame_pending'), 1)
    m.runFrom(address('test_compositor_loop'), 500_000)
    expect(m.readByte(oldPixel)).not.toBe(0)
    expect(m.readByte(mapAddress('frame_pending'))).toBe(0)

    m.writeWord(instance + 65 + 1, 24)
    m.writeByte(instance + 2, 7)
    m.writeByte(mapAddress('frame_pending'), 1)
    m.runFrom(address('test_compositor_loop'), 500_000)
    expect(m.readByte(oldPixel)).toBe(0)
    expect(m.readByte(newPixel)).not.toBe(0)
  })

  it('requests a compositor frame after the step callbacks run', () => {
    const m = machine()
    m.runFrom(address('test_room_init'))
    m.writeByte(mapAddress('yield'), 0x76) // Stop at the game loop's yield.
    m.runFrom(address('test_game_loop'))
    expect(m.readByte(mapAddress('frame_pending'))).toBe(1)
  })

  it('releases a game frame on every second greyscale tick', () => {
    const m = machine()
    for (const tick of [0, 1, 2, 3, 4, 5, 6]) {
      m.writeByte(mapAddress('_grey_count'), tick)
      m.runFrom(address('test_check_frame'))
      expect((m.regs.f & 1) !== 0, `tick ${tick}`).toBe(tick !== 0 && tick % 2 === 0)
    }
  })

  it('dispatches alarm zero through the object callback table', () => {
    const m = machine()
    m.runFrom(address('test_room_init'))
    const instance = 0xA000
    const object = 0xA300
    const head = mapAddress('scl_head_alarm')
    m.writeWord(instance, object)
    for (let i = 1; i < 12; i++) m.writeWord(instance + 38 + i * 2, 0xFFFF)
    m.writeWord(instance + 38, 1)
    m.writeWord(object + 85, address('test_alarm_callback'))
    m.writeWord(head, instance + 35)
    m.writeWord(mapAddress('scl_tail_alarm'), head + 2)
    m.runFrom(mapAddress('gml_step'))
    expect(m.readByte(0xA900)).toBe(42)
    expect(m.readWord(instance + 38)).toBe(0)
  })

  it('saves the first game-loop stack in task one before running the compositor', () => {
    const m = machine()
    m.runFrom(address('test_room_init'))
    m.writeByte(mapAddress('compositor_loop'), 0x76) // Stop at the first task switch.
    m.runFrom(address('test_return_to_loop'), 300_000)
    expect(m.readWord(mapAddress('__current_task'))).toBe(mapAddress('task3'))
    expect(m.readWord(mapAddress('task1') + 3)).toBeGreaterThan(0xE000)
    expect(m.readWord(mapAddress('task1') + 3)).toBeLessThan(0xF000)
    expect(m.readByte(mapAddress('frame_pending'))).toBe(1)
  })

  it('returns from the compositor to the game loop with a valid stack', () => {
    let steps = 0
    const m = machine(new Map([
      [mapAddress('check_frame'), machine => {
        const count = mapAddress('_grey_count')
        machine.writeByte(count, (machine.readByte(count) + 2) & 0xFF)
      }],
      [mapAddress('gml_step'), machine => {
        if (++steps === 3) machine.writeByte(mapAddress('gml_step'), 0x76)
      }],
    ]))
    m.runFrom(address('test_engine_init'), 500_000)
    m.runFrom(address('test_room_init'))
    m.runFrom(address('test_return_to_loop'), 2_000_000)
    expect(steps).toBe(3)
    expect(m.readWord(mapAddress('__current_task'))).toBe(mapAddress('task1'))
    expect(m.readWord(mapAddress('task1') + 3)).toBeGreaterThan(0xE000)
    expect(m.readWord(mapAddress('task3') + 3)).toBeGreaterThan(0xFE00)
    expect(m.regs.sp).toBeGreaterThan(0xE000)
  })
})
