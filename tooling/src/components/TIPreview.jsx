import React, { useRef, useEffect, useCallback, useState } from "react";
import useStore from "../store/useStore";
import { renderViewportRegion } from "../renderer/room-canvas.js";
import { applyOrderedDither } from "../renderer/dither.js";

const PREVIEW_ZOOM = 3;
const RENDER_DEBOUNCE = 150;

export default function TIPreview() {
  const canvasRef = useRef(null);
  const timeoutRef = useRef(null);
  const genRef = useRef(0);
  const [rendering, setRendering] = useState(false);
  const [viewEmpty, setViewEmpty] = useState(false);

  const {
    roomData,
    viewportX,
    viewportY,
    viewportW,
    viewportH,
    showTiles,
    showInstances,
  } = useStore();

  const doRender = useCallback(async () => {
    const canvas = canvasRef.current;
    if (!canvas || !roomData) return;
    const gen = ++genRef.current;
    setRendering(true);

    const off = document.createElement("canvas");
    off.width = viewportW;
    off.height = viewportH;
    const offCtx = off.getContext("2d");

    try {
      await renderViewportRegion(offCtx, roomData, {
        vx: viewportX,
        vy: viewportY,
        vw: viewportW,
        vh: viewportH,
        showTiles,
        showInstances,
      });

      if (gen !== genRef.current) return;

      applyOrderedDither(offCtx, viewportW, viewportH);

      if (gen !== genRef.current) return;

      const data = offCtx.getImageData(0, 0, viewportW, viewportH).data;
      let any = false;
      for (let i = 0; i < data.length; i += 4) {
        if (data[i] > 0 || data[i + 1] > 0 || data[i + 2] > 0) { any = true; break; }
      }
      setViewEmpty(!any);

      const ctx = canvas.getContext("2d");
      canvas.width = viewportW;
      canvas.height = viewportH;
      ctx.drawImage(off, 0, 0);
    } catch (e) {
      console.error("TI Preview render failed:", e);
    } finally {
      if (gen === genRef.current) setRendering(false);
    }
  }, [roomData, viewportX, viewportY, viewportW, viewportH, showTiles, showInstances]);

  useEffect(() => {
    if (timeoutRef.current) clearTimeout(timeoutRef.current);
    if (!roomData) return;

    timeoutRef.current = setTimeout(() => {
      doRender();
    }, RENDER_DEBOUNCE);

    return () => {
      if (timeoutRef.current) clearTimeout(timeoutRef.current);
    };
  }, [doRender, roomData]);

  if (!roomData) return null;

  const cssW = viewportW * PREVIEW_ZOOM;
  const cssH = viewportH * PREVIEW_ZOOM;

  return (
    <div className="ti-preview">
      <div className="ti-preview-header">
        <span>TI Preview ({viewportW}&times;{viewportH})</span>
        <span className="ti-preview-dims">
          {PREVIEW_ZOOM}&times; display | ({viewportX}, {viewportY})
        </span>
      </div>
      <div className="ti-preview-canvas-wrap">
        <canvas
          ref={canvasRef}
          className="ti-preview-canvas"
          style={{ width: cssW, height: cssH }}
        />
        {rendering && <div className="ti-preview-loading">rendering...</div>}
        {!rendering && viewEmpty && (
          <div className="ti-preview-empty">no tiles in viewport</div>
        )}
      </div>
      <div className="ti-preview-footer">
        4-level greyscale &middot; 1:1 pixels
      </div>
    </div>
  );
}
