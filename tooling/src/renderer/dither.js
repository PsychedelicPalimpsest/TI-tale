const BAYER_4 = [
  [  0,  8,  2, 10 ],
  [ 12,  4, 14,  6 ],
  [  3, 11,  1,  9 ],
  [ 15,  7, 13,  5 ],
];

const LEVELS = [0x00, 0x55, 0xAA, 0xFF];
const THRESHOLDS = [0.167, 0.500, 0.833];

function luminance(r, g, b) {
  return 0.299 * r + 0.587 * g + 0.114 * b;
}

function ditherPixel(r, g, b, x, y) {
  if (r === 0 && g === 0 && b === 0) return 0x00;

  const lum = luminance(r, g, b);
  const bayer = (BAYER_4[y % 4][x % 4] + 0.5) / 16.0;
  const d = Math.max(0, Math.min(1,
    lum / 255.0 + (bayer - 0.5) * 0.3
  ));

  if (d >= THRESHOLDS[2]) return LEVELS[3];
  if (d >= THRESHOLDS[1]) return LEVELS[2];
  if (d >= THRESHOLDS[0]) return LEVELS[1];
  return LEVELS[0];
}

const ALPHA_THRESHOLD = 128;

function ditherPixelFromData(data, i, x, y) {
  const a = data[i + 3];
  if (a < ALPHA_THRESHOLD) {
    data[i] = 0;
    data[i + 1] = 0;
    data[i + 2] = 0;
    data[i + 3] = 0;
    return;
  }
  const val = ditherPixel(data[i], data[i + 1], data[i + 2], x, y);
  data[i] = val;
  data[i + 1] = val;
  data[i + 2] = val;
  data[i + 3] = 255;
}

export function applyOrderedDither(ctx, w, h) {
  const imageData = ctx.getImageData(0, 0, w, h);
  const data = imageData.data;

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 4;
      ditherPixelFromData(data, i, x, y);
    }
  }

  ctx.putImageData(imageData, 0, 0);
}

export function applyOrderedDitherToImageData(imageData) {
  const data = imageData.data;
  const w = imageData.width;
  const h = imageData.height;

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 4;
      ditherPixelFromData(data, i, x, y);
    }
  }
}
