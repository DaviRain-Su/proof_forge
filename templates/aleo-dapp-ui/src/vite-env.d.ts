/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_ALEO_PROGRAM_ID?: string;
  readonly VITE_ALEO_NETWORK?: string;
  readonly VITE_ALEO_API?: string;
  readonly VITE_ALEO_FEE_MICROCREDITS?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
