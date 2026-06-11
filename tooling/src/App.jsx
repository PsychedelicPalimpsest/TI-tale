import React from "react";
import Layout from "./components/Layout";
import Toolbar from "./components/Toolbar";
import RoomExplorer from "./components/RoomExplorer";

export default function App() {
  return (
    <Layout>
      <Toolbar />
      <RoomExplorer />
    </Layout>
  );
}
