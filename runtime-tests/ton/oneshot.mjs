#!/usr/bin/env node
/**
 * One-shot @ton/sandbox runner for `pf run -t ton -- <method> [u64…]`.
 *
 * Env:
 *   PF_TON_ARTIFACT_DIR — OutputSet with *.compiled.boc + *.ton-abi.json
 *   PF_TON_METHOD       — method name (init|increment|get|…)
 *   PF_TON_ARGS         — space-separated decimals, 0x-hex, or Bytes leaves
 *   PF_TON_INIT_ARGS    — auto-init args when method ≠ init (default: 0)
 *
 * Honesty: engineering @ton/sandbox only — not mainnet, not formal.
 * Sync call FC at compiler; schedule = createMessage subset.
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

const FIXED_RANDOM_SEED = Buffer.alloc(32, 0x42);
const FIXED_NOW = 1_700_000_000;

function die(msg) {
  console.error(`ton-oneshot: FAIL: ${msg}`);
  process.exit(1);
}

function envReq(name) {
  const v = process.env[name];
  if (!v) die(`missing env ${name}`);
  return v;
}

function parseArgTokens(s) {
  if (!s || !s.trim()) return [];
  const out = [];
  for (const tok of s.split(/\s+/)) {
    const cleaned = tok.replace(/u64$/i, '').replace(/u$/i, '');
    if (/^0x[0-9a-fA-F]+$/.test(cleaned)) {
      let hex = cleaned.slice(2);
      if (hex.length % 2 === 1) hex = `0${hex}`;
      const bytes = [];
      for (let i = 0; i < hex.length; i += 2) {
        bytes.push(parseInt(hex.slice(i, i + 2), 16));
      }
      out.push({ kind: 'bytes', bytes });
      continue;
    }
    if (!/^\d+$/.test(cleaned)) die(`arg must be decimal or 0x-hex, got ${tok}`);
    out.push(BigInt(cleaned));
  }
  return out;
}

function abiBitWidth(type) {
  switch (type) {
    case 'uint256':
    case 'int256':
      return 256;
    case 'uint128':
    case 'int128':
      return 128;
    case 'uint32':
    case 'int32':
      return 32;
    case 'uint16':
    case 'int16':
      return 16;
    case 'uint8':
    case 'int8':
      return 8;
    default:
      return 64;
  }
}

function namedStorageFields(abi) {
  const fields = abi.storage?.fields;
  if (!Array.isArray(fields)) return [];
  return fields.filter((f) => f && typeof f === 'object' && f.name);
}

function fieldBitWidths(abi) {
  const named = namedStorageFields(abi);
  if (named.length === 0) return [64];
  return named.map((f) => abiBitWidth(f.type));
}

function findBocAndAbi(dir) {
  const entries = fs.readdirSync(dir);
  let boc = null;
  let abi = null;
  let stem = null;
  // Prefer Counter/StateCell-like single-file layout
  for (const ent of entries) {
    if (ent.endsWith('.compiled.boc') || ent.endsWith('.boc')) {
      boc = path.join(dir, ent);
      stem = ent.replace(/\.compiled\.boc$/, '').replace(/\.boc$/, '');
    }
    if (ent.endsWith('.ton-abi.json')) {
      abi = path.join(dir, ent);
    }
  }
  // Nested <Name>/<Name>.compiled.boc
  if (!boc) {
    for (const ent of entries) {
      const sub = path.join(dir, ent);
      if (!fs.statSync(sub).isDirectory()) continue;
      const cand = [
        path.join(sub, `${ent}.compiled.boc`),
        path.join(sub, `${ent}.boc`),
      ];
      for (const p of cand) {
        if (fs.existsSync(p)) {
          boc = p;
          stem = ent;
          break;
        }
      }
      const abiCand = path.join(sub, `${ent}.ton-abi.json`);
      if (fs.existsSync(abiCand)) abi = abiCand;
      if (boc) break;
    }
  }
  if (!boc) die(`no *.compiled.boc under ${dir}`);
  if (!abi) {
    const guess = path.join(path.dirname(boc), `${stem}.ton-abi.json`);
    if (fs.existsSync(guess)) abi = guess;
  }
  if (!abi) die(`no *.ton-abi.json next to ${boc}`);
  return { boc, abi, stem };
}

function flattenArgs(paramsSpec, tokens) {
  const spec = Array.isArray(paramsSpec) ? paramsSpec : [];
  if (spec.length === 0) {
    const out = [];
    for (const tok of tokens) {
      if (tok && typeof tok === 'object' && tok.kind === 'bytes') {
        for (const byte of tok.bytes) out.push({ bits: 8, value: BigInt(byte) });
      } else {
        out.push({ bits: 64, value: BigInt(tok) });
      }
    }
    return out;
  }
  const queue = [...tokens];
  const out = [];
  for (const p of spec) {
    const bits = abiBitWidth(p.type);
    if (bits === 8 && queue[0] && typeof queue[0] === 'object' && queue[0].kind === 'bytes') {
      const next = queue[0].bytes;
      if (next.length === 0) die(`empty Bytes token for param ${p.name}`);
      out.push({ bits: 8, value: BigInt(next[0]) });
      next.shift();
      if (next.length === 0) queue.shift();
      continue;
    }
    if (queue.length === 0) die(`missing arg for param ${p.name}`);
    const tok = queue.shift();
    if (tok && typeof tok === 'object' && tok.kind === 'bytes') {
      if (tok.bytes.length !== Math.ceil(bits / 8)) {
        die(`0x-hex width mismatch for ${p.name}: got ${tok.bytes.length} bytes, want ${Math.ceil(bits / 8)}`);
      }
      let v = 0n;
      for (const byte of tok.bytes) v = (v << 8n) | BigInt(byte);
      out.push({ bits, value: v });
    } else {
      out.push({ bits, value: BigInt(tok) });
    }
  }
  if (queue.length > 0) die(`too many args (leftover ${queue.length})`);
  return out;
}

function buildBody(op, queryId, encodedParams) {
  let b = beginCell().storeUint(BigInt(op), 32).storeUint(BigInt(queryId), 64);
  for (const p of encodedParams) {
    b = b.storeUint(p.value, p.bits);
  }
  return b.endCell();
}

function emptyStorageData(fieldBits) {
  let b = beginCell().storeUint(0, 64);
  for (const w of fieldBits) {
    b = b.storeUint(0, w);
  }
  return b.endCell();
}

class PfContract {
  constructor(address, init) {
    this.address = address;
    this.init = init;
  }
  async sendOp(provider, via, value, body, bounce = true) {
    await provider.internal(via, {
      value,
      bounce,
      sendMode: SendMode.PAY_GAS_SEPARATELY,
      body,
    });
  }
  async getGet(provider) {
    const r = await provider.get('get', []);
    return r.stack.readBigNumber();
  }
}

function loadMethod(abi, name) {
  const m = (abi.methods || []).find((x) => x.name === name);
  if (!m) die(`method '${name}' not in ton-abi (have: ${(abi.methods || []).map((x) => x.name).join(', ')})`);
  return m;
}



async function main() {
  const artifactDir = envReq('PF_TON_ARTIFACT_DIR');
  const method = envReq('PF_TON_METHOD');
  const args = parseArgTokens(process.env.PF_TON_ARGS || '');
  const initArgs = parseArgTokens(process.env.PF_TON_INIT_ARGS || '');

  if (!fs.existsSync(path.join(artifactDir, 'manifest.json'))) {
    die('missing manifest.json (run pf build -t ton first)');
  }

  const { boc, abi: abiPath, stem } = findBocAndAbi(artifactDir);
  // Product ton-abi may embed a non-JSON layoutMarker token inside fields[];
  // strip bare `"layoutMarker":N` array elements before parse.
  const abiRaw = fs.readFileSync(abiPath, 'utf8');
  const abiFixed = abiRaw.replace(
    /,\s*"layoutMarker"\s*:\s*\d+/g,
    '',
  );
  let abi;
  try {
    abi = JSON.parse(abiFixed);
  } catch (e) {
    die(`ton-abi JSON parse failed (${abiPath}): ${e.message}`);
  }
  const code = Cell.fromBoc(fs.readFileSync(boc))[0];
  const data = emptyStorageData(fieldBitWidths(abi));

  const blockchain = await Blockchain.create({ config: 'default' });
  blockchain.now = FIXED_NOW;
  blockchain.verbosity = {
    print: false,
    blockchainLogs: false,
    vmLogs: 'none',
    debugLogs: false,
  };

  const deployer = await blockchain.treasury('deployer', {
    balance: toNano('100'),
  });
  const init = { code, data };
  const address = contractAddress(0, init);
  const contract = blockchain.openContract(new PfContract(address, init));

  let queryId = 1n;

  async function sendMethod(m, tokens) {
    const body = buildBody(m.op, queryId++, flattenArgs(m.params || [], tokens));
    const bounce = m.mode !== 'init';
    const res = await contract.sendOp(
      deployer.getSender(),
      toNano(m.mode === 'init' ? '1' : '0.5'),
      body,
      bounce,
    );
    // Check compute success on contract tx
    const txs = res.transactions.filter((t) => {
      const dest = t.inMessage?.info?.dest;
      return dest instanceof Address && dest.equals(address);
    });
    if (txs.length === 0) die('no contract transaction');
    const desc = txs[0].description;
    if (desc.type !== 'generic') die(`unexpected tx description ${desc.type}`);
    const phase = desc.computePhase;
    if (!phase || phase.type !== 'vm') die('expected vm compute phase');
    if (!phase.success || phase.exitCode !== 0) {
      die(`compute failed exit=${phase.exitCode} success=${phase.success}`);
    }
    return res;
  }

  const isInit =
    method === 'init' || method === 'constructor' || method === 'deploy';

  if (isInit) {
    const m = loadMethod(abi, 'init');
    const params =
      args.length > 0
        ? args
        : m.params?.length
          ? Array(m.params.length).fill(0n)
          : [];
    await sendMethod(m, params);
    // Print get if available
    if ((abi.methods || []).some((x) => x.name === 'get')) {
      const v = await contract.getGet();
      console.log(v.toString());
    } else {
      console.log('ok');
    }
    console.error(`ton-oneshot: ok mode=init program=${stem}`);
    return;
  }

  // Auto-init then method
  const initM = loadMethod(abi, 'init');
  const initParams =
    initArgs.length > 0
      ? initArgs
      : initM.params?.length
        ? Array(initM.params.length).fill(0n)
        : [];
  await sendMethod(initM, initParams);

  const m = loadMethod(abi, method);
  if (m.mode === 'view' || method === 'get') {
    // Prefer get-method for view
    if (method === 'get' || m.name === 'get') {
      const v = await contract.getGet();
      console.log(v.toString());
      console.error(`ton-oneshot: ok mode=get program=${stem}`);
      return;
    }
  }

  await sendMethod(m, args);

  // After mutate, print get() if present
  if ((abi.methods || []).some((x) => x.name === 'get')) {
    const v = await contract.getGet();
    console.log(v.toString());
  } else {
    console.log('ok');
  }
  console.error(`ton-oneshot: ok mode=call method=${method} program=${stem}`);
}

main().catch((e) => {
  console.error(`ton-oneshot: FAIL: ${e?.stack || e}`);
  process.exit(1);
});
