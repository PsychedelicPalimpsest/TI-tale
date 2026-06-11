import { GRID_SIZE } from "../parser/types.js";
import { applyOrderedDither } from "./dither.js";

const IMG_CACHE = new Map();
const DITHER_CACHE = new Map();

export function loadImage(url) {
  if (IMG_CACHE.has(url)) return IMG_CACHE.get(url);
  const promise = new Promise((resolve, reject) => {
    const img = new Image();
    let settled = false;
    const finish = (err, val) => {
      if (settled) return;
      settled = true;
      if (err) reject(err);
      else {
        IMG_CACHE.set(url, val);
        resolve(val);
      }
    };
    img.onload = () => finish(null, img);
    img.onerror = () => { /* fallback will run */ };
    img.src = url;
    // Fallback: try createImageBitmap if the Image element fails to fire onload.
    setTimeout(async () => {
      if (settled) return;
      try {
        const res = await fetch(url);
        if (!res.ok) return;
        const blob = await res.blob();
        const bitmap = await createImageBitmap(blob);
        if (settled) return;
        const wrapped = {
          naturalWidth: bitmap.width,
          naturalHeight: bitmap.height,
          width: bitmap.width,
          height: bitmap.height,
          _bitmap: bitmap,
        };
        finish(null, wrapped);
      } catch {
        finish(new Error(`Failed to load ${url}`));
      }
    }, 300);
  });
  IMG_CACHE.set(url, promise);
  return promise;
}

export function clearCache() {
  IMG_CACHE.clear();
  DITHER_CACHE.clear();
}

function colourToRGB(hexOrNum) {
  if (!hexOrNum) return { r: 255, g: 255, b: 255, a: 1 };
  let n = parseInt(hexOrNum, 10);
  if (isNaN(n)) n = 4294967295;
  const b = n & 0xff;
  const g = (n >> 8) & 0xff;
  const r = (n >> 16) & 0xff;
  const a = ((n >> 24) & 0xff) / 255;
  return { r, g, b, a };
}

function undertaleUrl(rel) {
  return `/undertale/${rel}`;
}

async function getBgImage(bgName, bgCache) {
  if (bgCache.has(bgName)) return bgCache.get(bgName);
  const xmlUrl = undertaleUrl(`background/${bgName}.background.gmx`);
  try {
    const { parseBackground } = await import("../parser/background.js");
    const meta = await parseBackground(xmlUrl);
    const imgUrl = undertaleUrl(`background/${meta.data}`);
    const img = await loadImage(imgUrl);
    bgCache.set(bgName, img);
    return img;
  } catch {
    bgCache.set(bgName, null);
    return null;
  }
}

async function getObjSprite(objName, objSpriteCache) {
  if (objSpriteCache.has(objName)) return objSpriteCache.get(objName);
  try {
    const xmlUrl = undertaleUrl(`objects/${objName}.object.gmx`);
    const doc = await (await import("../util/xml.js")).fetchXML(xmlUrl);
    const el = doc.documentElement;
    const spriteName = el.getElementsByTagName("spriteName")[0]?.textContent;
    if (!spriteName || spriteName === "<undefined>") {
      objSpriteCache.set(objName, null);
      return null;
    }
    const { parseSprite } = await import("../parser/sprite.js");
    const spriteXml = undertaleUrl(`sprites/${spriteName}.sprite.gmx`);
    const spriteMeta = await parseSprite(spriteXml);
    if (spriteMeta.frames.length === 0) {
      objSpriteCache.set(objName, null);
      return null;
    }
    const imgUrl = undertaleUrl(`sprites/${spriteMeta.frames[0]}`);
    const img = await loadImage(imgUrl);
    const result = { img, ...spriteMeta };
    objSpriteCache.set(objName, result);
    return result;
  } catch {
    objSpriteCache.set(objName, null);
    return null;
  }
}

function ditherKey(img, sx, sy, sw, sh, tw, th) {
  return `${img.src}|${sx}|${sy}|${sw}|${sh}|${tw}|${th}`;
}

function makeTile(img, sx, sy, sw, sh, tw, th) {
  tw = Math.max(1, Math.round(tw));
  th = Math.max(1, Math.round(th));

  const key = ditherKey(img, sx, sy, sw, sh, tw, th);
  const hit = DITHER_CACHE.get(key);
  if (hit) return hit;

  const can = document.createElement("canvas");
  can.width = tw;
  can.height = th;
  const c = can.getContext("2d");
  c.imageSmoothingEnabled = false;
  c.drawImage(img, sx, sy, sw, sh, 0, 0, tw, th);
  applyOrderedDither(c, tw, th);
  DITHER_CACHE.set(key, can);
  return can;
}

