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

const hashRegion = (m: Z80TestMachine, start: number, length: number) => {
  let hash = 0
  for (let i = 0; i < length; i++) hash = ((hash * 33) ^ m.readByte(start + i)) >>> 0
  return hash
}

describe('linked application', () => {
  const boot = () => {
    const installSource = address('install_origin') - 0x4000
    const installSize = address('end_of_install') - address('install_location')
    const m = new Z80TestMachine({
      regions: [
        [0x4000, code],
        [address('install_location'), code.subarray(installSource, installSource + installSize)],
      ],
      stackPointer: 0xF000,
    })
    // All keys released on every row; movement only reads row 0.
    for (let row = 0; row < 8; row++) m.writeByte(address('_current_keymap') + row, 0xFF)
    m.runFrom(address('engine_init'), 500_000)
    m.runFrom(address('_ROOM_init_room_test'), 500_000)
    return m
  }
  it('rearms the test object alarm and visibly alternates its sprite frame', () => {
    const m = boot()

    const instance = address('fh_heap_instances') + 1
    const alarm0 = instance + 38
    const spriteIndex = instance + 63
    const rotation0 = instance + 65 + 17

    expect(m.readWord(alarm0)).toBe(30)
    expect(m.readByte(spriteIndex)).toBe(0)
    expect(m.readWord(rotation0)).toBe(address('_spr_test_0_rot0'))

    // Stop the compositor after one frame instead of entering the scheduler.
    m.writeByte(address('yield_raw'), 0x76)
    m.writeWord(address('cur_camprevx'), m.readWord(address('cur_camx')))
    m.writeWord(address('cur_camprevy'), m.readWord(address('cur_camy')))

    const compose = () => {
      m.writeByte(address('frame_pending'), 1)
      m.runFrom(address('compositor_loop'), 1_000_000)
      let phases = 0
      for (const name of ['current_phase1', 'current_phase2', 'current_phase3']) {
        phases = ((phases * 33) ^ hashRegion(m, m.readWord(address(name)), 768)) >>> 0
      }
      return {
        foreground: hashRegion(m, address('layer_foreground'), 768 * 2),
        phases,
      }
    }

    m.runFrom(address('gml_step'), 500_000)
    const openFrame = compose()
    for (let step = 2; step <= 30; step++) m.runFrom(address('gml_step'), 500_000)

    expect(m.readWord(alarm0)).toBe(30)
    expect(m.readByte(spriteIndex)).toBe(1)
    expect(m.readWord(rotation0)).toBe(address('_spr_test_1_rot0'))

    // The alarm must request a new render list for the alternate sprite frame.
    expect(m.readByte(instance + address('Instance_flags')) & 0x04).toBe(0x04)

    const closedFrame = compose()
    expect(m.readByte(instance + address('Instance_flags')) & 0x04).toBe(0)
    expect(closedFrame.foreground).not.toBe(openFrame.foreground)
    expect(closedFrame.phases).not.toBe(openFrame.phases)

    for (let step = 31; step <= 60; step++) m.runFrom(address('gml_step'), 500_000)
    expect(m.readWord(alarm0)).toBe(30)
    expect(m.readByte(spriteIndex)).toBe(0)
    expect(m.readWord(rotation0)).toBe(address('_spr_test_0_rot0'))
  })

  it('reads arrow keys from row 0 and applies velocity with boundary stops', () => {
    const m = boot()
    const instance = address('fh_heap_instances') + 1
    const flags = instance + address('Instance_flags')
    const x = instance + address('Instance_x')
    const y = instance + address('Instance_y')
    const hspeed = instance + address('Instance_hspeed')
    const vspeed = instance + address('Instance_vspeed')
    const dispX = instance + address('Instance_displayed_sprite') + address('Sprite_x_pos')
    const dispY = instance + address('Instance_displayed_sprite') + address('Sprite_y_pos')
    const keys = address('_current_keymap')

    const place = (px: number, py: number) => {
      m.writeWord(x, px)
      m.writeWord(y, py)
      m.writeWord(dispX, px)
      m.writeWord(dispY, py)
      // Re-arm the alarm so the sprite-frame toggle never fires mid-test.
      m.writeWord(instance + 38, 30)
    }
    const stepWithRow0 = (row0: number) => {
      m.writeByte(keys, row0)
      m.runFrom(address('gml_step'), 500_000)
    }

    // Spawned mid-screen by ROOM_init_room_test.
    expect(m.readWord(x)).toBe(40)
    expect(m.readWord(y)).toBe(24)

    place(40, 24)
    stepWithRow0(0xff) // Nothing pressed (active low).
    expect(m.readWord(hspeed)).toBe(0)
    expect(m.readWord(vspeed)).toBe(0)
    expect(m.readWord(x)).toBe(40)
    expect(m.readWord(y)).toBe(24)

    place(40, 24)
    stepWithRow0(0xfd) // Left pressed: bit1 = 0.
    expect(m.readWord(hspeed)).toBe(0xffff)
    expect(m.readWord(vspeed)).toBe(0)
    expect(m.readWord(x)).toBe(39)
    expect(m.readWord(dispX)).toBe(39)
    expect(m.readByte(flags) & 4).toBe(4)

    place(40, 24)
    stepWithRow0(0xfb) // Right pressed: bit2 = 0.
    expect(m.readWord(hspeed)).toBe(1)
    expect(m.readWord(x)).toBe(41)

    place(40, 24)
    stepWithRow0(0xf7) // Up pressed: bit3 = 0.
    expect(m.readWord(vspeed)).toBe(0xffff)
    expect(m.readWord(y)).toBe(23)
    expect(m.readWord(dispY)).toBe(23)

    place(40, 24)
    stepWithRow0(0xfe) // Down pressed: bit0 = 0.
    expect(m.readWord(vspeed)).toBe(1)
    expect(m.readWord(y)).toBe(25)

    place(40, 24)
    stepWithRow0(0xf9) // Left + right cancel out.
    expect(m.readWord(hspeed)).toBe(0)
    expect(m.readWord(x)).toBe(40)

    // Row 7 must be ignored; only row 0 drives movement.
    place(40, 24)
    m.writeByte(keys, 0xff)
    m.writeByte(keys + 7, 0x00)
    m.runFrom(address('gml_step'), 500_000)
    expect(m.readWord(hspeed)).toBe(0)
    expect(m.readWord(vspeed)).toBe(0)
    expect(m.readWord(x)).toBe(40)

    // Screen edges stop velocity instead of bouncing.
    place(0, 24)
    stepWithRow0(0xfd)
    expect(m.readWord(hspeed)).toBe(0)
    expect(m.readWord(x)).toBe(0)

    place(80, 24) // 96 - 16
    stepWithRow0(0xfb)
    expect(m.readWord(hspeed)).toBe(0)
    expect(m.readWord(x)).toBe(80)

    place(40, 0)
    stepWithRow0(0xf7)
    expect(m.readWord(vspeed)).toBe(0)
    expect(m.readWord(y)).toBe(0)

    place(40, 48) // 64 - 16
    stepWithRow0(0xfe)
    expect(m.readWord(vspeed)).toBe(0)
    expect(m.readWord(y)).toBe(48)

    // One pixel inside the edge still moves onto the edge.
    place(1, 24)
    stepWithRow0(0xfd)
    expect(m.readWord(x)).toBe(0)
    place(79, 24)
    stepWithRow0(0xfb)
    expect(m.readWord(x)).toBe(80)
  })
})
