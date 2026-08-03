/**
 * EventFlowTon engineering sandbox differential (TON-3).
 *
 * bump(n≤10): emit Moved external-out + bal+=n; get==bal.
 * bump(n>10): emit is rolled back with compute throw Cap (exit 200);
 *   state unchanged; bounce when bounceable.
 *
 * Five-phase assertions: compute / action / bounce separation, out-action count.
 * Not mainnet / formal Stage-0.
 */
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  buildBody,
  computeVm,
  contractGeneric,
  decodeEventBody,
  deployFresh,
  EXIT,
  parseStorage,
  readDataCell,
  toNano,
} from './helpers.js';

describe('EventFlowTon @ton/sandbox engineering differential', () => {
  it('bump(5): compute+action success, external Moved(0,5), get==5', async () => {
    const { blockchain, deployer, contract, address } =
      await deployFresh('EventFlowTon');

    await contract.sendOp(
      deployer.getSender(),
      toNano('1'),
      buildBody(0, 1n, 0n),
      false,
    );
    assert.equal(await contract.getGet(), 0n);

    const res = await contract.sendOp(
      deployer.getSender(),
      toNano('0.5'),
      buildBody(1, 2n, 5n),
      true,
    );

    const { tx, description } = contractGeneric(res, address);
    const vm = computeVm(description);
    assert.equal(vm.success, true);
    assert.equal(vm.exitCode, 0);
    assert.equal(description.aborted, false);

    // action phase: at least one out-action (external log)
    assert.ok(description.actionPhase, 'action phase present on success');
    assert.equal(description.actionPhase.success, true);
    assert.ok(
      (description.actionPhase.totalActions ?? 0) >= 1,
      `expected ≥1 out action, got ${description.actionPhase.totalActions}`,
    );
    assert.equal(description.bouncePhase, undefined);

    // result-level externals (sandbox aggregates external-out)
    assert.ok(res.externals.length >= 1, 'expected external out-message');
    const { eventIndex, args } = decodeEventBody(res.externals[0].body);
    assert.equal(eventIndex, 0, 'Moved is event index 0');
    assert.equal(args[0], 0n, 'src=bal before bump');
    assert.equal(args[1], 5n, 'dst=n');

    // tx.externals also populated on the contract transaction
    assert.ok((tx.externals?.length ?? 0) >= 1);

    assert.equal(await contract.getGet(), 5n);
    const data = await readDataCell(blockchain, address);
    assert.equal(parseStorage(data, 1).fields[0], 5n);
  });

  it('bump(11) bounceable: exit 200, no external, state unchanged, bounce ok', async () => {
    const { blockchain, deployer, contract, address } =
      await deployFresh('EventFlowTon');

    await contract.sendOp(
      deployer.getSender(),
      toNano('1'),
      buildBody(0, 1n, 3n),
      false,
    );
    // successful bump first
    await contract.sendOp(
      deployer.getSender(),
      toNano('0.5'),
      buildBody(1, 2n, 2n),
      true,
    );
    assert.equal(await contract.getGet(), 5n);
    const dataBefore = await readDataCell(blockchain, address);

    const res = await contract.sendOp(
      deployer.getSender(),
      toNano('0.5'),
      buildBody(1, 3n, 11n),
      /*bounce*/ true,
    );

    const { description } = contractGeneric(res, address);
    const vm = computeVm(description);
    assert.equal(vm.success, false);
    assert.equal(vm.exitCode, EXIT.userBase + 0); // Cap is error index 0 → 200
    assert.equal(description.aborted, true);
    // compute failure ⇒ action phase absent (queued emit discarded)
    assert.equal(description.actionPhase, undefined);
    assert.equal(description.bouncePhase?.type, 'ok');

    assert.equal(res.externals.length, 0, 'no external on aborted compute');
    const dataAfter = await readDataCell(blockchain, address);
    assert.ok(dataBefore.equals(dataAfter));
    assert.equal(await contract.getGet(), 5n);
  });

  it('bump(12) non-bounceable: exit 200, no bounce phase', async () => {
    const { deployer, contract, address } = await deployFresh('EventFlowTon');

    await contract.sendOp(
      deployer.getSender(),
      toNano('1'),
      buildBody(0, 1n, 0n),
      false,
    );

    const res = await contract.sendOp(
      deployer.getSender(),
      toNano('0.5'),
      buildBody(1, 4n, 12n),
      /*bounce*/ false,
    );

    const { description } = contractGeneric(res, address);
    const vm = computeVm(description);
    assert.equal(vm.exitCode, EXIT.userBase);
    assert.equal(description.aborted, true);
    assert.equal(description.bouncePhase, undefined);
    assert.equal(res.externals.length, 0);
    assert.equal(await contract.getGet(), 0n);
  });

  it('five-phase separation: success has compute+action; failure has compute+bounce only', async () => {
    const { deployer, contract, address } = await deployFresh('EventFlowTon');
    await contract.sendOp(
      deployer.getSender(),
      toNano('1'),
      buildBody(0, 1n, 0n),
      false,
    );

    const ok = await contract.sendOp(
      deployer.getSender(),
      toNano('0.5'),
      buildBody(1, 2n, 1n),
      true,
    );
    {
      const { description } = contractGeneric(ok, address);
      assert.equal(computeVm(description).success, true);
      assert.ok(description.actionPhase?.success);
      assert.equal(description.bouncePhase, undefined);
      assert.ok((description.actionPhase.totalActions ?? 0) >= 1);
    }

    const bad = await contract.sendOp(
      deployer.getSender(),
      toNano('0.5'),
      buildBody(1, 3n, 99n),
      true,
    );
    {
      const { description } = contractGeneric(bad, address);
      assert.equal(computeVm(description).success, false);
      assert.equal(description.actionPhase, undefined);
      assert.equal(description.bouncePhase?.type, 'ok');
    }
  });
});
