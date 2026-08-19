/**
 * Sha256BytesTon engineering sandbox differential (CAP-X-BYTES-TON-RT).
 *
 * deploy → probe(0x01, 0x02, 0x03, 0x04) → get == SHA-256(01 02 03 04).
 * Node crypto is the oracle. Not a UInt256 zero-word vector.
 * TON leaf is SHA256U over N unsigned byte bits (N=4 ≤ 127).
 *
 * Not mainnet / formal Stage-0 / keccak / N=127 runtime positive.
 */
import { createHash } from 'node:crypto';
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  buildBody,
  computeVm,
  contractGeneric,
  deployFresh,
  parseStorage,
  readDataCell,
  toNano,
} from './helpers.js';

const PROBE_BYTES = Uint8Array.from([0x01, 0x02, 0x03, 0x04]);
const EXPECTED = BigInt(
  '0x' + createHash('sha256').update(Buffer.from(PROBE_BYTES)).digest('hex'),
);

describe('Sha256BytesTon @ton/sandbox engineering differential', () => {
  it('probe(0x01,0x02,0x03,0x04) → get == SHA-256(01 02 03 04)', async () => {
    assert.notEqual(EXPECTED, 0n, 'oracle must not be the UInt256 zero word');

    const { blockchain, deployer, contract, address } = await deployFresh(
      'Sha256BytesTon',
      { fieldBits: [256] },
    );

    const initRes = await contract.sendOp(
      deployer.getSender(),
      toNano('1'),
      buildBody(/*op*/ 0, /*queryId*/ 1n),
      /*bounce*/ false,
    );
    {
      const { description } = contractGeneric(initRes, address);
      const vm = computeVm(description);
      assert.equal(vm.success, true);
      assert.equal(vm.exitCode, 0);
      assert.equal(description.aborted, false);
    }
    assert.equal(await contract.getGet(), 0n);

    const probeRes = await contract.sendOp(
      deployer.getSender(),
      toNano('0.5'),
      buildBody(/*op*/ 1, /*queryId*/ 2n, { bytes: PROBE_BYTES }),
      true,
    );
    {
      const { description } = contractGeneric(probeRes, address);
      const vm = computeVm(description);
      assert.equal(vm.success, true);
      assert.equal(vm.exitCode, 0);
      assert.equal(description.aborted, false);
      assert.ok(description.actionPhase?.success);
    }

    const got = await contract.getGet();
    assert.equal(got, EXPECTED);

    const data = await readDataCell(blockchain, address);
    const { layout, fields } = parseStorage(data, 1, 256);
    assert.notEqual(layout, 0n, 'layout marker written on init');
    assert.equal(fields[0], EXPECTED);
  });
});
