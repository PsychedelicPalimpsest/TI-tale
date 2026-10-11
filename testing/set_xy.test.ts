import { execFileSync } from 'node:child_process'
import { mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const app = resolve(import.meta.dirname, '../app')

// The set_x/set_y optimization must only flag a new render list when the
// position actually changes, and must evaluate its object argument once.
// Compile the real engine.h host-side and exercise the macros directly.
const runMacroHarness = () => {
  const dir = mkdtempSync(join(tmpdir(), 'set-xy-'))
  const source = join(dir, 'harness.c')
  const binary = join(dir, 'harness')
  writeFileSync(
    source,
    `
#define __z88dk_callee
#define __z88dk_fastcall
#define __z88dk_fastcall
#include "engine/engine.h"
#include <stdio.h>
int main(void) {
  static Instance inst;
  static Instance arr[2];

  // Same value on both copies: no render-list request.
  inst.x = 10; inst.displayed_sprite.x_pos = 10; inst.flags = 0;
  set_x(&inst, 10);
  if (inst.flags & 0x04) { printf("same x set dirty\\n"); return 1; }
  if (inst.x != 10 || inst.displayed_sprite.x_pos != 10) { printf("same x mutated\\n"); return 2; }

  // Different value: both copies update and the flag is set.
  set_x(&inst, 11);
  if (!(inst.flags & 0x04)) { printf("changed x missed dirty\\n"); return 3; }
  if (inst.x != 11 || inst.displayed_sprite.x_pos != 11) { printf("changed x not synced\\n"); return 4; }

  // Desynced display copy counts as a change even when x already matches.
  inst.flags = 0; inst.x = 20; inst.displayed_sprite.x_pos = 19;
  set_x(&inst, 20);
  if (!(inst.flags & 0x04)) { printf("desync x missed dirty\\n"); return 5; }
  if (inst.displayed_sprite.x_pos != 20) { printf("desync x not synced\\n"); return 6; }

  // Same checks for Y.
  inst.y = 7; inst.displayed_sprite.y_pos = 7; inst.flags = 0;
  set_y(&inst, 7);
  if (inst.flags & 0x04) { printf("same y set dirty\\n"); return 7; }
  set_y(&inst, 8);
  if (!(inst.flags & 0x04)) { printf("changed y missed dirty\\n"); return 8; }
  if (inst.y != 8 || inst.displayed_sprite.y_pos != 8) { printf("changed y not synced\\n"); return 9; }
  inst.flags = 0; inst.y = 20; inst.displayed_sprite.y_pos = 19;
  set_y(&inst, 20);
  if (!(inst.flags & 0x04)) { printf("desync y missed dirty\\n"); return 10; }

  // The object argument must be evaluated exactly once.
  arr[0].x = 0; arr[0].displayed_sprite.x_pos = 0; arr[0].flags = 0;
  arr[1].x = 0; arr[1].displayed_sprite.x_pos = 0; arr[1].flags = 0;
  int idx = 0;
  set_x(&arr[idx++], 5);
  if (idx != 1) { printf("obj evaluated %d times\\n", idx); return 11; }
  if (arr[0].x != 5 || arr[1].x != 0) { printf("wrong element updated\\n"); return 12; }
  idx = 0;
  set_y(&arr[idx++], 6);
  if (idx != 1) { printf("obj y evaluated %d times\\n", idx); return 13; }

  printf("PASS\\n");
  return 0;
}
`,
  )
  execFileSync('gcc', ['-I', app, source, '-o', binary], { stdio: 'pipe' })
  return execFileSync(binary, { encoding: 'utf8' }).trim()
}

describe('engine set_x/set_y macros', () => {
  it('only requests a render list on a real position change', () => {
    expect(runMacroHarness()).toBe('PASS')
  })
})
