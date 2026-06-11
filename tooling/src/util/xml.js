export async function fetchXML(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Failed to fetch ${url}: ${res.status}`);
  const text = await res.text();
  const parser = new DOMParser();
  return parser.parseFromString(text, "text/xml");
}

export function firstText(el, tag) {
  const child = el.getElementsByTagName(tag)[0];
  return child ? child.textContent : null;
}

export function parseIntAttr(el, attr) {
  const v = el.getAttribute(attr);
  return v != null ? parseInt(v, 10) : 0;
}
