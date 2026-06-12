import React, { useEffect, useRef, useState, useCallback } from "react";
import useStore from "../store/useStore";
import { applyOrderedDither } from "../renderer/dither.js";
import { loadImage } from "../renderer/room-canvas.js";

const KIND_LABEL = { sprite: "Sprite", background: "Background" };

export default function AssetEditor() {
  const {
    selectedAsset, closeAsset,
    redrawnSprites, redrawnBackgrounds,
    fetchRedrawn,
  } = useStore();
  const [original, setOriginal] = useState(null);
  const [dithered, setDithered] = useState(null);
  const [redraws, setRedraws] = useState([]);
  const [activeLabel, setActiveLabel] = useState(null);
  const [originalMeta, setOriginalMeta] = useState(null);
  const [error, setError] = useState(null);
  const [uploading, setUploading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [uploadLabel, setUploadLabel] = useState("");
  const [dragOver, setDragOver] = useState(false);
  const [dropNotice, setDropNotice] = useState(null);
  const fileInputRef = useRef(null);
  const dragCounter = useRef(0);

  useEffect(() => {
    if (!selectedAsset) return;
    setError(null);
    setOriginal(null);
    setDithered(null);
    setRedraws([]);
    setActiveLabel(null);
    setOriginalMeta(null);

    let cancelled = false;
    (async () => {
      try {
        const meta = await fetchMeta(selectedAsset);
        if (cancelled) return;
        setOriginalMeta(meta);
        const img = await loadImage(meta.srcUrl);
        if (cancelled) return;
        setOriginal(img);
        const dt = makeDithered(img);
        if (cancelled) return;
        setDithered(dt);
        // Pick a default active label from the bit-crunch size.
        setActiveLabel(`${dt.width}x${dt.height}`);
      } catch (e) {
        if (!cancelled) setError(String(e.message || e));
      }
    })();

    return () => { cancelled = true; };
  }, [selectedAsset]);

  useEffect(() => {
    fetchRedrawn();
  }, [fetchRedrawn]);

  // Whenever selectedAsset changes OR the store's redraw list updates,
  // reload the per-asset redraws from disk.
  useEffect(() => {
    if (!selectedAsset) return;
    let cancelled = false;
    (async () => {
      const entries = selectedAsset.kind === "sprite" ? redrawnSprites : redrawnBackgrounds;
      const mine = entries.filter((e) => e.name === selectedAsset.name);
      const loaded = [];
      for (const e of mine) {
        const img = await loadRedrawnByLabel(selectedAsset, e.label);
        if (cancelled) return;
        if (img) loaded.push({ label: e.label, img });
      }
      if (cancelled) return;
      setRedraws(loaded);
      setActiveLabel((cur) => {
        if (cur && loaded.some((r) => r.label === cur)) return cur;
        const tw = Math.round(dithered?.width ?? 0);
        const th = Math.round(dithered?.height ?? 0);
        return (
          loaded.find((r) => r.label === `${tw}x${th}`)?.label
          || loaded.find((r) => r.label === "1x")?.label
          || loaded[0]?.label
          || null
        );
      });
    })();
    return () => { cancelled = true; };
  }, [redrawnSprites, redrawnBackgrounds, selectedAsset, dithered]);

  const onDownload = useCallback(() => {
    if (!dithered) return;
    const name = sizedName(selectedAsset.name, dithered.width, dithered.height, "bitcrunch");
    downloadCanvas(dithered, name);
  }, [dithered, selectedAsset]);

  const onDownloadOriginal = useCallback(() => {
    if (!original) return;
    const w = original.naturalWidth ?? original.width;
    const h = original.naturalHeight ?? original.height;
    const name = sizedName(selectedAsset.name, w, h, "original");
    downloadCanvas(original, name);
  }, [original, selectedAsset]);

  const onDownloadRedraw = useCallback((label) => {
    const r = redraws.find((x) => x.label === label);
    if (!r) return;
    const w = r.img.naturalWidth ?? r.img.width;
    const h = r.img.naturalHeight ?? r.img.height;
    const name = sizedName(selectedAsset.name, w, h, `redraw_${label}`);
    downloadCanvas(r.img, name);
  }, [redraws, selectedAsset]);

  const onUploadClick = () => fileInputRef.current?.click();

  const doUpload = useCallback(async (file, labelOverride) => {
    if (!file || !selectedAsset) return;
    setUploading(true);
    setError(null);
    try {
      const dataUrl = await readFileAsDataURL(file);
      const dims = await imageDimensions(dataUrl);
      const explicitLabel = (labelOverride ?? uploadLabel ?? "").trim();
      const label = explicitLabel || `${dims.width}x${dims.height}`;
      const res = await fetch("/api/redrawn-upload", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          kind: selectedAsset.kind === "sprite" ? "sprites" : "backgrounds",
          name: selectedAsset.name,
          label,
          data: dataUrl,
        }),
      });
      const out = await res.json();
      if (!res.ok) throw new Error(out.error || "upload failed");
      await fetchRedrawn();
      setActiveLabel(out.label);
      setUploadLabel("");
      setDropNotice(`Uploaded as ${out.label}.png`);
      setTimeout(() => setDropNotice(null), 2500);
    } catch (err) {
      setError(String(err.message || err));
    } finally {
      setUploading(false);
    }
  }, [selectedAsset, uploadLabel, fetchRedrawn]);

  const onFileChange = useCallback((e) => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (file) doUpload(file);
  }, [doUpload]);

  // Drag-and-drop upload ------------------------------------------------

  const onDragEnter = useCallback((e) => {
    if (!selectedAsset) return;
    if (!hasFiles(e)) return;
    e.preventDefault();
    dragCounter.current += 1;
    if (dragCounter.current === 1) setDragOver(true);
  }, [selectedAsset]);

  const onDragOver = useCallback((e) => {
    if (!selectedAsset) return;
    if (!hasFiles(e)) return;
    e.preventDefault();
    e.dataTransfer.dropEffect = "copy";
  }, [selectedAsset]);

  const onDragLeave = useCallback((e) => {
    if (!selectedAsset) return;
    e.preventDefault();
    dragCounter.current = Math.max(0, dragCounter.current - 1);
    if (dragCounter.current === 0) setDragOver(false);
  }, [selectedAsset]);

  const onDrop = useCallback((e) => {
    if (!selectedAsset) return;
    e.preventDefault();
    dragCounter.current = 0;
    setDragOver(false);
    const files = e.dataTransfer?.files;
    if (!files || files.length === 0) return;
    const file = files[0];
    if (!file.type.startsWith("image/")) {
      setError(`Not an image: ${file.name || file.type}`);
      return;
    }
    // Allow the filename (without extension) to seed the upload label so
    // dropping a file named "frisk_2x.png" produces a label "frisk_2x".
    const stem = (file.name || "").replace(/\.[^.]+$/, "").trim();
    doUpload(file, stem || null);
  }, [selectedAsset, doUpload]);

  const onRemoveRedraw = useCallback(async (label) => {
    if (!selectedAsset) return;
    setBusy(true);
    try {
      const res = await fetch("/api/redrawn-delete", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          kind: selectedAsset.kind === "sprite" ? "sprites" : "backgrounds",
          name: selectedAsset.name,
          label,
        }),
      });
      const out = await res.json();
      if (!res.ok) throw new Error(out.error || "delete failed");
      await fetchRedrawn();
    } catch (err) {
      setError(String(err.message || err));
    } finally {
      setBusy(false);
    }
  }, [selectedAsset, fetchRedrawn]);

  if (!selectedAsset) return null;

  const targetW = dithered?.width || 0;
  const targetH = dithered?.height || 0;
  const activeRedraw = redraws.find((r) => r.label === activeLabel);

  return (
    <div
      className={`asset-editor ${dragOver ? "drag-over" : ""}`}
      onDragEnter={onDragEnter}
      onDragOver={onDragOver}
      onDragLeave={onDragLeave}
      onDrop={onDrop}
    >
      <div className="asset-editor-header">
        <div className="asset-editor-title">
          <span className="asset-editor-kind">{KIND_LABEL[selectedAsset.kind]}</span>
          <span className="asset-editor-name">{selectedAsset.name}</span>
        </div>
        <button className="asset-editor-close" onClick={closeAsset} title="Close">×</button>
      </div>

      {error && <div className="asset-editor-error">{error}</div>}

      {!originalMeta && !error && (
        <div className="asset-editor-loading">loading…</div>
      )}

      {originalMeta && (
        <>
          <div className="asset-editor-meta">
            source: {originalMeta.source}<br />
            target: <strong>{targetW}×{targetH} px</strong>
            {originalMeta.note && <> · {originalMeta.note}</>}
          </div>

          <div className="asset-editor-frames">
            <Frame label="Original" canvas={original} scale={zoomFor(original, 220)} />
            <Frame label={`Bit-crunched (${targetW}×${targetH})`} canvas={dithered} scale={zoomFor(dithered, 220)} />
            {activeRedraw ? (
              <Frame
                label={`Redraw (${activeRedraw.label})`}
                canvas={activeRedraw.img}
                scale={zoomFor(activeRedraw.img, 220)}
              />
            ) : (
              <div className="asset-editor-empty">
                <div className="asset-editor-empty-text">No redraw yet</div>
              </div>
            )}
          </div>

          <div className="asset-editor-actions">
            <button onClick={onDownload} disabled={!dithered} title="Download bit-crunched PNG at target size">
              Download bit-crunch
            </button>
            <button onClick={onDownloadOriginal} disabled={!original} title="Download original PNG (full colour)">
              Download original
            </button>
            {activeRedraw && (
              <button
                onClick={() => onDownloadRedraw(activeRedraw.label)}
                disabled={busy}
                title="Download the active redraw"
              >
                Download redraw
              </button>
            )}
          </div>

          <div className="asset-editor-redraws">
            <div className="asset-editor-redraws-label">
              Redraw versions ({redraws.length})
            </div>
            {redraws.length === 0 ? (
              <div className="asset-editor-redraws-empty">none yet</div>
            ) : (
              <div className="asset-editor-redraws-grid">
                {redraws.map((r) => (
                  <RedrawThumb
                    key={r.label}
                    canvas={r.img}
                    label={r.label}
                    active={r.label === activeLabel}
                    onClick={() => setActiveLabel(r.label)}
                    onDelete={() => onRemoveRedraw(r.label)}
                    disabled={busy}
                  />
                ))}
              </div>
            )}
          </div>

          <div className="asset-editor-upload">
            <input
              ref={fileInputRef}
              type="file"
              accept="image/png"
              style={{ display: "none" }}
              onChange={onFileChange}
            />
            <button onClick={onUploadClick} disabled={uploading}>
              {uploading ? "Uploading…" : "Upload redraw"}
            </button>
            <input
              type="text"
              className="asset-editor-upload-label"
              placeholder={`label (e.g. ${targetW}x${targetH}, 2x, draft)`}
              value={uploadLabel}
              onChange={(e) => setUploadLabel(e.target.value)}
              disabled={uploading}
            />
            <span className="asset-editor-hint">PNG, defaults to {targetW}×{targetH} · or drag a file in</span>
          </div>
          {dropNotice && (
            <div className="asset-editor-drop-notice">{dropNotice}</div>
          )}
        </>
      )}
      {dragOver && (
        <div className="asset-editor-drop-overlay">
          <div className="asset-editor-drop-overlay-inner">
            <div className="asset-editor-drop-icon">⤓</div>
            <div className="asset-editor-drop-title">Drop PNG to upload</div>
            <div className="asset-editor-drop-hint">
              The filename (minus extension) becomes the label.
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function hasFiles(e) {
  if (!e.dataTransfer) return false;
  return Array.from(e.dataTransfer.types || []).includes("Files");
}

function Frame({ label, canvas, scale }) {
  if (!canvas) {
    return (
      <div className="asset-editor-frame">
        <div className="asset-editor-frame-label">{label}</div>
        <div className="asset-editor-frame-canvas asset-editor-frame-empty">—</div>
      </div>
    );
  }
  return (
    <div className="asset-editor-frame">
      <div className="asset-editor-frame-label">{label}</div>
      <div className="asset-editor-frame-canvas">
        <canvas
          ref={(el) => {
            if (!el) return;
            if (el.width !== canvas.width) el.width = canvas.width;
            if (el.height !== canvas.height) el.height = canvas.height;
            const ctx = el.getContext("2d");
            ctx.clearRect(0, 0, el.width, el.height);
            ctx.drawImage(canvas, 0, 0);
          }}
          style={{
            width: canvas.width * scale,
            height: canvas.height * scale,
            imageRendering: "pixelated",
          }}
        />
      </div>
    </div>
  );
}

function RedrawThumb({ canvas, label, active, onClick, onDelete, disabled }) {
  if (!canvas) return null;
  return (
    <div className={`asset-editor-redraw-thumb ${active ? "active" : ""}`}>
      <div className="asset-editor-redraw-thumb-canvas" onClick={onClick}>
        <canvas
          ref={(el) => {
            if (!el) return;
            if (el.width !== canvas.width) el.width = canvas.width;
            if (el.height !== canvas.height) el.height = canvas.height;
            const ctx = el.getContext("2d");
            ctx.clearRect(0, 0, el.width, el.height);
            ctx.drawImage(canvas, 0, 0);
          }}
          style={{
            width: canvas.width * thumbZoom(canvas),
            height: canvas.height * thumbZoom(canvas),
            imageRendering: "pixelated",
          }}
        />
      </div>
      <div className="asset-editor-redraw-thumb-label">{label}</div>
      <button
        className="asset-editor-redraw-thumb-delete"
        onClick={onDelete}
        disabled={disabled}
        title="Delete this redraw"
      >×</button>
    </div>
  );
}

function thumbZoom(canvas) {
  const longest = Math.max(canvas.width, canvas.height);
  if (longest <= 0) return 1;
  return Math.max(1, Math.min(8, Math.floor(96 / longest)));
}

function zoomFor(canvas, maxDim) {
  if (!canvas) return 1;
  const longest = Math.max(canvas.width, canvas.height);
  if (longest <= 0) return 1;
  return Math.max(1, Math.floor(maxDim / longest));
}

function makeDithered(img) {
  const can = document.createElement("canvas");
  can.width = img.naturalWidth;
  can.height = img.naturalHeight;
  const ctx = can.getContext("2d", { willReadFrequently: true });
  ctx.drawImage(img, 0, 0);
  applyOrderedDither(ctx, can.width, can.height);
  return can;
}

async function fetchMeta(asset) {
  if (asset.kind === "sprite") {
    const xmlUrl = `/undertale/objects/${asset.name}.object.gmx`;
    const doc = await (await import("../util/xml.js")).fetchXML(xmlUrl);
    const spriteName = doc.documentElement.getElementsByTagName("spriteName")[0]?.textContent;
    if (!spriteName || spriteName === "<undefined>") {
      throw new Error(`Object ${asset.name} has no sprite`);
    }
    const { parseSprite } = await import("../parser/sprite.js");
    const meta = await parseSprite(`/undertale/sprites/${spriteName}.sprite.gmx`);
    if (!meta.frames.length) throw new Error(`Sprite ${spriteName} has no frames`);
    const srcUrl = `/undertale/sprites/${meta.frames[0]}`;
    return {
      source: `${asset.name} → ${spriteName}`,
      srcUrl,
      note: `sprite frame 0`,
    };
  }
  const xmlUrl = `/undertale/background/${asset.name}.background.gmx`;
  const doc = await (await import("../util/xml.js")).fetchXML(xmlUrl);
  const data = (doc.documentElement.getElementsByTagName("data")[0]?.textContent || "").trim().replace(/\\/g, "/");
  if (!data) throw new Error(`Background ${asset.name} has no data`);
  return {
    source: asset.name,
    srcUrl: `/undertale/background/${data}`,
    note: null,
  };
}

async function loadRedrawnByLabel(asset, label) {
  const kind = asset.kind === "sprite" ? "sprites" : "backgrounds";
  const url = `/redrawn/${kind}/${asset.name}_${label}.png`;
  try {
    const res = await fetch(url);
    if (!res.ok) return null;
    const blob = await res.blob();
    // Use a blob URL — works in environments where a plain `new Image()`
    // would refuse to decode. Avoids the cache too.
    const blobUrl = URL.createObjectURL(blob);
    const img = await new Promise((resolve, reject) => {
      const i = new Image();
      i.onload = () => resolve(i);
      i.onerror = () => reject(new Error("decode failed"));
      i.src = blobUrl;
      setTimeout(() => reject(new Error("decode timeout")), 3000);
    });
    URL.revokeObjectURL(blobUrl);
    return img;
  } catch {
    return null;
  }
}

function downloadCanvas(canvasOrImg, filename) {
  const w = canvasOrImg.naturalWidth ?? canvasOrImg.width;
  const h = canvasOrImg.naturalHeight ?? canvasOrImg.height;
  if (!w || !h) {
    console.warn("downloadCanvas: empty image", filename);
    return;
  }
  const safeName = filename.endsWith(".png") ? filename : `${filename}.png`;
  const can = document.createElement("canvas");
  can.width = w;
  can.height = h;
  const ctx = can.getContext("2d");
  ctx.drawImage(canvasOrImg, 0, 0);
  const url = can.toDataURL("image/png");
  fetch("/api/download", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ data: url, filename: safeName }),
  })
    .then((r) => r.json())
    .then((out) => {
      if (!out.url) return;
      const a = document.createElement("a");
      a.href = out.url;
      a.download = out.filename;
      document.body.appendChild(a);
      a.click();
      a.remove();
    })
    .catch(() => {});
}

function sizedName(base, w, h, suffix) {
  const size = w && h ? `_${w}x${h}` : "";
  return `${base}${size}_${suffix}.png`;
}

function readFileAsDataURL(file) {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(r.result);
    r.onerror = () => reject(new Error("failed to read file"));
    r.readAsDataURL(file);
  });
}

async function imageDimensions(dataUrl) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve({ width: img.naturalWidth, height: img.naturalHeight });
    img.onerror = () => reject(new Error("could not read image dimensions"));
    img.src = dataUrl;
  });
}
