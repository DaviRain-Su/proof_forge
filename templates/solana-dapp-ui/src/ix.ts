/**
 * ProofForge Solana instruction data encoding (product CPI/ELF rail).
 *
 * Layout (from PF sBPF entrypoint comments / runtime harnesses):
 *   handlerId : u64 little-endian
 *   params... : each non-Principal scalar as u64 little-endian
 *               (UInt8/16/32 zero-extended into u64)
 *
 * This is **not** Anchor 8-byte sighash discriminator.
 * Source of truth: `pf build -t solana` → `*.idl.json` handlerId + local pf/Mollusk.
 */

export function encodePfIxData(handlerId: number, params: bigint[] = []): Uint8Array {
  if (!Number.isInteger(handlerId) || handlerId < 0) {
    throw new Error(`invalid handlerId ${handlerId}`);
  }
  const out = new Uint8Array(8 + params.length * 8);
  const view = new DataView(out.buffer);
  view.setBigUint64(0, BigInt(handlerId), true);
  params.forEach((p, i) => {
    if (p < 0n || p > 0xffff_ffff_ffff_ffffn) {
      throw new Error(`param[${i}] out of u64 range`);
    }
    view.setBigUint64(8 + i * 8, p, true);
  });
  return out;
}

/** Read first u64 LE from program-owned state account data (StateCell count leaf). */
export function readU64Le(data: Uint8Array, offset = 0): bigint {
  if (data.length < offset + 8) throw new Error("account data too short for u64");
  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  return view.getBigUint64(offset, true);
}
