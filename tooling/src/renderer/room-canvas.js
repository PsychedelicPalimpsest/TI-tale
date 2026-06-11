import { GRID_SIZE } from "../parser/types.js";

const IMG_CACHE = new Map();

export function loadImage(url) {
  if (IMG_CACHE.has(url)) return IMG_CACHE.get(url);
  const img = new Image();
  img.crossOrigin = "anonymous";
  const promise = new Promise((resolve, reject) => {
    img.onload = () => {
      IMG_CACHE.set(url, img);
      resolve(img);
    };
    img.onerror = () => reject(new Error(`Failed to load ${url}`));
    img.src = url;
  });
  IMG_CACHE.set(url, promise);
  return promise;
}

export function clearCache() {
  IMG_CACHE.clear();
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

function drawTile(ctx, img, tile, scale, offsetX, offsetY) {
  const sx = tile.xo;
  const sy = tile.yo;
  const sw = tile.w;
  const sh = tile.h;
  const dx = (tile.x + offsetX) * scale;
  const dy = (tile.y + offsetY) * scale;
  const dw = sw * scale;
  const dh = sh * scale;

  const col = colourToRGB(tile.colour);
  if (col.a < 1 || col.r !== 255 || col.g !== 255 || col.b !== 255) {
    ctx.globalAlpha = col.a;
    const tmp = document.createElement("canvas");
    tmp.width = sw;
    tmp.height = sh;
    const tctx = tmp.getContext("2d");
    tctx.drawImage(img, sx, sy, sw, sh, 0, 0, sw, sh);
    tctx.globalCompositeOperation = "source-atop";
    tctx.fillStyle = `rgb(${col.r},${col.g},${col.b})`;
    tctx.fillRect(0, 0, sw, sh);
    ctx.drawImage(tmp, 0, 0, sw, sh, dx, dy, dw, dh);
    ctx.globalAlpha = 1;
  } else {
    ctx.drawImage(img, sx, sy, sw, sh, dx, dy, dw, dh);
  }
}

function drawInstance(ctx, spr, inst, scale, offsetX, offsetY) {
  const dx = (inst.x - spr.xorig + offsetX) * scale;
  const dy = (inst.y - spr.yorig + offsetY) * scale;
  const dw = spr.width * scale;
  const dh = spr.height * scale;

  if (inst.rotation === 0 && inst.scaleX === 1 && inst.scaleY === 1) {
    ctx.drawImage(spr.img, dx, dy, dw, dh);
  } else {
    ctx.save();
    const cx = (inst.x + offsetX) * scale;
    const cy = (inst.y + offsetY) * scale;
    ctx.translate(cx, cy);
    ctx.rotate((inst.rotation * Math.PI) / 180);
    ctx.scale(inst.scaleX, inst.scaleY);
    ctx.drawImage(spr.img, -spr.xorig * scale, -spr.yorig * scale, dw, dh);
    ctx.restore();
  }
}

export async function renderRoom(ctx, roomData, opts = {}) {
  const {
    offsetX = 0,
    offsetY = 0,
    scale = 1,
    showTiles = true,
    showInstances = true,
  } = opts;

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
        drawTile(ctx, img, t, scale, offsetX, offsetY);
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
    for (const { name, data } of spriteResults) {
      spriteLookup[name] = data;
    }

    for (const inst of instances) {
      const spr = spriteLookup[inst.objName];
      if (!spr) continue;
      drawInstance(ctx, spr, inst, scale, offsetX, offsetY);
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

  ctx.canvas.width = vw;
  ctx.canvas.height = vh;
  ctx.fillStyle = "#000000";
  ctx.fillRect(0, 0, vw, vh);

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

        let sx = t.xo;
        let sy = t.yo;
        let sw = t.w;
        let sh = t.h;
        let dx = t.x - vx;
        let dy = t.y - vy;

        if (dx < 0) { const c = -dx; sx += c; sw -= c; dx = 0; }
        if (dy < 0) { const c = -dy; sy += c; sh -= c; dy = 0; }
        if (dx + sw > vw) sw = vw - dx;
        if (dy + sh > vh) sh = vh - dy;
        if (sw <= 0 || sh <= 0) continue;

        ctx.drawImage(img, sx, sy, sw, sh, dx, dy, sw, sh);
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
    for (const { name, data } of spriteResults) {
      spriteLookup[name] = data;
    }

    for (const inst of instances) {
      const spr = spriteLookup[inst.objName];
      if (!spr) continue;

      const ix = inst.x - spr.xorig;
      const iy = inst.y - spr.yorig;
      if (ix + spr.width <= vx || iy + spr.height <= vy || ix >= vx + vw || iy >= vy + vh) continue;

      let sx = 0;
      let sy = 0;
      let sw = spr.width;
      let sh = spr.height;
      let dx = ix - vx;
      let dy = iy - vy;

      if (dx < 0) { const c = -dx; sx += c; sw -= c; dx = 0; }
      if (dy < 0) { const c = -dy; sy += c; sh -= c; dy = 0; }
      if (dx + sw > vw) sw = vw - dx;
      if (dy + sh > vh) sh = vh - dy;
      if (sw <= 0 || sh <= 0) continue;

      ctx.drawImage(spr.img, sx, sy, sw, sh, dx, dy, sw, sh);
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
