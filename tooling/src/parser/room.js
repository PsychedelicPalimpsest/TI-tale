import { fetchXML, firstText } from "../util/xml.js";

export async function parseRoom(file) {
  const doc = await fetchXML(file);
  const room = doc.documentElement;

  const width = parseInt(firstText(room, "width"), 10);
  const height = parseInt(firstText(room, "height"), 10);

  const instances = [];
  const instancesEl = room.getElementsByTagName("instances")[0];
  if (instancesEl) {
    for (const el of instancesEl.querySelectorAll("instance")) {
      instances.push({
        objName: el.getAttribute("objName") || "",
        x: parseInt(el.getAttribute("x"), 10),
        y: parseInt(el.getAttribute("y"), 10),
        scaleX: parseFloat(el.getAttribute("scaleX")) || 1,
        scaleY: parseFloat(el.getAttribute("scaleY")) || 1,
        rotation: parseFloat(el.getAttribute("rotation")) || 0,
        colour: el.getAttribute("colour") || "4294967295",
        name: el.getAttribute("name") || "",
      });
    }
  }

  const tiles = [];
  const tilesEl = room.getElementsByTagName("tiles")[0];
  if (tilesEl) {
    for (const el of tilesEl.querySelectorAll("tile")) {
      tiles.push({
        bgName: el.getAttribute("bgName") || "",
        x: parseInt(el.getAttribute("x"), 10),
        y: parseInt(el.getAttribute("y"), 10),
        w: parseInt(el.getAttribute("w"), 10),
        h: parseInt(el.getAttribute("h"), 10),
        xo: parseInt(el.getAttribute("xo"), 10),
        yo: parseInt(el.getAttribute("yo"), 10),
        depth: parseInt(el.getAttribute("depth"), 10),
        scaleX: parseFloat(el.getAttribute("scaleX")) || 1,
        scaleY: parseFloat(el.getAttribute("scaleY")) || 1,
        colour: el.getAttribute("colour") || "4294967295",
        id: el.getAttribute("id") || "",
      });
    }
  }

  return { width, height, instances, tiles };
}
