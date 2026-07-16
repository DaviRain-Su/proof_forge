#!/usr/bin/env bash
set -euo pipefail

# Compile and execute the generated EVM custom-error decoder without fetching
# npm dependencies. The local ethers stub implements only the ABI scalar slice
# that this smoke exercises; Foundry separately proves the emitted payload.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${EVM_CLIENT_SMOKE_OUT_DIR:-$ROOT/build/evm-contract-client-smoke}"
CLIENT_DIR="$OUT_DIR/client"
TSC_BIN="${TSC:-$ROOT/node_modules/.bin/tsc}"

command -v node >/dev/null 2>&1 || {
  echo "node not found; install Node.js, then run 'npm ci' from the repository root" >&2
  exit 1
}
command -v "$TSC_BIN" >/dev/null 2>&1 || {
  echo "TypeScript compiler not found at '$TSC_BIN'; run 'npm ci' from the repository root" >&2
  exit 1
}

rm -rf "$OUT_DIR"
mkdir -p "$CLIENT_DIR" "$OUT_DIR/node_modules/ethers"

lake build proof-forge
"$ROOT/.lake/build/bin/proof-forge" emit \
  --target evm \
  --fixture evm-errors \
  --format bytecode \
  --yul-output "$CLIENT_DIR/EvmErrorsProbe.yul" \
  --artifact-output "$CLIENT_DIR/EvmErrorsProbe.proof-forge-artifact.json" \
  -o "$CLIENT_DIR/EvmErrorsProbe.bin"

cat > "$OUT_DIR/node_modules/ethers/package.json" <<'JSON'
{
  "name": "ethers",
  "version": "0.0.0-proof-forge-smoke",
  "main": "index.js",
  "types": "index.d.ts"
}
JSON

cat > "$OUT_DIR/node_modules/ethers/index.d.ts" <<'TS'
export namespace ethers {
  type Contract = any;
  type ContractRunner = any;
  type ContractTransactionReceipt = any;
  type Interface = any;
  type Signer = any;
}

export const ethers: {
  AbiCoder: {
    defaultAbiCoder(): {
      decode(types: readonly string[], data: string): readonly unknown[];
    };
  };
  Contract: new (...args: readonly unknown[]) => any;
  Interface: new (...args: readonly unknown[]) => any;
};
TS

cat > "$OUT_DIR/node_modules/ethers/index.js" <<'JS'
function decodeStaticWords(types, data) {
  const hex = data.startsWith("0x") || data.startsWith("0X") ? data.slice(2) : data;
  if (!types.every((type) => /^uint(8|32|64|128|256)$/.test(type))) {
    throw new Error("smoke stub only decodes the supported static uint slice");
  }
  if (hex.length !== types.length * 64 || !/^[0-9a-fA-F]*$/.test(hex)) {
    throw new Error("invalid ABI word payload");
  }
  return types.map((_, index) => BigInt(`0x${hex.slice(index * 64, (index + 1) * 64)}`));
}

class UnusedContract {}
class UnusedInterface {}

exports.ethers = {
  AbiCoder: { defaultAbiCoder: () => ({ decode: decodeStaticWords }) },
  Contract: UnusedContract,
  Interface: UnusedInterface,
};
JS

cat > "$OUT_DIR/node-globals.d.ts" <<'TS'
declare function require(name: string): any;
declare module "node:fs" {
  const value: any;
  export = value;
}
declare module "node:path" {
  const value: any;
  export = value;
}
TS

cat > "$OUT_DIR/runtime-smoke.ts" <<'TS'
import {
  decodeProofForgeRevert,
  decodeProofForgeRevertDetails,
} from "./client/proof-forge-evm-abi";

function assertCondition(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

function word(value: bigint): string {
  return value.toString(16).padStart(64, "0");
}

const payload = `0X9432A7EE${word(9007199254740993n)}${word(3n)}`;
const decoded = decodeProofForgeRevertDetails({ error: { data: payload } });
assertCondition(decoded !== undefined, "custom-error payload was not decoded");
assertCondition(decoded?.error.soliditySelector === "9432a7ee", "selector lookup mismatch");
assertCondition(decoded?.args[0] === 9007199254740993n, "large uint64 lost precision");
assertCondition(decoded?.args[1] === 3n, "second uint64 mismatch");
assertCondition(decodeProofForgeRevert({ data: payload })?.assertionId === 7,
  "legacy decoder did not delegate to the detailed decoder");

const selectorOnly = decodeProofForgeRevertDetails({ data: "0x09caebf3" });
assertCondition(selectorOnly?.error.soliditySelector === "09caebf3",
  "selector-only custom error was not decoded");
assertCondition(selectorOnly?.args.length === 0, "selector-only error returned arguments");

assertCondition(decodeProofForgeRevertDetails({ data: `${payload}${word(4n)}` }) === undefined,
  "decoder accepted an extra ABI word");
assertCondition(decodeProofForgeRevertDetails({ data: payload.slice(0, -1) }) === undefined,
  "decoder accepted a truncated ABI word");
assertCondition(decodeProofForgeRevertDetails({ data: "0xdeadbeef" }) === undefined,
  "decoder accepted an unknown selector");

console.log("evm-contract-client-runtime: ok");
TS

cat > "$OUT_DIR/tsconfig.json" <<'JSON'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "CommonJS",
    "moduleResolution": "Node",
    "strict": true,
    "skipLibCheck": true,
    "esModuleInterop": true,
    "outDir": "dist",
    "rootDir": "."
  },
  "include": ["client/proof-forge-evm-abi.ts", "runtime-smoke.ts", "node-globals.d.ts"]
}
JSON

"$TSC_BIN" --project "$OUT_DIR/tsconfig.json"
NODE_PATH="$OUT_DIR/node_modules" node "$OUT_DIR/dist/runtime-smoke.js"
