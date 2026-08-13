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
from observation_v1 import CallObservationV1, call_observation_from_view_response_v1


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
    def encode_u256_le(n: int) -> bytes:
        """UInt256 little-endian 32-byte word (NEAR packed-raw / value_return)."""
        value = int(n)
        if value < 0 or value >= 1 << 256:
            raise ValueError(f"UInt256 out of range: {value}")
        return value.to_bytes(32, "little")

    @staticmethod
    def decode_u256_le(b: bytes, offset: int = 0) -> int:
        if offset + 32 > len(b):
            raise ValueError(
                f"UInt256 decode needs 32 bytes at {offset}, got {len(b)}"
            )
        return int.from_bytes(b[offset : offset + 32], "little")

    @staticmethod
    def encode_u32_le(n: int) -> bytes:
        """UInt32 LE wire for NEAR packed-raw params (exactInputLen=4)."""
        return struct.pack("<I", int(n) & 0xFFFFFFFF)

    @staticmethod
    def encode_i64_le(n: int) -> bytes:
        """Two's-complement Int64 little-endian (NEAR product scalar wire)."""
        return struct.pack("<q", int(n))

    @staticmethod
    def decode_i64_le(b: bytes, offset: int = 0) -> int:
        return struct.unpack_from("<q", b, offset)[0]

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

    def latest_block_height(self) -> int:
        """neard status.sync_info.latest_block_height (engineering pin only)."""
        st = self.status()
        sync = st.get("sync_info") or {}
        h = sync.get("latest_block_height")
        if h is None:
            raise NearRpcError(f"status missing sync_info.latest_block_height: {st!r}")
        return int(h)

    def latest_block_time_unix_seconds(self) -> int:
        """Best-effort whole seconds from status.sync_info.latest_block_time.

        neard emits RFC3339 / ISO-8601 timestamps. Engineering pin only —
        not a formal clock model.
        """
        st = self.status()
        sync = st.get("sync_info") or {}
        raw = sync.get("latest_block_time")
        if raw is None:
            raise NearRpcError(f"status missing sync_info.latest_block_time: {st!r}")
        if isinstance(raw, (int, float)):
            # Some builds may expose nanoseconds or seconds as number.
            v = int(raw)
            if v > 10**12:  # ns
                return v // 1_000_000_000
            if v > 10**10:  # ms
                return v // 1000
            return v
        s = str(raw).strip()
        # RFC3339: 2024-01-02T03:04:05.123456789Z
        from datetime import datetime, timezone

        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        # Trim subsecond to 6 digits for fromisoformat if longer.
        if "." in s:
            head, rest = s.split(".", 1)
            frac = ""
            tz = ""
            for i, ch in enumerate(rest):
                if ch.isdigit():
                    frac += ch
                else:
                    tz = rest[i:]
                    break
            frac = (frac + "000000")[:6]
            s = f"{head}.{frac}{tz}"
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return int(dt.timestamp())

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

    def view_state_values(self, account_id: str | None = None) -> dict[bytes, bytes]:
        """Return the complete raw key/value state for one sandbox account.

        Runtime suites use this only for engineering observations of the
        product-owned storage layout. It is not a ReferenceMachine proof or a
        target-refinement claim.
        """
        target = account_id or self.account_id
        res = self.rpc_call(
            "query",
            {
                "request_type": "view_state",
                "finality": "optimistic",
                "account_id": target,
                "prefix_base64": "",
                "include_proof": False,
            },
        )
        if type(res) is not dict:
            raise NearRpcError(f"view_state {target}: response must be an object")
        if "error" in res:
            raise NearRpcError(f"view_state {target}: {res['error']}")
        rows = res.get("values")
        if type(rows) is not list:
            raise NearRpcError(f"view_state {target}: values must be an array")
        values: dict[bytes, bytes] = {}
        for item in rows:
            try:
                if type(item) is not dict:
                    raise TypeError("row must be an object")
                if type(item.get("key")) is not str or type(item.get("value")) is not str:
                    raise TypeError("row key/value must be strings")
                key = base64.b64decode(item["key"], validate=True)
                value = base64.b64decode(item["value"], validate=True)
            except (KeyError, TypeError, ValueError) as error:
                raise NearRpcError(
                    f"view_state {target}: malformed key/value row {item!r}"
                ) from error
            if key in values:
                raise NearRpcError(
                    f"view_state {target}: duplicate key {item['key']!r}"
                )
            values[key] = value
        return values

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
        return self.call_on(
            self.account_id,
            method,
            args,
            expect_success=expect_success,
            gas=gas,
            deposit=deposit,
        )

    def call_on(
        self,
        account_id: str,
        method: str,
        args: bytes = b"",
        *,
        expect_success: bool = True,
        gas: int = 50_000_000_000_000,
        deposit: int = 0,
        signer: str | None = None,
    ) -> dict[str, Any]:
        """Function-call `method` on `account_id`.

        Default signer is the master account. Pass `signer=` to sign as a
        key-carrying subaccount so `predecessor_account_id` inside the callee
        equals that subaccount (ADR-0031 S1 caller tests).
        Deposit attaches to the callee account (useful when the jar lives on a
        subaccount so master gas burn does not confound balance deltas).
        """
        signer_id = signer or self.account_id
        print(
            f"near-rpc: call_on {account_id}.{method}({len(args)} arg bytes)"
            f" signer={signer_id} expect_success={expect_success} deposit={deposit}"
        )
        return self.sign_and_send(
            account_id,
            [self.action_function_call(method, args, gas=gas, deposit=deposit)],
            expect_success=expect_success,
            signer=signer_id,
        )

    def view(self, method: str, args: bytes = b"") -> bytes:
        return self.view_on(self.account_id, method, args)

    def view_response_on(
        self, account_id: str, method: str, args: bytes = b""
    ) -> dict[str, Any]:
        res = self.rpc_call(
            "query",
            {
                "request_type": "call_function",
                "finality": "optimistic",
                "account_id": account_id,
                "method_name": method,
                "args_base64": base64.b64encode(args).decode(),
            },
        )
        if type(res) is not dict:
            raise NearRpcError(
                f"view {account_id}.{method}: response must be an object"
            )
        if res.get("error"):
            raise NearRpcError(f"view {account_id}.{method}: {res['error']}")
        return res

    def view_on(self, account_id: str, method: str, args: bytes = b"") -> bytes:
        res = self.view_response_on(account_id, method, args)
        try:
            return bytes(res["result"])
        except (KeyError, TypeError, ValueError) as error:
            raise NearRpcError(
                f"view {account_id}.{method}: malformed result bytes"
            ) from error

    def observe_view(
        self, method: str, args: bytes = b""
    ) -> CallObservationV1:
        """Capture a successful query and full pre/post KV snapshots.

        This feeds the engineering observation adapter only. It does not turn
        near-sandbox into a formal target semantics or refinement checker.
        """
        pre_storage = self.view_state_values()
        response = self.view_response_on(self.account_id, method, args)
        post_storage = self.view_state_values()
        try:
            return call_observation_from_view_response_v1(
                method, args, response, pre_storage, post_storage
            )
        except ValueError as error:
            raise NearRpcError(
                f"view {self.account_id}.{method}: invalid observation: {error}"
            ) from error

    def view_u64(self, method: str, args: bytes = b"") -> int:
        return self.view_u64_on(self.account_id, method, args)

    def view_u64_on(self, account_id: str, method: str, args: bytes = b"") -> int:
        raw = self.view_on(account_id, method, args)
        if len(raw) < 8:
            raise NearRpcError(
                f"view {account_id}.{method}: expected ≥8 LE bytes, got {raw!r}"
            )
        return self.decode_u64_le(raw, 0)

    def view_i64_pair(self, method: str, args: bytes = b"") -> tuple[int, int]:
        """Decode first 16 bytes as two little-endian Int64 leaves."""
        raw = self.view(method, args)
        if len(raw) < 16:
            raise NearRpcError(
                f"view {method}: expected ≥16 LE bytes for i64 pair, got {raw!r}"
            )
        return self.decode_i64_le(raw, 0), self.decode_i64_le(raw, 8)

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
