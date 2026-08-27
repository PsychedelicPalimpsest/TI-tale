import { describe, expect, it } from 'vitest'
import { address, machine, mapAddress } from './test_machine.js'

type TestMachine = ReturnType<typeof machine>
type Entry = [number, number]

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
function remove(m: TestMachine, key: number, payload: number) {
  m.regs.hl = key & 0xffff
  m.regs.bc = payload & 0xffff
  m.runFrom(address('test_binary_remove'))
}
function changeDepth(m: TestMachine, oldKey: number, newKey: number, payload: number) {
  m.regs.hl = oldKey & 0xffff
  m.regs.de = newKey & 0xffff
  m.regs.bc = payload & 0xffff
  m.runFrom(address('test_binary_change_depth'))
}
function bsearch(m: TestMachine, key: number) {
  m.regs.bc = key & 0xffff
  m.runFrom(address('test_binary_search'))
  return m.regs.de
}
function signed16(n: number) {
  return (n << 16) >> 16
}
function expectedInsert(entries: Entry[], key: number, payload: number): Entry[] {
  const normalized = entries.map(([entryKey, entryPayload]) => [entryKey & 0xffff, entryPayload & 0xffff] as Entry)
  const index = normalized.findIndex(([entryKey]) => signed16(entryKey) > key)
  const at = index === -1 ? normalized.length : index
  return [...normalized.slice(0, at), [key & 0xffff, payload & 0xffff], ...normalized.slice(at)]
}
function expectedUpperBound(entries: Entry[], key: number) {
  const index = entries.findIndex(([entryKey]) => signed16(entryKey) > key)
  const at = index === -1 ? entries.length : index
  return head() + at * recordSize
}
function expectedRemove(entries: Entry[], key: number, payload: number): Entry[] {
  const normalized = entries.map(([entryKey, entryPayload]) => [entryKey & 0xffff, entryPayload & 0xffff] as Entry)
  const index = normalized.findIndex(
    ([entryKey, entryPayload]) => entryKey === (key & 0xffff) && entryPayload === (payload & 0xffff),
  )
  if (index === -1) return normalized
  return [...normalized.slice(0, index), ...normalized.slice(index + 1)]
}
function expectedChange(entries: Entry[], oldKey: number, newKey: number, payload: number): Entry[] {
  const normalized = entries.map(([entryKey, entryPayload]) => [entryKey & 0xffff, entryPayload & 0xffff] as Entry)
  if ((oldKey & 0xffff) === (newKey & 0xffff)) return normalized
  const removed = expectedRemove(normalized, oldKey, payload)
  if (removed.length === normalized.length) return normalized
  return expectedInsert(removed, newKey, payload)
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

describe('binary insert extended coverage', () => {
  it('inserts at every position for arrays from empty to full', () => {
    for (let length = 0; length < capacity; length++) {
      const initial = Array.from({ length }, (_, index) => [index * 4, 0x6000 + index] as Entry)

      for (let position = 0; position <= length; position++) {
        const m = machine()
        const key = position === 0 ? -1 : position === length ? length * 4 + 1 : position * 4 - 1
        const payload = 0x6100 + position
        writeArray(m, initial)
        insert(m, key, payload)

        expect(readArray(m), `length ${length}, position ${position}`).toEqual(expectedInsert(initial, key, payload))
        expect(tail(m)).toBe(head() + (length + 1) * recordSize)
      }
    }
  })

  it('orders signed 16-bit keys across the sign boundary', () => {
    const m = machine()
    writeArray(m, [])
    let expected: Entry[] = []
    const keys = [0, 32767, -32768, -1, 1, -32768, 32767, -2, 32766]

    keys.forEach((key, index) => {
      const payload = 0x7000 + index
      insert(m, key, payload)
      expected = expectedInsert(expected, key, payload)
      expect(readArray(m), `after inserting ${key}`).toEqual(expected)
    })

    expect(sortedKeys(m)).toEqual([...keys].sort((a, b) => a - b))
  })

  it('keeps duplicate records stable at both sorted-array edges', () => {
    const cases: Array<{ key: number; initial: Entry[]; payload: number }> = [
      { key: -32768, initial: [[-32768, 0x7101], [-32768, 0x7102], [-1, 0x7103]], payload: 0x7104 },
      { key: 32767, initial: [[0, 0x7201], [32767, 0x7202], [32767, 0x7203]], payload: 0x7204 },
    ]

    cases.forEach(({ key, initial, payload }) => {
      const m = machine()
      writeArray(m, initial)
      insert(m, key, payload)
      expect(readArray(m)).toEqual(expectedInsert(initial, key, payload))
    })
  })

  it('preserves records through deterministic mixed signed inserts', () => {
    const seeds = [0x0001, 0x1234, 0x8000, 0xffff]

    seeds.forEach((seed) => {
      const m = machine()
      writeArray(m, [])
      let state = seed
      let expected: Entry[] = []

      for (let index = 0; index < capacity; index++) {
        state = (state * 25173 + 13849) & 0xffff
        const key = (state << 16) >> 16
        const payload = (0x9000 + seed + index) & 0xffff
        insert(m, key, payload)
        expected = expectedInsert(expected, key, payload)

        expect(readArray(m), `seed ${seed.toString(16)}, insert ${index}`).toEqual(expected)
        expect(tail(m)).toBe(head() + (index + 1) * recordSize)
      }
    })
  })

  it('preserves guard words outside the storage region', () => {
    const m = machine()
    const before = head() - 4
    const after = head() + capacity * recordSize
    m.writeWord(before, 0x1357)
    m.writeWord(before + 2, 0x2468)
    m.writeWord(after, 0x55aa)
    m.writeWord(after + 2, 0xaa55)
    writeArray(m, [[-10, 0x7301], [0, 0x7302], [10, 0x7303]])

    insert(m, 5, 0x7304)

    expect(m.readWord(before)).toBe(0x1357)
    expect(m.readWord(before + 2)).toBe(0x2468)
    expect(m.readWord(after)).toBe(0x55aa)
    expect(m.readWord(after + 2)).toBe(0xaa55)
  })
})

describe('binary search upper bound', () => {
  it('returns head for an empty array', () => {
    const m = machine()
    writeArray(m, [])
    expect(bsearch(m, 0)).toBe(head())
    expect(bsearch(m, -32768)).toBe(head())
    expect(bsearch(m, 32767)).toBe(head())
  })

  it('returns head when the key is smaller than every record', () => {
    const m = machine()
    writeArray(m, [[10, 1], [20, 2], [30, 3]])
    expect(bsearch(m, 5)).toBe(head())
    expect(bsearch(m, -1)).toBe(head())
  })

  it('returns tail when the key is larger than every record', () => {
    const m = machine()
    const entries: Entry[] = [[10, 1], [20, 2], [30, 3]]
    writeArray(m, entries)
    expect(bsearch(m, 30)).toBe(head() + entries.length * recordSize)
    expect(bsearch(m, 31)).toBe(head() + entries.length * recordSize)
  })

  it('returns the first record strictly greater than the key', () => {
    const m = machine()
    const entries: Entry[] = [[1, 1], [3, 3], [5, 5], [7, 7]]
    writeArray(m, entries)
    expect(bsearch(m, 4)).toBe(head() + 2 * recordSize)
    expect(bsearch(m, 5)).toBe(head() + 3 * recordSize)
    expect(bsearch(m, 0)).toBe(head())
  })

  it('points past every duplicate of the searched key', () => {
    const m = machine()
    const entries: Entry[] = [[2, 0x2001], [2, 0x2002], [2, 0x2003], [5, 0x2005]]
    writeArray(m, entries)
    expect(bsearch(m, 2)).toBe(head() + 3 * recordSize)
  })

  it('handles a single-element array on both sides of the key', () => {
    const m = machine()
    writeArray(m, [[10, 0xa0]])
    expect(bsearch(m, 1)).toBe(head())
    expect(bsearch(m, 10)).toBe(head() + recordSize)
    expect(bsearch(m, 20)).toBe(head() + recordSize)
  })

  it('orders signed 16-bit keys across the sign boundary', () => {
    const m = machine()
    const entries: Entry[] = [[-32768, 1], [-1, 2], [0, 3], [32767, 4]]
    writeArray(m, entries)
    expect(bsearch(m, -32768)).toBe(head() + recordSize)
    expect(bsearch(m, -2)).toBe(head() + recordSize)
    expect(bsearch(m, -1)).toBe(head() + 2 * recordSize)
    expect(bsearch(m, 0)).toBe(head() + 3 * recordSize)
    expect(bsearch(m, 32767)).toBe(head() + 4 * recordSize)
  })

  it('matches the insertion point for every key and array length', () => {
    for (let length = 0; length <= capacity; length++) {
      const initial = Array.from({ length }, (_, index) => [index * 4, 0x6000 + index] as Entry)
      const keys = [-1, ...initial.map(([key]) => signed16(key)), length * 4 + 1, 1]

      for (const key of keys) {
        const m = machine()
        writeArray(m, initial)
        expect(bsearch(m, key), `length ${length}, key ${key}`).toBe(expectedUpperBound(initial, key))
      }
    }
  })

  it('preserves BC', () => {
    const m = machine()
    writeArray(m, [[1, 1], [3, 3], [5, 5]])
    m.regs.bc = 0x1234
    m.runFrom(address('test_binary_search'))
    expect(m.regs.bc).toBe(0x1234)
  })
})

describe('binary remove', () => {
  it('is a no-op on an empty array', () => {
    const m = machine()
    writeArray(m, [])
    remove(m, 5, 0xaaaa)
    expect(readArray(m)).toEqual([])
    expect(tail(m)).toBe(head())
  })

  it('removes the only element', () => {
    const m = machine()
    writeArray(m, [[5, 0xaaaa]])
    remove(m, 5, 0xaaaa)
    expect(readArray(m)).toEqual([])
    expect(tail(m)).toBe(head())
  })

  it('removes from the beginning', () => {
    const m = machine()
    writeArray(m, [[10, 1], [20, 2], [30, 3]])
    remove(m, 10, 1)
    expect(readArray(m)).toEqual([[20, 2], [30, 3]])
  })

  it('removes from the end', () => {
    const m = machine()
    writeArray(m, [[10, 1], [20, 2], [30, 3]])
    remove(m, 30, 3)
    expect(readArray(m)).toEqual([[10, 1], [20, 2]])
  })

  it('removes from the middle', () => {
    const m = machine()
    writeArray(m, [[10, 1], [20, 2], [30, 3]])
    remove(m, 20, 2)
    expect(readArray(m)).toEqual([[10, 1], [30, 3]])
  })

  it('selects the matching payload among duplicate keys', () => {
    const m = machine()
    writeArray(m, [[2, 0x2001], [2, 0x2002], [2, 0x2003], [5, 0x2005]])
    remove(m, 2, 0x2002)
    expect(readArray(m)).toEqual([[2, 0x2001], [2, 0x2003], [5, 0x2005]])
  })

  it('is a no-op when the key exists but the payload does not', () => {
    const m = machine()
    const initial: Entry[] = [[2, 0x2001], [2, 0x2002], [5, 0x2005]]
    writeArray(m, initial)
    remove(m, 2, 0x2099)
    expect(readArray(m)).toEqual(initial)
    expect(tail(m)).toBe(head() + initial.length * recordSize)
  })

  it('is a no-op when the key is missing', () => {
    const m = machine()
    const initial: Entry[] = [[1, 1], [3, 3], [5, 5]]
    writeArray(m, initial)
    remove(m, 4, 1)
    expect(readArray(m)).toEqual(initial)
  })

  it('rewinds tail by exactly 4 bytes', () => {
    const m = machine()
    writeArray(m, [[1, 1], [2, 2], [3, 3]])
    const before = tail(m)
    remove(m, 2, 2)
    expect(tail(m)).toBe(before - 4)
  })

  it('does not overwrite memory beyond the old tail', () => {
    const m = machine()
    writeArray(m, [[1, 1], [3, 3], [5, 5]])
    const sentinel = head() + 3 * recordSize
    m.writeWord(sentinel, 0x55aa)
    m.writeWord(sentinel + 2, 0xaa55)
    remove(m, 3, 3)
    expect(m.readWord(sentinel)).toBe(0x55aa)
    expect(m.readWord(sentinel + 2)).toBe(0xaa55)
  })

  it('removes signed-boundary keys by payload', () => {
    const m = machine()
    writeArray(m, [[-32768, 0x8101], [-1, 0x8102], [0, 0x8103], [32767, 0x8104]])
    remove(m, -1, 0x8102)
    expect(readArray(m)).toEqual([[-32768 & 0xffff, 0x8101], [0, 0x8103], [32767, 0x8104]])
  })

  it('removes every position for arrays from one element to full', () => {
    for (let length = 1; length <= capacity; length++) {
      const initial = Array.from({ length }, (_, index) => [index * 4, 0x6000 + index] as Entry)

      for (let position = 0; position < length; position++) {
        const m = machine()
        writeArray(m, initial)
        const [key, payload] = initial[position]
        remove(m, key, payload)
        expect(readArray(m), `length ${length}, position ${position}`).toEqual(expectedRemove(initial, key, payload))
        expect(tail(m)).toBe(head() + (length - 1) * recordSize)
      }
    }
  })

  it('clears the array by removing records from the front', () => {
    const m = machine()
    const initial = Array.from({ length: 8 }, (_, index) => [index, 0x4000 + index] as Entry)
    writeArray(m, initial)
    let expected = initial
    for (const [key, payload] of initial) {
      remove(m, key, payload)
      expected = expectedRemove(expected, key, payload)
      expect(readArray(m)).toEqual(expected)
    }
    expect(tail(m)).toBe(head())
  })

  it('clears the array by removing records from the back', () => {
    const m = machine()
    const initial = Array.from({ length: 8 }, (_, index) => [index, 0x4000 + index] as Entry)
    writeArray(m, initial)
    let expected = initial
    for (const [key, payload] of [...initial].reverse()) {
      remove(m, key, payload)
      expected = expectedRemove(expected, key, payload)
      expect(readArray(m)).toEqual(expected)
    }
    expect(tail(m)).toBe(head())
  })

  it('preserves guard words outside the storage region', () => {
    const m = machine()
    const before = head() - 4
    const after = head() + capacity * recordSize
    m.writeWord(before, 0x1357)
    m.writeWord(before + 2, 0x2468)
    m.writeWord(after, 0x55aa)
    m.writeWord(after + 2, 0xaa55)
    writeArray(m, [[-10, 0x7301], [0, 0x7302], [10, 0x7303]])

    remove(m, 0, 0x7302)

    expect(m.readWord(before)).toBe(0x1357)
    expect(m.readWord(before + 2)).toBe(0x2468)
    expect(m.readWord(after)).toBe(0x55aa)
    expect(m.readWord(after + 2)).toBe(0xaa55)
  })
})

describe('binary change depth', () => {
  it('is a no-op when the key does not change', () => {
    const m = machine()
    const initial: Entry[] = [[1, 0x1001], [5, 0x1005], [9, 0x1009]]
    writeArray(m, initial)
    changeDepth(m, 5, 5, 0x1005)
    expect(readArray(m)).toEqual(initial)
  })

  it('does not restack a duplicate when the key is unchanged', () => {
    const m = machine()
    const initial: Entry[] = [[2, 0x2001], [2, 0x2002], [2, 0x2003], [5, 0x2005]]
    writeArray(m, initial)
    changeDepth(m, 2, 2, 0x2002)
    expect(readArray(m)).toEqual(initial)
  })

  it('is a no-op on an empty array', () => {
    const m = machine()
    writeArray(m, [])
    changeDepth(m, 1, 2, 0xaaaa)
    expect(readArray(m)).toEqual([])
    expect(tail(m)).toBe(head())
  })

  it('is a no-op when the record is missing', () => {
    const m = machine()
    const initial: Entry[] = [[1, 1], [3, 3], [5, 5]]
    writeArray(m, initial)
    changeDepth(m, 3, 8, 0x9999)
    expect(readArray(m)).toEqual(initial)
  })

  it('updates a key in place when it still belongs in the same slot', () => {
    const m = machine()
    writeArray(m, [[1, 1], [5, 5], [10, 10]])
    changeDepth(m, 5, 6, 5)
    expect(readArray(m)).toEqual([[1, 1], [6, 5], [10, 10]])
  })

  it('moves an item left', () => {
    const m = machine()
    writeArray(m, [[1, 1], [5, 5], [10, 10], [15, 15]])
    changeDepth(m, 10, 3, 10)
    expect(readArray(m)).toEqual([[1, 1], [3, 10], [5, 5], [15, 15]])
  })

  it('moves an item right', () => {
    const m = machine()
    writeArray(m, [[1, 1], [5, 5], [10, 10], [15, 15]])
    changeDepth(m, 5, 12, 5)
    expect(readArray(m)).toEqual([[1, 1], [10, 10], [12, 5], [15, 15]])
  })

  it('moves the first item to the end', () => {
    const m = machine()
    writeArray(m, [[1, 1], [5, 5], [10, 10]])
    changeDepth(m, 1, 20, 1)
    expect(readArray(m)).toEqual([[5, 5], [10, 10], [20, 1]])
  })

  it('moves the last item to the front', () => {
    const m = machine()
    writeArray(m, [[1, 1], [5, 5], [10, 10]])
    changeDepth(m, 10, 0, 10)
    expect(readArray(m)).toEqual([[0, 10], [1, 1], [5, 5]])
  })

  it('keeps the payload attached while moving among duplicates', () => {
    const m = machine()
    writeArray(m, [[2, 0x2001], [2, 0x2002], [8, 0x2008]])
    changeDepth(m, 2, 8, 0x2001)
    expect(readArray(m)).toEqual([[2, 0x2002], [8, 0x2008], [8, 0x2001]])
  })

  it('does not change tail', () => {
    const m = machine()
    writeArray(m, [[1, 1], [5, 5], [10, 10]])
    const before = tail(m)
    changeDepth(m, 5, 0, 5)
    expect(tail(m)).toBe(before)
    changeDepth(m, 0, 20, 5)
    expect(tail(m)).toBe(before)
    changeDepth(m, 20, 6, 5)
    expect(tail(m)).toBe(before)
  })

  it('crosses the signed 16-bit boundary', () => {
    const m = machine()
    const initial: Entry[] = [[-32768, 1], [-1, 2], [0, 3], [32767, 4]]
    writeArray(m, initial)
    changeDepth(m, -32768, 32766, 1)
    const afterFirst = expectedChange(initial, -32768, 32766, 1)
    expect(readArray(m)).toEqual(afterFirst)
    changeDepth(m, 32767, -32768, 4)
    expect(readArray(m)).toEqual(expectedChange(afterFirst, 32767, -32768, 4))
  })

  it('moves every item to every new key for arrays up to capacity', () => {
    for (let length = 1; length <= 8; length++) {
      const initial = Array.from({ length }, (_, index) => [index * 4, 0x8000 + index] as Entry)
      const newKeys = [-2, ...initial.map(([key]) => signed16(key)), ...initial.map(([key]) => signed16(key) + 1), length * 4 + 5]

      for (let position = 0; position < length; position++) {
        for (const newKey of newKeys) {
          const m = machine()
          writeArray(m, initial)
          const [oldKey, payload] = initial[position]
          changeDepth(m, oldKey, newKey, payload)
          expect(readArray(m), `length ${length}, pos ${position}, newKey ${newKey}`).toEqual(
            expectedChange(initial, oldKey, newKey, payload),
          )
          expect(tail(m)).toBe(head() + length * recordSize)
        }
      }
    }
  })

  it('preserves records through mixed signed depth changes', () => {
    const m = machine()
    writeArray(m, [])
    const payloads = [0x9001, 0x9002, 0x9003, 0x9004, 0x9005]
    const keys = [0, 100, -50, 32767, -32768]
    keys.forEach((key, index) => insert(m, key, payloads[index]))

    let expected: Entry[] = []
    keys.forEach((key, index) => {
      expected = expectedInsert(expected, key, payloads[index])
    })
    expect(readArray(m)).toEqual(expected)

    const changes: Array<[number, number, number]> = [
      [100, -100, 0x9002],
      [32767, 1, 0x9004],
      [-32768, 50, 0x9005],
      [0, 0, 0x9001],
      [-50, 200, 0x9003],
    ]
    for (const [oldKey, newKey, payload] of changes) {
      changeDepth(m, oldKey, newKey, payload)
      expected = expectedChange(expected, oldKey, newKey, payload)
      expect(readArray(m), `change ${oldKey} -> ${newKey}`).toEqual(expected)
    }
  })

  it('preserves guard words outside the storage region', () => {
    const m = machine()
    const before = head() - 4
    const after = head() + capacity * recordSize
    m.writeWord(before, 0x1357)
    m.writeWord(before + 2, 0x2468)
    m.writeWord(after, 0x55aa)
    m.writeWord(after + 2, 0xaa55)
    writeArray(m, [[-10, 0x7301], [0, 0x7302], [10, 0x7303]])

    changeDepth(m, -10, 20, 0x7301)
    changeDepth(m, 20, -20, 0x7301)

    expect(m.readWord(before)).toBe(0x1357)
    expect(m.readWord(before + 2)).toBe(0x2468)
    expect(m.readWord(after)).toBe(0x55aa)
    expect(m.readWord(after + 2)).toBe(0xaa55)
  })
})