function drawTile(ctx, img, tile, scale, autoGen, tiSW, tiSH) {
  const dx = tile.x * scale;
  const dy = tile.y * scale;
  const dw = tile.w * scale;
  const dh = tile.h * scale;

  if (autoGen) {
    const tw = Math.max(1, Math.round(tile.w * tiSW));
    const th = Math.max(1, Math.round(tile.h * tiSH));
    const dithered = makeTile(img, tile.xo, tile.yo, tile.w, tile.h, tw, th);
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(dithered, 0, 0, tw, th, dx, dy, dw, dh);
    ctx.imageSmoothingEnabled = true;
    return;
  }

  const col = colourToRGB(tile.colour);
  if (col.a < 1 || col.r !== 255 || col.g !== 255 || col.b !== 255) {
    ctx.globalAlpha = col.a;
    const tmp = document.createElement("canvas");
    tmp.width = tile.w;
    tmp.height = tile.h;
    const tctx = tmp.getContext("2d");
    tctx.drawImage(img, tile.xo, tile.yo, tile.w, tile.h, 0, 0, tile.w, tile.h);
    tctx.globalCompositeOperation = "source-atop";
    tctx.fillStyle = `rgb(${col.r},${col.g},${col.b})`;
    tctx.fillRect(0, 0, tile.w, tile.h);
    ctx.drawImage(tmp, 0, 0, tile.w, tile.h, dx, dy, dw, dh);
    ctx.globalAlpha = 1;
  } else {
    ctx.drawImage(img, tile.xo, tile.yo, tile.w, tile.h, dx, dy, dw, dh);
  }
}

function drawInstance(ctx, spr, inst, scale, autoGen, tiSW, tiSH) {
  const dx = (inst.x - spr.xorig) * scale;
  const dy = (inst.y - spr.yorig) * scale;
  const dw = spr.width * scale;
  const dh = spr.height * scale;

  if (autoGen) {
    const tw = Math.max(1, Math.round(spr.width * tiSW));
    const th = Math.max(1, Math.round(spr.height * tiSH));
    const dithered = makeTile(spr.img, 0, 0, spr.width, spr.height, tw, th);
    ctx.imageSmoothingEnabled = false;
    if (inst.rotation === 0 && inst.scaleX === 1 && inst.scaleY === 1) {
      ctx.drawImage(dithered, 0, 0, dw, dh, dx, dy, dw, dh);
    } else {
      ctx.save();
      ctx.translate(inst.x * scale, inst.y * scale);
      ctx.rotate((inst.rotation * Math.PI) / 180);
      ctx.scale(inst.scaleX, inst.scaleY);
      ctx.drawImage(dithered, 0, 0, dw, dh, -spr.xorig * scale, -spr.yorig * scale, dw, dh);
      ctx.restore();
    }
    ctx.imageSmoothingEnabled = true;
    return;
  }

  if (inst.rotation === 0 && inst.scaleX === 1 && inst.scaleY === 1) {
    ctx.drawImage(spr.img, dx, dy, dw, dh);
  } else {
    ctx.save();
    ctx.translate(inst.x * scale, inst.y * scale);
    ctx.rotate((inst.rotation * Math.PI) / 180);
    ctx.scale(inst.scaleX, inst.scaleY);
    ctx.drawImage(spr.img, -spr.xorig * scale, -spr.yorig * scale, dw, dh);
    ctx.restore();
  }
}

export async function renderRoom(ctx, roomData, opts = {}) {
  const { scale = 1, showTiles = true, showInstances = true, autoGen = false, tiSW = 1, tiSH = 1 } = opts;
  const { width, height, tiles, instances } = roomData;

  ctx.canvas.width = width * scale;
  ctx.canvas.height = height * scale;
  ctx.fillStyle = "#000000";
  ctx.fillRect(0, 0, ctx.canvas.width, ctx.canvas.height);

  const bgCache = new Map();

  if (showTiles && tiles.length > 0) {
    const sortedTiles = [...tiles].sort((a, b) => (b.depth || 0) - (a.depth || 0));
    const byBg = {};
    for (const t of sortedTiles) {
      if (!byBg[t.bgName]) byBg[t.bgName] = [];
      byBg[t.bgName].push(t);
    }
    const bgNames = Object.keys(byBg);
    const bgResults = await Promise.all(
      bgNames.map(async (name) => ({ name, img: await getBgImage(name, bgCache) }))
    );
    for (const { name, img } of bgResults) {
      if (!img) continue;
      for (const t of byBg[name]) {
        drawTile(ctx, img, t, scale, autoGen, tiSW, tiSH);
      }
    }
  }

  if (showInstances && instances.length > 0) {
    const objSpriteCache = new Map();
    const uniqueObjs = [...new Set(instances.map(i => i.objName))];
    const spriteResults = await Promise.all(
      uniqueObjs.map(async (name) => ({ name, data: await getObjSprite(name, objSpriteCache) }))
    );
    const spriteLookup = {};
    for (const { name, data } of spriteResults) spriteLookup[name] = data;
    for (const inst of instances) {
      const spr = spriteLookup[inst.objName];
      if (!spr || !spr.width || !spr.height) continue;
      drawInstance(ctx, spr, inst, scale, autoGen, tiSW, tiSH);
    }
  }
}

