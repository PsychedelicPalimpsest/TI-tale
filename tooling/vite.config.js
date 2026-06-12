import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import fs from "fs";
import path from "path";

const ENV_FILE = path.resolve("../.env");
let undertaleRoot = "";

try {
  const raw = fs.readFileSync(ENV_FILE, "utf-8");
  const m = raw.match(/^UNDERTALE="(.+)"$/m);
  if (m) undertaleRoot = m[1];
} catch {}

export default defineConfig({
  plugins: [react(), serveRawAssets()],
  server: {
    port: 5173,
  },
});

function serveRawAssets() {
  const redrawnRoot = path.resolve("app/assets/redrawn");

  return {
    name: "serve-raw-assets",
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        const stripQuery = (s) => {
          const i = s.indexOf("?");
          return i === -1 ? s : s.slice(0, i);
        };

        const serveFile = (base, rel) => {
          const p = path.resolve(base, stripQuery(rel));
          if (!p.startsWith(base)) return false;
          try {
            const buf = fs.readFileSync(p);
            const ext = path.extname(p).toLowerCase();
            const types = {
              ".png": "image/png",
              ".xml": "application/xml",
              ".gmx": "application/xml",
              ".gml": "text/plain",
              ".ogg": "audio/ogg",
              ".wav": "audio/wav",
              ".mp3": "audio/mpeg",
              ".json": "application/json",
            };
            res.setHeader("Content-Type", types[ext] || "application/octet-stream");
            res.setHeader("Cache-Control", "no-store");
            res.end(buf);
            return true;
          } catch {
            return false;
          }
        };

        if (req.url.startsWith("/undertale/") && undertaleRoot) {
          const rel = req.url.slice("/undertale/".length);
          if (serveFile(undertaleRoot, rel)) return;
        }
        if (req.url.startsWith("/redrawn/")) {
          const rel = req.url.slice("/redrawn/".length);
          if (serveFile(redrawnRoot, rel)) return;
        }
        if (req.url === "/api/room-list" && undertaleRoot) {
          try {
            const roomsDir = path.join(undertaleRoot, "rooms");
            const files = fs.readdirSync(roomsDir).filter(f => f.endsWith(".room.gmx"));
            res.setHeader("Content-Type", "application/json");
            res.end(JSON.stringify(files));
            return;
          } catch {
            res.statusCode = 500;
            res.end("[]");
            return;
          }
        }

        if (req.url === "/api/redrawn-list") {
          try {
            // Each redraw file is named `<name>_<label>.png` where label is
            // either a `<W>x<H>` size string or a custom user string.
            // The base name (the first `_`-delimited token) is the asset name.
            const list = (dir) => {
              if (!fs.existsSync(dir)) return [];
              return fs.readdirSync(dir, { withFileTypes: true })
                .filter(d => d.isFile() && d.name.toLowerCase().endsWith(".png"))
                .map(d => d.name.replace(/\.png$/i, ""))
                .map((base) => {
                  const usi = base.lastIndexOf("_");
                  if (usi < 1) return { name: base, label: "original" };
                  return { name: base.slice(0, usi), label: base.slice(usi + 1) };
                });
            };
            res.setHeader("Content-Type", "application/json");
            res.end(JSON.stringify({
              sprites: list(path.join(redrawnRoot, "sprites")),
              backgrounds: list(path.join(redrawnRoot, "backgrounds")),
            }));
            return;
          } catch (e) {
            res.statusCode = 500;
            res.setHeader("Content-Type", "application/json");
            res.end(JSON.stringify({ error: String(e) }));
            return;
          }
        }

        if (req.url === "/api/redrawn-upload" && req.method === "POST") {
          let body = "";
          req.on("data", (chunk) => { body += chunk; });
          req.on("end", () => {
            try {
              const { kind, name, label, data } = JSON.parse(body);
              if (!["sprites", "backgrounds"].includes(kind)) throw new Error("invalid kind");
              if (!/^[A-Za-z0-9_\-]+$/.test(name)) throw new Error("invalid name");
              const safeLabel = String(label || "1x").replace(/[^A-Za-z0-9_\-]/g, "_").slice(0, 64) || "1x";
              const m = /^data:image\/png;base64,(.+)$/.exec(data || "");
              if (!m) throw new Error("expected data URL of PNG");
              const buf = Buffer.from(m[1], "base64");
              const dest = path.join(redrawnRoot, kind, `${name}_${safeLabel}.png`);
              fs.mkdirSync(path.dirname(dest), { recursive: true });
              fs.writeFileSync(dest, buf);
              res.setHeader("Content-Type", "application/json");
              res.end(JSON.stringify({ ok: true, path: `/redrawn/${kind}/${name}_${safeLabel}.png`, label: safeLabel }));
            } catch (e) {
              res.statusCode = 400;
              res.setHeader("Content-Type", "application/json");
              res.end(JSON.stringify({ error: String(e.message || e) }));
            }
          });
          return;
        }

        if (req.url === "/api/redrawn-delete" && req.method === "POST") {
          let body = "";
          req.on("data", (chunk) => { body += chunk; });
          req.on("end", () => {
            try {
              const { kind, name, label } = JSON.parse(body);
              if (!["sprites", "backgrounds"].includes(kind)) throw new Error("invalid kind");
              if (!/^[A-Za-z0-9_\-]+$/.test(name)) throw new Error("invalid name");
              const safeLabel = String(label || "").replace(/[^A-Za-z0-9_\-]/g, "_").slice(0, 64);
              if (!safeLabel) throw new Error("label required");
              const dest = path.join(redrawnRoot, kind, `${name}_${safeLabel}.png`);
              if (fs.existsSync(dest)) fs.unlinkSync(dest);
              res.setHeader("Content-Type", "application/json");
              res.end(JSON.stringify({ ok: true }));
            } catch (e) {
              res.statusCode = 400;
              res.setHeader("Content-Type", "application/json");
              res.end(JSON.stringify({ error: String(e.message || e) }));
            }
          });
          return;
        }

        next();
      });
    },
  };
}
