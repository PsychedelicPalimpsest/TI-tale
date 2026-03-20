# Project TI-tale: Undertale for TI-84 Plus

## Project Overview
TI-tale is an ambitious port of *Undertale* to the Z80-based TI-84 Plus (non-CE) graphing calculator. The project aims to replicate the core experience of Undertale within the extreme constraints of 1990s-era hardware.

## Target Hardware Constraints
- **Processor:** Z80 (~6 MHz or 15 MHz in fast mode).
- **Display:** 96x64 monochrome LCD.
- **Memory:** ~24KB of user RAM (standard).
- **Graphics:** 4-color software grayscale (simulated via bitplane toggling in `app/engine/greyscale.asm`).

## Technical Architecture
- **Engine:** Custom assembly/C hybrid (`app/`).
- **Rendering:** A "Scene Tiller" (`app/engine/scene_tiller.asm`) handles tile-based background rendering.
- **Asset Pipeline:** Tooling (`tooling/`) bridges GameMaker Studio 1.4 (`.gmx`) assets to TI-friendly binary formats.
- **Grayscale Palette:** 
  - White (00)
  - Light Grey (01)
  - Dark Grey (10)
  - Black (11)
  - Light Blue (Transparency/Key)

## Current Tooling State
- `gml.py`: Interprets GameMaker Studio 1.4 Room, Object, Sprite, and Background XML.
- `visualizer.py`: An `arcade`-based tool to preview GMX rooms.
- **TI-MODE:** A specialized preview mode that enforces the 4-color palette and only uses assets from the project's local `data/` directory.

## Development Mandates
1. **Efficiency First:** Every byte and clock cycle counts.
2. **Asset Integrity:** All final assets must reside in `data/` and adhere to the 4-color palette.
3. **Viewport focus:** The TI screen is only 96x64. All designs must be legible at this resolution.