export async function renderViewportRegion(ctx, roomData, opts = {}) {
  const {
    vx = 0, vy = 0,
    vw = 96, vh = 64,
    showTiles = true,
    showInstances = true,
  } = opts;
  const { tiles, instances } = roomData;
  const OUT_W = 96;
  const OUT_H = 64;

  ctx.canvas.width = OUT_W;
  ctx.canvas.height = OUT_H;
  ctx.fillStyle = "#000000";
  ctx.fillRect(0, 0, OUT_W, OUT_H);

  const sx = OUT_W / vw;
  const sy = OUT_H / vh;
  const bgCache = new Map();

  if (showTiles && tiles.length > 0) {
    const sortedTiles = [...tiles].sort((a, b) => (b.depth || 0) - (a.depth || 0));
    const byBg = {};
    for (const t of sortedTiles) {
      if (!byBg[t.bgName]) byBg[t.bgName] = [];
      byBg[t.bgName].push(t);
    }

    const bgNames = Object.keys(byBg);
    const bgResults = await Promise.all(
      bgNames.map(async (name) => ({ name, img: await getBgImage(name, bgCache) }))
    );

    for (const { name, img } of bgResults) {
      if (!img) continue;
      for (const t of byBg[name]) {
        if (t.x + t.w <= vx || t.y + t.h <= vy || t.x >= vx + vw || t.y >= vy + vh) continue;

        const dx = Math.round((t.x - vx) * sx);
        const dy = Math.round((t.y - vy) * sy);
        const right = Math.round((t.x + t.w - vx) * sx);
        const bottom = Math.round((t.y + t.h - vy) * sy);
        const dw = Math.max(1, right - dx);
        const dh = Math.max(1, bottom - dy);
        if (dw <= 0 || dh <= 0) continue;

        const tile = makeTile(img, t.xo, t.yo, t.w, t.h, dw, dh);
        ctx.drawImage(tile, 0, 0, dw, dh, dx, dy, dw, dh);
      }
    }
  }

  if (showInstances && instances.length > 0) {
    const objSpriteCache = new Map();
    const uniqueObjs = [...new Set(instances.map(i => i.objName))];
    const spriteResults = await Promise.all(
      uniqueObjs.map(async (name) => ({ name, data: await getObjSprite(name, objSpriteCache) }))
    );
    const spriteLookup = {};
    for (const { name, data } of spriteResults) spriteLookup[name] = data;

    for (const inst of instances) {
      const spr = spriteLookup[inst.objName];
      if (!spr || !spr.width || !spr.height) continue;

      const ix = inst.x - (spr.xorig || 0);
      const iy = inst.y - (spr.yorig || 0);
      if (ix + spr.width <= vx || iy + spr.height <= vy || ix >= vx + vw || iy >= vy + vh) continue;

      const dx = Math.round((ix - vx) * sx);
      const dy = Math.round((iy - vy) * sy);
      const right = Math.round((ix + spr.width - vx) * sx);
      const bottom = Math.round((iy + spr.height - vy) * sy);
      const dw = Math.max(1, right - dx);
      const dh = Math.max(1, bottom - dy);
      if (dw <= 0 || dh <= 0) continue;

      const tile = makeTile(spr.img, 0, 0, spr.width, spr.height, dw, dh);
      ctx.drawImage(tile, 0, 0, dw, dh, dx, dy, dw, dh);
    }
  }
}

export function drawGrid(ctx, scale, roomW, roomH) {
  ctx.save();
  ctx.strokeStyle = "rgba(128, 128, 128, 0.15)";
  ctx.lineWidth = 0.5;
  const gs = GRID_SIZE * scale;
  for (let x = 0; x <= roomW * scale; x += gs) {
    ctx.beginPath();
    ctx.moveTo(x, 0);
    ctx.lineTo(x, roomH * scale);
    ctx.stroke();
  }
  for (let y = 0; y <= roomH * scale; y += gs) {
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(roomW * scale, y);
    ctx.stroke();
  }
  ctx.restore();
}

export function drawViewport(ctx, vx, vy, vw, vh, scale) {
  ctx.save();
  ctx.strokeStyle = "#00ff00";
  ctx.lineWidth = 2;
  ctx.strokeRect(vx * scale, vy * scale, vw * scale, vh * scale);

  const dashLen = 4;
  ctx.beginPath();
  ctx.setLineDash([dashLen, dashLen]);
  ctx.strokeStyle = "rgba(0, 255, 0, 0.3)";
  ctx.strokeRect(vx * scale - 1, vy * scale - 1, vw * scale + 2, vh * scale + 2);
  ctx.setLineDash([]);
  ctx.restore();
}
