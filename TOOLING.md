# Tooling Overview

This document provides an overview of the tools available in the `tooling/` directory for the TI-tale project. These tools are designed to facilitate the conversion of assets (sprites, backgrounds, rooms) from Undertale's format to the limited 4-color grayscale palette of the TI-83+/TI-84+ calculator series.

## Core Tools

### 1. GML Parser & Asset Pipeline (`gml.py`)
`gml.py` is the core library and command-line tool for parsing Undertale GML files (XML format) and managing the asset export process.

- **Purpose:** Loads room data, instances, and tiles; provides methods to quantize images to the TI-84 Plus 4-color palette.
- **Usage (Library):** Used by other tools to load room metadata and process assets.
- **Usage (CLI):** Can be used to batch-export assets for a specific room.
  ```bash
  python tooling/gml.py export <room_name>
  ```

### 2. Room Visualizer (`visualizer.py`)
A graphical tool built with `arcade` to visualize Undertale rooms and simulate their appearance on the TI-84 Plus screen.

- **Purpose:** Preview how GML rooms will look, including instance placement and tile layouts. It features a "TI Mode" that mimics the 96x64 resolution and 4-color palette.
- **Usage:**
  ```bash
  python tooling/visualizer.py <room_name>
  ```
- **Controls:**
  - `T`: Toggle TI-mode (96x64 low-res preview).
  - `I`: Toggle instance visibility.
  - `L`: Lock/Unlock viewport to camera.
  - `Z`: Lock/Unlock zoom to TI-scale.
  - Arrow Keys: Pan the camera.
  - `Q`/`E`: Zoom in/out (when zoom is unlocked).

### 3. Sprite Remaker TUI (`tooling/remaker/`)
A Terminal User Interface (TUI) application built with `textual` for fine-tuning the conversion of individual sprites and backgrounds.

- **Entry Point:** `tooling/remaker/app.py`
- **Features:**
  - Batch processing of sprites and backgrounds.
  - Adjustable parameters for scaling, brightness, contrast, gamma, and alpha threshold.
  - Multiple quantization methods: Threshold, Floyd-Steinberg, and Ordered Dithering.
  - Live preview window (using `arcade`) to see changes in real-time.
- **Usage:**
  ```bash
  python tooling/remaker/app.py
  ```

## Internal Components

- **`tooling/remaker/image_processor.py`**: Contains the logic for image manipulation, including quantization, dithering algorithms (Floyd-Steinberg, Bayer-matrix ordered), and color space conversions.
- **`tooling/remaker/preview_window.py`**: A helper script that opens a separate window to show a side-by-side comparison of the original asset vs. the TI-processed version.
- **`tooling/remaker/test_*.py`**: Unit tests for the image processor, TUI state management, and preview window.

## Data Structure

The tools interact with the `data/` directory to store and retrieve assets:
- `data/backgrounds/`: Processed background PNGs.
- `data/sprites/`: Processed sprite PNGs.
- `data/tiles/`: Processed tileset PNGs.
- `data/rooms.json`: Metadata mapping for room IDs and names.

## Environment Setup

Ensure you have the required dependencies installed:
```bash
pip install arcade textual pillow numpy python-dotenv beautifulsoup4
```
You should also set up an `.env` file with the path to your Undertale assets if necessary (see `.env.example`).
