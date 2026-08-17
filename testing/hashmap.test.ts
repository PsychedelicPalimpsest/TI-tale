import { describe, expect, it } from 'vitest'
import { address, machine, mapAddress } from './test_machine.js'

type TestMachine = ReturnType<typeof machine>

const base = () => mapAddress('hm_base_testing')
const tailStorage = () => mapAddress('test_hmap_tail_storage')
const pool = () => mapAddress('test_hmap_pool')
const keyA = () => mapAddress('test_hmap_key_a')
const keyB = () => mapAddress('test_hmap_key_b')
const keyC = () => mapAddress('test_hmap_key_c')
const emptyKey = () => mapAddress('test_hmap_key_empty')
const keyD = () => mapAddress('test_hmap_key_d')

const keys = {
  a: [0x01, 0x02, 0x03],
  b: [0x01, 0x02, 0x0B],
  c: [0x01, 0x02, 0x13],
  empty: [0x00, 0x00, 0x01],
  d: [0x00, 0x00, 0x00],
}

function hash1(key: number[], seed = 0): number {
  return key.reduce((hash, byte) => ((hash ^ byte) + hash) & 0xFF, seed)
}

function bucketFor(key: number[]): number {
  return base() + 2 * (hash1(key) & 7)
}

function writeKey(m: TestMachine, addressValue: number, key: number[]) {
  m.writeBlock(addressValue, key)
}

function initialize(m: TestMachine) {
  m.runFrom(address('test_hmap_init'))
}

function allocate(m: TestMachine, keyAddress: number): number {
  m.regs.a = 0
  m.regs.hl = keyAddress
  m.runFrom(address('test_hmap_alloc'))
  return m.regs.hl
}

function lookup(m: TestMachine, keyAddress: number) {
  m.regs.a = 0
  m.regs.hl = keyAddress
  m.runFrom(address('test_hmap_lookup'))
}

function isZero(m: TestMachine): boolean {
  return (m.regs.f & 0x40) !== 0
}

describe('hash functions', () => {
  it('computes hash_func1 with xor, add, and byte overflow', () => {
    const m = machine()
    m.regs.a = 0xF0
    m.regs.d = 0xF0
    m.regs.e = 0x2F

    m.runFrom(address('test_hash_func1'))

    expect(m.regs.a).toBe(0xCF)
  })

  it('computes hash_func2 with an eight-bit rotation', () => {
    const m = machine()
    m.regs.a = 0x12
    m.regs.d = 0x12
    m.regs.e = 0x34

    m.runFrom(address('test_hash_func2'))

    expect(m.regs.a).toBe(0xB6)
  })

  it('hashes all key bytes with hash_func1', () => {
    const m = machine()
    writeKey(m, keyA(), keys.a)
    m.regs.a = 0
    m.regs.hl = keyA()

    m.runFrom(address('test_xhash1'))

    expect(m.regs.a).toBe(hash1(keys.a))
    expect(m.regs.hl).toBe(keyA() + keys.a.length)
  })

  it('hashes all key bytes with hash_func2', () => {
    const m = machine()
    writeKey(m, keyA(), keys.a)
    m.regs.a = 0
    m.regs.hl = keyA()

    m.runFrom(address('test_xhash2'))

    expect(m.regs.a).not.toBe(hash1(keys.a))
    expect(m.regs.hl).toBe(keyA() + keys.a.length)
  })
})

describe('hashmap buckets and allocation', () => {
  it('clears every two-byte bucket entry during initialization', () => {
    const m = machine()

    initialize(m)

    for (let offset = 0; offset < 16; offset++) {
      expect(m.readByte(base() + offset)).toBe(0)
    }
    expect(m.readWord(tailStorage())).toBe(pool())
  })

  it('allocates an object, links its bucket, and copies its key', () => {
    const m = machine()
    initialize(m)
    writeKey(m, keyA(), keys.a)

    const object = allocate(m, keyA())

    expect(object).toBe(pool())
    expect(m.readWord(tailStorage())).toBe(pool() + 5)
    expect(m.readWord(object)).toBe(0)
    expect(Array.from({ length: 3 }, (_, i) => m.readByte(object + 2 + i))).toEqual(keys.a)
    expect(m.readWord(bucketFor(keys.a))).toBe(object)
  })

  it('keeps separate buckets independent', () => {
    const m = machine()
    initialize(m)
    writeKey(m, keyA(), keys.a)
    writeKey(m, keyD(), keys.d)

    const first = allocate(m, keyA())
    const second = allocate(m, keyD())

    expect(bucketFor(keys.a)).not.toBe(bucketFor(keys.d))
    expect(m.readWord(bucketFor(keys.a))).toBe(first)
    expect(m.readWord(bucketFor(keys.d))).toBe(second)
    expect(m.readWord(first)).toBe(0)
    expect(m.readWord(second)).toBe(0)
  })

  it('links colliding objects in insertion order', () => {
    const m = machine()
    initialize(m)
    writeKey(m, keyA(), keys.a)
    writeKey(m, keyB(), keys.b)

    const first = allocate(m, keyA())
    const second = allocate(m, keyB())

    expect(bucketFor(keys.a)).toBe(bucketFor(keys.b))
    expect(m.readWord(bucketFor(keys.a))).toBe(first)
    expect(m.readWord(first)).toBe(second)
    expect(m.readWord(second)).toBe(0)
  })
})

describe('hashmap lookup', () => {
  it('finds the head of a collision chain', () => {
    const m = machine()
    initialize(m)
    writeKey(m, keyA(), keys.a)
    writeKey(m, keyB(), keys.b)
    const first = allocate(m, keyA())
    const second = allocate(m, keyB())

    lookup(m, keyB())

    expect(isZero(m)).toBe(false)
    expect(m.regs.hl).toBe(second)
    expect(m.regs.bc).toBe(first)
    expect(first).not.toBe(second)
  })

  it('finds an older object after traversing a collision chain', () => {
    const m = machine()
    initialize(m)
    writeKey(m, keyA(), keys.a)
    writeKey(m, keyB(), keys.b)
    const first = allocate(m, keyA())
    allocate(m, keyB())

    lookup(m, keyA())

    expect(isZero(m)).toBe(false)
    expect(m.regs.hl).toBe(first)
    expect(m.regs.bc).toBe(bucketFor(keys.a))
  })

  it('returns zero for a missing key in a non-empty collision chain', () => {
    const m = machine()
    initialize(m)
    writeKey(m, keyA(), keys.a)
    writeKey(m, keyB(), keys.b)
    writeKey(m, keyC(), keys.c)
    allocate(m, keyA())
    allocate(m, keyB())

    lookup(m, keyC())

    expect(isZero(m)).toBe(true)
  })

  it('returns zero for a key in an empty bucket', () => {
    const m = machine()
    initialize(m)
    writeKey(m, keyA(), keys.a)
    writeKey(m, emptyKey(), keys.empty)
    allocate(m, keyA())
    const spBefore = m.regs.sp

    lookup(m, emptyKey())

    expect(isZero(m)).toBe(true)
    expect(m.regs.sp).toBe((spBefore - 2) & 0xFFFF)
  })
})
