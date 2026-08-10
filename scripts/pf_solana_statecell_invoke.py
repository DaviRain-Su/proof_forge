#!/usr/bin/env python3
"""Create PF StateCell state account + send init/increment on local RPC (solders)."""
from __future__ import annotations

import argparse
import base64
import json
import struct
import sys
import time
import urllib.request


DISCRIMINATOR_DOMAIN = "proof-forge-solana-v1:"


def instruction_discriminator(name: str, param_count: int) -> bytes:
    """Match runtime-tests/solana instruction_discriminator (body-only S1b)."""
    import hashlib

    params = ",".join(["u64"] * param_count)
    preimage = f"{DISCRIMINATOR_DOMAIN}{name}({params})"
    return hashlib.sha256(preimage.encode("utf-8")).digest()[:8]


def disc_name_for_ix(ix: dict) -> str:
    # Initializer callables are emitted as `initialize` in S1b asm.
    mode = (ix.get("mode") or "").lower()
    name = ix.get("name") or ""
    if mode in ("initialize", "initializer") or name == "init":
        return "initialize"
    return name


def encode_ix(ix: dict, params: list[int]) -> bytes:
    name = disc_name_for_ix(ix)
    out = bytearray(instruction_discriminator(name, len(params)))
    for p in params:
        if p < 0 or p > 0xFFFFFFFFFFFFFFFF:
            raise SystemExit(f"param out of u64: {p}")
        out += struct.pack("<Q", p)
    return bytes(out)


def rpc(url: str, method: str, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.load(resp)
    if "error" in data:
        raise RuntimeError(data["error"])
    return data["result"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rpc", required=True)
    ap.add_argument("--program-id", required=True)
    ap.add_argument("--payer-keypair", required=True)
    ap.add_argument("--state-keypair", required=True)
    ap.add_argument("--idl", required=True)
    ap.add_argument("--space", type=int, default=16)
    ap.add_argument("--init", type=int, default=7)
    ap.add_argument("--delta", type=int, default=5)
    args = ap.parse_args()

    idl = json.load(open(args.idl))
    by_name = {i["name"]: i for i in idl["instructions"]}
    for need in ("init", "increment"):
        if need not in by_name:
            print(f"FAIL: idl missing {need}", file=sys.stderr)
            return 1

    try:
        from solders.keypair import Keypair
        from solders.pubkey import Pubkey
        from solders.instruction import AccountMeta, Instruction
        from solders.message import Message
        from solders.transaction import Transaction
        from solders.hash import Hash
        from solders.system_program import create_account, CreateAccountParams
    except ImportError as e:
        print(f"FAIL: solders required for create+invoke ({e})", file=sys.stderr)
        print(
            "      python3 -m venv /tmp/pf-sol-venv && /tmp/pf-sol-venv/bin/pip install solders",
            file=sys.stderr,
        )
        return 2

    payer = Keypair.from_json(open(args.payer_keypair).read())
    state_kp = Keypair.from_json(open(args.state_keypair).read())
    program = Pubkey.from_string(args.program_id)
    state = state_kp.pubkey()
    print(f"state={state}")

    def latest_blockhash() -> Hash:
        bh = rpc(args.rpc, "getLatestBlockhash", [{"commitment": "confirmed"}])
        return Hash.from_string(bh["value"]["blockhash"])

    def send_tx(ixs, signers) -> str:
        blockhash = latest_blockhash()
        msg = Message.new_with_blockhash(ixs, payer.pubkey(), blockhash)
        tx = Transaction.new_unsigned(msg)
        tx.sign(signers, blockhash)
        raw = base64.b64encode(bytes(tx)).decode()
        sig = rpc(
            args.rpc,
            "sendTransaction",
            [
                raw,
                {
                    "encoding": "base64",
                    "preflightCommitment": "confirmed",
                    "skipPreflight": False,
                },
            ],
        )
        for _ in range(60):
            st = rpc(
                args.rpc,
                "getSignatureStatuses",
                [[sig], {"searchTransactionHistory": True}],
            )
            val = (st["value"] or [None])[0]
            if val and val.get("confirmationStatus") in ("confirmed", "finalized"):
                if val.get("err"):
                    raise RuntimeError(f"tx err {val['err']} sig={sig}")
                return sig
            time.sleep(0.2)
        raise RuntimeError(f"not confirmed: {sig}")

    rent = rpc(args.rpc, "getMinimumBalanceForRentExemption", [args.space])
    print(f"create_account space={args.space} lamports={rent} owner={program}")
    info = rpc(args.rpc, "getAccountInfo", [str(state), {"encoding": "base64"}])
    if not info.get("value"):
        ca = create_account(
            CreateAccountParams(
                from_pubkey=payer.pubkey(),
                to_pubkey=state,
                lamports=int(rent),
                space=args.space,
                owner=program,
            )
        )
        sig = send_tx([ca], [payer, state_kp])
        print(f"create_account sig={sig}")
    else:
        print("state account already exists")

    def send_handler(
        name: str,
        params: list[int],
        *,
        writable: bool = True,
        state_is_signer: bool = False,
    ) -> str:
        ix_spec = by_name[name]
        data = encode_ix(ix_spec, params)
        # Body-only StateCell init requires state is_signer + is_writable.
        metas = [
            AccountMeta(state, is_signer=state_is_signer, is_writable=writable),
        ]
        ix = Instruction(program, data, metas)
        signers = [payer, state_kp] if state_is_signer else [payer]
        return send_tx([ix], signers)

    def read_count() -> int:
        """StateCell ordinary layout: [layout_marker u64 | count u64] (16 bytes)."""
        info = rpc(args.rpc, "getAccountInfo", [str(state), {"encoding": "base64"}])
        val = info.get("value")
        if not val:
            raise RuntimeError("state missing")
        raw = base64.b64decode(val["data"][0])
        if len(raw) < 16:
            raise RuntimeError(f"StateCell data too short {len(raw)} (want >=16)")
        marker = struct.unpack_from("<Q", raw, 0)[0]
        count = struct.unpack_from("<Q", raw, 8)[0]
        print(f"state_layout marker={marker} count@8={count} raw_hex={raw.hex()}")
        return count

    print(
        f"init({args.init}) disc={instruction_discriminator('initialize', 1).hex()} "
        f"handlerId={by_name['init']['handlerId']}"
    )
    print("  sig=", send_handler("init", [args.init], writable=True, state_is_signer=True))
    print(
        f"increment({args.delta}) disc={instruction_discriminator('increment', 1).hex()} "
        f"handlerId={by_name['increment']['handlerId']}"
    )
    # entry: state writable, not signer (see StateCell.s)
    print("  sig=", send_handler("increment", [args.delta], writable=True, state_is_signer=False))
    try:
        if "get" in by_name:
            print(f"get handlerId={by_name['get']['handlerId']}")
            print("  sig=", send_handler("get", [], writable=False, state_is_signer=False))
    except Exception as e:
        print(f"get ix note: {e}")
    count = read_count()
    expected = args.init + args.delta
    print(f"state_u64={count} expected_count={expected}")
    if count == expected:
        print("OK count matches init+delta")
    else:
        print(
            f"FAIL count layout mismatch: got {count} want {expected}",
            file=sys.stderr,
        )
        print(f"STATE_PUBKEY={state}")
        return 3
    print(f"STATE_PUBKEY={state}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
