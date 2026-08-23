import { describe, expect, it } from 'vitest'
import { address, machine } from './test_machine.js'

describe('utils comparison and bit macros', () => {
  it.each([
    { hl: 0x0001, de: 0x0002, carry: true, zero: false },
    { hl: 0x1234, de: 0x1234, carry: false, zero: true },
    { hl: 0x0003, de: 0x0002, carry: false, zero: false },
  ])('compares HL and DE while preserving HL: $hl vs $de', ({ hl, de, carry, zero }) => {
    const m = machine()
    m.regs.hl = hl
    m.regs.de = de

    m.runFrom(address('test_utils_compare_hlde'))

    expect(m.regs.hl).toBe(hl)
    expect((m.regs.f & 1) !== 0).toBe(carry)
    expect((m.regs.f & 0x40) !== 0).toBe(zero)
  })

  it('compares HL and BC while preserving HL', () => {
    const m = machine()
    m.regs.hl = 0x0001
    m.regs.bc = 0x0002

    m.runFrom(address('test_utils_compare_hlbc'))

    expect(m.regs.hl).toBe(0x0001)
    expect((m.regs.f & 1) !== 0).toBe(true)
    expect((m.regs.f & 0x40) !== 0).toBe(false)
  })

  it.each([
    [0x00, 0x00],
    [0x01, 0x01],
    [0x02, 0x03],
    [0x80, 0xFF],
    [0xA0, 0xFF],
    [0xFF, 0xFF],
  ])('cascades the highest set bit: %j', (input, expected) => {
    const m = machine()
    m.regs.a = input

    m.runFrom(address('test_utils_msb_maska'))

    expect(m.regs.a).toBe(expected)
  })
})

describe('utils sign and carry arithmetic macros', () => {
  it.each([
    ['test_utils_ld_bc_a', 'bc'],
    ['test_utils_ld_de_a', 'de'],
    ['test_utils_ld_hl_a', 'hl'],
  ])('sign-extends A with %s', (routine, pair) => {
    for (const [input, expected] of [[0x00, 0x0000], [0x7F, 0x007F], [0x80, 0xFF80], [0xFF, 0xFFFF]]) {
      const m = machine()
      m.regs.a = input

      m.runFrom(address(routine))

      expect(m.regs[pair as 'bc' | 'de' | 'hl']).toBe(expected)
    }
  })

  it.each([
    ['test_utils_add_hl_a', 'hl', 0x12FF, 0x01, 0x1300],
    ['test_utils_add_hl_a', 'hl', 0xFFFF, 0x01, 0x0000],
    ['test_utils_sub_hl_a', 'hl', 0x1200, 0x01, 0x11FF],
    ['test_utils_sub_hl_a', 'hl', 0x0000, 0x01, 0xFFFF],
  ])('handles 16-bit carry or borrow with %s', (routine, pair, initial, delta, expected) => {
    const m = machine()
    m.regs[pair as 'hl'] = initial
    m.regs.a = delta

    m.runFrom(address(routine))

    expect(m.regs.hl).toBe(expected)
  })

  it('adds an 8-bit value to HL and returns the result in BC', () => {
    const m = machine()
    m.regs.hl = 0x12FF
    m.regs.a = 1

    m.runFrom(address('test_utils_add_hl_a_bc'))

    expect(m.regs.bc).toBe(0x1300)
  })

  it('adds an 8-bit value to HL and returns the result in DE', () => {
    const m = machine()
    m.regs.hl = 0x12FF
    m.regs.a = 1

    m.runFrom(address('test_utils_add_hl_a_de'))

    expect(m.regs.de).toBe(0x1300)
    expect(m.regs.hl).toBe(0x12FF)
  })

  it.each([
    [0x0000, 0x0000],
    [0x0001, 0xFFFF],
    [0x8000, 0x8000],
    [0xFFFF, 0x0001],
  ])('negates HL: %j', (input, expected) => {
    const m = machine()
    m.regs.hl = input

    m.runFrom(address('test_utils_neghl'))

    expect(m.regs.hl).toBe(expected)
  })
})

describe('utils constant-offset macros', () => {
  it.each([
    [0x00, 0x12F0],
    [0x20, 0x1310],
    [0xFF, 0x13EF],
  ])('adds A to a constant HL offset: %j', (input, expected) => {
    const m = machine()
    m.regs.a = input

    m.runFrom(address('test_utils_add_nn_a_hl'))

    expect(m.regs.hl).toBe(expected)
  })

  it.each([
    [0x00, 0xB800],
    [0x7F, 0xB8FE],
    [0xFF, 0xB9FE],
  ])('adds twice A to a constant HL offset: %j', (input, expected) => {
    const m = machine()
    m.regs.a = input

    m.runFrom(address('test_utils_add_nn_2a_hl'))

    expect(m.regs.hl).toBe(expected)
  })

  it('adds A to a constant BC offset', () => {
    const m = machine()
    m.regs.a = 0x34

    m.runFrom(address('test_utils_add_nn_a_bc'))

    expect(m.regs.bc).toBe(0x1234)
  })
})

describe('utils signed 8-bit offsets', () => {
  it.each([
    ['test_utils_add_bc_a_signed', 'bc'],
    ['test_utils_add_de_a_signed', 'de'],
    ['test_utils_add_hl_a_signed', 'hl'],
  ])('adds signed offsets with %s', (routine, pair) => {
    for (const [initial, delta, expected] of [
      [0x1000, 0x01, 0x1001],
      [0x1000, 0xFF, 0x0FFF],
      [0x00FF, 0xFE, 0x00FD],
    ]) {
      const m = machine()
      m.regs[pair as 'bc' | 'de' | 'hl'] = initial
      m.regs.a = delta

      m.runFrom(address(routine))

      expect(m.regs[pair as 'bc' | 'de' | 'hl']).toBe(expected)
    }
  })
})

