/**
 * ScheduleFlow engineering sandbox differential (BL-8 / TON-4 runtime).
 *
 * Product TON materializer lowers `schedule ledger.daily(count)` to
 * Tolk `createMessage` + `SEND_MODE_PAY_FEES_SEPARATELY`:
 *   bounce = BounceMode.NoBounce  → info.bounce === false
 *   value  = 0
 *   dest   = (workchain 0, SHA-256(UTF-8 "ledger") as uint256)  — STUB only
 *   body   = storeUint(op,32) · storeUint(query_id=0,64) · storeUint(arg,64)
 *            where op = first 4 bytes BE of SHA-256(UTF-8 "daily")
 *            and storeUint is big-endian (TON cell bits; @ton/core loadUint).
 *
 * Assert message shape only. Dest is NOT a real deployed account; this is
 * an engineering @ton/sandbox differential, not mainnet / formal Stage-0 /
 * hermetic release evidence.
 */
import { createHash } from 'node:crypto';
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Address } from '@ton/core';
import {
  buildBody,
  computeVm,
  contractGeneric,
  deployFresh,
  parseStorage,
  readDataCell,
  toNano,
} from './helpers.js';

/** SHA-256(UTF-8 s) as lower-case hex (matches Lean Crypto.sha256Hex). */
function sha256Hex(s) {
  return createHash('sha256').update(s, 'utf8').digest('hex');
}

/** First 4 bytes of SHA-256(UTF-8 method) as big-endian uint32. */
function methodOp32(method) {
  const d = createHash('sha256').update(method, 'utf8').digest();
  return d.readUInt32BE(0);
}

// Pinned stubs — re-derived here so the suite fails closed if either the
// emission policy or the local pin drifts. Cross-check with Python:
//   hashlib.sha256(b"ledger").hexdigest()
//   int.from_bytes(hashlib.sha256(b"daily").digest()[:4], "big")
const LEDGER_DEST_HASH_HEX =
  'fe14010b4fe83303852f0467c919ef9a7ca089b91e96e3aad7d426dd87079297';
const DAILY_OP = 0x6f31304c; // 1865494604

// Sanity: pins must match local crypto (catches accidental edit of constants).
assert.equal(sha256Hex('ledger'), LEDGER_DEST_HASH_HEX);
assert.equal(methodOp32('daily'), DAILY_OP);

const EXPECTED_DEST = new Address(
  0,
  Buffer.from(LEDGER_DEST_HASH_HEX, 'hex'),
);

/** Internal out-messages produced by a contract transaction. */
function internalOutMessages(tx) {
  return tx.outMessages.values().filter((m) => m.info.type === 'internal');
}

/**
 * Decode product schedule body envelope:
 *   op:u32 BE · query_id:u64 BE · arg:u64 BE*  (Tolk storeUint = big-endian)
 */
function decodeScheduleBody(body) {
  const s = body.beginParse();
  const op = s.loadUint(32);
  const queryId = s.loadUintBig(64);
  const args = [];
  while (s.remainingBits >= 64) {
    args.push(s.loadUintBig(64));
  }
  return { op, queryId, args };
}

