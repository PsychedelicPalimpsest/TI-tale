import React from "react";
import useStore from "../store/useStore";
import { GRID_SIZE } from "../parser/types.js";

export default function Toolbar() {
  const {
    scale, setScale,
    viewportX, viewportY,
    viewportW, viewportH, setViewportSize,
    showGrid, toggleGrid,
    showViewport, toggleViewport,
    showTiles, toggleTiles,
    showInstances, toggleInstances,
    autoGen, toggleAutoGen,
    showPreview, togglePreview,
    roomData,
  } = useStore();

  const handleWChange = (e) => {
    const v = parseInt(e.target.value, 10);
    if (!isNaN(v)) setViewportSize(v, viewportH);
  };
  const handleHChange = (e) => {
    const v = parseInt(e.target.value, 10);
    if (!isNaN(v)) setViewportSize(viewportW, v);
  };

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
        <label>W:</label>
        <input
          type="number"
          className="viewport-size"
          value={viewportW}
          onChange={handleWChange}
          min={16}
          max={640}
          step={8}
        />
        <label>H:</label>
        <input
          type="number"
          className="viewport-size"
          value={viewportH}
          onChange={handleHChange}
          min={16}
          max={480}
          step={8}
        />
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
          &nbsp;| VP: ({viewportX},{viewportY})
        </div>
      )}
    </div>
  );
}
