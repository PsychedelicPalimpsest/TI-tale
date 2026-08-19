import { describe, expect, it } from 'vitest'
import { address, machine, mapAddress } from './test_machine.js'

type TestMachine = ReturnType<typeof machine>

const base = () => mapAddress('bh_base_binary_testing')
const tail = () => mapAddress('bh_tail_binary_testing')
const reservedSlots = () => mapAddress('bh_reservation_binary_testing')
const reservation = 7
const recordSize = 4

function recordAddress(index: number) {
  return base() + index * recordSize
}

function writeRecord(m: TestMachine, index: number, key: number, payload: number) {
  m.writeWord(recordAddress(index), key & 0xFFFF)
  m.writeWord(recordAddress(index) + 2, payload)
}

function initializeRecords(m: TestMachine) {
  for (let index = 0; index < reservation; index++) {
    writeRecord(m, index, 0x7FFF, 0x7000 + index)
  }
}

function readRecord(m: TestMachine, index: number) {
  return [m.readWord(recordAddress(index)), m.readWord(recordAddress(index) + 2)]
}

function runSiftUp(m: TestMachine, index: number) {
  m.regs.hl = index * recordSize
  m.runFrom(address('test_bh_siftup'))
}

function runSiftDown(m: TestMachine, index: number) {
  m.regs.hl = index * recordSize
  m.runFrom(address('test_bh_siftdown'))
}

describe('binary heap definition', () => {
  it('reserves a two-byte tail followed by the requested records', () => {
    expect(reservedSlots()).toBe(reservation)
    expect(tail()).toBe(base() - 2)
  })
})

describe('binary heap sift-up', () => {
  it('moves a smaller child above its parent and keeps the payload attached', () => {
    const m = machine()
    writeRecord(m, 0, 10, 0xA000)
    writeRecord(m, 1, 20, 0xA001)
    writeRecord(m, 2, 3, 0xA002)

    runSiftUp(m, 2)

    expect(readRecord(m, 0)).toEqual([3, 0xA002])
    expect(readRecord(m, 2)).toEqual([10, 0xA000])
    expect(readRecord(m, 1)).toEqual([20, 0xA001])
  })

  it('continues toward the root through multiple levels', () => {
    const m = machine()
    writeRecord(m, 0, 30, 0xB000)
    writeRecord(m, 1, 20, 0xB001)
    writeRecord(m, 2, 10, 0xB002)
    writeRecord(m, 3, 0, 0xB003)

    runSiftUp(m, 3)

    expect([0, 1, 2, 3].map(index => readRecord(m, index))).toEqual([
      [0, 0xB003],
      [30, 0xB000],
      [10, 0xB002],
      [20, 0xB001],
    ])
  })

  it('compares keys as signed 16-bit values', () => {
    const m = machine()
    writeRecord(m, 0, 1, 0xC000)
    writeRecord(m, 1, 0xFFFF, 0xC001)

    runSiftUp(m, 1)

    expect(readRecord(m, 0)).toEqual([0xFFFF, 0xC001])
    expect(readRecord(m, 1)).toEqual([1, 0xC000])
  })

  it('handles signed comparison at the 16-bit extremes', () => {
    const m = machine()
    writeRecord(m, 0, 0x7FFF, 0xC100)
    writeRecord(m, 1, 0x8000, 0xC101)

    runSiftUp(m, 1)

    expect(readRecord(m, 0)).toEqual([0x8000, 0xC101])
    expect(readRecord(m, 1)).toEqual([0x7FFF, 0xC100])
  })

  it('does not swap an equal key', () => {
    const m = machine()
    writeRecord(m, 0, 7, 0xD000)
    writeRecord(m, 1, 7, 0xD001)

    runSiftUp(m, 1)

    expect(readRecord(m, 0)).toEqual([7, 0xD000])
    expect(readRecord(m, 1)).toEqual([7, 0xD001])
  })

  it('leaves the root unchanged', () => {
    const m = machine()
    writeRecord(m, 0, 0x1234, 0xE000)

    runSiftUp(m, 0)

    expect(readRecord(m, 0)).toEqual([0x1234, 0xE000])
  })
})

