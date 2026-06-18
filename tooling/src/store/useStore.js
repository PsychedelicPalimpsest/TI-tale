import { create } from "zustand";
import {
  TI84_W,
  TI84_H,
  PREVIEW_ZOOM_DEFAULT,
  PREVIEW_ZOOM_MIN,
  PREVIEW_ZOOM_MAX,
} from "../parser/types.js";

const VIEWPORT_SCALE_MIN = 0.25;
const VIEWPORT_SCALE_MAX = 8;
const PREVIEW_ZOOM_STORAGE_KEY = "titale.previewZoom";

function readStoredPreviewZoom() {
  try {
    if (typeof localStorage === "undefined") return PREVIEW_ZOOM_DEFAULT;
    const raw = localStorage.getItem(PREVIEW_ZOOM_STORAGE_KEY);
    if (raw == null) return PREVIEW_ZOOM_DEFAULT;
    const n = parseFloat(raw);
    if (!Number.isFinite(n)) return PREVIEW_ZOOM_DEFAULT;
    return Math.max(PREVIEW_ZOOM_MIN, Math.min(PREVIEW_ZOOM_MAX, n));
  } catch (e) {
    console.warn("Could not read previewZoom from localStorage", e);
    return PREVIEW_ZOOM_DEFAULT;
  }
}

function writeStoredPreviewZoom(z) {
  try {
    if (typeof localStorage === "undefined") return;
    localStorage.setItem(PREVIEW_ZOOM_STORAGE_KEY, String(z));
  } catch (e) {
    console.warn("Could not persist previewZoom to localStorage", e);
  }
}

