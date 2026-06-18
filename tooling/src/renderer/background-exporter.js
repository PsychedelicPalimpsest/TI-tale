import { loadImage } from "./room-canvas.js";

const LEVELS = [0x00, 0x55, 0xAA, 0xFF];

const LEVEL_TO_BITS = [
  [1, 1], // LEVEL 0 (0x00) → Black on TI-84
  [0, 1], // LEVEL 1 (0x55) → Dark grey on TI-84
  [1, 0], // LEVEL 2 (0xAA) → Light grey on TI-84
  [0, 0], // LEVEL 3 (0xFF) → White on TI-84
];

const BG_COLOURS = [
  "#000000", // 0 = white  (LEVEL 0 on canvas = black, maps to TI white on export)
  "#555555", // 1 = lt grey
  "#AAAAAA", // 2 = dk grey
  "#FFFFFF", // 3 = black  (LEVEL 3 on canvas = white, maps to TI black on export)
];

function quantizeToLevel(r) {
  if (r < 42) return 0;
  if (r < 128) return 1;
  if (r < 213) return 2;
  return 3;
}

function undertaleUrl(rel) {
  return `/undertale/${rel}`;
}

async function loadRedrawnImages(entries, kind) {
  if (!entries || entries.length === 0) return {};
  const byName = {};
  for (const e of entries) {
    if (!byName[e.name]) byName[e.name] = e.label;
  }
  const results = await Promise.all(
    Object.entries(byName).map(async ([name, label]) => {
      const url = `/redrawn/${kind}/${name}_${label}.png`;
      try {
        const head = await fetch(url, { method: "HEAD" });
        if (!head.ok) return [name, null];
        const img = await loadImage(`${url}?t=${Date.now()}-${Math.random()}`);
        return [name, img];
      } catch {
        return [name, null];
      }
    })
  );
  const out = {};
  for (const [name, img] of results) if (img) out[name] = img;
  return out;
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
    const { fetchXML } = await import("../util/xml.js");
    const doc = await fetchXML(xmlUrl);
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

export async function renderRoomForExport(roomData, opts = {}) {
  const {
    viewportScale = 1,
    defaultBgLevel = 0,
    includeTiles = true,
    instanceToggles = {},
    redrawnBackgrounds = [],
    redrawnSprites = [],
  } = opts;

  const { width, height, tiles, instances } = roomData;
  const scale = viewportScale;
  const canvasW = Math.round(width * scale);
  const canvasH = Math.round(height * scale);

  const canvas = document.createElement("canvas");
  canvas.width = canvasW;
  canvas.height = canvasH;
  const ctx = canvas.getContext("2d");
  ctx.imageSmoothingEnabled = false;

  ctx.fillStyle = BG_COLOURS[defaultBgLevel];
  ctx.fillRect(0, 0, canvasW, canvasH);

  const redrawnBgImgs = await loadRedrawnImages(redrawnBackgrounds, "backgrounds");
  const redrawnSprImgs = await loadRedrawnImages(redrawnSprites, "sprites");

  if (includeTiles && tiles.length > 0) {
    const sortedTiles = [...tiles].sort((a, b) => (b.depth || 0) - (a.depth || 0));
    const byBg = {};
    for (const t of sortedTiles) {
      if (!redrawnBgImgs[t.bgName]) continue;
      if (!byBg[t.bgName]) byBg[t.bgName] = [];
      byBg[t.bgName].push(t);
    }
    for (const [name, img] of Object.entries(redrawnBgImgs)) {
      const tileList = byBg[name];
      if (!tileList) continue;
      for (const t of tileList) {
        const dx = t.x * scale;
        const dy = t.y * scale;
        const dw = t.w * scale;
        const dh = t.h * scale;
        ctx.drawImage(img, t.xo, t.yo, t.w, t.h, dx, dy, dw, dh);
      }
    }
  }

  if (instances.length > 0) {
    const objSpriteCache = new Map();
    const uniqueObjs = [...new Set(instances.map((i) => i.objName))];

    const spriteResults = await Promise.all(
      uniqueObjs.map(async (name) => {
        const toggled = instanceToggles[name] !== false;
        if (!toggled || !redrawnSprImgs[name]) return { name, data: null };
        const orig = await getObjSprite(name, objSpriteCache);
        if (!orig) return { name, data: null };
        return { name, data: { ...orig, img: redrawnSprImgs[name] } };
      })
    );

    const spriteLookup = {};
    for (const { name, data } of spriteResults) spriteLookup[name] = data;

    for (const inst of instances) {
      const spr = spriteLookup[inst.objName];
      if (!spr || !spr.width || !spr.height) continue;

      const dx = (inst.x - spr.xorig) * scale;
      const dy = (inst.y - spr.yorig) * scale;
      const dw = spr.width * scale;
      const dh = spr.height * scale;

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
  }

  return canvas;
}

export function canvasToBin(canvas, defaultBgLevel) {
  const ctx = canvas.getContext("2d");
  const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
  const data = imageData.data;
  const w = canvas.width;
  const h = canvas.height;

  const widthInBytes = Math.ceil(w / 8);
  const headerSize = 4;
  const bodySize = h * widthInBytes * 2;
  const buf = new ArrayBuffer(headerSize + bodySize);
  const view = new DataView(buf);
  const bytes = new Uint8Array(buf);

  view.setUint16(0, widthInBytes, true);
  view.setUint16(2, h, true);

  let offset = headerSize;

  for (let y = 0; y < h; y++) {
    const rowLight = new Uint8Array(widthInBytes);
    const rowDark = new Uint8Array(widthInBytes);

    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 4;
      const r = data[i];
      const a = data[i + 3];

      let level;
      if (a < 128) {
        level = defaultBgLevel;
      } else {
        level = quantizeToLevel(r);
      }

      const [lightBit, darkBit] = LEVEL_TO_BITS[level];
      const byteIdx = Math.floor(x / 8);
      const bitIdx = 7 - (x % 8);

      if (lightBit) rowLight[byteIdx] |= (1 << bitIdx);
      if (darkBit) rowDark[byteIdx] |= (1 << bitIdx);
    }

    for (let b = 0; b < widthInBytes; b++) {
      bytes[offset++] = rowLight[b];
      bytes[offset++] = rowDark[b];
    }
  }

  return buf;
}

export async function buildBgBin(roomData, opts = {}) {
  const canvas = await renderRoomForExport(roomData, opts);
  return canvasToBin(canvas, opts.defaultBgLevel ?? 0);
}
