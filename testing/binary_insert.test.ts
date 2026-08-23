import { describe, expect, it } from 'vitest'
import { address, machine, mapAddress } from './test_machine.js'

type TestMachine = ReturnType<typeof machine>

const head = () => mapAddress('binary_insert_head')
const tailPtr = () => mapAddress('binary_insert_tail_ptr')
const capacity = 16
const recordSize = 4

function tail(m: TestMachine) {
  return m.readWord(tailPtr())
}
function setTail(m: TestMachine, v: number) {
  m.writeWord(tailPtr(), v)
}
function writeRecord(m: TestMachine, index: number, key: number, payload: number) {
  const a = head() + index * recordSize
  m.writeWord(a, key & 0xffff)
  m.writeWord(a + 2, payload & 0xffff)
}
function readRecord(m: TestMachine, index: number) {
  const a = head() + index * recordSize
  return [m.readWord(a) & 0xffff, m.readWord(a + 2) & 0xffff] as const
}
function readArray(m: TestMachine) {
  const len = (tail(m) - head()) / recordSize
  return Array.from({ length: len }, (_, i) => readRecord(m, i))
}
function writeArray(m: TestMachine, entries: Array<[number, number]>) {
  entries.forEach(([k, p], i) => writeRecord(m, i, k, p))
  setTail(m, head() + entries.length * recordSize)
}
function sortedKeys(m: TestMachine) {
  return readArray(m).map(([k]) => (k << 16) >> 16)
}
function insert(m: TestMachine, key: number, payload: number) {
  m.regs.hl = key & 0xffff
  m.regs.bc = payload & 0xffff
  m.runFrom(address('test_binary_insert'))
}

describe('binary insert basics', () => {
  it('inserts into an empty array', () => {
    const m = machine()
    writeArray(m, [])
    insert(m, 5, 0xaaaa)
    expect(readArray(m)).toEqual([[5, 0xaaaa]])
    expect(tail(m)).toBe(head() + 4)
  })
  it('inserts at the beginning', () => {
    const m = machine()
    writeArray(m, [[10, 1], [20, 2], [30, 3]])
    insert(m, 5, 0xbb01)
    expect(readArray(m)).toEqual([[5, 0xbb01], [10, 1], [20, 2], [30, 3]])
  })
  it('inserts at the end', () => {
    const m = machine()
    writeArray(m, [[1, 1], [2, 2], [3, 3]])
    insert(m, 9, 0xbb02)
    expect(readArray(m)).toEqual([[1, 1], [2, 2], [3, 3], [9, 0xbb02]])
  })
  it('inserts in the middle', () => {
    const m = machine()
    writeArray(m, [[1, 1], [3, 3], [5, 5], [7, 7]])
    insert(m, 4, 0xcccc)
    expect(readArray(m)).toEqual([[1, 1], [3, 3], [4, 0xcccc], [5, 5], [7, 7]])
  })
  it('keeps payload attached to its key', () => {
    const m = machine()
    writeArray(m, [[1, 0x1001], [5, 0x1005]])
    insert(m, 3, 0x1003)
    expect(readArray(m)).toEqual([[1, 0x1001], [3, 0x1003], [5, 0x1005]])
  })
  it('inserts after existing duplicates (stable upper bound)', () => {
    const m = machine()
    writeArray(m, [[2, 0x2001], [2, 0x2002], [5, 0x2005]])
    insert(m, 2, 0x2003)
    const arr = readArray(m)
    expect(arr.map(([k]) => k)).toEqual([2, 2, 2, 5])
    expect(arr[2]).toEqual([2, 0x2003])
  })
  it('handles single-element array smaller key', () => {
    const m = machine()
    writeArray(m, [[10, 0xa0]])
    insert(m, 1, 0xa1)
    expect(readArray(m)).toEqual([[1, 0xa1], [10, 0xa0]])
  })
  it('handles single-element array larger key', () => {
    const m = machine()
    writeArray(m, [[10, 0xa0]])
    insert(m, 20, 0xa2)
    expect(readArray(m)).toEqual([[10, 0xa0], [20, 0xa2]])
  })
})

describe('binary insert ordering', () => {
  it('maintains sorted order through sequential inserts', () => {
    const m = machine()
    writeArray(m, [])
    const keys = [5, 1, 9, 3, 7, 2, 8, 4, 6]
    keys.forEach((k, i) => insert(m, k, 0x3000 + k))
    const out = sortedKeys(m)
    expect(out).toEqual([...keys].sort((a, b) => a - b))
  })
  it('sorts an already sorted insertion sequence', () => {
    const m = machine()
    writeArray(m, [])
    for (let k = 0; k < 8; k++) insert(m, k, 0x4000 + k)
    expect(sortedKeys(m)).toEqual([0, 1, 2, 3, 4, 5, 6, 7])
  })
  it('sorts reverse insertion sequence', () => {
    const m = machine()
    writeArray(m, [])
    for (let k = 7; k >= 0; k--) insert(m, k, 0x4000 + k)
    expect(sortedKeys(m)).toEqual([0, 1, 2, 3, 4, 5, 6, 7])
  })
  it('produces correct order for power-of-two sized arrays', () => {
    const m = machine()
    writeArray(m, [[2, 2], [4, 4], [6, 6], [8, 8]])
    insert(m, 5, 55)
    expect(sortedKeys(m)).toEqual([2, 4, 5, 6, 8])
  })
  it('handles two-element edge', () => {
    const m = machine()
    writeArray(m, [[10, 1], [20, 2]])
    insert(m, 15, 9)
    expect(sortedKeys(m)).toEqual([10, 15, 20])
  })
})

describe('binary insert mechanics', () => {
  it('advances tail by exactly 4 bytes', () => {
    const m = machine()
    writeArray(m, [[1, 1], [2, 2]])
    const before = tail(m)
    insert(m, 3, 3)
    expect(tail(m)).toBe(before + 4)
  })
  it('does not overwrite memory beyond the new tail', () => {
    const m = machine()
    writeArray(m, [[1, 1], [3, 3]])
    const sentinel = head() + capacity * recordSize
    m.writeWord(sentinel, 0x55aa)
    m.writeWord(sentinel + 2, 0xaa55)
    insert(m, 2, 2)
    expect(m.readWord(sentinel)).toBe(0x55aa)
    expect(m.readWord(sentinel + 2)).toBe(0xaa55)
  })
  it('preserves order of elements before insertion point', () => {
    const m = machine()
    writeArray(m, [[1, 0x01], [2, 0x02], [10, 0x0a], [20, 0x14]])
    insert(m, 5, 0x05)
    expect(readArray(m).slice(0, 2)).toEqual([[1, 0x01], [2, 0x02]])
  })
  it('preserves order of elements after insertion point', () => {
    const m = machine()
    writeArray(m, [[1, 0x01], [2, 0x02], [10, 0x0a], [20, 0x14]])
    insert(m, 5, 0x05)
    expect(readArray(m).slice(3)).toEqual([[10, 0x0a], [20, 0x14]])
  })
  it('fills up to capacity', () => {
    const m = machine()
    const init = Array.from({ length: capacity - 1 }, (_, i) => [i * 2, 0x5000 + i] as [number, number])
    writeArray(m, init)
    insert(m, 1, 0x9999)
    expect(readArray(m).length).toBe(capacity)
    expect(sortedKeys(m)).toEqual([...init.map(([k]) => k), 1].sort((a, b) => a - b))
  })
})
