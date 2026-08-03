#!/usr/bin/env python3
"""NEAR near-sandbox engineering runtime differential (BL-13).

Suites:
  counter  — Examples/Counter: init / increment / get + overflow state-hold
  pairret  — fixtures/PairRet: named Struct aggregate return (N×8 LE)

Env (set by scripts/near_runtime_test.sh):
  PF_NEAR_RPC          e.g. http://127.0.0.1:PORT
  PF_NEAR_HOME         near-sandbox --home directory (validator_key.json)
  PF_NEAR_WASM         path to product .wasm for the suite
  PF_NEAR_SUITE        counter | pairret | all  (default: all, requires both wasm paths)
  PF_NEAR_COUNTER_WASM / PF_NEAR_PAIRRET_WASM when suite=all with separate boots

Honesty: engineering sandbox differential only — not testnet/mainnet,
not formal Stage-0 / hermetic / Reference↔sandbox closure.
"""

from __future__ import annotations

import os
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
        elif suite == "all":
            # Same sandbox / same account: run counter then pairret only if
            # caller redeploys after a fresh home (script boots once per suite).
            raise SystemExit(
                "near-runtime: suite=all requires separate sandbox homes; "
                "script should invoke suite=counter and suite=pairret separately"
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
