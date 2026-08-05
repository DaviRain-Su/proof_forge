#!/usr/bin/env python3
"""NEAR near-sandbox engineering runtime differential (BL-13 / BL-20 / BL-30).

Suites:
  counter     — Examples/Counter: init / increment / get + overflow state-hold
  pairret     — fixtures/PairRet: named Struct aggregate return (N×8 LE)
  arrayret    — fixtures/ArrayRet: anonymous Array UInt64 2 return (N×8 LE)
  optionret   — fixtures/OptionRet: anonymous Option UInt64 none/some (2×8 LE)
  optionstate — fixtures/OptionState: Option UInt64 state tag+payload (BL-30)

Env (set by scripts/near_runtime_test.sh):
  PF_NEAR_RPC          e.g. http://127.0.0.1:PORT
  PF_NEAR_HOME         near-sandbox --home directory (validator_key.json)
  PF_NEAR_WASM         path to product .wasm for the suite
  PF_NEAR_SUITE        counter | pairret | arrayret | optionret | optionstate | tipjarasync | tokenjarasync | envreadjar | single

Honesty: engineering sandbox differential only — not testnet/mainnet,
not formal Stage-0 / hermetic / Reference↔sandbox closure.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

from near_rpc import NearClient, NearRpcError


def _require_env(name: str) -> str:
    v = os.environ.get(name, "").strip()
    if not v:
        raise SystemExit(f"near-runtime: missing env {name}")
    return v


def suite_counter(client: NearClient, wasm: Path) -> None:
    print("=== suite: Counter (init/increment/get + overflow state-hold) ===")
    client.deploy(wasm)

    # init(7)
    client.call("init", NearClient.encode_u64_le(7))
    got = client.view_u64("get")
    if got != 7:
        raise AssertionError(f"after init(7): get() expected 7, got {got}")
    print("counter: init(7) → get()==7 ok")

    # increment(5) → 12
    inc = client.call("increment", NearClient.encode_u64_le(5))
    sv = NearClient.success_value_bytes(inc)
    if sv is not None and len(sv) >= 8:
        ret = NearClient.decode_u64_le(sv, 0)
        if ret != 12:
            raise AssertionError(f"increment(5) SuccessValue expected 12, got {ret}")
        print(f"counter: increment(5) SuccessValue=={ret} ok")
    got = client.view_u64("get")
    if got != 12:
        raise AssertionError(f"after increment(5): get() expected 12, got {got}")
    print("counter: get()==12 ok")

    # Overflow: count=12 + (2^64-1) must fail; state must NOT advance.
    max_u64 = (1 << 64) - 1
    client.call(
        "increment",
        NearClient.encode_u64_le(max_u64),
        expect_success=False,
    )
    got = client.view_u64("get")
    if got != 12:
        raise AssertionError(
            f"after overflow increment: get() must stay 12 (state hold), got {got}"
        )
    print("counter: overflow increment fails + state holds at 12 ok")

    # Second successful increment still works after failed overflow.
    client.call("increment", NearClient.encode_u64_le(1))
    got = client.view_u64("get")
    if got != 13:
        raise AssertionError(f"after post-overflow increment(1): get() expected 13, got {got}")
    print("counter: post-overflow increment(1) → get()==13 ok")
    print("suite Counter: PASS")


def suite_pairret(client: NearClient, wasm: Path) -> None:
    print("=== suite: PairRet (named Struct aggregate N×8 LE return) ===")
    client.deploy(wasm)

    # init(3, 5) — two packed LE u64 args
    init_args = NearClient.encode_u64_le(3) + NearClient.encode_u64_le(5)
    client.call("init", init_args)

    a, b = client.view_u64_pair("getPair")
    if (a, b) != (3, 5):
        raise AssertionError(f"after init(3,5): getPair expected (3,5), got ({a},{b})")
    print("pairret: init(3,5) → getPair()==(3,5) ok")

    # setPair(11, 22) mutates + returns 16-byte aggregate
    set_args = NearClient.encode_u64_le(11) + NearClient.encode_u64_le(22)
    set_res = client.call("setPair", set_args)
    sv = NearClient.success_value_bytes(set_res)
    if sv is None or len(sv) < 16:
        raise AssertionError(
            f"setPair SuccessValue expected ≥16 LE bytes, got {sv!r}"
        )
    ra, rb = NearClient.decode_u64_le(sv, 0), NearClient.decode_u64_le(sv, 8)
    if (ra, rb) != (11, 22):
        raise AssertionError(f"setPair SuccessValue expected (11,22), got ({ra},{rb})")
    print(f"pairret: setPair(11,22) SuccessValue==({ra},{rb}) ok")

    a, b = client.view_u64_pair("getPair")
    if (a, b) != (11, 22):
        raise AssertionError(f"after setPair: getPair expected (11,22), got ({a},{b})")
    raw = client.view("getPair")
    if len(raw) < 16:
        raise AssertionError(f"getPair raw length expected ≥16, got {len(raw)}")
    # Exact 16-byte layout check (product ABI: 2× u64-le, no trailing junk required
    # beyond first 16; accept exact or longer host padding).
    if raw[:16] != NearClient.encode_u64_le(11) + NearClient.encode_u64_le(22):
        raise AssertionError(f"getPair raw LE bytes mismatch: {raw[:16].hex()}")
    print("pairret: getPair() raw 16 LE bytes == 0b0b.. / 0x16.. ok")
    print("suite PairRet: PASS")


def suite_arrayret(client: NearClient, wasm: Path) -> None:
    print("=== suite: ArrayRet (anonymous Array UInt64 2 → N×8 LE return) ===")
    client.deploy(wasm)

    init_args = NearClient.encode_u64_le(7) + NearClient.encode_u64_le(9)
    client.call("init", init_args)

    a, b = client.view_u64_pair("getArr")
    if (a, b) != (7, 9):
        raise AssertionError(f"after init(7,9): getArr expected (7,9), got ({a},{b})")
    print("arrayret: init(7,9) → getArr()==(7,9) ok")

    set_args = NearClient.encode_u64_le(11) + NearClient.encode_u64_le(22)
    set_res = client.call("setArr", set_args)
    sv = NearClient.success_value_bytes(set_res)
    if sv is None or len(sv) < 16:
        raise AssertionError(
            f"setArr SuccessValue expected ≥16 LE bytes, got {sv!r}"
        )
    ra, rb = NearClient.decode_u64_le(sv, 0), NearClient.decode_u64_le(sv, 8)
    if (ra, rb) != (11, 22):
        raise AssertionError(f"setArr SuccessValue expected (11,22), got ({ra},{rb})")
    print(f"arrayret: setArr(11,22) SuccessValue==({ra},{rb}) ok")

    a, b = client.view_u64_pair("getArr")
    if (a, b) != (11, 22):
        raise AssertionError(f"after setArr: getArr expected (11,22), got ({a},{b})")
    raw = client.view("getArr")
    if len(raw) < 16:
        raise AssertionError(f"getArr raw length expected ≥16, got {len(raw)}")
    if raw[:16] != NearClient.encode_u64_le(11) + NearClient.encode_u64_le(22):
        raise AssertionError(f"getArr raw LE bytes mismatch: {raw[:16].hex()}")
    print("arrayret: getArr() raw 16 LE bytes ok")
    print("suite ArrayRet: PASS")


def suite_optionret(client: NearClient, wasm: Path) -> None:
    print("=== suite: OptionRet (anonymous Option UInt64 none/some → 2×8 LE) ===")
    client.deploy(wasm)

    client.call("init", NearClient.encode_u64_le(42))

    tag, payload = client.view_u64_pair("asNone")
    if (tag, payload) != (0, 0):
        raise AssertionError(f"asNone expected (0,0), got ({tag},{payload})")
    raw_none = client.view("asNone")
    if raw_none[:16] != NearClient.encode_u64_le(0) + NearClient.encode_u64_le(0):
        raise AssertionError(f"asNone raw LE bytes mismatch: {raw_none[:16].hex()}")
    print("optionret: asNone()==(0,0) exact 16 LE ok")

    some_res = client.call("asSome", NearClient.encode_u64_le(99))
    sv = NearClient.success_value_bytes(some_res)
    if sv is None or len(sv) < 16:
        raise AssertionError(
            f"asSome SuccessValue expected ≥16 LE bytes, got {sv!r}"
        )
    tag, payload = NearClient.decode_u64_le(sv, 0), NearClient.decode_u64_le(sv, 8)
    if (tag, payload) != (1, 99):
        raise AssertionError(f"asSome(99) SuccessValue expected (1,99), got ({tag},{payload})")
    print(f"optionret: asSome(99) SuccessValue==({tag},{payload}) ok")

    tag, payload = client.view_u64_pair("asSomeOfSeed")
    if (tag, payload) != (1, 42):
        raise AssertionError(
            f"asSomeOfSeed expected (1,42), got ({tag},{payload})"
        )
    raw_some = client.view("asSomeOfSeed")
    if raw_some[:16] != NearClient.encode_u64_le(1) + NearClient.encode_u64_le(42):
        raise AssertionError(
            f"asSomeOfSeed raw LE bytes mismatch: {raw_some[:16].hex()}"
        )
    print("optionret: asSomeOfSeed()==(1,42) exact 16 LE ok")
    print("suite OptionRet: PASS")


def suite_optionstate(client: NearClient, wasm: Path) -> None:
    print("=== suite: OptionState (Option UInt64 state tag+payload, BL-30) ===")
    client.deploy(wasm)

    # init() → none default (tag=0, payload=0)
    client.call("init", b"")
    tag, payload = client.view_u64_pair("getSlot")
    if (tag, payload) != (0, 0):
        raise AssertionError(f"after init: getSlot expected (0,0), got ({tag},{payload})")
    raw_none = client.view("getSlot")
    if raw_none[:16] != NearClient.encode_u64_le(0) + NearClient.encode_u64_le(0):
        raise AssertionError(f"after init: getSlot raw LE mismatch: {raw_none[:16].hex()}")
    peek = client.view_u64("peek")
    if peek != 0:
        raise AssertionError(f"after init: peek expected 0, got {peek}")
    print("optionstate: init() → getSlot()==(0,0), peek()==0 ok")

    # setSome(99) → tag=1, payload=99
    set_res = client.call("setSome", NearClient.encode_u64_le(99))
    sv = NearClient.success_value_bytes(set_res)
    if sv is None or len(sv) < 8:
        raise AssertionError(f"setSome SuccessValue expected ≥8 LE bytes, got {sv!r}")
    ret = NearClient.decode_u64_le(sv, 0)
    if ret != 99:
        raise AssertionError(f"setSome(99) SuccessValue expected 99, got {ret}")
    tag, payload = client.view_u64_pair("getSlot")
    if (tag, payload) != (1, 99):
        raise AssertionError(f"after setSome(99): getSlot expected (1,99), got ({tag},{payload})")
    raw_some = client.view("getSlot")
    if raw_some[:16] != NearClient.encode_u64_le(1) + NearClient.encode_u64_le(99):
        raise AssertionError(
            f"after setSome: getSlot raw LE mismatch: {raw_some[:16].hex()}"
        )
    peek = client.view_u64("peek")
    if peek != 99:
        raise AssertionError(f"after setSome(99): peek expected 99, got {peek}")
    print("optionstate: setSome(99) → getSlot()==(1,99), peek()==99 ok")

    # clear() must zero payload (pin): not leave stale 99 under tag=0
    client.call("clear", b"")
    tag, payload = client.view_u64_pair("getSlot")
    if (tag, payload) != (0, 0):
        raise AssertionError(
            f"after clear: getSlot expected (0,0) zeroed payload, got ({tag},{payload})"
        )
    raw_clear = client.view("getSlot")
    if raw_clear[:16] != NearClient.encode_u64_le(0) + NearClient.encode_u64_le(0):
        raise AssertionError(
            f"after clear: getSlot raw LE must be all-zero, got {raw_clear[:16].hex()}"
        )
    peek = client.view_u64("peek")
    if peek != 0:
        raise AssertionError(f"after clear: peek expected 0, got {peek}")
    print("optionstate: clear() → getSlot()==(0,0) payload zeroed, peek()==0 ok")
    print("suite OptionState: PASS")


def suite_tipjarasync(client: NearClient, wasm: Path) -> None:
    print("=== suite: TipJarAsync (pf.assets deposit + transferAsync, ADR-0029 C2) ===")
    # Fresh receiver subaccount so the fire-and-forget transfer is observable
    # as a real balance delta (honest end-to-end evidence, not a log claim).
    receiver = f"receiver.{client.account_id}"
    funding = 10**20
    client.create_subaccount(receiver, funding)
    base_balance = client.view_account_balance(receiver)
    print(f"tipjarasync: receiver={receiver} base_balance={base_balance}")

    client.deploy(wasm)

    # init(0) → get()==0
    client.call("init", NearClient.encode_u64_le(0))
    got = client.view_u64("get")
    if got != 0:
        raise AssertionError(f"after init(0): get() expected 0, got {got}")
    print("tipjarasync: init(0) → get()==0 ok")

    # tip(receiver, 1000) with exact attached deposit 1000 → success.
    amount = 1000
    args = (
        NearClient.encode_principal_account_id(receiver)
        + NearClient.encode_u64_le(amount)
    )
    res = client.call("tip", args, deposit=amount)
    sv = NearClient.success_value_bytes(res)
    if sv is None or len(sv) < 8:
        raise AssertionError(f"tip SuccessValue expected ≥8 LE bytes, got {sv!r}")
    ret = NearClient.decode_u64_le(sv, 0)
    if ret != amount:
        raise AssertionError(f"tip SuccessValue expected {amount}, got {ret}")
    got = client.view_u64("get")
    if got != amount:
        raise AssertionError(f"after tip: get() expected {amount}, got {got}")
    # transferAsync delivered: receiver balance grew by exactly amount.
    after = client.view_account_balance(receiver)
    if after != base_balance + amount:
        raise AssertionError(
            f"receiver balance expected +{amount} ({base_balance + amount}), got {after}"
        )
    print(f"tipjarasync: tip(receiver,{amount}) deposit={amount} → get()=={amount}, "
          f"receiver +{amount} ok")

    # Repeat tip (fire-and-forget again) keeps working.
    res2 = client.call("tip", args, deposit=amount)
    got = client.view_u64("get")
    if got != 2 * amount:
        raise AssertionError(f"after second tip: get() expected {2 * amount}, got {got}")
    after2 = client.view_account_balance(receiver)
    if after2 != base_balance + 2 * amount:
        raise AssertionError(
            f"receiver balance expected +{2 * amount}, got {after2}"
        )
    print("tipjarasync: second tip → get()==2000, receiver +2000 ok")

    # Wrong attached deposit (999 ≠ 1000) must fail; state must hold.
    client.call("tip", args, deposit=amount - 1, expect_success=False)
    got = client.view_u64("get")
    if got != 2 * amount:
        raise AssertionError(f"after wrong-deposit tip: get() must stay {2 * amount}, got {got}")
    print("tipjarasync: deposit=999 tip fails + state holds ok")

    # Zero attached deposit must fail; state must hold.
    client.call("tip", args, deposit=0, expect_success=False)
    got = client.view_u64("get")
    if got != 2 * amount:
        raise AssertionError(f"after zero-deposit tip: get() must stay {2 * amount}, got {got}")
    print("tipjarasync: deposit=0 tip fails + state holds ok")
    print("suite TipJarAsync: PASS")


def suite_tokenjarasync(client: NearClient, wasm: Path, mock_token_wat: Path,
                        wat2wasm: str) -> None:
    """ADR-0030 E1-NEAR: pf.assets.token.transferAsync → NEP-141 ft_transfer.

    Deploys the product-built jar AND a minimal mock NEP-141 token (built from
    the pinned runtime-tests/near/mock_token.wat with the locked wat2wasm; the
    mock asserts exactly 1 yoctoNEAR attached deposit — the NEP-141 core
    requirement — inside its ft_transfer). Calls
    token.transferAsync(mint, dst, amount) on the jar and asserts:
      * the jar entry succeeds and returns the new tips count;
      * the jar state advances (fire-and-forget: caller doesn't wait);
      * the cross-contract receipt to the mint (token contract) account is a
        SUCCESS and logs "ft_transfer ok" — the promise really executed the
        mock's ft_transfer, which verified the 1 yoctoNEAR deposit.

    Honest claim: the mock token has NO ledger bookkeeping, so this does NOT
    observe token balance deltas; it observes the real cross-contract
    execution of ft_transfer with the exact deposit assertion plus the
    fire-and-forget state advance on the jar side.
    """
    print("=== suite: TokenJarAsync (pf.assets.token.transferAsync, ADR-0030 E1) ===")

    # Build the mock token wasm from the pinned WAT with the locked wat2wasm.
    mock_wasm = mock_token_wat.with_suffix(".wasm")
    subprocess.run(
        [wat2wasm, str(mock_token_wat), "-o", str(mock_wasm)],
        check=True,
    )

    # Deploy the product-built jar to the master account.
    client.deploy(wasm)

    # init(0) → get()==0
    client.call("init", NearClient.encode_u64_le(0))
    got = client.view_u64("get")
    if got != 0:
        raise AssertionError(f"after init(0): get() expected 0, got {got}")
    print("tokenjarasync: init(0) → get()==0 ok")

    # Create the mint (token contract) subaccount WITH the master's key and
    # deploy the mock NEP-141 token onto it.
    mint_account = f"mocktoken.{client.account_id}"
    client.create_subaccount_with_key(mint_account, 10**23)
    client.deploy_to(mint_account, mock_wasm)
    print(f"tokenjarasync: mock NEP-141 token deployed on {mint_account} ok")

    # Create a receiver subaccount (plain account; NEP-141 receiver).
    receiver = f"tokenrcv.{client.account_id}"
    client.create_subaccount(receiver, 10**20)

    amount = 500
    args = (
        NearClient.encode_principal_account_id(mint_account)
        + NearClient.encode_principal_account_id(receiver)
        + NearClient.encode_u64_le(amount)
    )
    # token.transferAsync does not require attached deposit on the caller's
    # entry (the 1 yoctoNEAR comes from the contract's own balance via the
    # promise function call). deposit=0 on the caller's transaction.
    res = client.call("tipToken", args, deposit=0)

    # The jar entry must succeed and return the new tips count.
    sv = NearClient.success_value_bytes(res)
    if sv is None or len(sv) < 8:
        raise AssertionError(f"tipToken SuccessValue expected ≥8 LE bytes, got {sv!r}")
    ret = NearClient.decode_u64_le(sv, 0)
    if ret != amount:
        raise AssertionError(f"tipToken SuccessValue expected {amount}, got {ret}")
    print(f"tokenjarasync: tipToken(mint,{receiver},{amount}) SuccessValue=={ret} ok")

    # State advances: fire-and-forget → jar doesn't wait for promise result.
    got = client.view_u64("get")
    if got != amount:
        raise AssertionError(f"after tipToken: get() expected {amount}, got {got}")
    print(f"tokenjarasync: get()=={amount} (state advanced, fire-and-forget) ok")

    # Verify the cross-contract receipt to the mint account: it must be a
    # SUCCESS whose logs contain "ft_transfer ok" — the mock executed and its
    # 1 yoctoNEAR attached-deposit assertion held.
    receipts = res.get("receipts_outcome", [])
    mint_outcome = None
    for r in receipts:
        outcome = r.get("outcome", {})
        if outcome.get("executor_id", "") == mint_account:
            mint_outcome = outcome
            break
    if mint_outcome is None:
        raise AssertionError(
            f"no receipt to mint account {mint_account} found; "
            f"executors={[r.get('outcome',{}).get('executor_id','?') for r in receipts]}"
        )
    status = mint_outcome.get("status", {})
    if "SuccessValue" not in status and "SuccessReceiptId" not in status:
        raise AssertionError(f"mint receipt is not a success: status={status!r}")
    logs = mint_outcome.get("logs", [])
    if not any("ft_transfer ok" in line for line in logs):
        raise AssertionError(f"mint receipt missing 'ft_transfer ok' log: logs={logs!r}")
    print(
        "tokenjarasync: mint receipt SUCCESS + 'ft_transfer ok' log"
        " (1 yoctoNEAR deposit asserted by mock) ok"
    )

    # State-hold on fire-and-forget: second call also succeeds.
    res2 = client.call("tipToken", args, deposit=0)
    got = client.view_u64("get")
    if got != 2 * amount:
        raise AssertionError(f"after second tipToken: get() expected {2 * amount}, got {got}")
    print(f"tokenjarasync: second tipToken → get()=={2 * amount} ok")

    print("suite TokenJarAsync: PASS")


def suite_envreadjar(client: NearClient, wasm: Path) -> None:
    """ADR-0030 E2-NEAR: pf.assets.native.balanceOfSelf → host account_balance.

    Deploys the jar onto a key-carrying subaccount so master gas burn does not
    confound the jar's account_balance. Honesty about UInt64 range guard vs
    NEAR storage staking:
      Subaccount funding for a deployed WASM is typically >> 2^64 (storage
      stake). The product path traps when the high 64 bits of account_balance
      are nonzero — same UInt64 discipline as EVM SELFBALANCE / CW bank query.
      This suite therefore:
        1. Proves acceptNative deposit advances tip state and increases the
           RPC-observed jar balance by exactly the attached amount (gas paid
           by master, deposit lands on the jar).
        2. Calls nativeBalance(): if the jar balance fits in UInt64, asserts
           equality with RPC view_account; otherwise asserts the view fails
           (range guard). Both outcomes are product-correct.
    """
    print("=== suite: EnvReadJar (pf.assets.native.balanceOfSelf, ADR-0030 E2-NEAR) ===")
    jar = f"envreadjar.{client.account_id}"
    # Fund enough for storage stake of the small jar WASM (~1 KB) plus headroom.
    client.create_subaccount_with_key(jar, 10**24)
    client.deploy_to(jar, wasm)
    print(f"envreadjar: jar deployed on {jar}")

    client.call_on(jar, "init", NearClient.encode_u64_le(0))
    got = client.view_u64_on(jar, "get")
    if got != 0:
        raise AssertionError(f"after init(0): get() expected 0, got {got}")
    print("envreadjar: init(0) → get()==0 ok")

    base_balance = client.view_account_balance(jar)
    print(f"envreadjar: jar base_balance={base_balance}")
    u64_max = (1 << 64) - 1

    def try_native_balance(*, expect_success: bool) -> int | None:
        """Call nativeBalance view. Returns decoded UInt64 on success, None on fail."""
        try:
            raw = client.view_on(jar, "nativeBalance", b"")
            if len(raw) < 8:
                raise AssertionError(f"nativeBalance return too short: {raw!r}")
            val = NearClient.decode_u64_le(raw, 0)
            if not expect_success:
                raise AssertionError(
                    f"nativeBalance expected fail (range guard), got {val}"
                )
            return val
        except NearRpcError as e:
            if expect_success:
                raise AssertionError(
                    f"nativeBalance expected success, got error: {e}"
                ) from e
            return None

    bal0: int | None
    if base_balance <= u64_max:
        bal0 = try_native_balance(expect_success=True)
        if bal0 != base_balance:
            raise AssertionError(
                f"nativeBalance after init expected {base_balance}, got {bal0}"
            )
        print(f"envreadjar: nativeBalance()=={bal0} (fits UInt64) ok")
    else:
        bal0 = try_native_balance(expect_success=False)
        if bal0 is not None:
            raise AssertionError(
                f"nativeBalance must trap when balance>{u64_max}, got {bal0}"
            )
        print(
            f"envreadjar: nativeBalance traps on balance>{u64_max} "
            f"(UInt64 range guard) ok"
        )

    # Deposit path: exact attached_deposit advances tips + jar RPC balance.
    # Gas is paid by master; deposit lands entirely on the jar subaccount.
    amount = 1000
    res = client.call_on(
        jar, "acceptNative", NearClient.encode_u64_le(amount), deposit=amount
    )
    sv = NearClient.success_value_bytes(res)
    if sv is None or len(sv) < 8:
        raise AssertionError(f"acceptNative SuccessValue expected ≥8 LE bytes, got {sv!r}")
    ret = NearClient.decode_u64_le(sv, 0)
    if ret != amount:
        raise AssertionError(f"acceptNative SuccessValue expected {amount}, got {ret}")
    got = client.view_u64_on(jar, "get")
    if got != amount:
        raise AssertionError(f"after acceptNative: get() expected {amount}, got {got}")
    after = client.view_account_balance(jar)
    # Deposit lands on the jar; gas is paid by master. Storage-stake accounting
    # on the callee can move the liquid balance by more than `amount` (init
    # already wrote the tips key; a subsequent store may still adjust the
    # locked/unlocked split reported by view_account). Require a non-decrease
    # of at least the attached deposit rather than exact equality.
    if after < base_balance + amount:
        raise AssertionError(
            f"jar balance expected ≥ base+{amount} ({base_balance + amount}), "
            f"got {after} (base={base_balance})"
        )
    print(
        f"envreadjar: acceptNative({amount}) deposit={amount} → get()=={amount}, "
        f"jar balance {base_balance} → {after} (Δ={after - base_balance}) ok"
    )

    if after <= u64_max:
        bal1 = try_native_balance(expect_success=True)
        if bal1 != after:
            raise AssertionError(
                f"nativeBalance after deposit expected {after}, got {bal1}"
            )
        print(f"envreadjar: nativeBalance after deposit == {bal1} ok")
    else:
        bal1 = try_native_balance(expect_success=False)
        if bal1 is not None:
            raise AssertionError(
                f"nativeBalance must still trap when balance>{u64_max}, got {bal1}"
            )
        print("envreadjar: nativeBalance still traps post-deposit (range guard) ok")

    # Wrong deposit must fail; tip state holds.
    client.call_on(
        jar,
        "acceptNative",
        NearClient.encode_u64_le(amount),
        deposit=amount - 1,
        expect_success=False,
    )
    got = client.view_u64_on(jar, "get")
    if got != amount:
        raise AssertionError(
            f"after wrong-deposit acceptNative: get() must stay {amount}, got {got}"
        )
    print("envreadjar: wrong-deposit acceptNative fails + state holds ok")
    print("suite EnvReadJar: PASS")


def main(argv: list[str]) -> int:
    suite = os.environ.get("PF_NEAR_SUITE", "single").strip().lower()
    rpc = _require_env("PF_NEAR_RPC")
    home = Path(_require_env("PF_NEAR_HOME"))

    try:
        client = NearClient(rpc, home)
        # Smoke: node status
        st = client.status()
        chain = st.get("chain_id") or st.get("sync_info", {})
        print(f"near-runtime: rpc={rpc} account={client.account_id} status_ok chain={chain!r}")

        if suite in ("counter", "single"):
            wasm = Path(os.environ.get("PF_NEAR_WASM") or _require_env("PF_NEAR_COUNTER_WASM"))
            suite_counter(client, wasm)
        elif suite == "pairret":
            wasm = Path(os.environ.get("PF_NEAR_WASM") or _require_env("PF_NEAR_PAIRRET_WASM"))
            suite_pairret(client, wasm)
        elif suite == "arrayret":
            wasm = Path(os.environ.get("PF_NEAR_WASM") or _require_env("PF_NEAR_ARRAYRET_WASM"))
            suite_arrayret(client, wasm)
        elif suite == "optionret":
            wasm = Path(os.environ.get("PF_NEAR_WASM") or _require_env("PF_NEAR_OPTIONRET_WASM"))
            suite_optionret(client, wasm)
        elif suite == "optionstate":
            wasm = Path(os.environ.get("PF_NEAR_WASM") or _require_env("PF_NEAR_OPTIONSTATE_WASM"))
            suite_optionstate(client, wasm)
        elif suite == "tipjarasync":
            wasm = Path(os.environ.get("PF_NEAR_WASM") or _require_env("PF_NEAR_TIPJARASYNC_WASM"))
            suite_tipjarasync(client, wasm)
        elif suite == "tokenjarasync":
            wasm = Path(os.environ.get("PF_NEAR_WASM") or _require_env("PF_NEAR_TOKENJARASYNC_WASM"))
            mock_wat = Path(os.environ.get(
                "PF_NEAR_MOCK_TOKEN_WAT",
                str(Path(__file__).parent / "mock_token.wat"),
            ))
            wat2wasm = os.environ.get("PF_NEAR_WAT2WASM", "wat2wasm")
            suite_tokenjarasync(client, wasm, mock_wat, wat2wasm)
        elif suite == "envreadjar":
            wasm = Path(os.environ.get("PF_NEAR_WASM") or _require_env("PF_NEAR_ENVREADJAR_WASM"))
            suite_envreadjar(client, wasm)
        elif suite == "all":
            # Same sandbox / same account: run suites only if
            # caller redeploys after a fresh home (script boots once per suite).
            raise SystemExit(
                "near-runtime: suite=all requires separate sandbox homes; "
                "script should invoke each suite separately"
            )
        else:
            raise SystemExit(f"near-runtime: unknown PF_NEAR_SUITE={suite!r}")
    except (NearRpcError, AssertionError, OSError) as e:
        print(f"near-runtime: FAIL: {e}", file=sys.stderr)
        return 1

    print("near-runtime: all selected suites PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
