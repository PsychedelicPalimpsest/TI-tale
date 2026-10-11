import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { Z80TestMachine } from 'z80-testing-library'

const app = resolve(import.meta.dirname, '../app')
const map = readFileSync(resolve(app, 'out.map'), 'utf8')
const code = new Uint8Array(readFileSync(resolve(app, 'out_CODE.bin')))
const address = (name: string) => {
  const match = map.match(new RegExp(`^${name}\\s*=\\s*\\$([0-9A-Fa-f]+)`, 'm'))
  if (!match) throw new Error(`Missing map address: ${name}`)
  return Number.parseInt(match[1], 16)
}

const readPixels = (m: Z80TestMachine) =>
  Uint8Array.from({ length: 1536 }, (_, offset) => m.readByte(address('layer_foreground') + offset))

const readPhases = (m: Z80TestMachine) =>
  Uint8Array.from({ length: 2304 }, (_, offset) => {
    const phase = Math.floor(offset / 768) + 1
    return m.readByte(m.readWord(address(`current_phase${phase}`)) + offset % 768)
  })

// Each source pixel has interleaved light and dark bytes. The three masks
// rotate by row, and each phase is a column-major 12 x 64 byte screen.
const expectedPhases = (pixels: Uint8Array) => {
  const masks = [0x94, 0x49, 0x22]
  const phases = new Uint8Array(2304)
  for (let col = 0; col < 12; col++) {
    for (let row = 0; row < 64; row++) {
      const source = col * 128 + row * 2
      const light = pixels[source]
      const dark = pixels[source + 1]
      for (let phase = 0; phase < 3; phase++) {
        const mask = masks[(row + phase) % 3]
        phases[phase * 768 + col * 64 + row] = (light & mask) | (dark & (~mask & 0xff))
      }
    }
  }
  return phases
}

function fixture() {
  const installSource = address('install_origin') - 0x4000
  const installSize = address('end_of_install') - address('install_location')
  const m = new Z80TestMachine({
    regions: [
      [0x4000, code],
      [address('install_location'), code.subarray(installSource, installSource + installSize)],
    ],
    stackPointer: 0xF000,
  })
  m.runFrom(address('engine_init'), 500_000)
  m.writeByte(address('_current_keymap'), 0xFF)
  m.runFrom(address('_ROOM_init_room_test'), 500_000)
  m.writeWord(address('cur_camprevx'), m.readWord(address('cur_camx')))
  m.writeWord(address('cur_camprevy'), m.readWord(address('cur_camy')))
  m.writeByte(address('yield_raw'), 0x76) // Halt after one composed frame.

  const compose = (entry = 'compositor_loop') => {
    if (entry === 'compositor_loop') m.writeByte(address('frame_pending'), 1)
    m.runFrom(address(entry), 1_500_000)
    const pixels = readPixels(m)
    const phases = readPhases(m)
    expect(phases, `phase buffers after ${entry}`).toEqual(expectedPhases(pixels))
    return { pixels, phases }
  }

  const instance = address('fh_heap_instances') + 1
  return { m, compose, instance }
}