describe('binary heap sift-down', () => {
  it('moves the smaller child above a larger parent', () => {
    const m = machine()
    initializeRecords(m)
    writeRecord(m, 0, 10, 0xF000)
    writeRecord(m, 1, 3, 0xF001)
    writeRecord(m, 2, 20, 0xF002)

    runSiftDown(m, 0)

    expect(readRecord(m, 0)).toEqual([3, 0xF001])
    expect(readRecord(m, 1)).toEqual([10, 0xF000])
    expect(readRecord(m, 2)).toEqual([20, 0xF002])
  })

  it('continues downward after the first swap', () => {
    const m = machine()
    writeRecord(m, 0, 100, 0xA100)
    writeRecord(m, 1, 50, 0xA101)
    writeRecord(m, 2, 60, 0xA102)
    writeRecord(m, 3, 70, 0xA103)
    writeRecord(m, 4, 80, 0xA104)
    writeRecord(m, 5, 90, 0xA105)
    writeRecord(m, 6, 100, 0xA106)

    runSiftDown(m, 0)

    expect([0, 1, 2, 3, 4, 5, 6].map(index => readRecord(m, index))).toEqual([
      [50, 0xA101],
      [70, 0xA103],
      [60, 0xA102],
      [100, 0xA100],
      [80, 0xA104],
      [90, 0xA105],
      [100, 0xA106],
    ])
  })

  it('chooses the right child when it is smaller than the left child', () => {
    const m = machine()
    initializeRecords(m)
    writeRecord(m, 0, 10, 0xA200)
    writeRecord(m, 1, 8, 0xA201)
    writeRecord(m, 2, 3, 0xA202)

    runSiftDown(m, 0)

    expect(readRecord(m, 0)).toEqual([3, 0xA202])
    expect(readRecord(m, 1)).toEqual([8, 0xA201])
    expect(readRecord(m, 2)).toEqual([10, 0xA200])
  })

  it('compares keys as signed 16-bit values', () => {
    const m = machine()
    initializeRecords(m)
    writeRecord(m, 0, 1, 0xA300)
    writeRecord(m, 1, 0xFFFF, 0xA301)
    writeRecord(m, 2, 2, 0xA302)

    runSiftDown(m, 0)

    expect(readRecord(m, 0)).toEqual([0xFFFF, 0xA301])
    expect(readRecord(m, 1)).toEqual([1, 0xA300])
    expect(readRecord(m, 2)).toEqual([2, 0xA302])
  })

  it('handles signed comparison at the 16-bit extremes', () => {
    const m = machine()
    initializeRecords(m)
    writeRecord(m, 0, 0x7FFF, 0xA310)
    writeRecord(m, 1, 0x8000, 0xA311)
    writeRecord(m, 2, 1, 0xA312)

    runSiftDown(m, 0)

    expect(readRecord(m, 0)).toEqual([0x8000, 0xA311])
    expect(readRecord(m, 1)).toEqual([0x7FFF, 0xA310])
    expect(readRecord(m, 2)).toEqual([1, 0xA312])
  })

  it('leaves a leaf unchanged', () => {
    const m = machine()
    writeRecord(m, 6, 0x1234, 0xA400)
    const before = Array.from({ length: reservation }, (_, index) => readRecord(m, index))

    runSiftDown(m, 6)

    expect(Array.from({ length: reservation }, (_, index) => readRecord(m, index))).toEqual(before)
  })

  it('does not read or write beyond the reserved records', () => {
    const m = machine()
    const sentinel = recordAddress(reservation)
    m.writeWord(sentinel, 0x55AA)
    m.writeWord(sentinel + 2, 0xAA55)
    writeRecord(m, 3, 1, 0xA503)

    runSiftDown(m, 3)

    expect(m.readWord(sentinel)).toBe(0x55AA)
    expect(m.readWord(sentinel + 2)).toBe(0xAA55)
  })
})
