import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Minimal Vite config for Aleo wallet dApp.
// If you later add @provablehq/sdk / wasm, mirror aleo-dev-toolkit optimizeDeps.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: true,
  },
  build: {
    target: "esnext",
  },
});
