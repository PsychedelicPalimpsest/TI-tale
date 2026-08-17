import { describe, expect, it } from 'vitest'
import { address, machine } from './test_machine.js'

describe('linked core routines', () => {
  it('initializes the interrupt vector and timer registers', () => {
    const m = machine()

    m.runFrom(address('test_setup_interrupts'))

    expect(m.readByte(0x8000)).toBe(0x81)
    expect(m.readByte(0x8100)).toBe(0x81)
  })
})
