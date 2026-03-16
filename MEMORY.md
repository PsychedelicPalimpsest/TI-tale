# Notes about memory usage

## Pages:

| Page  | Usage                                                                                       |
| ----- | ------------------------------------------------------------------------------------------- |
| 4000h | App ROM page                                                                                |
| 8000h | For more ram, we swap out the ram page to 83. Giving us 16KB of RAM, **Executable**         |
| C000h | The normal ram page is used here, but luckly for us it is mostly unused! **Not Executable** |

## 8000h

Great place for executable code, entire page is available

| Address | Usage                               |
| ------- | ----------------------------------- |
| 8000h   | Interrupt vector table (256 bytes)  |
| 8100h   | Small data segment (See ram area 1) |
| 8181h   | Interupt code                       |

## C000h

Great place for small global variable, but not executable, and is not fully available

| Address | Usage                      |
| ------- | -------------------------- |
| C000h   | Asm variable location      |
| D000h   | C static variable location |

## Ram area 1:

At 8100h, a read write area that is currently unused. 81h bytes long
