/**
 * Shared helpers for TON engineering sandbox differentials.
 *
 * Env:
 *   PROOF_FORGE_FIXTURES_DIR — product CLI output root with
 *     <Name>/<Name>.compiled.boc and optional <Name>.ton-abi.json
 *
 * Honesty: @ton/sandbox is a local TVM emulator, not mainnet or formal Stage-0.
 */
import fs from 'node:fs';
import path from 'node:path';
import {
  Address,
  beginCell,
  Cell,
  contractAddress,
  SendMode,
  toNano,
} from '@ton/core';
import { Blockchain } from '@ton/sandbox';

export { toNano, Address, Cell, beginCell };

/** Stable seed for same-host engineering runs (MessageParams; not chain entropy). */
export const FIXED_RANDOM_SEED = Buffer.alloc(32, 0x42);

/** UNIX time fixed for deterministic storage fees / now reads. */
export const FIXED_NOW = 1_700_000_000;

/** Product exit codes (EmitIRV1.err*). */
export const EXIT = Object.freeze({
  overflow: 100,
  divZero: 101,
  invalidShift: 102,
  assert: 103,
  loopBound: 104,
  layout: 105,
  userBase: 200,
});

export function fixturesRoot() {
  const root = process.env.PROOF_FORGE_FIXTURES_DIR;
  if (!root) {
    throw new Error(
      'PROOF_FORGE_FIXTURES_DIR is unset (run scripts/ton_runtime_test.sh)',
    );
  }
  return root;
}

