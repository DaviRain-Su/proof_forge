/**
 * Controlled template renderer for the rwa-share-v1 vertical.
 * Text must stay in sync with src/RwaShareRegistry.lean (the golden source);
 * if they drift, the machine gate fails loudly — that is the intended alarm.
 */

export type ShareFields = {
  assetName: string;
  totalSupply: string;
  maxPerTx: string;
  windowBlocks: string;
  windowCap: string;
};

export function sanitizeIdent(raw: string, fallback: string): string {
  const cleaned = raw.trim().replace(/[^A-Za-z0-9_]/g, "");
  if (!cleaned || !/^[A-Za-z_]/.test(cleaned)) return fallback;
  return cleaned;
}

const GOLDEN = `import ProofForgeV2

namespace Proofship

open ProofForgeV2.Language

-- ProofShip rwa-share-v1 share registry with transfer policy.
-- Generated from the controlled template; policy values arrive as ctor args.
program __PROGRAM__ where
  state owner : Principal
  state totalSupply : UInt64
  state issued : UInt64
  state balance : Map Principal UInt64
  state allowlist : Map Principal UInt64
  state maxPerTx : UInt64
  state windowCap : UInt64
  state windowStart : UInt64
  state windowSpent : UInt64

  event Issued(amount : UInt64)
  event Transferred(amount : UInt64)

  error NotAllowed()
  error InsufficientBalance()

  init(supply : UInt64, perTx : UInt64, window : UInt64) do
    owner := context.caller
    totalSupply := supply
    issued := 0
    balance := Map.empty()
    allowlist := Map.empty()
    maxPerTx := perTx
    windowCap := window
    windowStart := context.blockHeight
    windowSpent := 0

  entry setAllow(who : Principal, ok : UInt64) : UInt64 do
    assert context.caller == owner
    assert ok <= 1
    allowlist[who] := ok
    return ok

  entry issue(to : Principal, amount : UInt64) : UInt64 do
    assert context.caller == owner
    assert issued + amount <= totalSupply
    match balance[to] with
    | Option.some(v) => do
      balance[to] := v + amount
      issued := issued + amount
      emit Issued(amount)
      return issued
    | _ => do
      balance[to] := amount
      issued := issued + amount
      emit Issued(amount)
      return issued

  entry transfer(to : Principal, amount : UInt64) : UInt64 do
    assert amount <= maxPerTx
    match allowlist[to] with
    | Option.some(flag) => do
      assert flag == 1
      if windowStart + __WINDOW_BLOCKS__ <= context.blockHeight then
        windowStart := context.blockHeight
        windowSpent := 0
      assert windowSpent + amount <= windowCap
      match balance[context.caller] with
      | Option.some(bal) => do
        assert amount <= bal
        match balance[to] with
        | Option.some(tb) => do
          balance[context.caller] := bal - amount
          balance[to] := tb + amount
          windowSpent := windowSpent + amount
          emit Transferred(amount)
          return windowSpent
        | _ => do
          balance[context.caller] := bal - amount
          balance[to] := amount
          windowSpent := windowSpent + amount
          emit Transferred(amount)
          return windowSpent
      | _ => do
        revert InsufficientBalance()
    | _ => do
      revert NotAllowed()

  view balanceOf(who : Principal) : UInt64 do
    match balance[who] with
    | Option.some(v) => do
      return v
    | _ => do
      return 0

  view isAllowed(who : Principal) : Bool do
    match allowlist[who] with
    | Option.some(flag) => do
      return flag == 1
    | _ => do
      return false

  view issuedTotal() : UInt64 do
    return issued

  view policy() : UInt64 do
    return maxPerTx

end Proofship
`;

export function renderProgram(fields: ShareFields): { program: string; source: string } {
  const program = sanitizeIdent(fields.assetName, "RwaShareRegistry");
  const windowBlocks = /^[0-9]+$/.test(fields.windowBlocks) ? fields.windowBlocks : "1000";
  const source = GOLDEN.replaceAll("__PROGRAM__", program).replaceAll(
    "__WINDOW_BLOCKS__",
    windowBlocks,
  );
  return { program, source };
}

/** Local NL → fields extraction (the full product path is a code agent over MCP). */
export function extractFields(nl: string): ShareFields {
  const num = (re: RegExp): string | null => {
    const m = nl.replace(/[,_]/g, "").match(re);
    return m?.[1] ?? null;
  };
  return {
    assetName: nl.includes("发票") ? "InvoiceShare" : "RwaShareRegistry",
    totalSupply: num(/总量[^0-9]{0,6}([0-9]{1,20})/) ?? "1000000",
    maxPerTx: num(/单笔[^0-9]{0,8}([0-9]{1,20})/) ?? "50000",
    windowBlocks: num(/([0-9]{1,10})\s*(?:个)?块/) ?? "1000",
    windowCap: num(/(?:累计|窗口内)[^0-9]{0,8}([0-9]{1,20})/) ?? "100000",
  };
}
