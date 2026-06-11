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
        const serveFile = (base, rel) => {
          const p = path.resolve(base, rel);
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
        next();
      });
    },
  };
}
