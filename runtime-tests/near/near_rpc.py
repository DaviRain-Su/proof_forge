"""Minimal NEAR JSON-RPC client for locked near-sandbox (engineering only).

Talks to a local neard sandbox via JSON-RPC + borsh-signed transactions.
No near-api-rs / near-workspaces / near-cli dependency — fewest moving parts
for real deploy+call receipts against Tool-Lock near-sandbox 2.13.0.

Not testnet/mainnet, not formal Stage-0 / Reference↔sandbox closure.
"""

from __future__ import annotations

import base64
import hashlib
import json
import struct
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

import base58
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


class NearRpcError(RuntimeError):
    pass


class NearClient:
    def __init__(self, rpc: str, home: Path, account_id: str = "test.near") -> None:
        self.rpc = rpc.rstrip("/")
        self.home = Path(home)
        self.account_id = account_id
        key = json.loads((self.home / "validator_key.json").read_text())
        if key["account_id"] != account_id:
            raise NearRpcError(
                f"validator_key account_id={key['account_id']!r} != {account_id!r}"
            )
        sk_raw = base58.b58decode(key["secret_key"].split(":", 1)[1])
        seed = sk_raw[:32]
        self._priv = Ed25519PrivateKey.from_private_bytes(seed)
        self._pub = self._priv.public_key().public_bytes_raw()
        self.public_key_str = "ed25519:" + base58.b58encode(self._pub).decode()

    # --- wire helpers -------------------------------------------------

    @staticmethod
    def borsh_string(s: str) -> bytes:
        b = s.encode()
        return struct.pack("<I", len(b)) + b

    @staticmethod
    def borsh_bytes(b: bytes) -> bytes:
        return struct.pack("<I", len(b)) + b

    @staticmethod
    def u64(n: int) -> bytes:
        return struct.pack("<Q", n)

    @staticmethod
    def u128(n: int) -> bytes:
        return int(n).to_bytes(16, "little")

    @staticmethod
    def encode_u64_le(n: int) -> bytes:
        return struct.pack("<Q", int(n) & ((1 << 64) - 1))

    @staticmethod
    def encode_principal_account_id(account_id: str) -> bytes:
        """ADR-0029 C2: Principal as 9×u64 LE leaves (len + 8 body words).

        Body is the exact wire shape `u32le(len) || utf8-account-id-bytes`
        zero-padded to 64 bytes across 8 LE words.
        """
        raw = account_id.encode("utf-8")
        if not (2 <= len(raw) <= 64):
            raise ValueError(f"account-id length {len(raw)} outside 2..64")
        body = raw + b"\x00" * (64 - len(raw))
        out = [len(raw)]
        for i in range(8):
            out.append(int.from_bytes(body[i * 8 : (i + 1) * 8], "little"))
        return b"".join(struct.pack("<Q", w) for w in out)

    @staticmethod
    def decode_u64_le(b: bytes, offset: int = 0) -> int:
        return struct.unpack_from("<Q", b, offset)[0]

    # --- RPC ----------------------------------------------------------

    @staticmethod
    def action_create_account() -> bytes:
        # Action enum tag 0 = CreateAccount
        return bytes([0])

    @staticmethod
    def action_transfer(amount: int) -> bytes:
        # Action enum tag 3 = Transfer
        return bytes([3]) + NearClient.u128(amount)

    def view_account_balance(self, account_id: str) -> int:
        res = self.rpc_call(
            "query",
            {
                "request_type": "view_account",
                "finality": "optimistic",
                "account_id": account_id,
            },
        )
        if res.get("error"):
            raise NearRpcError(f"view_account {account_id}: {res['error']}")
        return int(res["amount"])

    def create_subaccount(self, sub_id: str, initial_balance: int) -> dict[str, Any]:
        """Create `sub_id` under the master account with an initial balance."""
        return self.sign_and_send(
            sub_id,
            [self.action_create_account(), self.action_transfer(initial_balance)],
        )

    def action_add_full_access_key(self) -> bytes:
        # Action enum tag 5 = AddKey { public_key, access_key }.
        # PublicKey::ED25519 = curve byte 0 + 32 raw bytes; AccessKey =
        # nonce u64(0) + AccessKeyPermission enum — declaration order is
        # FunctionCall=0, FullAccess=1 (Borsh variant index).
        return (
            bytes([5])
            + bytes([0])
            + self._pub
            + self.u64(0)
            + bytes([1])
        )

    def create_subaccount_with_key(
        self, sub_id: str, initial_balance: int
    ) -> dict[str, Any]:
        """Create `sub_id` under the master account, funded, carrying the
        master's full-access key so the master key can also sign *as* the
        subaccount (needed to deploy a contract onto it)."""
        return self.sign_and_send(
            sub_id,
            [
                self.action_create_account(),
                self.action_transfer(initial_balance),
                self.action_add_full_access_key(),
            ],
        )

    def rpc_call(self, method: str, params: Any) -> Any:
        body = json.dumps(
            {"jsonrpc": "2.0", "id": "pf-near-runtime", "method": method, "params": params}
        ).encode()
        req = urllib.request.Request(
            self.rpc, data=body, headers={"content-type": "application/json"}
        )
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = json.loads(resp.read().decode())
        except urllib.error.URLError as e:
            raise NearRpcError(f"rpc transport {method}: {e}") from e
        if "error" in data:
            raise NearRpcError(f"rpc {method}: {data['error']}")
        return data["result"]

    def status(self) -> Any:
        return self.rpc_call("status", [])

    def access_key(self, account_id: str | None = None) -> tuple[int, bytes]:
        res = self.rpc_call(
            "query",
            {
                "request_type": "view_access_key",
                "finality": "optimistic",
                "account_id": account_id or self.account_id,
                "public_key": self.public_key_str,
            },
        )
        return int(res["nonce"]), base58.b58decode(res["block_hash"])

    # --- actions ------------------------------------------------------

    @staticmethod
    def action_deploy(code: bytes) -> bytes:
        # Action enum tag 1 = DeployContract { code }
        return bytes([1]) + NearClient.borsh_bytes(code)

    @staticmethod
    def action_function_call(
        method: str,
        args: bytes,
        gas: int = 50_000_000_000_000,
        deposit: int = 0,
    ) -> bytes:
        # Action enum tag 2 = FunctionCall
        return (
            bytes([2])
            + NearClient.borsh_string(method)
            + NearClient.borsh_bytes(args)
            + NearClient.u64(gas)
            + NearClient.u128(deposit)
        )

    def sign_and_send(
        self,
        receiver: str,
        actions: list[bytes],
        *,
        expect_success: bool = True,
        signer: str | None = None,
    ) -> dict[str, Any]:
        signer_id = signer or self.account_id
        nonce, block_hash = self.access_key(signer_id)
        nonce += 1
        actions_blob = struct.pack("<I", len(actions)) + b"".join(actions)
        tx = (
            self.borsh_string(signer_id)
            + bytes([0])
            + self._pub  # PublicKey::ED25519
            + self.u64(nonce)
            + self.borsh_string(receiver)
            + block_hash
            + actions_blob
        )
        sig = self._priv.sign(hashlib.sha256(tx).digest())
        signed = tx + bytes([0]) + sig
        res = self.rpc_call("broadcast_tx_commit", [base64.b64encode(signed).decode()])
        status = res.get("status", {})
        failed = "Failure" in status
        if not failed:
            for r in res.get("receipts_outcome", []):
                st = r.get("outcome", {}).get("status", {})
                if "Failure" in st:
                    failed = True
                    break
        if expect_success and failed:
            raise NearRpcError(f"tx failure: status={status!r} receipts={res.get('receipts_outcome')!r}")
        if not expect_success and not failed:
            raise NearRpcError(
                f"expected tx/receipt failure, got success: status={status!r}"
            )
        return res

    def deploy(self, wasm_path: Path) -> dict[str, Any]:
        code = Path(wasm_path).read_bytes()
        magic = code[:4]
        if magic != b"\x00asm":
            raise NearRpcError(f"bad Wasm magic in {wasm_path}: {magic!r}")
        print(f"near-rpc: deploy {len(code)} bytes → {self.account_id}")
        return self.sign_and_send(self.account_id, [self.action_deploy(code)])

    def deploy_to(self, account_id: str, wasm_path: Path) -> dict[str, Any]:
        """Deploy `wasm_path` onto `account_id`, signing as that account
        (requires the master key to be a full-access key on it — see
        create_subaccount_with_key)."""
        code = Path(wasm_path).read_bytes()
        magic = code[:4]
        if magic != b"\x00asm":
            raise NearRpcError(f"bad Wasm magic in {wasm_path}: {magic!r}")
        print(f"near-rpc: deploy {len(code)} bytes → {account_id}")
        return self.sign_and_send(
            account_id, [self.action_deploy(code)], signer=account_id
        )

    def call(
        self,
        method: str,
        args: bytes = b"",
        *,
        expect_success: bool = True,
        gas: int = 50_000_000_000_000,
        deposit: int = 0,
    ) -> dict[str, Any]:
        print(
            f"near-rpc: call {method}({len(args)} arg bytes)"
            f" expect_success={expect_success} deposit={deposit}"
        )
        return self.sign_and_send(
            self.account_id,
            [self.action_function_call(method, args, gas=gas, deposit=deposit)],
            expect_success=expect_success,
        )

    def view(self, method: str, args: bytes = b"") -> bytes:
        res = self.rpc_call(
            "query",
            {
                "request_type": "call_function",
                "finality": "optimistic",
                "account_id": self.account_id,
                "method_name": method,
                "args_base64": base64.b64encode(args).decode(),
            },
        )
        if res.get("error"):
            raise NearRpcError(f"view {method}: {res['error']}")
        return bytes(res["result"])

    def view_u64(self, method: str, args: bytes = b"") -> int:
        raw = self.view(method, args)
        if len(raw) < 8:
            raise NearRpcError(f"view {method}: expected ≥8 LE bytes, got {raw!r}")
        return self.decode_u64_le(raw, 0)

    def view_u64_pair(self, method: str, args: bytes = b"") -> tuple[int, int]:
        raw = self.view(method, args)
        if len(raw) < 16:
            raise NearRpcError(f"view {method}: expected ≥16 LE bytes, got {raw!r}")
        return self.decode_u64_le(raw, 0), self.decode_u64_le(raw, 8)

    @staticmethod
    def success_value_bytes(tx_res: dict[str, Any]) -> bytes | None:
        """Extract raw SuccessValue (base64) from final execution outcome if present."""
        status = tx_res.get("status", {})
        if "SuccessValue" in status:
            sv = status["SuccessValue"]
            if sv is None or sv == "":
                return b""
            return base64.b64decode(sv)
        # Prefer last receipt outcome with SuccessValue (function result).
        for r in reversed(tx_res.get("receipts_outcome", [])):
            st = r.get("outcome", {}).get("status", {})
            if "SuccessValue" in st:
                sv = st["SuccessValue"]
                if sv is None or sv == "":
                    return b""
                return base64.b64decode(sv)
        return None
