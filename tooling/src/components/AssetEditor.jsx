import React, { useEffect, useRef, useState, useCallback } from "react";
import useStore from "../store/useStore";
import { applyOrderedDither } from "../renderer/dither.js";
import { loadImage } from "../renderer/room-canvas.js";

const KIND_LABEL = { sprite: "Sprite", background: "Background" };

export default function AssetEditor() {
  const { selectedAsset, closeAsset, redrawnSprites, redrawnBackgrounds, fetchRedrawn } = useStore();
  const [original, setOriginal] = useState(null);
  const [dithered, setDithered] = useState(null);
  const [redrawn, setRedrawn] = useState(null);
  const [originalMeta, setOriginalMeta] = useState(null);
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);
  const [uploading, setUploading] = useState(false);
  const fileInputRef = useRef(null);

  useEffect(() => {
    if (!selectedAsset) return;
    setError(null);
    setOriginal(null);
    setDithered(null);
    setRedrawn(null);
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
        const r = await loadRedrawnIfExists(selectedAsset);
        if (cancelled) return;
        setRedrawn(r);
      } catch (e) {
        if (!cancelled) setError(String(e.message || e));
      }
    })();

    return () => { cancelled = true; };
  }, [selectedAsset]);

  useEffect(() => {
    fetchRedrawn();
  }, [fetchRedrawn]);

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

  const onDownloadRedrawn = useCallback(() => {
    if (!redrawn) return;
    const w = redrawn.naturalWidth ?? redrawn.width;
    const h = redrawn.naturalHeight ?? redrawn.height;
    const name = sizedName(selectedAsset.name, w, h, "redrawn");
    downloadCanvas(redrawn, name);
  }, [redrawn, selectedAsset]);

  const onUploadClick = () => fileInputRef.current?.click();

  const onFileChange = useCallback(async (e) => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file || !selectedAsset) return;
    setUploading(true);
    setError(null);
    try {
      const dataUrl = await readFileAsDataURL(file);
      const res = await fetch("/api/redrawn-upload", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          kind: selectedAsset.kind === "sprite" ? "sprites" : "backgrounds",
          name: selectedAsset.name,
          data: dataUrl,
        }),
      });
      const out = await res.json();
      if (!res.ok) throw new Error(out.error || "upload failed");
      await fetchRedrawn();
      const fresh = await loadImage(`/redrawn/${out.path.split("/").slice(2).join("/")}?t=${Date.now()}`);
      setRedrawn(fresh);
    } catch (err) {
      setError(String(err.message || err));
    } finally {
      setUploading(false);
    }
  }, [selectedAsset, fetchRedrawn]);

  const onRemoveRedrawn = useCallback(async () => {
    if (!selectedAsset) return;
    setBusy(true);
    try {
      const res = await fetch("/api/redrawn-delete", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          kind: selectedAsset.kind === "sprite" ? "sprites" : "backgrounds",
          name: selectedAsset.name,
        }),
      });
      const out = await res.json();
      if (!res.ok) throw new Error(out.error || "delete failed");
      await fetchRedrawn();
      setRedrawn(null);
    } catch (err) {
      setError(String(err.message || err));
    } finally {
      setBusy(false);
    }
  }, [selectedAsset, fetchRedrawn]);

  if (!selectedAsset) return null;

  const hasRedrawn = redrawn != null;
  const targetW = dithered?.width || 0;
  const targetH = dithered?.height || 0;

  return (
    <div className="asset-editor">
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
            {hasRedrawn ? (
              <Frame label="Your redraw" canvas={redrawn} scale={zoomFor(redrawn, 220)} />
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
            {hasRedrawn && (
              <button onClick={onDownloadRedrawn} disabled={busy} title="Download your current redraw">
                Download redraw
              </button>
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
              {uploading ? "Uploading…" : hasRedrawn ? "Replace redraw" : "Upload redraw"}
            </button>
            {hasRedrawn && (
              <button onClick={onRemoveRedrawn} disabled={busy} className="asset-editor-remove">
                Remove
              </button>
            )}
            <span className="asset-editor-hint">PNG, {targetW}×{targetH} recommended</span>
          </div>
        </>
      )}
    </div>
  );
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

async function loadRedrawnIfExists(asset) {
  const kind = asset.kind === "sprite" ? "sprites" : "backgrounds";
  const url = `/redrawn/${kind}/${asset.name}.png`;
  try {
    const res = await fetch(url, { method: "HEAD" });
    if (!res.ok) return null;
    return await loadImage(`${url}?t=${Date.now()}`);
  } catch {
    return null;
  }
}

function downloadCanvas(canvasOrImg, filename) {
  // Always rasterize to a canvas, then download as a self-contained PNG data URL.
  // Using the asset URL directly would download whatever the server serves
  // (could be an HTML fallback page if the file is missing) and wouldn't be
  // a portable PNG the user could open in any image editor.
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
  const a = document.createElement("a");
  a.href = url;
  a.download = safeName;
  document.body.appendChild(a);
  a.click();
  a.remove();
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
