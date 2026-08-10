import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { nodePolyfills } from "vite-plugin-node-polyfills";

export default defineConfig({
  plugins: [react(), nodePolyfills({ include: ["buffer"] })],
  server: { host: "127.0.0.1", port: 5175 },
  define: {
    "process.env": {},
  },
});
