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

  it('copies installed code into its RAM phase', () => {
    const m = machine()
    const source = mapAddress('install_origin')
    const destination = mapAddress('install_location')
    const firstByte = m.readByte(source)
    m.writeByte(destination, 0)

    m.runFrom(address('test_install_hooks'))

    expect(m.readByte(destination)).toBe(firstByte)
    expect(m.readWord(mapAddress('greyscale_addr'))).toBe(mapAddress('greyscale_tick'))
  })
})
