import { describe, expect, it } from 'vitest'
import { address, machine, mapAddress } from './test_machine.js'

describe('linked engine routines', () => {
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
