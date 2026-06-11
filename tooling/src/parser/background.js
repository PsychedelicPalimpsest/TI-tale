import { fetchXML, firstText } from "../util/xml.js";

export async function parseBackground(file) {
  const doc = await fetchXML(file);
  const bg = doc.documentElement;

  const istileset = firstText(bg, "istileset") === "-1";
  const tilewidth = parseInt(firstText(bg, "tilewidth"), 10);
  const tileheight = parseInt(firstText(bg, "tileheight"), 10);
  const tilexoff = parseInt(firstText(bg, "tilexoff"), 10);
  const tileyoff = parseInt(firstText(bg, "tileyoff"), 10);
  const tilehsep = parseInt(firstText(bg, "tilehsep"), 10);
  const tilevsep = parseInt(firstText(bg, "tilevsep"), 10);
  const imgWidth = parseInt(firstText(bg, "width"), 10);
  const imgHeight = parseInt(firstText(bg, "height"), 10);
  const data = (firstText(bg, "data") || "").trim().replace(/\\/g, "/");

  return { istileset, tilewidth, tileheight, tilexoff, tileyoff, tilehsep, tilevsep, imgWidth, imgHeight, data };
}
