# ADR-0030 E1a — EVM Runtime Gate Scenarios (TokenJar + ERC-20 Mock)

This document describes the Anvil runtime differential for the E1a
`pf.assets.token.transfer` EVM binding (ERC-20 `transfer(address,uint256)`,
controlled dynamic callee). It is a **main-agent merge concern** — the worker
lane does not execute Anvil (no Foundry on this host by default).

## Components

* `ERC20Mock.sol` — minimal ERC-20 mock compiled with locked solc 0.8.34.
  Supports:
  - `mint(to, amount)` — mint tokens
  - `balanceOf(addr)` — read balance (public mapping)
  - `transfer(to, amount)` — standard bool-return + two non-standard modes:
    - `setNoReturnMode(true)` → USDT-style (no return data, `returndatasize==0`)
    - `setReturnFalseMode(true)` → returns `false` on insufficient balance

* `Examples/TokenJar.lean` — product source: `tipToken(mint, dst, amount)`
  calls `pf.assets.token.transfer(mint, dst, amount)` + increments `tips`.

## Build

```bash
# Build TokenJar EVM artifact via product CLI
lake build proof_forge_next
.lake/build/bin/proof-forge-next build Examples/TokenJar.lean \
  --module Examples.TokenJar --target evm -o build/v2/tokenjar-evm

# Compile ERC20Mock.sol with locked solc
solc --bin --abi runtime-tests/evm/ERC20Mock.sol -o build/v2/erc20mock
```

## Anvil Scenario Matrix

Start Anvil: `anvil --port 8545 --silent`

### 1. Deploy
- Deploy `ERC20Mock` (constructor no args).
- Deploy `TokenJar` with `initial=0` (constructor `uint64` arg = 0).

### 2. Happy path: tipToken transfers ERC-20 from contract balance
- `ERC20Mock.mint(TokenJar.address, 2000)` — give TokenJar 2000 tokens.
- Verify `ERC20Mock.balanceOf(TokenJar.address) == 2000`.
- `TokenJar.tipToken(ERC20Mock.address, dstAddr, 1000)` —
  Principal args: mint=ERC20Mock address (20B), dst=dstAddr (20B), amount=1000.
- Assert `ERC20Mock.balanceOf(dstAddr) == 1000` (dst received).
- Assert `ERC20Mock.balanceOf(TokenJar.address) == 1000` (contract spent).
- Assert `TokenJar.get() == 1000` (tips counter incremented).

### 3. Negative: insufficient contract balance → revert
- `TokenJar.tipToken(ERC20Mock.address, dstAddr, 5000)` — contract has 1000,
  transfer needs 5000.
- Transaction must revert (ERC-20 `transfer` reverts on insufficient balance).
- Assert `TokenJar.get() == 1000` (state unchanged — failure propagated).
- Assert `ERC20Mock.balanceOf(TokenJar.address) == 1000` (balance unchanged).

### 4. Negative: false return → revert (TokenJar return-value predicate)
- Set `ERC20Mock.setReturnFalseMode(true)`.
- `TokenJar.tipToken(ERC20Mock.address, dstAddr, 1000)` — contract has 1000,
  ERC-20 returns `false` (bool false).
- Transaction must revert (TokenJar's return-value predicate checks
  `returndatasize==32` → first word must be nonzero; false=0 → revert).
- Assert `TokenJar.get() == 1000` (state unchanged).
- Assert `ERC20Mock.balanceOf(TokenJar.address) == 1000` (balance unchanged).
- Reset: `ERC20Mock.setReturnFalseMode(false)`.

### 5. USDT-style no-return → success path
- Set `ERC20Mock.setNoReturnMode(true)`.
- `TokenJar.tipToken(ERC20Mock.address, dstAddr, 500)` — ERC-20 returns
  nothing (`returndatasize==0`).
- TokenJar's return-value predicate accepts `returndatasize==0` as success.
- Assert `ERC20Mock.balanceOf(dstAddr) == 1500` (received 1000 + 500).
- Assert `ERC20Mock.balanceOf(TokenJar.address) == 500`.
- Assert `TokenJar.get() == 1500` (tips incremented).
- Reset: `ERC20Mock.setNoReturnMode(false)`.

### 6. Wire-shape negative: mint Principal len != 20 → revert
- `TokenJar.tipToken` with mint Principal body length 21 (or any != 20).
- Transaction must revert (Principal wire-shape gate).
- Assert state unchanged.

### 7. Wire-shape negative: dst Principal high limb nonzero → revert
- `TokenJar.tipToken` with dst Principal having a nonzero high limb (w3..w7).
- Transaction must revert (high-limb zero gate).
- Assert state unchanged.

## Principal ABI encoding

TokenJar entry `tipToken(mint, dst, amount)` has 3 Principal + 1 UInt64 params.
Each Principal is 9 ABI words: len + 8×LE body words. For a 20-byte address:

```
len = 20
w0 = LE bytes[0:8]
w1 = LE bytes[8:16]
w2 = LE bytes[16:20]  (high 32 bits must be 0)
w3..w7 = 0
```

The cast command for `tipToken`:
```
cast send --rpc-url $rpc --private-key $pk $tokenjar \
  "tipToken(uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64)" \
  <mint_len> <mint_w0> ... <mint_w7> \
  <dst_len> <dst_w0> ... <dst_w7> \
  <amount>
```

## Notes

- Engineering only: not formal Reference↔Anvil; no OZ/family credit.
- The ERC-20 mock is intentionally minimal — it does not implement
  `transferFrom`/`approve` (not needed for E1a which uses `transfer` only).
- `decimals` is 18 (standard) but TokenJar does not check decimals (that's a
  NetworkProfile asset registry concern, not a Plan lowering concern).