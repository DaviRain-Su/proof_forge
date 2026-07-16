#!/usr/bin/env python3

import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import sys


PINNED_REVISION = "62f6cae30942f82958695697d3de8b4e1447ea7f"
GATE_PATHS = {
    "valueVault": "value-vault/summary.json",
    "mappingEvents": "token/mapping-events-summary.json",
    "token": "token/summary.json",
    "remoteCall": "remote-call/summary.json",
    "aggregate": "aggregate/summary.json",
}
HEX_32 = re.compile(r"^0x[0-9a-fA-F]{64}$")
SHA_256 = re.compile(r"^[0-9a-f]{64}$")


def fail(message: str) -> None:
    raise ValueError(f"stylus Nitro evidence: {message}")


def load_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        fail(f"{path} must contain an object")
    return value


def identities(artifact: dict) -> dict:
    outputs = artifact.get("artifactBundle", {}).get("outputs")
    if not isinstance(outputs, list):
        fail("artifact bundle outputs are missing")
    by_kind = {item.get("kind"): item.get("sha256") for item in outputs if isinstance(item, dict)}
    expected = {
        "planSha256": by_kind.get("stylus-plan"),
        "storageSha256": by_kind.get("stylus-storage-layout"),
        "abiSha256": by_kind.get("solidity-abi"),
    }
    if not all(isinstance(value, str) and SHA_256.fullmatch(value) for value in expected.values()):
        fail("artifact plan/storage/ABI identities are missing or malformed")
    return expected


def validate_gate(name: str, path: Path, expected_chain_id: int | None) -> tuple[dict, int]:
    gate = load_json(path)
    if gate.get("schema") != "proof-forge.stylus.nitro-gate.v1":
        fail(f"gate {name} has the wrong schema")
    if gate.get("gate") != name:
        fail(f"gate {name} summary identifies {gate.get('gate')!r}")
    if gate.get("state") != "passed" or gate.get("skipped") is not False:
        fail(f"gate {name} did not pass or was skipped")
    if gate.get("provenance") != "nitro-testnode":
        fail(f"gate {name} is not Nitro testnode evidence")
    chain_id = gate.get("chainId")
    if not isinstance(chain_id, int) or chain_id <= 0:
        fail(f"gate {name} has an invalid chain id")
    if expected_chain_id is not None and chain_id != expected_chain_id:
        fail(f"gate {name} chain id {chain_id} does not match {expected_chain_id}")
    transactions = gate.get("transactions")
    if not isinstance(transactions, dict) or not transactions:
        fail(f"gate {name} has no transactions")
    if not all(isinstance(value, str) and HEX_32.fullmatch(value) for value in transactions.values()):
        fail(f"gate {name} contains a malformed transaction hash")
    artifacts = gate.get("artifacts")
    if not isinstance(artifacts, dict) or not artifacts:
        fail(f"gate {name} has no artifact identities")
    if not all(isinstance(value, str) and SHA_256.fullmatch(value) for value in artifacts.values()):
        fail(f"gate {name} contains a malformed artifact hash")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return {
        "state": "passed",
        "skipped": False,
        "provenance": "nitro-testnode",
        "chainId": chain_id,
        "transactions": transactions,
        "artifacts": artifacts,
        "summarySha256": digest,
    }, chain_id


def assemble(artifact_path: Path, doctor_path: Path, evidence_root: Path) -> dict:
    artifact = load_json(artifact_path)
    if artifact.get("target") != "wasm-arbitrum-stylus":
        fail("artifact target must be wasm-arbitrum-stylus")
    doctor = load_json(doctor_path)
    if doctor.get("ready") is not True:
        fail("Nitro doctor is not ready")
    if doctor.get("nitroRevision") != PINNED_REVISION:
        fail("Nitro doctor does not report the pinned revision")
    gates = {}
    chain_id = None
    for name, relative in GATE_PATHS.items():
        gates[name], chain_id = validate_gate(name, evidence_root / relative, chain_id)
    doctor_chain = doctor.get("rpcChainId")
    if str(doctor_chain) not in {str(chain_id), hex(chain_id)}:
        fail(f"doctor RPC chain id {doctor_chain!r} does not match gate chain id {chain_id}")
    return {
        "schemaVersion": "1",
        "target": "wasm-arbitrum-stylus",
        "planSchemaVersion": "stylus-plan-v1",
        "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
        "identities": identities(artifact),
        "nitro": {
            "revision": PINNED_REVISION,
            "rpcEndpoint": doctor.get("rpcEndpoint"),
            "chainId": chain_id,
            "doctorSha256": hashlib.sha256(doctor_path.read_bytes()).hexdigest(),
        },
        "gates": gates,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact", type=Path, required=True)
    parser.add_argument("--doctor", type=Path, required=True)
    parser.add_argument("--evidence-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    temporary = args.output.with_suffix(args.output.suffix + ".tmp")
    args.output.unlink(missing_ok=True)
    temporary.unlink(missing_ok=True)
    try:
        payload = assemble(args.artifact, args.doctor, args.evidence_root)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        temporary.replace(args.output)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1
    print(f"stylus-nitro-evidence: ok ({args.output})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
