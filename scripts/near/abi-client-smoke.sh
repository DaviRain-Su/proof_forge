#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${NEAR_ABI_CLIENT_OUT:-$ROOT/build/near-abi-client}"

rm -rf "$OUT"
mkdir -p "$OUT/node_modules/near-api-js"
lake build ProofForge.Contract.Client >/dev/null
lake env lean --run Tests/NearAbiClientFixture.lean "$OUT/proof-forge-near.ts"

cat > "$OUT/node_modules/near-api-js/index.d.ts" <<'TS'
export class Account {}
export const transactions: { functionCall(...args: unknown[]): unknown };
TS
cat > "$OUT/node_modules/near-api-js/index.js" <<'JS'
exports.Account = class Account {};
exports.transactions = { functionCall: (...args) => ({ args }) };
JS
cat > "$OUT/smoke.ts" <<'TS'
import {
  encodeNearBorshArgs,
  decodeNearBorshU64,
  decodeNearBorshU32,
  decodeNearBorshBool,
  decodeNearBorshResult,
} from "./proof-forge-near";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

const value = 0x0102030405060708n;
const encoded = encodeNearBorshArgs(["u64"], [value]);
assert(Array.from(encoded).join(",") === "8,7,6,5,4,3,2,1", "u64 Borsh encoding drift");
assert(decodeNearBorshU64(encoded) === value, "u64 Borsh round-trip drift");
assert(decodeNearBorshU32(Uint8Array.from([120, 86, 52, 18])) === 0x12345678, "u32 decode drift");
assert(decodeNearBorshBool(Uint8Array.from([1])) === true, "bool decode drift");
const pairSchema = { kind: "fixedArray" as const, element: "u32" as const, length: 2 };
const pair = encodeNearBorshArgs([pairSchema], [[0x11223344, 0x55667788]]);
assert(Array.from(pair).join(",") === "68,51,34,17,136,119,102,85", "fixed-array encoding drift");
assert(JSON.stringify(decodeNearBorshResult(pairSchema, pair)) === JSON.stringify([0x11223344, 0x55667788]), "fixed-array decode drift");
console.log("near-abi-client: ok");
TS
cat > "$OUT/sandbox-smoke.ts" <<'TS'
import { connect, echo } from "./proof-forge-near";

declare const process: { env: Record<string, string | undefined> };

const rpcUrl = process.env.NEAR_RPC_URL;
const contractId = process.env.NEAR_CONTRACT_ID;
if (!rpcUrl || !contractId) throw new Error("missing NEAR sandbox connection environment");

const provider = {
  async query(request: Record<string, unknown>): Promise<unknown> {
    const response = await fetch(rpcUrl, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: "proof-forge-near-abi", method: "query", params: request }),
    });
    const payload = await response.json() as { result?: unknown; error?: unknown };
    if (payload.error) throw new Error(`NEAR RPC error: ${JSON.stringify(payload.error)}`);
    return payload.result;
  },
};

connect(contractId, { connection: { provider } } as any);
echo(42n, { finality: "optimistic" }).then((value) => {
  if (value !== 42n) throw new Error(`expected echo(42) to return 42, got ${String(value)}`);
  console.log("near-abi-client-sandbox: ok (generated client echo(42n) -> 42n)");
});
TS
cat > "$OUT/tsconfig.json" <<'JSON'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "CommonJS",
    "moduleResolution": "Node",
    "strict": true,
    "skipLibCheck": true,
    "outDir": "dist"
  },
  "include": ["proof-forge-near.ts", "smoke.ts", "sandbox-smoke.ts"]
}
JSON

"$ROOT/node_modules/.bin/tsc" -p "$OUT/tsconfig.json"
node "$OUT/dist/smoke.js"
