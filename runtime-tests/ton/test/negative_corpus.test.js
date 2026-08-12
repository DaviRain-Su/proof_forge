/**
 * StateCell/Counter-shaped negative corpus — bad body / unknown op honesty (TON).
 *
 * Product Tolk emitter (ton-tolk-boc-v1) pins:
 *   - body.remainingBits < 96 → early return (no throw; bounce-safe)
 *   - unknown op → ignore / no throw (bounce-safe)
 *   - known op with truncated param → loadUint fails (compute abort)
 *   - overflow → exit 100 + state hold
 *
 * Complements state_cell.test.js. Engineering @ton/sandbox only —
 * not mainnet / formal Stage-0. Do not claim "unknown op reverts".
 */
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  beginCell,
  buildBody,
  computeVm,
  contractGeneric,
  deployFresh,
  EXIT,
  readDataCell,
  toNano,
} from './helpers.js';

/** Body with op + query_id only (no params). ≥96 bits → enters dispatch. */
function headerOnly(op, queryId) {
  return beginCell()
    .storeUint(BigInt(op), 32)
    .storeUint(BigInt(queryId), 64)
    .endCell();
}

/** Body with op + query_id + partial u64 (32 bits) — truncated param. */
function truncatedParam(op, queryId, half) {
  return beginCell()
    .storeUint(BigInt(op), 32)
    .storeUint(BigInt(queryId), 64)
    .storeUint(BigInt(half), 32)
    .endCell();
}

describe('StateCell negative corpus (@ton/sandbox)', () => {
  it('unknown op is ignored (no throw); state holds; recovery works', async () => {
    // Honesty pin: emitter comment "Unknown op: ignore (no throw) for bounce safety."
    const { blockchain, deployer, contract, address } =
      await deployFresh('StateCell');

    await contract.sendOp(
      deployer.getSender(),
      toNano('1'),
      buildBody(0, 1n, 7n),
      false,
    );
    assert.equal(await contract.getGet(), 7n);
    const dataBefore = await readDataCell(blockchain, address);

    const bad = await contract.sendOp(
      deployer.getSender(),
      toNano('0.5'),
      buildBody(/*unknown op*/ 99, 2n, 1n),
      true,
    );
    {
      const { description } = contractGeneric(bad, address);
      const vm = computeVm(description);
      // Must not abort / throw — silent ignore is the product contract.
      assert.equal(vm.success, true, 'unknown op must ignore (not throw)');
      assert.equal(vm.exitCode, 0);
      assert.equal(description.aborted, false);
    }

    const dataAfter = await readDataCell(blockchain, address);
    assert.ok(dataBefore.equals(dataAfter), 'c4 must not change on unknown op');
    assert.equal(await contract.getGet(), 7n);

    // Recovery
    const ok = await contract.sendOp(
      deployer.getSender(),
      toNano('0.5'),
      buildBody(1, 3n, 5n),
      true,
    );
    {
      const { description } = contractGeneric(ok, address);
      const vm = computeVm(description);
      assert.equal(vm.success, true);
      assert.equal(vm.exitCode, 0);
    }
    assert.equal(await contract.getGet(), 12n);
  });

  it('increment with missing u64 param aborts; state holds', async () => {
    // header-only has ≥96 bits so dispatch enters op==1 then loadUint(64) fails.
    const { blockchain, deployer, contract, address } =
      await deployFresh('StateCell');

    await contract.sendOp(
      deployer.getSender(),
      toNano('1'),
      buildBody(0, 1n, 7n),
      false,
    );
    const dataBefore = await readDataCell(blockchain, address);

    const short = await contract.sendOp(
      deployer.getSender(),
      toNano('0.5'),
      headerOnly(/*increment*/ 1, 2n),
      true,
    );
    {
      const { description } = contractGeneric(short, address);
      const vm = computeVm(description);
      assert.equal(vm.success, false, 'header-only increment must fail load');
      assert.notEqual(vm.exitCode, 0);
      assert.equal(description.aborted, true);
    }

    const dataAfter = await readDataCell(blockchain, address);
    assert.ok(dataBefore.equals(dataAfter), 'c4 must not change on short body');
    assert.equal(await contract.getGet(), 7n);
  });

  it('increment with truncated u64 param aborts; state holds', async () => {
    const { blockchain, deployer, contract, address } =
      await deployFresh('StateCell');

    await contract.sendOp(
      deployer.getSender(),
      toNano('1'),
      buildBody(0, 1n, 12n),
      false,
    );
    const dataBefore = await readDataCell(blockchain, address);

    const trunc = await contract.sendOp(
      deployer.getSender(),
      toNano('0.5'),
      truncatedParam(1, 4n, 0x12345678),
      true,
    );
    {
      const { description } = contractGeneric(trunc, address);
      const vm = computeVm(description);
      assert.equal(vm.success, false, 'truncated param must fail');
      assert.notEqual(vm.exitCode, 0);
      assert.equal(description.aborted, true);
    }

    const dataAfter = await readDataCell(blockchain, address);
    assert.ok(dataBefore.equals(dataAfter));
    assert.equal(await contract.getGet(), 12n);
  });

  it('empty / sub-header body early-returns (no throw); state holds', async () => {
    // Honesty pin: remainingBits < 96 → return; bounce-safe, not a trap.
    const { blockchain, deployer, contract, address } =
      await deployFresh('StateCell');

    await contract.sendOp(
      deployer.getSender(),
      toNano('1'),
      buildBody(0, 1n, 7n),
      false,
    );
    const dataBefore = await readDataCell(blockchain, address);

    const empty = await contract.sendOp(
      deployer.getSender(),
      toNano('0.5'),
      beginCell().endCell(),
      true,
    );
    {
      const { description } = contractGeneric(empty, address);
      const vm = computeVm(description);
      assert.equal(vm.success, true, 'empty body early-return must not throw');
      assert.equal(vm.exitCode, 0);
      assert.equal(description.aborted, false);
    }

    // Partial header only (32-bit op, no query_id) — still < 96 bits.
    const partial = await contract.sendOp(
      deployer.getSender(),
      toNano('0.5'),
      beginCell().storeUint(1n, 32).endCell(),
      true,
    );
    {
      const { description } = contractGeneric(partial, address);
      const vm = computeVm(description);
      assert.equal(vm.success, true, 'sub-header body early-return must not throw');
      assert.equal(vm.exitCode, 0);
    }

    const dataAfter = await readDataCell(blockchain, address);
    assert.ok(dataBefore.equals(dataAfter));
    assert.equal(await contract.getGet(), 7n);
  });

  it('overflow exit 100 remains pinned (corpus cross-check)', async () => {
    const { blockchain, deployer, contract, address } =
      await deployFresh('StateCell');

    await contract.sendOp(
      deployer.getSender(),
      toNano('1'),
      buildBody(0, 1n, 7n),
      false,
    );
    const dataBefore = await readDataCell(blockchain, address);
    const maxU64 = (1n << 64n) - 1n;

    const ovf = await contract.sendOp(
      deployer.getSender(),
      toNano('0.5'),
      buildBody(1, 9n, maxU64),
      true,
    );
    {
      const { description } = contractGeneric(ovf, address);
      const vm = computeVm(description);
      assert.equal(vm.exitCode, EXIT.overflow);
      assert.equal(description.aborted, true);
    }
    const dataAfter = await readDataCell(blockchain, address);
    assert.ok(dataBefore.equals(dataAfter));
    assert.equal(await contract.getGet(), 7n);
  });
});
