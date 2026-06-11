import { create } from "zustand";
import { TI84_W, TI84_H } from "../parser/types.js";

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
    } catch (e) {
      set({ error: e.message, loading: false });
    }
  },

  setScale: (s) => set({ scale: Math.max(0.25, Math.min(8, s)) }),
  setViewport: (x, y) => set({ viewportX: x, viewportY: y }),
  setViewportScale: (s) => set((state) => {
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
}));

export default store;