describe('utils fast and DE/BC compares', () => {
  it.each([
    { hl: 0x1234, de: 0x1234, carry: false, sign: false },
    { hl: 0x0034, de: 0x1234, carry: true, sign: true },
    { hl: 0x1334, de: 0x1234, carry: false, sign: false },
  ])('CpHLDE_fast compares high byte without low borrow: $hl vs $de', ({ hl, de, carry, sign }) => {
    const m = machine()
    m.regs.hl = hl
    m.regs.de = de
    m.runFrom(address('test_utils_compare_hlde_fast'))
    expect(m.regs.hl).toBe(hl)
    expect(m.regs.de).toBe(de)
    expect((m.regs.f & 1) !== 0).toBe(carry)
    expect((m.regs.f & 0x80) !== 0).toBe(sign)
  })

  it.each([
    { hl: 0x0001, bc: 0x0002, carry: true },
    { hl: 0x1234, bc: 0x1234, carry: false },
    { hl: 0x1200, bc: 0x11ff, carry: false },
  ])('CpHLBC_fast compares HL-BC with carry propagation: $hl vs $bc', ({ hl, bc, carry }) => {
    const m = machine()
    m.regs.hl = hl
    m.regs.bc = bc
    m.runFrom(address('test_utils_compare_hlbc_fast'))
    expect(m.regs.hl).toBe(hl)
    expect((m.regs.f & 1) !== 0).toBe(carry)
  })

  it.each([
    { de: 0x0001, bc: 0x0002, carry: true },
    { de: 0x1234, bc: 0x1234, carry: false },
    { de: 0x1200, bc: 0x11ff, carry: false },
  ])('CpDEBC compares DE-BC with carry propagation', ({ de, bc, carry }) => {
    const m = machine()
    m.regs.de = de
    m.regs.bc = bc
    m.runFrom(address('test_utils_compare_debc'))
    expect(m.regs.de).toBe(de)
    expect(m.regs.bc).toBe(bc)
    expect((m.regs.f & 1) !== 0).toBe(carry)
  })
})

describe('utils memory compares', () => {
  const wordAddr = 0xb400
  function checkPHLBC(m: ReturnType<typeof machine>) {
    return { carry: (m.regs.f & 1) !== 0, sign: (m.regs.f & 0x80) !== 0, overflow: (m.regs.f & 0x04) !== 0 }
  }
  it.each([
    { mem: 0x1234, bc: 0x1234, carry: false, sign: false },
    { mem: 0x1000, bc: 0x2000, carry: true, sign: true },
    { mem: 0x2000, bc: 0x1000, carry: false, sign: false },
    { mem: 0x0001, bc: 0xffff, carry: true, sign: false },
  ])('CpPHL_BC computes (hl)-bc: mem $mem vs bc $bc', ({ mem, bc, carry, sign }) => {
    const m = machine()
    m.writeWord(wordAddr, mem)
    m.regs.hl = wordAddr
    m.regs.bc = bc
    m.runFrom(address('test_utils_cphl_bc'))
    expect(m.regs.hl).toBe(wordAddr + 1)
    expect(m.readWord(wordAddr)).toBe(mem)
    const flags = checkPHLBC(m)
    expect(flags.carry).toBe(carry)
    expect(flags.sign).toBe(sign)
  })

  it.each([
    { mem: 0x1234, bc: 0x1234, carry: false, sign: false },
    { mem: 0x1000, bc: 0x2000, carry: false, sign: false },
    { mem: 0x2000, bc: 0x1000, carry: true, sign: true },
  ])('CpBC_PHL computes bc-(hl): bc $bc vs mem $mem', ({ mem, bc, carry, sign }) => {
    const m = machine()
    m.writeWord(wordAddr, mem)
    m.regs.hl = wordAddr
    m.regs.bc = bc
    m.runFrom(address('test_utils_cbc_phl'))
    expect(m.regs.hl).toBe(wordAddr + 1)
    expect(m.readWord(wordAddr)).toBe(mem)
    const flags = checkPHLBC(m)
    expect(flags.carry).toBe(carry)
    expect(flags.sign).toBe(sign)
  })

  it('CpPHL_BC and CpBC_PHL are inverses', () => {
    for (const [mem, bc] of [[0x8000, 0x7fff], [0x7fff, 0x8000], [0x0000, 0xffff]] as const) {
      const m1 = machine()
      m1.writeWord(wordAddr, mem)
      m1.regs.hl = wordAddr
      m1.regs.bc = bc
      m1.runFrom(address('test_utils_cphl_bc'))
      const c1 = (m1.regs.f & 1) !== 0
      const s1 = (m1.regs.f & 0x80) !== 0
      const m2 = machine()
      m2.writeWord(wordAddr, mem)
      m2.regs.hl = wordAddr
      m2.regs.bc = bc
      m2.runFrom(address('test_utils_cbc_phl'))
      const c2 = (m2.regs.f & 1) !== 0
      const s2 = (m2.regs.f & 0x80) !== 0
      expect(c1).not.toBe(c2)
      expect(s1).not.toBe(s2)
    }
  })
})
