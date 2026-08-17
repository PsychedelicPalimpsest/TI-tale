import { describe, expect, it } from 'vitest'
import { address, machine, mapAddress } from './test_machine.js'

type TestMachine = ReturnType<typeof machine>

const heapField = (field: string, name = 'testing') =>
  mapAddress(`fh_${field}_${name}`)
const freeHead = (name = 'testing') => heapField('freehead', name)
const heapOrigin = (name = 'testing') => freeHead(name)
const tailPlus = (name = 'testing') => heapField('tailplus', name)
const heap = (name = 'testing') => heapField('heap', name)

function initialize(m: TestMachine) {
  m.runFrom(address('test_fheap_init_inline'))
}

function allocate(
  m: TestMachine,
  routine = 'test_fheap_alloc',
  name = 'testing',
): number {
  m.regs.hl = heapOrigin(name)
  m.runFrom(address(routine))
  return m.regs.hl
}

function free(m: TestMachine, ptr: number, name = 'testing') {
  m.regs.hl = heapOrigin(name)
  m.regs.de = ptr
  m.runFrom(address('test_fheap_free'))
}

function iterate(
  m: TestMachine,
  routine = 'test_fheap_foreach',
  name = 'testing',
) {
  m.regs.hl = heapOrigin(name)
  m.runFrom(address(routine))
}

describe('fixed heap initialization', () => {
  it('initializes an inline heap', () => {
    const m = machine()

    initialize(m)

    expect(m.readWord(freeHead())).toBe(0)
    expect(m.readWord(tailPlus())).toBe(heap())
    expect(m.readByte(heap())).toBe(1)
  })

  it('initializes a heap from its origin pointer', () => {
    const m = machine()
    m.regs.hl = heapOrigin()

    m.runFrom(address('test_fheap_init'))

    expect(m.readWord(freeHead())).toBe(0)
    expect(m.readWord(tailPlus())).toBe(heap())
    expect(m.readByte(heap())).toBe(heap() >> 8)
  })

  it('allocates correctly after pointer-based initialization', () => {
    const m = machine()
    m.regs.hl = heapOrigin()

    m.runFrom(address('test_fheap_init'))

    expect(allocate(m)).toBe(heap() + 1)
  })

  it('reinitializes headers after previous allocations and frees', () => {
    const m = machine()
    initialize(m)
    const ptr = allocate(m)
    free(m, ptr)

    initialize(m)

    expect(m.readWord(freeHead())).toBe(0)
    expect(m.readWord(tailPlus())).toBe(heap())
    expect(m.readByte(heap())).toBe(1)
  })
})

describe('fixed heap allocation', () => {
  it('allocates every reserved slot sequentially', () => {
    const m = machine()
    initialize(m)

    const pointers = [allocate(m), allocate(m), allocate(m), allocate(m)]

    expect(pointers).toEqual([
      heap() + 1,
      heap() + 5,
      heap() + 9,
      heap() + 13,
    ])
    expect(m.readWord(tailPlus())).toBe(heap() + 16)
    expect(m.readByte(heap() + 16)).toBe(0)
  })

  it('does not overwrite memory immediately after a full heap', () => {
    const m = machine()
    const sentinel = heap() + 16
    m.writeByte(sentinel, 0xA5)
    initialize(m)

    allocate(m)
    allocate(m)
    allocate(m)
    allocate(m)

    expect(m.readByte(sentinel)).toBe(0xA5)
  })

  it('supports a one-slot heap and reuses its only slot', () => {
    const m = machine()
    m.runFrom(address('test_fheap_init_inline_single'))

    const first = allocate(m, 'test_fheap_alloc_small', 'single')
    const tail = m.readWord(tailPlus('single'))
    free(m, first, 'single')

    expect(first).toBe(heap('single') + 1)
    expect(m.readWord(freeHead('single'))).toBe(first)
    expect(allocate(m, 'test_fheap_alloc_small', 'single')).toBe(first)
    expect(m.readWord(tailPlus('single'))).toBe(tail)
    expect(m.readWord(freeHead('single'))).toBe(0)
  })

  it('handles object allocation across a page boundary', () => {
    const m = machine()
    m.runFrom(address('test_fheap_init_inline_boundary'))

    const pointers = [
      allocate(m, 'test_fheap_alloc_small', 'boundary'),
      allocate(m, 'test_fheap_alloc_small', 'boundary'),
      allocate(m, 'test_fheap_alloc_small', 'boundary'),
    ]

    expect(pointers).toEqual([
      heap('boundary') + 1,
      heap('boundary') + 4,
      heap('boundary') + 7,
    ])
    expect(m.readWord(tailPlus('boundary'))).toBe(heap('boundary') + 9)
  })
})