describe('sprite and object rendering', () => {
  it('walks a full render queue when its tail has the same low address byte', () => {
    const { m, compose, instance } = fixture()
    const counter = 0xF200
    const callback = 0xF210
    m.writeBlock(callback, [0x21, counter & 0xff, counter >> 8, 0x34, 0xC9])
    m.writeWord(m.readWord(instance + address('Instance_obj')) + address('Object_draw'), callback)

    const queue = address('object_render_queue')
    for (let entry = 0; entry < 64; entry++) {
      m.writeWord(queue + entry * 4, 0)
      m.writeWord(queue + entry * 4 + 2, instance)
    }
    m.writeWord(address('object_render_queue_tail'), queue + 256)

    compose()
    expect(m.readByte(counter)).toBe(64)
  })

  it('converts all columns on both sides of a phase-buffer swap', () => {
    const { m } = fixture()
    const foreground = address('layer_foreground')
    for (let offset = 0; offset < 1536; offset++) {
      m.writeByte(foreground + offset, (offset * 37 + (offset >> 3) * 11) & 0xff)
    }

    const firstBuffers = [1, 2, 3].map(phase => m.readWord(address(`current_phase${phase}`)))
    m.runFrom(address('_greyscale_swap'), 300_000)
    expect(readPhases(m)).toEqual(expectedPhases(readPixels(m)))
    const secondBuffers = [1, 2, 3].map(phase => m.readWord(address(`current_phase${phase}`)))
    expect(secondBuffers).not.toEqual(firstBuffers)

    for (let offset = 0; offset < 1536; offset++) {
      m.writeByte(foreground + offset, (offset * 19 + (offset >> 2) * 7 + 0xA5) & 0xff)
    }
    m.runFrom(address('_greyscale_swap'), 300_000)
    expect(readPhases(m)).toEqual(expectedPhases(readPixels(m)))
    expect([1, 2, 3].map(phase => m.readWord(address(`current_phase${phase}`)))).toEqual(firstBuffers)
  })

  it('reconverts unchanged frames and clears a redundant render-list request', () => {
    const { m, compose, instance } = fixture()
    const first = compose()
    expect(m.readByte(instance + address('Instance_flags')) & 4).toBe(0)
    expect(compose()).toEqual(first)

    m.writeByte(instance + address('Instance_flags'), m.readByte(instance + address('Instance_flags')) | 4)
    expect(compose()).toEqual(first)
    expect(m.readByte(instance + address('Instance_flags')) & 4).toBe(0)
  })

  it('updates every phase for movement, animation, hiding, and showing', () => {
    const { m, compose, instance } = fixture()
    let frame = compose()
    expect(compose()).toEqual(frame)

    m.writeWord(instance + address('Instance_x'), 48)
    m.writeWord(instance + address('Instance_displayed_sprite') + address('Sprite_x_pos'), 48)
    m.writeByte(instance + address('Instance_flags'), m.readByte(instance + address('Instance_flags')) | 4)
    let next = compose()
    expect(next.pixels).not.toEqual(frame.pixels)
    expect(compose()).toEqual(next)
    frame = next

    m.writeByte(instance + address('Instance_sprite_index'), 1)
    next = compose()
    expect(next.pixels).not.toEqual(frame.pixels)
    expect(m.readByte(instance + address('Instance_last_sprite_index'))).toBe(1)
    expect(m.readWord(instance + address('Instance_displayed_sprite') + address('Sprite_rotation_entries')))
      .toBe(address('_spr_test_1_rot0'))
    expect(compose()).toEqual(next)
    frame = next

    m.writeByte(instance + address('Instance_flags'), m.readByte(instance + address('Instance_flags')) & ~2)
    next = compose()
    expect(next.pixels).not.toEqual(frame.pixels)
    expect(compose()).toEqual(next)
    frame = next

    m.writeByte(instance + address('Instance_flags'), m.readByte(instance + address('Instance_flags')) | 2)
    next = compose()
    expect(next.pixels).not.toEqual(frame.pixels)
    expect(compose()).toEqual(next)
  })

  it('removes a destroyed sprite from the next frame', () => {
    const { m, compose, instance } = fixture()
    const first = compose()
    const id = m.readWord(instance + address('Instance_id'))
    m.regs.hl = id
    m.runFrom(address('_instance_destroy'), 500_000)
    m.runFrom(address('gml_step'), 500_000)
    expect(m.readByte(instance - 1)).toBe(1)
    const next = compose()
    expect(next.pixels).not.toEqual(first.pixels)
    expect(compose()).toEqual(next)
  })

  it('refreshes a hidden sprite after camera movement', () => {
    const { m, compose, instance } = fixture()
    const first = compose()
    m.writeByte(instance + address('Instance_flags'), m.readByte(instance + address('Instance_flags')) & ~2)
    const hidden = compose()
    expect(hidden.pixels).not.toEqual(first.pixels)
    expect(compose()).toEqual(hidden)

    m.writeWord(address('cur_camx'), 8)
    m.writeByte(address('frame_pending'), 1)
    m.runFrom(address('compositor_loop'), 1_500_000) // Background rebuild yields first.
    expect(m.readByte(instance + address('Instance_flags')) & 4).toBe(4)
    expect(compose('compositor_loop@rejoin')).toEqual(hidden)

    m.writeByte(instance + address('Instance_flags'), m.readByte(instance + address('Instance_flags')) | 2)
    const shown = compose()
    expect(shown.pixels).not.toEqual(hidden.pixels)
    expect(m.readByte(instance + address('Instance_flags')) & 4).toBe(0)
    expect(compose()).toEqual(shown)
  })

  it('does not draw a disabled sprite or an invalid frame index', () => {
    const { m, compose, instance } = fixture()
    const first = compose()
    const sprite = instance + address('Instance_displayed_sprite')

    m.writeByte(sprite + address('Sprite_flags'), 0)
    const disabled = compose()
    expect(disabled.pixels).not.toEqual(first.pixels)
    expect(compose()).toEqual(disabled)

    m.writeByte(instance + address('Instance_sprite_index'), 255)
    expect(compose()).toEqual(disabled)
    expect(m.readByte(instance + address('Instance_last_sprite_index'))).toBe(0)

    m.writeByte(instance + address('Instance_sprite_index'), 0)
    m.writeByte(sprite + address('Sprite_flags'), 1)
    const enabled = compose()
    expect(enabled.pixels).toEqual(first.pixels)
    expect(compose()).toEqual(enabled)
  })

  it('keeps a render-list request pending while hidden or disabled', { timeout: 20000 }, () => {
    const { m, compose, instance } = fixture()
    const flagsAddr = instance + address('Instance_flags')
    const spriteFlags = instance + address('Instance_displayed_sprite') + address('Sprite_flags')
    compose()
    expect(m.readByte(flagsAddr) & 4).toBe(0)

    // Hiding keeps the pending request until the sprite is visible again.
    m.writeByte(flagsAddr, m.readByte(flagsAddr) & ~2)
    const hidden = compose()
    m.writeWord(address('cur_camx'), 8)
    m.writeByte(address('frame_pending'), 1)
    m.runFrom(address('compositor_loop'), 1_500_000) // Background rebuild yields first.
    expect(m.readByte(flagsAddr) & 4).toBe(4)
    expect(compose('compositor_loop@rejoin')).toEqual(hidden)
    expect(m.readByte(flagsAddr) & 4).toBe(4)
    m.writeByte(flagsAddr, m.readByte(flagsAddr) | 2)
    compose()
    expect(m.readByte(flagsAddr) & 4).toBe(0)

    // Disabling behaves the same way: the request survives camera moves.
    compose()
    expect(m.readByte(flagsAddr) & 4).toBe(0)
    m.writeByte(spriteFlags, 0)
    const disabled = compose()
    m.writeWord(address('cur_camx'), 16)
    m.writeByte(address('frame_pending'), 1)
    m.runFrom(address('compositor_loop'), 1_500_000)
    expect(m.readByte(flagsAddr) & 4).toBe(4)
    expect(compose('compositor_loop@rejoin')).toEqual(disabled)
    expect(m.readByte(flagsAddr) & 4).toBe(4)
    m.writeByte(spriteFlags, 1)
    compose()
    expect(m.readByte(flagsAddr) & 4).toBe(0)
  })

  it('updates overlapping pixels when render depth reverses', () => {
    const { m, compose } = fixture()
    compose()

    m.regs.sp = 0xE000
    m.writeWord(0xE000, address('_obj_test'))
    m.writeWord(0xE002, 24)
    m.writeWord(0xE004, 40)
    m.writeWord(0xE006, 1)
    m.runFrom(address('_instance_create_depth'), 200_000)
    const second = m.regs.hl
    m.regs.sp = 0xF000
    expect(second).not.toBe(0)
    m.writeByte(second + address('Instance_sprite_index'), 1)
    const front = compose()

    m.regs.hl = 1
    m.regs.de = 0xFFFF
    m.regs.bc = second
    m.runFrom(address('__change_render_queue'), 300_000)
    m.writeWord(second + address('Instance_depth'), 0xFFFF)
    m.writeWord(second + address('Instance_queued_depth'), 0xFFFF)
    const behind = compose()
    expect(behind.pixels).not.toEqual(front.pixels)
    expect(compose()).toEqual(behind)
  })
})
