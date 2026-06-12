# TI-tale Tooling

TI-tale is a port of Undertale to the TI-84 Plus (non-CE). The engine is written in z80 assembly, and Undertale's GameMaker source code is ported to C.

## Tooling

The `tooling/` directory contains a visual room explorer for the Undertale GameMaker project files. Its purpose is to help porters:

- **Visualize rooms** --- Render full room maps with tile backgrounds and object/sprite instances, with pan and zoom controls.
- **Inspect sprites** --- See how objects and tiles are placed, scaled, and rotated within each room.
- **Bit-crunch preview** --- Apply a 4-level greyscale Bayer ordered dither to all rendered graphics, simulating how the game would appear on the TI-84's 96×64-pixel display. This allows artists to professionally redraw sprites with the calculator's constraints in mind.
- **Asset recreation chain** --- End-to-end workflow for redrawing assets: open an asset, see its bit-crunched target, download the bit-crunch as a starting PNG, edit it externally, then upload the redraw and see it in the room. Multiple zoom-level redraws per asset are supported.

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
│   ├── Toolbar.jsx          # Controls: zoom, grid, viewport, bit-crunch, toggles
│   └── AssetEditor.jsx      # Per-asset modal: bit-crunch preview, download, redraws
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

### Asset pipeline

A custom Vite middleware plugin in `vite.config.js` mounts read-only and writeable routes against the project:

- `/undertale/<path>` → files under `$UNDERTALE/` (read-only game assets: `.room.gmx`, `.background.gmx`, `.sprite.gmx`, PNGs).
- `/redrawn/<path>` → files under `tooling/app/assets/redrawn/` (artist redrawn assets, intended to replace the originals on the TI-84). Each file is named `<asset-name>_<label>.png` where `label` is either a `<W>x<H>` size string or a custom user string. The middleware strips the `?query` portion before reading the file so cache-busters don't 404.
- `/api/room-list` → JSON list of `.room.gmx` filenames in the project's `rooms/` directory.
- `/api/redrawn-list` → JSON of `{sprites: [{name,label}], backgrounds: [{name,label}]}` for all redraw files on disk.
- `/api/redrawn-upload` (POST) → writes a base64-encoded PNG to `/redrawn/<kind>/<name>_<label>.png`. Body: `{kind: "sprites"|"backgrounds", name, label, data: "data:image/png;base64,..."}`.
- `/api/redrawn-delete` (POST) → removes a single redraw file. Body: `{kind, name, label}`.

The dev server reads `../.env` once at startup for the `UNDERTALE` path; restart Vite if it changes.

### Notes

- **1:1 pixel invariant** --- `TIPreview.jsx` always allocates a 96×64 internal canvas; the `previewZoom` setting scales it purely via CSS. Don't write to the canvas at any size other than 96×64 or the 1-px-to-1-px guarantee breaks.
- **Dither preserves alpha** --- `dither.js` uses an alpha threshold of 128: pixels below it are forced to fully transparent `(0,0,0,0)`, pixels at or above it are dithered and forced to opaque. Don't regress to unconditionally writing `alpha=255` or transparent sprite regions will fill with black.
- **Greyscale ramp is fixed** --- The 4 levels are `[0x00, 0x55, 0xAA, 0xFF]` (0/33/67/100%). Don't change them without re-tuning the Bayer thresholds in the same file.
- **Dither cache** --- `room-canvas.js` memoises dithered tiles by source rect and target size (`DITHER_CACHE`). It is cleared by `clearCache()`, which is called whenever the room changes; toggling bit-crunch settings is therefore a re-render, not a cache invalidation.
- **Per-label redraws** --- One asset can have many redraws at different sizes, each with a unique `label` (default `<W>x<H>` of the bit-crunched target, or a user-chosen string). The `AssetEditor` modal shows them all as thumbnails with their labels; the active one is auto-selected by matching the bit-crunch size. The active redraw is used when the "Use redrawn" toggle is on in the main canvas.
- **"Show only redrawn" / "Use redrawn"** --- Toolbar toggles in `Toolbar.jsx`. The first hides any tile or instance that has no redrawn version of its asset; the second swaps the original for the redrawn image in the main canvas. When a redrawn asset is used, the renderer draws a 1-px green outline around it as a visual indicator.
- **Toolbar conventions** --- The viewport-scale `<select>` shows the `— custom —` placeholder when `viewportScale` isn't in `VIEWPORT_SCALES`; the sibling `<input type="number">` is the free-form entry. The same pattern is used in the TI preview for display zoom. `previewZoom` is the only piece of state persisted to `localStorage` (key `titale.previewZoom`).

### Running

```bash
cd tooling
npm install
npm run dev
```

The dev server starts on `http://localhost:5173`. Before running, ensure `../.env` contains an `UNDERTALE` variable pointing to the Undertale GameMaker project root.
