/**
 * StateCell engineering sandbox differential (TON-3).
 *
 * init(7) → increment(delta=5) → get == 12; c4 data matches.
 * overflow → exit 100; state unchanged; bounce phase when bounceable.
 *
 * Not mainnet / formal Stage-0 / TST-SEM-002/003.
 */
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  buildBody,
  computeVm,
  contractGeneric,
  contractTxs,
  deployFresh,
  EXIT,
  parseStorage,
  readDataCell,
  toNano,
} from './helpers.js';

describe('StateCell @ton/sandbox engineering differential', () => {
  it('init(7) + increment(5) → compute exit 0, get==12, c4 count==12', async () => {
    const { blockchain, deployer, contract, address } =
      await deployFresh('StateCell');

    const initRes = await contract.sendOp(
      deployer.getSender(),
      toNano('1'),
      buildBody(/*op*/ 0, /*queryId*/ 1n, /*initial*/ 7n),
      /*bounce*/ false,
    );
    {
      const { description } = contractGeneric(initRes, address);
      const vm = computeVm(description);
      assert.equal(vm.success, true);
      assert.equal(vm.exitCode, 0);
      assert.equal(description.aborted, false);
      assert.ok(description.actionPhase?.success);
    }

    assert.equal(await contract.getGet(), 7n);
    {
      const data = await readDataCell(blockchain, address);
      const { layout, fields } = parseStorage(data, 1);
      assert.notEqual(layout, 0n, 'layout marker written on init');
      assert.equal(fields[0], 7n);
    }

    const incRes = await contract.sendOp(
      deployer.getSender(),
      toNano('0.5'),
      buildBody(/*op*/ 1, /*queryId*/ 2n, /*delta*/ 5n),
      true,
    );
    {
      const { description } = contractGeneric(incRes, address);
      const vm = computeVm(description);
      assert.equal(vm.success, true);
      assert.equal(vm.exitCode, 0);
      assert.equal(description.aborted, false);
      // five-phase: compute success + action success; no bounce on happy path
      assert.ok(description.actionPhase?.success);
      assert.equal(description.bouncePhase, undefined);
    }

    assert.equal(await contract.getGet(), 12n);
    {
      const data = await readDataCell(blockchain, address);
      const { fields } = parseStorage(data, 1);
      assert.equal(fields[0], 12n);
    }
  });

  it('overflow increment → exit 100, state unchanged, bounce ok when bounceable', async () => {
    const { blockchain, deployer, contract, address } =
      await deployFresh('StateCell');

    await contract.sendOp(
      deployer.getSender(),
      toNano('1'),
      buildBody(0, 1n, 7n),
      false,
    );
    await contract.sendOp(
      deployer.getSender(),
      toNano('0.5'),
      buildBody(1, 2n, 5n),
      true,
    );
    assert.equal(await contract.getGet(), 12n);

    const dataBefore = await readDataCell(blockchain, address);
    const maxU64 = (1n << 64n) - 1n;

    const ovf = await contract.sendOp(
      deployer.getSender(),
      toNano('0.5'),
      buildBody(1, 3n, maxU64),
      /*bounce*/ true,
    );

    const { description } = contractGeneric(ovf, address);
    const vm = computeVm(description);
    assert.equal(vm.success, false);
    assert.equal(vm.exitCode, EXIT.overflow);
    assert.equal(description.aborted, true);
    // action phase skipped on compute failure
    assert.equal(description.actionPhase, undefined);
    // bounce phase present for bounceable inbound
    assert.equal(description.bouncePhase?.type, 'ok');

    const dataAfter = await readDataCell(blockchain, address);
    assert.ok(dataBefore.equals(dataAfter), 'c4 data must not change on overflow');
    assert.equal(await contract.getGet(), 12n);

    // treasury receives bounce (extra tx after contract)
    assert.ok(
      ovf.transactions.length >= 2,
      `expected bounce cascade, got ${ovf.transactions.length} txs`,
    );
  });

  it('overflow non-bounceable → exit 100, no bounce phase, state unchanged', async () => {
    const { blockchain, deployer, contract, address } =
      await deployFresh('StateCell');

    await contract.sendOp(
      deployer.getSender(),
      toNano('1'),
      buildBody(0, 1n, 12n),
      false,
    );
    const dataBefore = await readDataCell(blockchain, address);
    const maxU64 = (1n << 64n) - 1n;

    const ovf = await contract.sendOp(
      deployer.getSender(),
      toNano('0.5'),
      buildBody(1, 9n, maxU64),
      /*bounce*/ false,
    );

    const { description } = contractGeneric(ovf, address);
    const vm = computeVm(description);
    assert.equal(vm.exitCode, EXIT.overflow);
    assert.equal(description.aborted, true);
    assert.equal(description.bouncePhase, undefined);

    const dataAfter = await readDataCell(blockchain, address);
    assert.ok(dataBefore.equals(dataAfter));
    assert.equal(await contract.getGet(), 12n);

    // Only treasury + contract (no bounce return)
    const cTxs = contractTxs(ovf, address);
    assert.equal(cTxs.length, 1);
  });
});
