# Notes about memory usage

This project is a TI-83+ Flash Application. It uses a custom memory map to manage greyscale graphics and interrupts efficiently.

## Pages:

| Page  | Usage                                                                                       |
| ----- | ------------------------------------------------------------------------------------------- |
| 4000h | App ROM page (Flash). Code executes from here.                                              |
| 8000h | RAM page 83 is swapped here for extra executable RAM. **Executable**                        |
| C000h | Normal system RAM page (typically page 01 on TI-83+). **Not Executable**                    |

## 8000h (RAM Page 83)

This page is mapped to `$8000-$BFFF`. It is used for the interrupt vector table and interrupt service routine (ISR).

| Address | Usage                                                              |
| ------- | ------------------------------------------------------------------ |
| 8000h   | Interrupt vector table (257 bytes, filled with 81h)                |
| 8101h   | Free RAM area (previously "Ram area 1", ~128 bytes)                |
| 8181h   | Interrupt Service Routine (ISR) code                               |

## C000h (System RAM)

This page is used for variables, buffers, and the C stack.

| Address | Usage                                                              |
| ------- | ------------------------------------------------------------------ |
| C000h   | Assembly global variables (`_first_rom_page`, `_gray_count`, etc.) |
| C100h   | C static/global variables (`c_bss`)                                |
| C500h   | Screen Buffers start                                               |
| C500h   | `working_dark` (768 bytes)                                         |
| C800h   | `working_light` (768 bytes)                                        |
| CB00h   | Greyscale Phase 1 Buffer (768 bytes)                               |
| CE00h   | Greyscale Phase 2 Buffer (768 bytes)                               |
| D100h   | Greyscale Phase 3 Buffer (768 bytes)                               |
| D400h   | Greyscale Phase 1 Alt Buffer (768 bytes)                           |
| D700h   | Greyscale Phase 2 Alt Buffer (768 bytes)                           |
| DA00h   | Greyscale Phase 3 Alt Buffer (768 bytes)                           |

## Greyscale Buffers

The engine uses a 3-phase greyscale technique. Two sets of buffers (primary and alt) are used for double-buffering or phase switching. Each buffer is 768 bytes (96x64 pixels).
