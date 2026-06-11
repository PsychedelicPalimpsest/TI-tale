import React, { useState, useEffect } from "react";
import useStore from "../store/useStore";
import { GRID_SIZE, VIEWPORT_SCALES, TI84_W, TI84_H } from "../parser/types.js";

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

  const vpW = Math.round(TI84_W * viewportScale);
  const vpH = Math.round(TI84_H * viewportScale);

  const isPreset = VIEWPORT_SCALES.includes(viewportScale);
  const [customText, setCustomText] = useState(
    isPreset ? "" : viewportScale.toFixed(2)
  );

  useEffect(() => {
    if (isPreset) {
      setCustomText("");
    } else {
      setCustomText(viewportScale.toFixed(2));
    }
  }, [viewportScale, isPreset]);

  const handleCustomChange = (e) => {
    const raw = e.target.value;
    setCustomText(raw);
    if (raw === "") return;
    const n = parseFloat(raw);
    if (!Number.isFinite(n)) return;
    setViewportScale(n);
  };

  const handleCustomBlur = () => {
    if (customText === "") {
      setCustomText(isPreset ? "" : viewportScale.toFixed(2));
    }
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
        <label>Scale:</label>
        <select
          className="viewport-scale-select"
          value={isPreset ? viewportScale : ""}
          onChange={(e) => setViewportScale(parseFloat(e.target.value))}
        >
          <option value="" disabled>&mdash; custom &mdash;</option>
          {VIEWPORT_SCALES.map((s) => {
            const w = Math.round(TI84_W * s);
            const h = Math.round(TI84_H * s);
            return (
              <option key={s} value={s}>
                {s.toFixed(2)}x ({w}&times;{h})
              </option>
            );
          })}
        </select>
        <input
          type="number"
          className="viewport-scale-input"
          min="0.25"
          max="8"
          step="0.25"
          value={customText}
          placeholder="custom"
          onChange={handleCustomChange}
          onBlur={handleCustomBlur}
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
          &nbsp;| VP: ({viewportX},{viewportY}) {vpW}&times;{vpH}
        </div>
      )}
    </div>
  );
}
