# TI-tale Tooling

TI-tale is a port of Undertale to the TI-84 Plus (non-CE). The engine is written in z80 assembly, and Undertale's GameMaker source code is ported to C.

## Tooling

The `tooling/` directory contains a visual room explorer for the Undertale GameMaker project files. Its purpose is to help porters:

- **Visualize rooms** --- Render full room maps with tile backgrounds and object/sprite instances, with pan and zoom controls.
- **Inspect sprites** --- See how objects and tiles are placed, scaled, and rotated within each room.
- **Bit-crunch preview** --- Apply a 4-level greyscale Bayer ordered dither to all rendered graphics, simulating how the game would appear on the TI-84's 96×64-pixel display. This allows artists to professionally redraw sprites with the calculator's constraints in mind.

## Architecture

A **Vite + React** single-page application using Zustand for state management. It connects to an Undertale GameMaker project root (configured via a `../.env` file) and serves raw XML and PNG assets through a custom Vite middleware plugin.

### Source layout

```
src/
├── main.jsx                 # React entry point
├── App.jsx                  # Root component
├── components/
│   ├── Layout.jsx           # App shell: header, sidebar, main area, preview panel
│   ├── RoomExplorer.jsx     # Main room canvas (rendering, panning, zooming)
│   ├── TIPreview.jsx        # TI-84 96×64 viewport preview canvas
│   └── Toolbar.jsx          # Controls: zoom, grid, viewport, bit-crunch, toggles
├── parser/
│   ├── types.js             # Constants (TI-84 screen size, tile sizing, grid)
│   ├── room.js              # .room.gmx XML parser
│   ├── background.js        # .background.gmx XML parser
│   └── sprite.js            # .sprite.gmx XML parser
├── renderer/
│   ├── dither.js            # 4-level greyscale Bayer ordered dithering
│   └── room-canvas.js       # Full rendering engine (tiles, instances, grid, viewport)
├── store/
│   └── useStore.js          # Zustand global state
├── styles/
│   └── main.css             # Dark-themed monospace stylesheet
└── util/
    └── xml.js               # XML fetch/parse helpers (DOMParser-based)
```

### Key concepts

- **Tile** --- A 20×20 pixel chunk of a background image placed in a room. GameMaker tiles reference a background (tile sheet), a source position, and a target position/depth in the room.
- **Instance** --- An object placed in a room. Each instance references an object, which references a sprite. Instances have position, scale, rotation, and colour.
- **Bit-Crunch (AutoGen)** --- An ordered-dithering pipeline that converts full-colour sprites into 4-level greyscale (black, dark grey, light grey, white) using a 4×4 Bayer matrix. This approximates how graphics would render on the TI-84 Plus's limited display.
- **TI Preview** --- A 96×64 pixel canvas showing the bit-crunched content of the current viewport region, rendered at 1:1 pixel mapping to the calculator's screen.

### Running

```bash
cd tooling
npm install
npm run dev
```

The dev server starts on `http://localhost:5173`. Before running, ensure `../.env` contains an `UNDERTALE` variable pointing to the Undertale GameMaker project root.
