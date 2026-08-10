/**
 * ProofForge Solana body-only (S1b) instruction encoding.
 *
 * Discriminator (8 bytes) =
 *   first 8 bytes of sha256("proof-forge-solana-v1:" ++ name ++ "(" ++ types ++ ")")
 * where types are "u64" joined by comma (one per scalar param).
 *
 * Then each non-Principal scalar param as u64 little-endian.
 *
 * Initializer callables use disc name `initialize` (not source `init`).
 *
 * CPI-product programs (TransferSol etc.) use handlerId u64 LE instead —
 * see pf_solana_ix_codec / profile. This UI targets StateCell-shaped body-only.
 *
 * StateCell account data layout (ordinary single-field body-only):
 *   bytes[0..8]  = layout marker (non-zero when initialized)
 *   bytes[8..16] = count u64 LE
 */

const DISC_DOMAIN = "proof-forge-solana-v1:";

/** StateCell / single-field ordinary state: 8-byte layout marker then fields. */
export const STATE_HEADER_BYTES = 8;
export const STATECELL_COUNT_OFFSET = STATE_HEADER_BYTES;

async function sha256(bytes: Uint8Array): Promise<Uint8Array> {
  // Copy into a fresh ArrayBuffer so TS DOM lib accepts BufferSource under
  // stricter ArrayBuffer vs SharedArrayBuffer typing (TS 5.x + vite).
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  const buf = await crypto.subtle.digest("SHA-256", copy);
  return new Uint8Array(buf);
}

export async function instructionDiscriminator(
  name: string,
  paramCount: number,
): Promise<Uint8Array> {
  const types = Array.from({ length: paramCount }, () => "u64").join(",");
  const preimage = `${DISC_DOMAIN}${name}(${types})`;
  const digest = await sha256(new TextEncoder().encode(preimage));
  return digest.slice(0, 8);
}

/** Map IDL instruction → disc name used by S1b emitter. */
export function discNameForIx(ix: { name: string; mode?: string }): string {
  const mode = (ix.mode ?? "").toLowerCase();
  if (mode === "initialize" || mode === "initializer" || ix.name === "init") {
    return "initialize";
  }
  return ix.name;
}

export async function encodePfIxData(
  ix: { name: string; mode?: string; handlerId?: number },
  params: bigint[] = [],
): Promise<Uint8Array> {
  const disc = await instructionDiscriminator(discNameForIx(ix), params.length);
  const out = new Uint8Array(8 + params.length * 8);
  out.set(disc, 0);
  const view = new DataView(out.buffer);
  params.forEach((p, i) => {
    if (p < 0n || p > 0xffff_ffff_ffff_ffffn) {
      throw new Error(`param[${i}] out of u64 range`);
    }
    view.setBigUint64(8 + i * 8, p, true);
  });
  return out;
}

/** Read u64 LE from account data at offset. */
export function readU64Le(data: Uint8Array, offset = 0): bigint {
  if (data.length < offset + 8) throw new Error("account data too short for u64");
  // Copy slice so DataView does not depend on SharedArrayBuffer-backed views.
  const slice = data.slice(offset, offset + 8);
  const view = new DataView(slice.buffer, slice.byteOffset, slice.byteLength);
  return view.getBigUint64(0, true);
}

/** StateCell count leaf (after 8-byte layout marker). */
export function readStateCellCount(data: Uint8Array): bigint {
  if (data.length < STATECELL_COUNT_OFFSET + 8) {
    throw new Error(`StateCell data too short: ${data.length}`);
  }
  return readU64Le(data, STATECELL_COUNT_OFFSET);
}
