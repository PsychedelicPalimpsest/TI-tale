import React, { useRef, useEffect, useCallback, useState } from "react";
import useStore from "../store/useStore";
import { renderRoom, drawGrid, drawViewport, clearCache } from "../renderer/room-canvas.js";
import { TI84_W, TI84_H } from "../parser/types.js";

export default function RoomExplorer() {
  const canvasRef = useRef(null);
  const containerRef = useRef(null);
  const cleanCache = useRef(null);
  const genRef = useRef(0);
  const dragging = useRef(false);
  const dragStart = useRef({ x: 0, y: 0, vx: 0, vy: 0 });
  const [rendering, setRendering] = useState(false);
  const [cacheVersion, setCacheVersion] = useState(0);

  const {
    roomData,
    loading,
    error,
    scale,
    viewportX,
    viewportY,
    viewportScale,
    setViewport,
    showGrid,
    showViewport,
    showTiles,
    showInstances,
    autoGen,
  } = useStore();

  const vpW = Math.round(TI84_W * viewportScale);
  const vpH = Math.round(TI84_H * viewportScale);

  const tiSW = TI84_W / vpW;
  const tiSH = TI84_H / vpH;

  const buildCleanCache = useCallback(async () => {
    if (!roomData) return;
    const gen = ++genRef.current;

    const off = document.createElement("canvas");
    off.width = roomData.width * scale;
    off.height = roomData.height * scale;
    const octx = off.getContext("2d");

    setRendering(true);
    try {
      await renderRoom(octx, roomData, {
        scale,
        showTiles,
        showInstances,
        autoGen,
        tiSW,
        tiSH,
      });

      if (showGrid) {
        drawGrid(octx, scale, roomData.width, roomData.height);
      }

      if (gen !== genRef.current) return;
      cleanCache.current = off;
      setCacheVersion(v => v + 1);
    } finally {
      if (gen === genRef.current) setRendering(false);
    }
  }, [roomData, scale, showTiles, showInstances, showGrid, autoGen, tiSW, tiSH]);

  useEffect(() => {
    cleanCache.current = null;
    clearCache();
    buildCleanCache();
  }, [buildCleanCache]);

  const composite = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas || !cleanCache.current) return;
    const ctx = canvas.getContext("2d");
    const src = cleanCache.current;
    canvas.width = src.width;
    canvas.height = src.height;
    ctx.drawImage(src, 0, 0);

    if (showViewport) {
      drawViewport(ctx, viewportX, viewportY, vpW, vpH, scale);
    }
  }, [viewportX, viewportY, vpW, vpH, showViewport, scale, cacheVersion]);

  useEffect(() => {
    composite();
  }, [composite]);

  const clampViewport = useCallback((vx, vy) => {
    if (!roomData) return { vx, vy };
    const maxX = Math.max(0, roomData.width - vpW);
    const maxY = Math.max(0, roomData.height - vpH);
    return {
      vx: Math.max(0, Math.min(Math.round(vx), maxX)),
      vy: Math.max(0, Math.min(Math.round(vy), maxY)),
    };
  }, [roomData, vpW, vpH]);

  const handleMouseDown = useCallback((e) => {
    if (e.target !== canvasRef.current) return;
    dragging.current = true;
    dragStart.current = {
      x: e.clientX,
      y: e.clientY,
      vx: viewportX,
      vy: viewportY,
    };
    e.preventDefault();
  }, [viewportX, viewportY]);

  const handleMouseMove = useCallback((e) => {
    if (!dragging.current || !roomData) return;
    const dx = (e.clientX - dragStart.current.x) / scale;
    const dy = (e.clientY - dragStart.current.y) / scale;
    const vx = dragStart.current.vx + dx;
    const vy = dragStart.current.vy + dy;
    const clamped = clampViewport(vx, vy);
    setViewport(clamped.vx, clamped.vy);
  }, [scale, roomData, clampViewport, setViewport]);

  const handleMouseUp = useCallback(() => {
    dragging.current = false;
  }, []);

  const handleWheel = useCallback((e) => {
    e.preventDefault();
    const { setScale } = useStore.getState();
    const cur = useStore.getState().scale;
    const delta = e.deltaY > 0 ? -0.5 : 0.5;
    setScale(cur + delta);
  }, []);

  if (loading) return <div className="room-loading">Loading room XML...</div>;
  if (error) return <div className="room-error">Error: {error}</div>;
  if (!roomData) return <div className="room-empty">Select a room to begin</div>;

  return (
    <div
      ref={containerRef}
      className="room-explorer"
      onMouseDown={handleMouseDown}
      onMouseMove={handleMouseMove}
      onMouseUp={handleMouseUp}
      onMouseLeave={handleMouseUp}
      onWheel={handleWheel}
    >
      <canvas ref={canvasRef} className="room-canvas" />
      {rendering && <div className="render-overlay">Rendering tiles &amp; sprites...</div>}
    </div>
  );
}
