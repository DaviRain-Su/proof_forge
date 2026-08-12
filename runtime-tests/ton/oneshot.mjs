#!/usr/bin/env node
/**
 * One-shot @ton/sandbox runner for `pf run -t ton -- <method> [u64…]`.
 *
 * Env:
 *   PF_TON_ARTIFACT_DIR — OutputSet with *.compiled.boc + *.ton-abi.json
 *   PF_TON_METHOD       — method name (init|increment|get|…)
 *   PF_TON_ARGS         — space-separated u64 decimals
 *   PF_TON_INIT_ARGS    — auto-init u64 when method ≠ init (default: 0)
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

function parseU64s(s) {
  if (!s || !s.trim()) return [];
  return s.split(/\s+/).map((tok) => {
    const cleaned = tok.replace(/u64$/i, '').replace(/u$/i, '');
    if (!/^\d+$/.test(cleaned)) die(`arg must be u64 decimal, got ${tok}`);
    return BigInt(cleaned);
  });
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

function buildBody(op, queryId, params) {
  let b = beginCell().storeUint(BigInt(op), 32).storeUint(BigInt(queryId), 64);
  for (const p of params) {
    b = b.storeUint(p, 64);
  }
  return b.endCell();
}

function emptyStorageData(fieldCount) {
  let b = beginCell().storeUint(0, 64);
  for (let i = 0; i < fieldCount; i++) {
    b = b.storeUint(0, 64);
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

function fieldCount(abi) {
  const fields = abi.storage?.fields;
  if (Array.isArray(fields)) {
    // may mix objects and layoutMarker number
    return fields.filter((f) => f && typeof f === 'object' && f.name).length || 1;
  }
  return 1;
}

async function main() {
  const artifactDir = envReq('PF_TON_ARTIFACT_DIR');
  const method = envReq('PF_TON_METHOD');
  const args = parseU64s(process.env.PF_TON_ARGS || '');
  const initArgs = parseU64s(process.env.PF_TON_INIT_ARGS || '');

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
  const nFields = fieldCount(abi);
  const data = emptyStorageData(nFields);

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

  async function sendMethod(m, params) {
    const body = buildBody(m.op, queryId++, params);
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
    if (m.params && params.length !== m.params.length) {
      die(`init wants ${m.params.length} args, got ${params.length}`);
    }
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

  const want = m.params?.length ?? args.length;
  if (args.length !== want && (m.params?.length ?? 0) > 0) {
    die(`method ${method} wants ${want} args, got ${args.length}`);
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
