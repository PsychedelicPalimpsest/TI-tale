import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { Z80TestMachine, Z88dkSymbols } from 'z80-testing-library'

const root = dirname(fileURLToPath(import.meta.url))
const mapPath = resolve(root, 'build/routines.map')
const mapContent = readFileSync(mapPath, 'utf8')
const code = new Uint8Array(readFileSync(resolve(root, 'build/routines_code.bin')))
const core = new Uint8Array(readFileSync(resolve(root, 'build/routines_code_core.bin')))
const engine = new Uint8Array(readFileSync(resolve(root, 'build/routines_code_engine.bin')))
const symbols = new Z88dkSymbols(mapContent)

export const mapAddress = (name: string): number => {
  const match = mapContent.match(new RegExp(`^${name}\\s*=\\s*\\$([0-9A-Fa-f]+)`, 'm'))
  if (!match) throw new Error(`Missing map address: ${name}`)
  return Number.parseInt(match[1], 16)
}

const codeOrigin = mapAddress('__code_head')
const coreOrigin = mapAddress('__code_core_head')
const engineOrigin = mapAddress('__code_engine_head')
const enginePhaseOffset = mapAddress('install_origin') - engineOrigin
const installOrigin = mapAddress('install_location')

export const CODE_ORIGIN = codeOrigin
export const machine = () =>
  new Z80TestMachine({
    regions: [
      [codeOrigin, code],
      [coreOrigin, core],
      [engineOrigin, engine],
      [installOrigin, engine.subarray(enginePhaseOffset)],
    ],
    stackPointer: 0xF000,
  })

export const address = (name: string): number => symbols.get(name)