const store = create((set, get) => ({
  roomFile: "",
  roomData: null,
  loading: false,
  rendering: false,
  error: null,

  scale: 1,
  viewportX: 0,
  viewportY: 0,
  viewportScale: 1,
  showGrid: false,
  showViewport: true,
  showTiles: true,
  showInstances: true,
  autoGen: false,
  showPreview: false,
  previewZoom: readStoredPreviewZoom(),

  selectedAsset: null,
  redrawnSprites: [],
  redrawnBackgrounds: [],
  showOnlyRedrawn: false,
  useRedrawn: false,

  showExporter: false,
  exportBgLevel: 0,
  exportIncludeTiles: true,
  exportInstanceToggles: {},

  roomList: [],

  fetchRoomList: async () => {
    try {
      const res = await fetch("/api/room-list");
      const files = await res.json();
      set({ roomList: files });
    } catch (e) {
      console.error("Failed to fetch room list", e);
    }
  },

  fetchRedrawn: async () => {
    try {
      const res = await fetch("/api/redrawn-list");
      const data = await res.json();
      set({
        redrawnSprites: data.sprites || [],
        redrawnBackgrounds: data.backgrounds || [],
      });
    } catch (e) {
      console.error("Failed to fetch redrawn list", e);
    }
  },

  selectAsset: (asset) => set({ selectedAsset: asset }),
  closeAsset: () => set({ selectedAsset: null }),
  toggleShowOnlyRedrawn: () => set((s) => ({ showOnlyRedrawn: !s.showOnlyRedrawn })),
  toggleUseRedrawn: () => set((s) => ({ useRedrawn: !s.useRedrawn })),

  toggleExporter: () => set((s) => {
    if (!s.showExporter && s.roomData) {
      const toggles = {};
      const uniqueObjs = [...new Set(s.roomData.instances.map((i) => i.objName))];
      for (const name of uniqueObjs) toggles[name] = true;
      return { showExporter: true, exportInstanceToggles: toggles };
    }
    // Closing — auto-save config
    if (s.showExporter) {
      get().saveRoomConfig();
    }
    return { showExporter: false };
  }),
  setExportBgLevel: (level) => set({ exportBgLevel: level }),
  setExportIncludeTiles: (v) => set({ exportIncludeTiles: v }),
  toggleExportObjectType: (objName) =>
    set((s) => ({
      exportInstanceToggles: {
        ...s.exportInstanceToggles,
        [objName]: !s.exportInstanceToggles[objName],
      },
    })),
  toggleAllExportObjectTypes: () =>
    set((s) => {
      const toggles = { ...s.exportInstanceToggles };
      const allOn = Object.values(toggles).every((v) => v);
      for (const k of Object.keys(toggles)) toggles[k] = !allOn;
      return { exportInstanceToggles: toggles };
    }),
  saveRoomConfig: async () => {
    const s = get();
    if (!s.roomFile) return;
    const name = s.roomFile.replace(/\.room\.gmx$/i, "");
    const cfg = {
      bgLevel: s.exportBgLevel,
      includeTiles: s.exportIncludeTiles,
      instanceToggles: s.exportInstanceToggles,
      viewportScale: s.viewportScale,
    };
    try {
      await fetch("/api/export-config-save", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, config: cfg }),
      });
    } catch (e) {
      console.error("Failed to save room config", e);
    }
  },
  loadRoomConfig: async (roomFile) => {
    if (!roomFile) return;
    const name = roomFile.replace(/\.room\.gmx$/i, "");
    try {
      const res = await fetch(`/api/export-config/${encodeURIComponent(name)}`);
      if (!res.ok) return;
      const cfg = await res.json();
      set({
        exportBgLevel: cfg.bgLevel ?? 0,
        exportIncludeTiles: cfg.includeTiles ?? true,
        exportInstanceToggles: cfg.instanceToggles ?? {},
      });
      if (cfg.viewportScale != null) {
        get().setViewportScale(cfg.viewportScale);
      }
    } catch {
      // No config for this room is fine
    }
  },

  loadRoom: async (file) => {
    if (!file) return;
    set({ roomFile: file, loading: true, error: null, roomData: null });
    try {
      const { parseRoom } = await import("../parser/room.js");
      const url = `/undertale/rooms/${file}`;
      const data = await parseRoom(url);
      set({
        roomData: data,
        loading: false,
        scale: 1,
        viewportX: 0,
        viewportY: 0,
        viewportScale: 1,
      });
      get().loadRoomConfig(file);
    } catch (e) {
      set({ error: e.message, loading: false });
    }
  },

  setScale: (s) => set({ scale: Math.max(0.25, Math.min(8, s)) }),
  setViewport: (x, y) => set({ viewportX: x, viewportY: y }),
  setViewportScale: (raw) => set((state) => {
    const n = Number(raw);
    if (!Number.isFinite(n)) return {};
    const s = Math.max(VIEWPORT_SCALE_MIN, Math.min(VIEWPORT_SCALE_MAX, n));
    const vw = Math.round(TI84_W * s);
    const vh = Math.round(TI84_H * s);
    const maxX = Math.max(0, (state.roomData?.width || 0) - vw);
    const maxY = Math.max(0, (state.roomData?.height || 0) - vh);
    return {
      viewportScale: s,
      viewportX: Math.max(0, Math.min(state.viewportX, maxX)),
      viewportY: Math.max(0, Math.min(state.viewportY, maxY)),
    };
  }),
  toggleGrid: () => set((s) => ({ showGrid: !s.showGrid })),
  toggleViewport: () => set((s) => ({ showViewport: !s.showViewport })),
  toggleTiles: () => set((s) => ({ showTiles: !s.showTiles })),
  toggleInstances: () => set((s) => ({ showInstances: !s.showInstances })),
  toggleAutoGen: () => set((s) => ({ autoGen: !s.autoGen })),
  togglePreview: () => set((s) => ({ showPreview: !s.showPreview })),
  setPreviewZoom: (z) => {
    const n = Number(z);
    if (!Number.isFinite(n)) return;
    const clamped = Math.max(PREVIEW_ZOOM_MIN, Math.min(PREVIEW_ZOOM_MAX, n));
    writeStoredPreviewZoom(clamped);
    set({ previewZoom: clamped });
  },
}));

export default store;
