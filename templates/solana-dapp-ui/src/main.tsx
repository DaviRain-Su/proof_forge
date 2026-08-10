import React from "react";
import ReactDOM from "react-dom/client";
import { Buffer } from "buffer";
import { App } from "./App";
import "./styles.css";
import "@solana/wallet-adapter-react-ui/styles.css";

// wallet-adapter / web3.js expect Buffer in the browser
(globalThis as unknown as { Buffer: typeof Buffer }).Buffer = Buffer;

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
