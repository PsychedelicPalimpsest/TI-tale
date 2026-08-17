# Z80 Routine Tests

This directory runs headless routine tests with
[`z80-testing-library`](https://github.com/jannone/z80-testing-library). It
loads the project's `core.lib` and `engine.lib` into the library's bare
`Z80TestMachine`; it does not load a TI-84 CRT or emulate TI-OS.

## Run

The z88dk tools must be available on `PATH`.

```sh
npm install
npm test
npm run typecheck
```

`make test-binary` can be used when only the Z80 image is needed. The build
emits split section images and a map under `build/`. The loader maps the
ordinary code, core code, packed install source, and phased `$8500` engine
code into their linked addresses.

## Add A Routine

1. Add an alias in `routines.asm` so the linker pulls the routine from an app
   library. Use a leading underscore on the public alias so
   `Z88dkSymbols` can resolve it.
2. Add a test to the relevant `*.test.ts` file, using `machine()` for an
   isolated machine and `address()` for the alias address.
3. Initialize every global or memory region the routine expects before
   calling `runFrom()`.

For routines with non-standard register conventions, set registers directly
before `runFrom()` as the existing multiplication tests do. Use stubs in
`test_stubs.asm` only for OS entry points that are not part of the routine
under test.
