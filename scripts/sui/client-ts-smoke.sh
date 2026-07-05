#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

BUILD_DIR="${1:-build/sui/counter-client-ts}"
SMOKE_DIR="build/sui/client-ts-smoke"

rm -rf "$BUILD_DIR" "$SMOKE_DIR"
lake env proof-forge build --target move-sui --fixture counter -o "$BUILD_DIR"

test -f "$BUILD_DIR/proof-forge-client.ts"

mkdir -p "$SMOKE_DIR"
cp "$BUILD_DIR/proof-forge-client.ts" "$SMOKE_DIR/proof-forge-client.ts"

cat > "$SMOKE_DIR/consumer.ts" <<'TS'
import {
  TARGET,
  PACKAGE_NAME,
  MODULE_NAME,
  COUNTER_TYPE,
  PACKAGE_ID,
  type CounterObjectRef,
  counterType,
  createCounter,
  initializeCounter,
  incrementCounter,
  valueCounter,
  getCounterValue,
} from "./proof-forge-client";

const ref: CounterObjectRef = { objectId: "0x1", version: "1", digest: "abc" };
const calls: Array<{ target: string; arguments?: unknown[] }> = [];
const tx = {
  object(id: string): unknown {
    return { kind: "object", id };
  },
  moveCall(input: { target: string; arguments?: unknown[] }): unknown {
    calls.push(input);
    return input;
  },
};

if (TARGET !== "move-sui") throw new Error("unexpected target");
if (PACKAGE_NAME !== "counter") throw new Error("unexpected package");
if (MODULE_NAME !== "counter") throw new Error("unexpected module");
if (COUNTER_TYPE !== "Counter") throw new Error("unexpected object type");

const fullType: string = counterType(PACKAGE_ID);
createCounter(tx);
initializeCounter(tx);
incrementCounter(tx, ref);
valueCounter(tx, ref.objectId);
getCounterValue(tx, ref);

if (!fullType.includes("::counter::Counter")) throw new Error("unexpected Counter type");
if (calls.length !== 5) throw new Error("unexpected call count");
TS

cat > "$SMOKE_DIR/tsconfig.json" <<'JSON'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "CommonJS",
    "strict": true,
    "noEmit": true,
    "skipLibCheck": true
  },
  "include": ["consumer.ts", "proof-forge-client.ts"]
}
JSON

tsc -p "$SMOKE_DIR/tsconfig.json"

grep -E 'move-sui|Sui|Counter|object|init|create|increment|value|get' \
  "$BUILD_DIR/proof-forge-client.ts" >/dev/null

echo "sui-client-ts-smoke: ok"