describe('ScheduleFlow @ton/sandbox engineering differential', () => {
  it('later(): success + parent state advances + exactly one internal out-msg shape', async () => {
    const { blockchain, deployer, contract, address } =
      await deployFresh('ScheduleFlow');

    // init(5) — op 0
    await contract.sendOp(
      deployer.getSender(),
      toNano('1'),
      buildBody(0, 1n, 5n),
      false,
    );
    assert.equal(await contract.getGet(), 5n);

    // later() — op 1, no entry params; schedules ledger.daily(count=5) then count+=1
    const res = await contract.sendOp(
      deployer.getSender(),
      toNano('0.5'),
      buildBody(1, 2n),
      true,
    );

    const { tx, description } = contractGeneric(res, address);
    const vm = computeVm(description);
    assert.equal(vm.success, true, 'schedule entry compute must succeed');
    assert.equal(vm.exitCode, 0);
    assert.equal(description.aborted, false);
    assert.ok(description.actionPhase?.success, 'action phase must succeed');
    assert.ok(
      (description.actionPhase.totalActions ?? 0) >= 1,
      `expected ≥1 out action, got ${description.actionPhase.totalActions}`,
    );
    assert.equal(description.bouncePhase, undefined);

    // Parent continues after schedule: count := count + 1
    assert.equal(await contract.getGet(), 6n);
    {
      const data = await readDataCell(blockchain, address);
      assert.equal(parseStorage(data, 1).fields[0], 6n);
    }

    // Exactly one internal out-message from the parent contract tx.
    // (externals stay empty — schedule is createMessage, not createExternalLogMessage)
    const internals = internalOutMessages(tx);
    assert.equal(
      internals.length,
      1,
      `expected exactly one internal out-message, got ${internals.length}`,
    );
    assert.equal(
      (tx.externals?.length ?? 0),
      0,
      'schedule must not emit external-out',
    );

    const msg = internals[0];
    const info = msg.info;
    assert.equal(info.type, 'internal');
    // BounceMode.NoBounce → bounce flag false (non-bounceable)
    assert.equal(info.bounce, false, 'schedule bounce must be NoBounce/false');
    assert.equal(info.bounced, false);
    // MVP value = 0 (no GRAM attached; fees paid separately by send mode)
    assert.equal(info.value.coins, 0n, 'schedule value must be 0');
    // Dest = (0, SHA-256("ledger")) stub — NOT a live deployed account
    assert.ok(
      info.dest instanceof Address && info.dest.equals(EXPECTED_DEST),
      `dest must be stub 0:${LEDGER_DEST_HASH_HEX}, got ${info.dest}`,
    );
    assert.equal(info.dest.workChain, 0);

    // Body: op32 BE · query_id=0 · arg=5 (count at schedule site, pre-increment)
    const { op, queryId, args } = decodeScheduleBody(msg.body);
    assert.equal(
      op,
      DAILY_OP,
      `op must be first-4-BE of SHA-256("daily") = 0x${DAILY_OP.toString(16)}`,
    );
    assert.equal(queryId, 0n, 'query_id fixed 0 on MVP schedule');
    assert.equal(args.length, 1, 'exactly one UInt64 schedule arg');
    assert.equal(args[0], 5n, 'arg is count at schedule time (before +1)');
  });

  it('later() with init(0): body arg a0=0 still forms a valid schedule envelope', async () => {
    const { deployer, contract, address } = await deployFresh('ScheduleFlow');

    await contract.sendOp(
      deployer.getSender(),
      toNano('1'),
      buildBody(0, 1n, 0n),
      false,
    );

    const res = await contract.sendOp(
      deployer.getSender(),
      toNano('0.5'),
      buildBody(1, 2n),
      true,
    );

    const { tx, description } = contractGeneric(res, address);
    assert.equal(computeVm(description).success, true);
    assert.equal(await contract.getGet(), 1n);

    const internals = internalOutMessages(tx);
    assert.equal(internals.length, 1);
    const { op, queryId, args } = decodeScheduleBody(internals[0].body);
    assert.equal(op, DAILY_OP);
    assert.equal(queryId, 0n);
    assert.equal(args[0], 0n);
    assert.equal(internals[0].info.bounce, false);
    assert.equal(internals[0].info.value.coins, 0n);
    assert.ok(internals[0].info.dest.equals(EXPECTED_DEST));
  });
});

describe('Counter schedule-absence regression (no createMessage)', () => {
  it('increment has zero internal out-messages (no schedule emission path)', async () => {
    const { deployer, contract, address } = await deployFresh('Counter');

    await contract.sendOp(
      deployer.getSender(),
      toNano('1'),
      buildBody(0, 1n, 7n),
      false,
    );
    const res = await contract.sendOp(
      deployer.getSender(),
      toNano('0.5'),
      buildBody(1, 2n, 5n),
      true,
    );

    const { tx, description } = contractGeneric(res, address);
    assert.equal(computeVm(description).success, true);
    assert.equal(await contract.getGet(), 12n);

    const internals = internalOutMessages(tx);
    assert.equal(
      internals.length,
      0,
      `Counter must not emit createMessage/internal outs, got ${internals.length}`,
    );
  });
});
