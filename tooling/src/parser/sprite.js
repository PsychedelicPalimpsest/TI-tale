import { fetchXML, firstText } from "../util/xml.js";

export async function parseSprite(file) {
  const doc = await fetchXML(file);
  const sprite = doc.documentElement;

  const width = parseInt(firstText(sprite, "width"), 10);
  const height = parseInt(firstText(sprite, "height"), 10);
  const xorig = parseInt(firstText(sprite, "xorig"), 10);
  const yorig = parseInt(firstText(sprite, "yorig"), 10);

  const frames = [];
  const framesEl = sprite.getElementsByTagName("frames")[0];
  if (framesEl) {
    for (const el of framesEl.querySelectorAll("frame")) {
      const rel = el.textContent.trim().replace(/\\/g, "/");
      frames.push(rel);
    }
  }

  return { width, height, xorig, yorig, frames };
}
