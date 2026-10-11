import { execFileSync } from 'node:child_process'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const tooling = resolve(import.meta.dirname, '../tooling/profile_gen.py')
const appMap = resolve(import.meta.dirname, '../app/out.map')

// The compositor optimization splits composition into adjacent regions that
// share boundary labels (compose_pre_draw -> compose_draw_begin -> ...).
// profile_gen must accept consecutive START/STOP markers on the same label
// and every new region must resolve to a real address in the map.
describe('profiler region generation', () => {
  it('parses shared-boundary markers and resolves new compose regions', () => {
    const regions = execFileSync('python3', [tooling, '--regions'], { encoding: 'utf8' })
    for (const name of [
      'compose_pre_draw',
      'compose_draw_begin',
      'compose_draw',
      'compose_draw_end',
      'compose_post_draw',
      'compose_draw_gui',
      'instance_sweep',
      'instance_flush_render_queue',
      '__hl',
    ]) {
      expect(regions, name).toContain(name)
    }

    const output = execFileSync(
      'python3',
      [tooling, '--gen-regions', '--map', appMap],
      { encoding: 'utf8' },
    )
    for (const name of [
      'compose_pre_draw',
      'compose_draw_begin',
      'compose_draw',
      'compose_draw_end',
      'compose_post_draw',
      'compose_draw_gui',
    ]) {
      expect(output, name).toContain(`start-end ${name} `)
    }
    // Adjacent regions share an exact boundary address.
    const line = (n: string) => output.split('\n').find(l => l.startsWith(`start-end ${n} `))!
    expect(line('compose_draw_begin').split(' ')[2]).toBe(line('compose_pre_draw').split(' ')[3])
    expect(line('compose_draw').split(' ')[2]).toBe(line('compose_draw_begin').split(' ')[3])
  })
})
