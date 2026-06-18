import React, { useState, useCallback, useEffect, useRef } from "react";
import useStore from "../store/useStore";
import { renderRoomForExport, buildBgBin } from "../renderer/background-exporter.js";

const BG_LABELS = ["White", "Light Grey", "Dark Grey", "Black"];
const PREVIEW_MAX_W = 440;

export default function BackgroundExporter() {
  const {
    roomData,
    roomFile,
    viewportScale,
    exportBgLevel,
    exportIncludeTiles,
    exportInstanceToggles,
    redrawnSprites,
    redrawnBackgrounds,
    setExportBgLevel,
    setExportIncludeTiles,
    toggleExportObjectType,
    toggleAllExportObjectTypes,
    saveRoomConfig,
  } = useStore();

  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [previewCanvas, setPreviewCanvas] = useState(null);
  const [previewLoading, setPreviewLoading] = useState(false);
  const previewCanvasRef = useRef(null);
  const previewGen = useRef(0);

  const scale = viewportScale;
  const exportW = Math.round((roomData?.width || 0) * scale);
  const exportH = Math.round((roomData?.height || 0) * scale);
  const roomName = (roomFile || "room").replace(".room.gmx", "");
  const defaultFilename = `export_${roomName}_${exportW}x${exportH}.bin`;

  const uniqueObjs = roomData
    ? [...new Set(roomData.instances.map((i) => i.objName))].sort()
    : [];

  useEffect(() => {
    if (!roomData) return;
    let cancelled = false;
    previewGen.current += 1;
    const gen = previewGen.current;

    setPreviewLoading(true);
    (async () => {
      try {
        const canvas = await renderRoomForExport(roomData, {
          viewportScale: scale,
          defaultBgLevel: exportBgLevel,
          includeTiles: exportIncludeTiles,
          instanceToggles: exportInstanceToggles,
          redrawnBackgrounds,
          redrawnSprites,
        });
        if (cancelled || gen !== previewGen.current) return;
        setPreviewCanvas(canvas);
      } catch (err) {
        if (cancelled || gen !== previewGen.current) return;
        console.error("Preview render failed", err);
      } finally {
        if (!cancelled && gen === previewGen.current) {
          setPreviewLoading(false);
        }
      }
    })();
    return () => { cancelled = true; };
  }, [roomData, scale, exportBgLevel, exportIncludeTiles, exportInstanceToggles, redrawnBackgrounds, redrawnSprites]);

  useEffect(() => {
    if (!previewCanvas || !previewCanvasRef.current) return;
    const displayCtx = previewCanvasRef.current.getContext("2d");
    const pw = previewCanvas.width;
    const ph = previewCanvas.height;
    const zoom = Math.min(1, PREVIEW_MAX_W / pw);
    const dw = Math.round(pw * zoom);
    const dh = Math.round(ph * zoom);
    previewCanvasRef.current.width = dw;
    previewCanvasRef.current.height = dh;
    displayCtx.imageSmoothingEnabled = false;
    displayCtx.drawImage(previewCanvas, 0, 0, dw, dh);
  }, [previewCanvas]);

  const handleShiftToggle = useCallback(
    (e, objName) => {
      if (e.shiftKey) {
        e.preventDefault();
        toggleAllExportObjectTypes();
      } else {
        toggleExportObjectType(objName);
      }
    },
    [toggleExportObjectType, toggleAllExportObjectTypes]
  );

  const onExport = useCallback(async () => {
    if (!roomData) return;
    setBusy(true);
    setError(null);
    try {
      const bin = await buildBgBin(roomData, {
        viewportScale: scale,
        defaultBgLevel: exportBgLevel,
        includeTiles: exportIncludeTiles,
        instanceToggles: exportInstanceToggles,
        redrawnBackgrounds,
        redrawnSprites,
      });

      await saveRoomConfig();

      const filename = defaultFilename;
      const blob = new Blob([bin], { type: "application/octet-stream" });

      try {
        const handle = await window.showSaveFilePicker({
          suggestedName: filename,
          types: [
            {
              description: "Binary file",
              accept: { "application/octet-stream": [".bin"] },
            },
          ],
        });
        const writable = await handle.createWritable();
        await writable.write(blob);
        await writable.close();
      } catch {
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = filename;
        document.body.appendChild(a);
        a.click();
        a.remove();
        URL.revokeObjectURL(url);
      }
    } catch (err) {
      setError(String(err.message || err));
    } finally {
      setBusy(false);
    }
  }, [roomData, scale, exportBgLevel, exportIncludeTiles, exportInstanceToggles, redrawnBackgrounds, redrawnSprites, defaultFilename, saveRoomConfig]);

  if (!roomData) return null;

  const previewZoom = previewCanvas
    ? Math.min(1, PREVIEW_MAX_W / previewCanvas.width)
    : 1;

  return (
    <div className="background-exporter">
      <div className="background-exporter-header">
        <span className="background-exporter-title">Export Background .bin</span>
        <span className="background-exporter-room">{roomName}</span>
      </div>

      {error && <div className="background-exporter-error">{error}</div>}

      <div className="background-exporter-columns">
        <div className="background-exporter-settings">
          <div className="background-exporter-section">
            <label className="background-exporter-field">
              <span>Default BG colour:</span>
              <select
                value={exportBgLevel}
                onChange={(e) => setExportBgLevel(Number(e.target.value))}
              >
                {BG_LABELS.map((l, i) => (
                  <option key={i} value={i}>{l}</option>
                ))}
              </select>
            </label>

            <label className="background-exporter-field toggle-label">
              <input
                type="checkbox"
                checked={exportIncludeTiles}
                onChange={(e) => setExportIncludeTiles(e.target.checked)}
              />
              <span>Include tiles</span>
            </label>
          </div>

          <div className="background-exporter-section">
            <div className="background-exporter-section-title">
              Instances
              <button
                className="background-exporter-bulk-btn"
                onClick={toggleAllExportObjectTypes}
                title="Toggle all object types"
              >
                toggle all
              </button>
            </div>
            <div className="background-exporter-instance-list">
              {uniqueObjs.map((name) => {
                const count = roomData.instances.filter((i) => i.objName === name).length;
                const checked = exportInstanceToggles[name] !== false;
                return (
                  <label
                    key={name}
                    className="background-exporter-instance-item toggle-label"
                  >
                    <input
                      type="checkbox"
                      checked={checked}
                      onChange={(e) => handleShiftToggle(e, name)}
                    />
                    <span>{name}</span>
                    <span className="background-exporter-instance-count">({count})</span>
                  </label>
                );
              })}
              {uniqueObjs.length === 0 && (
                <div className="background-exporter-empty">No instances in this room</div>
              )}
            </div>
          </div>

          <div className="background-exporter-section">
            <label className="background-exporter-field">
              <span>Scale:</span>
              <span className="background-exporter-value">
                {scale.toFixed(2)}x ({exportW}&times;{exportH})
              </span>
            </label>

            <label className="background-exporter-field">
              <span>Filename:</span>
              <span className="background-exporter-value">{defaultFilename}</span>
            </label>
          </div>

          <div className="background-exporter-section">
            <button
              className="background-exporter-export-btn"
              onClick={onExport}
              disabled={busy}
            >
              {busy ? "Exporting..." : "Export .bin"}
            </button>
          </div>

          <div className="background-exporter-autosave">
            settings auto-saved per room
          </div>
        </div>

        <div className="background-exporter-preview">
          <div className="background-exporter-preview-label">
            Preview {previewZoom < 1 ? `(${(previewZoom * 100).toFixed(0)}%)` : ""}
          </div>
          <div className="background-exporter-preview-box">
            {previewLoading && !previewCanvas && (
              <div className="background-exporter-preview-loading">rendering…</div>
            )}
            <canvas
              ref={previewCanvasRef}
              className="background-exporter-preview-canvas"
              style={{ display: previewCanvas ? "block" : "none" }}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
