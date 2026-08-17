import { describe, expect, it } from 'vitest'
import { address, machine, mapAddress } from './test_machine.js'

type TestMachine = ReturnType<typeof machine>

const head = () => mapAddress('scl_head_testing')
const tail = () => mapAddress('scl_tail_testing')
const count = () => mapAddress('test_scl_count')
const seen = () => mapAddress('test_scl_seen')
const sprites = () => [
  mapAddress('test_scl_sprite_a'),
  mapAddress('test_scl_sprite_b'),
  mapAddress('test_scl_sprite_c'),
  mapAddress('test_scl_sprite_d'),
]

function initialize(m: TestMachine) {
  m.runFrom(address('test_scl_init'))
}

function append(m: TestMachine, sprite: number) {
  m.regs.hl = sprite
  m.runFrom(address('test_scl_append'))
}

function pop(m: TestMachine, sprite: number) {
  m.regs.hl = sprite
  m.runFrom(address('test_scl_pop'))
}

function listEntry(m: TestMachine, index: number): number {
  return m.readWord(head() + index * 2)
}

function backPointer(m: TestMachine, sprite: number): number {
  return m.readWord(sprite + 2)
}

function iterate(m: TestMachine, routine: string) {
  m.runFrom(address(routine))
}

describe('SCL initialization and append', () => {
  it('initializes an empty list with its tail at the head', () => {
    const m = machine()
    initialize(m)

    expect(m.readWord(head())).toBe(0)
    expect(m.readWord(tail())).toBe(head())
  })

  it('appends sprites in order and records back-pointers', () => {
    const m = machine()
    const [a, b, c] = sprites()
    initialize(m)

    append(m, a)
    append(m, b)
    append(m, c)

    expect(listEntry(m, 0)).toBe(a + 2)
    expect(listEntry(m, 1)).toBe(b + 2)
    expect(listEntry(m, 2)).toBe(c + 2)
    expect(listEntry(m, 3)).toBe(0)
    expect(backPointer(m, a)).toBe(head())
    expect(backPointer(m, b)).toBe(head() + 2)
    expect(backPointer(m, c)).toBe(head() + 4)
    expect(m.readWord(tail())).toBe(head() + 6)
  })

  it('does not append the same sprite twice', () => {
    const m = machine()
    const [a] = sprites()
    initialize(m)
    append(m, a)
    const originalTail = m.readWord(tail())

    append(m, a)

    expect(m.readWord(tail())).toBe(originalTail)
    expect(listEntry(m, 0)).toBe(a + 2)
    expect(listEntry(m, 1)).toBe(0)
  })

  it('fills the reserved list capacity without changing ordering', () => {
    const m = machine()
    const [a, b, c, d] = sprites()
    initialize(m)
    append(m, a)
    append(m, b)
    append(m, c)
    append(m, d)

    expect([0, 1, 2, 3].map(index => listEntry(m, index))).toEqual([
      a + 2,
      b + 2,
      c + 2,
      d + 2,
    ])
    expect(m.readWord(tail())).toBe(head() + 8)
  })
})

describe('SCL iteration', () => {
  it('iterates every active sprite in list order', () => {
    const m = machine()
    const [a, b, c] = sprites()
    initialize(m)
    append(m, a)
    append(m, b)
    append(m, c)

    iterate(m, 'test_scl_iterate_record')

    expect(m.readByte(count())).toBe(3)
    expect(m.readWord(seen())).toBe(a)
    expect(m.readWord(seen() + 2)).toBe(b)
    expect(m.readWord(seen() + 4)).toBe(c)
  })

  it('preserves iteration state when the callback clobbers HL, DE, and AF', () => {
    const m = machine()
    const [a, b, c] = sprites()
    initialize(m)
    append(m, a)
    append(m, b)
    append(m, c)

    iterate(m, 'test_scl_iterate_clobber')

    expect(m.readByte(count())).toBe(3)
  })
})

describe('SCL removal', () => {
  it('removes the last sprite and clears its back-pointer', () => {
    const m = machine()
    const [a, b, c] = sprites()
    initialize(m)
    append(m, a)
    append(m, b)
    append(m, c)

    pop(m, c)

    expect(backPointer(m, c)).toBe(0)
    expect(listEntry(m, 0)).toBe(a + 2)
    expect(listEntry(m, 1)).toBe(b + 2)
    expect(listEntry(m, 2)).toBe(0)
    expect(m.readWord(tail())).toBe(head() + 4)
  })

  it('moves the last sprite into a removed middle slot', () => {
    const m = machine()
    const [a, b, c] = sprites()
    initialize(m)
    append(m, a)
    append(m, b)
    append(m, c)

    pop(m, b)

    expect(backPointer(m, b)).toBe(0)
    expect(listEntry(m, 0)).toBe(a + 2)
    expect(listEntry(m, 1)).toBe(c + 2)
    expect(listEntry(m, 2)).toBe(0)
    expect(backPointer(m, c)).toBe(head() + 2)
    expect(m.readWord(tail())).toBe(head() + 4)
  })

  it('removes the first sprite and compacts the list', () => {
    const m = machine()
    const [a, b, c] = sprites()
    initialize(m)
    append(m, a)
    append(m, b)
    append(m, c)

    pop(m, a)

    expect(backPointer(m, a)).toBe(0)
    expect(listEntry(m, 0)).toBe(c + 2)
    expect(listEntry(m, 1)).toBe(b + 2)
    expect(listEntry(m, 2)).toBe(0)
    expect(backPointer(m, c)).toBe(head())
    expect(m.readWord(tail())).toBe(head() + 4)
  })

  it('ignores a sprite that is not in the list', () => {
    const m = machine()
    const [a, b] = sprites()
    initialize(m)
    append(m, a)
    const originalTail = m.readWord(tail())

    pop(m, b)

    expect(m.readWord(tail())).toBe(originalTail)
    expect(listEntry(m, 0)).toBe(a + 2)
    expect(backPointer(m, b)).toBe(0)
  })

  it('can remove every current element during iteration', () => {
    const m = machine()
    const [a, b, c] = sprites()
    initialize(m)
    append(m, a)
    append(m, b)
    append(m, c)

    iterate(m, 'test_scl_remove_all')

    expect(m.readByte(count())).toBe(3)
    expect(m.readWord(head())).toBe(0)
    expect(m.readWord(tail())).toBe(head())
    expect(backPointer(m, a)).toBe(0)
    expect(backPointer(m, b)).toBe(0)
    expect(backPointer(m, c)).toBe(0)
  })
})
