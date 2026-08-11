/**
 * ADR-0025 Principal wire encoding for the PF EVM ABI:
 * a 20-byte address becomes 9 uint64 leaves:
 *   len = 20, w0/w1 = LE first/next 8 bytes, w2 = LE last 4 bytes, w3..w7 = 0.
 * Must stay byte-identical with scripts/anvil-check.sh principal_words_from_addr.
 */
export function principalWords(address: string): bigint[] {
  const hex = address.trim().toLowerCase().replace(/^0x/, "");
  if (!/^[0-9a-f]{40}$/.test(hex)) {
    throw new Error(`bad address: ${address}`);
  }
  const bytes = new Uint8Array(20);
  for (let i = 0; i < 20; i += 1) {
    bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  const le = (offset: number, len: number): bigint => {
    let v = 0n;
    for (let i = len - 1; i >= 0; i -= 1) {
      v = (v << 8n) | BigInt(bytes[offset + i] ?? 0);
    }
    return v;
  };
  return [20n, le(0, 8), le(8, 8), le(16, 4), 0n, 0n, 0n, 0n, 0n];
}

export function parseAmount(raw: string, label: string): bigint {
  const cleaned = raw.trim().replace(/[,_]/g, "");
  if (!/^[0-9]+$/.test(cleaned)) throw new Error(`bad ${label}: ${raw}`);
  return BigInt(cleaned);
}