describe('fixed heap free lists', () => {
  it('preserves the object tail while storing free-list metadata', () => {
    const m = machine()
    initialize(m)
    const ptr = allocate(m)
    m.writeByte(ptr, 0xAA)
    m.writeByte(ptr + 1, 0xBB)
    m.writeByte(ptr + 2, 0xCC)

    free(m, ptr)

    expect(m.readWord(freeHead())).toBe(ptr)
    expect(m.readByte(ptr - 1)).toBe(1)
    expect(m.readWord(ptr)).toBe(0)
    expect(m.readByte(ptr + 2)).toBe(0xCC)
  })

  it('preserves HL and DE and decrements BC by two when freeing', () => {
    const m = machine()
    initialize(m)
    const ptr = allocate(m)
    const origin = heapOrigin()
    m.regs.hl = origin
    m.regs.de = ptr
    m.regs.bc = 0x1234

    m.runFrom(address('test_fheap_free'))

    expect(m.regs.hl).toBe(origin)
    expect(m.regs.de).toBe(ptr)
    expect(m.regs.bc).toBe(0x1232)
  })

  it('reuses freed objects in LIFO order', () => {
    const m = machine()
    initialize(m)
    const first = allocate(m)
    const second = allocate(m)
    const tail = m.readWord(tailPlus())

    free(m, second)
    expect(m.readWord(freeHead())).toBe(second)
    expect(m.readWord(second)).toBe(0)
    free(m, first)

    expect(m.readWord(freeHead())).toBe(first)
    expect(m.readWord(first)).toBe(second)
    expect(allocate(m)).toBe(first)
    expect(m.readWord(freeHead())).toBe(second)
    expect(allocate(m)).toBe(second)
    expect(m.readWord(freeHead())).toBe(0)
    expect(m.readWord(tailPlus())).toBe(tail)
  })

  it('keeps a free-list chain across a page boundary', () => {
    const m = machine()
    m.runFrom(address('test_fheap_init_inline_boundary'))
    const first = allocate(m, 'test_fheap_alloc_small', 'boundary')
    const second = allocate(m, 'test_fheap_alloc_small', 'boundary')

    free(m, first, 'boundary')
    free(m, second, 'boundary')

    expect(m.readWord(freeHead('boundary'))).toBe(second)
    expect(allocate(m, 'test_fheap_alloc_small', 'boundary')).toBe(second)
    expect(allocate(m, 'test_fheap_alloc_small', 'boundary')).toBe(first)
    expect(m.readWord(freeHead('boundary'))).toBe(0)
  })
})

describe('fixed heap iteration', () => {
  it('reports no objects for an empty heap', () => {
    const m = machine()
    initialize(m)

    iterate(m)

    expect(m.readByte(mapAddress('test_foreach_count'))).toBe(0)
  })

  it('iterates allocated objects and skips freed objects', () => {
    const m = machine()
    initialize(m)
    const first = allocate(m)
    const freed = allocate(m)
    const third = allocate(m)
    free(m, freed)

    iterate(m, 'test_fheap_foreach_record')

    const seen = mapAddress('test_foreach_seen')
    expect(m.readByte(mapAddress('test_foreach_count'))).toBe(2)
    expect(m.readWord(seen)).toBe(first - 1)
    expect(m.readWord(seen + 2)).toBe(third - 1)
  })

  it('handles freed objects at both iteration boundaries', () => {
    const m = machine()
    initialize(m)
    const first = allocate(m)
    const middle = allocate(m)
    const last = allocate(m)
    free(m, first)
    free(m, last)

    iterate(m, 'test_fheap_foreach_record')

    const seen = mapAddress('test_foreach_seen')
    expect(m.readByte(mapAddress('test_foreach_count'))).toBe(1)
    expect(m.readWord(seen)).toBe(middle - 1)
  })

  it('sees a freed slot as allocated again after reuse', () => {
    const m = machine()
    initialize(m)
    const first = allocate(m)
    const second = allocate(m)
    const third = allocate(m)
    free(m, second)
    expect(allocate(m)).toBe(second)

    iterate(m, 'test_fheap_foreach_record')

    const seen = mapAddress('test_foreach_seen')
    expect(m.readByte(mapAddress('test_foreach_count'))).toBe(3)
    expect(m.readWord(seen)).toBe(first - 1)
    expect(m.readWord(seen + 2)).toBe(second - 1)
    expect(m.readWord(seen + 4)).toBe(third - 1)
  })

  it('reports zero objects when every allocated object is freed', () => {
    const m = machine()
    initialize(m)
    const first = allocate(m)
    const second = allocate(m)
    free(m, first)
    free(m, second)

    iterate(m)

    expect(m.readByte(mapAddress('test_foreach_count'))).toBe(0)
  })

  it('keeps iterating when the callback clobbers HL, DE, and AF', () => {
    const m = machine()
    initialize(m)
    allocate(m)
    allocate(m)

    iterate(m, 'test_fheap_foreach_clobber')

    expect(m.readByte(mapAddress('test_foreach_count'))).toBe(2)
  })

  it('iterates a minimum-size heap across a page boundary', () => {
    const m = machine()
    m.runFrom(address('test_fheap_init_inline_boundary'))
    allocate(m, 'test_fheap_alloc_small', 'boundary')
    const freed = allocate(m, 'test_fheap_alloc_small', 'boundary')
    allocate(m, 'test_fheap_alloc_small', 'boundary')
    free(m, freed, 'boundary')

    iterate(m, 'test_fheap_foreach_small', 'boundary')

    expect(m.readByte(mapAddress('test_foreach_count'))).toBe(2)
  })
})
