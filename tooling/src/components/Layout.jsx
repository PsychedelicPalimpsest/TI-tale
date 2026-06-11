import React, { useState, useEffect } from "react";
import useStore from "../store/useStore";
import TIPreview from "./TIPreview";

export default function Layout({ children }) {
  const { fetchRoomList, loadRoom, roomFile, roomList, showPreview } = useStore();
  const [selected, setSelected] = useState("");

  useEffect(() => {
    fetchRoomList();
  }, []);

  useEffect(() => {
    if (!roomFile && roomList.length > 0) {
      const first = roomList.find(f => f === "room_ruins1.room.gmx") ||
                    roomList.find(f => !f.startsWith("TEST") && f !== "bullettest.room.gmx") ||
                    roomList[0];
      setSelected(first);
      loadRoom(first);
    } else if (roomFile) {
      setSelected(roomFile);
    }
  }, [roomList, roomFile]);

  const handleRoomChange = (e) => {
    const val = e.target.value;
    setSelected(val);
    loadRoom(val);
  };

  return (
    <div className="app-layout">
      <header className="app-header">
        <h1 className="app-title">TI-tale Room Explorer</h1>
        <div className="room-selector">
          <label htmlFor="room-select">Room:</label>
          <select id="room-select" value={selected} onChange={handleRoomChange}>
            {roomList.map((f) => (
              <option key={f} value={f}>{f.replace(".room.gmx", "")}</option>
            ))}
          </select>
        </div>
      </header>
      <div className="app-body">
        <aside className="app-sidebar">
          <AssetList />
        </aside>
        <main className="app-main">
          {children}
        </main>
        {showPreview && (
          <aside className="app-preview">
            <TIPreview />
          </aside>
        )}
      </div>
    </div>
  );
}

function AssetList() {
  const { roomData } = useStore();

  if (!roomData) return <div className="sidebar-empty">No room loaded</div>;

  const bgNames = [...new Set(roomData.tiles.map((t) => t.bgName))].sort();
  const objNames = [...new Set(roomData.instances.map((i) => i.objName))].sort();

  return (
    <div className="asset-list">
      <h3>Assets</h3>
      <details open>
        <summary>Backgrounds ({bgNames.length})</summary>
        <ul>
          {bgNames.map((n) => (
            <li key={n} className="asset-item bg-item">
              <span className="status-dot unknown" title="Not yet checked" />
              {n}
            </li>
          ))}
        </ul>
      </details>
      <details open>
        <summary>Objects ({objNames.length})</summary>
        <ul>
          {objNames.map((n) => (
            <li key={n} className="asset-item obj-item">
              <span className="status-dot unknown" title="Not yet checked" />
              {n}
            </li>
          ))}
        </ul>
      </details>
    </div>
  );
}
