import React from "react";
import useStore from "../store/useStore";
import { GRID_SIZE, VIEWPORT_SCALES } from "../parser/types.js";

export default function Toolbar() {
  const {
    scale, setScale,
    viewportScale, setViewportScale,
    showGrid, toggleGrid,
    showViewport, toggleViewport,
    showTiles, toggleTiles,
    showInstances, toggleInstances,
    autoGen, toggleAutoGen,
    showPreview, togglePreview,
    roomData,
    viewportX,
    viewportY,
  } = useStore();

  const vpW = Math.round(96 * viewportScale);
  const vpH = Math.round(64 * viewportScale);

  return (
    <div className="toolbar">
      <div className="toolbar-group">
        <label>Zoom:</label>
        <input
          type="range"
          min="1"
          max="8"
          step="0.5"
          value={scale}
          onChange={(e) => setScale(parseFloat(e.target.value))}
        />
        <span className="toolbar-value">{scale}x</span>
      </div>

      <div className="toolbar-group">
        <label className="toggle-label">
          <input type="checkbox" checked={showGrid} onChange={toggleGrid} />
          Grid ({GRID_SIZE}x{GRID_SIZE})
        </label>
      </div>

      <div className="toolbar-group">
        <label className="toggle-label">
          <input type="checkbox" checked={showViewport} onChange={toggleViewport} />
          Viewport
        </label>
        <label>Scale:</label>
        <select
          className="viewport-scale-select"
          value={viewportScale}
          onChange={(e) => setViewportScale(parseFloat(e.target.value))}
        >
          {VIEWPORT_SCALES.map((s) => {
            const w = Math.round(96 * s);
            const h = Math.round(64 * s);
            return (
              <option key={s} value={s}>
                {s.toFixed(2)}x ({w}&times;{h})
              </option>
            );
          })}
        </select>
      </div>

      <div className="toolbar-group toolbar-separator" />

      <div className="toolbar-group">
        <label className="toggle-label">
          <input type="checkbox" checked={autoGen} onChange={toggleAutoGen} />
          Bit-Crunch
        </label>
      </div>

      <div className="toolbar-group">
        <label className="toggle-label">
          <input type="checkbox" checked={showPreview} onChange={togglePreview} />
          TI Preview
        </label>
      </div>

      <div className="toolbar-group toolbar-separator" />

      <div className="toolbar-group">
        <label className="toggle-label">
          <input type="checkbox" checked={showTiles} onChange={toggleTiles} />
          Tiles
        </label>
        <label className="toggle-label">
          <input type="checkbox" checked={showInstances} onChange={toggleInstances} />
          Instances
        </label>
      </div>

      {roomData && (
        <div className="toolbar-group toolbar-info">
          Room: {roomData.width}x{roomData.height} px
          &nbsp;| Tiles: {roomData.tiles.length}
          &nbsp;| Instances: {roomData.instances.length}
          &nbsp;| VP: ({viewportX},{viewportY}) {vpW}&times;{vpH}
        </div>
      )}
    </div>
  );
}