export function bocPath(name) {
  const root = fixturesRoot();
  const candidates = [
    path.join(root, name, `${name}.compiled.boc`),
    path.join(root, name, `${name}.boc`),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  // last-resort walk
  const dir = path.join(root, name);
  if (fs.existsSync(dir)) {
    for (const ent of fs.readdirSync(dir)) {
      if (ent.endsWith('.compiled.boc') || ent.endsWith('.boc')) {
        return path.join(dir, ent);
      }
    }
  }
  throw new Error(
    `BoC for ${name} not found under ${path.join(root, name)} (need product finalize with fift)`,
  );
}

export function loadCode(name) {
  return Cell.fromBoc(fs.readFileSync(bocPath(name)))[0];
}

export function loadTonAbi(name) {
  const p = path.join(fixturesRoot(), name, `${name}.ton-abi.json`);
  if (!fs.existsSync(p)) return null;
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

/**
 * Normalize c4 field bit-widths. Default remains historical uint64 slots.
 * UInt256 state is a single 256-bit cell field (EmitIRV1 `uint256`).
 */
export function normalizeFieldBits(fieldCountOrBits = 1, fieldBits = 64) {
  if (Array.isArray(fieldCountOrBits)) {
    return fieldCountOrBits.map((n) => Number(n));
  }
  const count = Number(fieldCountOrBits);
  if (Array.isArray(fieldBits)) {
    if (fieldBits.length !== count) {
      throw new Error(
        `fieldBits length ${fieldBits.length} != fieldCount ${count}`,
      );
    }
    return fieldBits.map((n) => Number(n));
  }
  return Array.from({ length: count }, () => Number(fieldBits));
}

/** c4 flat Storage: __layout:uint64 + exact-width fields (zeros = uninitialized). */
export function emptyStorageData(fieldCount = 1, fieldBits = 64) {
  const bits = normalizeFieldBits(fieldCount, fieldBits);
  let b = beginCell().storeUint(0, 64);
  for (const w of bits) {
    b = b.storeUint(0, w);
  }
  return b.endCell();
}

/**
 * Internal-message body: 32-bit op + 64-bit query_id + consecutive exact-width
 * params (ton-internal-msg-v1 / EmitIRV1). Default remains u64.
 *
 * Bytes N is packed as N consecutive `storeUint(byte, 8)` (param `byteWidth=1`).
 * Pass `{ bytes: Uint8Array|number[] }` or `{ kind: 'bytes', bytes }`.
 * UInt256 uses `{ kind: 'uint256', value }` / `{ bits: 256, value }`.
 */
export function buildBody(op, queryId, ...params) {
  let b = beginCell()
    .storeUint(BigInt(op), 32)
    .storeUint(BigInt(queryId), 64);
  for (const p of params) {
    if (p && typeof p === 'object') {
      const bytes = p.bytes ?? (p.kind === 'bytes' ? p.value : undefined);
      if (bytes !== undefined) {
        for (const byte of bytes) {
          const n = Number(byte);
          if (!Number.isInteger(n) || n < 0 || n > 255) {
            throw new Error(`Bytes leaf must be 0..255, got ${byte}`);
          }
          b = b.storeUint(n, 8);
        }
        continue;
      }
      const bits = Number(p.bits ?? (p.kind === 'uint256' ? 256 : 0));
      if (bits > 0) {
        b = b.storeUint(BigInt(p.value), bits);
        continue;
      }
    }
    b = b.storeUint(BigInt(p), 64);
  }
  return b.endCell();
}

/**
 * Minimal Contract surface for sandbox.openContract:
 * sendOp → provider.internal; getGet → get-method `get`.
 */
export class PfContract {
  /**
   * @param {Address} address
   * @param {{ code: Cell, data: Cell }} init
   */
  constructor(address, init) {
    this.address = address;
    this.init = init;
  }

  /**
   * @param {import('@ton/core').ContractProvider} provider
   * @param {import('@ton/core').Sender} via
   * @param {bigint} value
   * @param {Cell} body
   * @param {boolean} bounce
   */
  async sendOp(provider, via, value, body, bounce = true) {
    await provider.internal(via, {
      value,
      bounce,
      sendMode: SendMode.PAY_GAS_SEPARATELY,
      body,
    });
  }

  /** @param {import('@ton/core').ContractProvider} provider */
  async getGet(provider) {
    const r = await provider.get('get', []);
    return r.stack.readBigNumber();
  }
}

/**
 * Fresh Blockchain with fixed config/now/verbosity + funded treasury + open contract.
 * @param {string} name program stem under PROOF_FORGE_FIXTURES_DIR
 * @param {{ fieldCount?: number, fieldBits?: number|number[] }} [opts]
 */
export async function deployFresh(name, opts = {}) {
  const fieldCount = opts.fieldCount ?? (Array.isArray(opts.fieldBits) ? opts.fieldBits.length : 1);
  const fieldBits = opts.fieldBits ?? 64;
  const code = loadCode(name);
  const data = emptyStorageData(fieldCount, fieldBits);
  const blockchain = await Blockchain.create({ config: 'default' });
  blockchain.now = FIXED_NOW;
  blockchain.verbosity = {
    print: false,
    blockchainLogs: false,
    vmLogs: 'none',
    debugLogs: false,
  };
  blockchain.recordStorage = true;

  const deployer = await blockchain.treasury('deployer', {
    balance: toNano('100'),
  });
  const init = { code, data };
  const address = contractAddress(0, init);
  /** @type {import('@ton/sandbox').SandboxContract<PfContract>} */
  const contract = blockchain.openContract(new PfContract(address, init));

  const msgParams = { randomSeed: FIXED_RANDOM_SEED, now: FIXED_NOW };

  return {
    blockchain,
    deployer,
    contract,
    address,
    code,
    data,
    msgParams,
    toNano,
  };
}

/** Account transactions on `address` (skips treasury). */
export function contractTxs(result, address) {
  return result.transactions.filter((t) => {
    const dest = t.inMessage?.info?.dest;
    return dest instanceof Address && dest.equals(address);
  });
}

/** First contract-side generic tx description, or throws. */
export function contractGeneric(result, address) {
  const txs = contractTxs(result, address);
  if (txs.length === 0) {
    throw new Error('no contract transaction in result');
  }
  // Prefer the first non-success bounce/compute target; usually index 0 is the recv.
  const tx = txs[0];
  if (tx.description.type !== 'generic') {
    throw new Error(`expected generic description, got ${tx.description.type}`);
  }
  return { tx, description: tx.description };
}

export function computeVm(description) {
  const phase = description.computePhase;
  if (!phase || phase.type !== 'vm') {
    throw new Error(`expected vm compute phase, got ${phase?.type}`);
  }
  return phase;
}

/** Parse c4 flat Storage cell → { layout, fields: bigint[] }. */
export function parseStorage(dataCell, fieldCount = 1, fieldBits = 64) {
  const bits = normalizeFieldBits(fieldCount, fieldBits);
  const s = dataCell.beginParse();
  const layout = s.loadUintBig(64);
  const fields = [];
  for (const w of bits) {
    fields.push(s.loadUintBig(w));
  }
  return { layout, fields };
}

export async function readDataCell(blockchain, address) {
  const sc = await blockchain.getContract(address);
  const st = sc.accountState;
  if (!st || st.type !== 'active' || !st.state.data) {
    throw new Error('account is not active with data');
  }
  return st.state.data;
}

/** Decode emit body: eventIndex:u32 + arg:u64* (EmitIRV1). */
export function decodeEventBody(body) {
  const s = body.beginParse();
  const eventIndex = s.loadUint(32);
  const args = [];
  while (s.remainingBits >= 64) {
    args.push(s.loadUintBig(64));
  }
  return { eventIndex, args };
}
