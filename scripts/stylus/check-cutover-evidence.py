#!/usr/bin/env python3

import argparse
import datetime
import json
import pathlib
import re
import sys


REQUIRED_GATES = (
    "valueVault",
    "mappingEvents",
    "token",
    "remoteCall",
    "aggregate",
)
PINNED_REVISION = "62f6cae30942f82958695697d3de8b4e1447ea7f"
LOCAL_RPC_ENDPOINT = "http://127.0.0.1:8547"
HEX_32 = re.compile(r"^0x[0-9a-fA-F]{64}$")
SHA_256 = re.compile(r"^[0-9a-f]{64}$")


def fail(message: str) -> None:
    raise ValueError(f"stylus cutover evidence: {message}")


def validate(payload: object, plan_sha: str, storage_sha: str, abi_sha: str,
             now: datetime.datetime, max_age_seconds: int) -> dict:
    if not isinstance(payload, dict):
        fail("root must be an object")
    if payload.get("schemaVersion") != "1":
        fail("schemaVersion must be 1")
    if payload.get("target") != "wasm-arbitrum-stylus":
        fail("target must be wasm-arbitrum-stylus")
    if payload.get("planSchemaVersion") != "stylus-plan-v1":
        fail("planSchemaVersion must be stylus-plan-v1")
    identities = payload.get("identities")
    expected = {
        "planSha256": plan_sha,
        "storageSha256": storage_sha,
        "abiSha256": abi_sha,
    }
    if identities != expected:
        fail("plan/storage/ABI identity does not match this artifact")
    generated = payload.get("generatedAt")
    if not isinstance(generated, str):
        fail("generatedAt must be an ISO-8601 UTC timestamp")
    try:
        timestamp = datetime.datetime.fromisoformat(generated.replace("Z", "+00:00"))
    except ValueError:
        fail("generatedAt must be an ISO-8601 UTC timestamp")
    if timestamp.tzinfo is None:
        fail("generatedAt must include a timezone")
    age = (now - timestamp.astimezone(datetime.timezone.utc)).total_seconds()
    if age < -300:
        fail("generatedAt is in the future")
    if age > max_age_seconds:
        fail(f"evidence is stale ({int(age)} seconds old)")
    nitro = payload.get("nitro")
    if not isinstance(nitro, dict):
        fail("nitro identity must be an object")
    if nitro.get("revision") != PINNED_REVISION:
        fail("nitro revision does not match the pinned testnode")
    if nitro.get("rpcEndpoint") != LOCAL_RPC_ENDPOINT:
        fail("nitro RPC endpoint is not the pinned local testnode")
    chain_id = nitro.get("chainId")
    if not isinstance(chain_id, int) or chain_id <= 0:
        fail("nitro chainId must be a positive integer")
    if not isinstance(nitro.get("doctorSha256"), str) or not SHA_256.fullmatch(nitro["doctorSha256"]):
        fail("nitro doctor hash is malformed")
    gates = payload.get("gates")
    if not isinstance(gates, dict):
        fail("gates must be an object")
    for name in REQUIRED_GATES:
        gate = gates.get(name)
        if not isinstance(gate, dict):
            fail(f"missing required gate {name}")
        if gate.get("skipped") is not False:
            fail(f"gate {name} must explicitly set skipped=false")
        if gate.get("state") != "passed":
            fail(f"gate {name} did not pass")
        if gate.get("provenance") != "nitro-testnode":
            fail(f"gate {name} must have nitro-testnode provenance")
        if gate.get("chainId") != chain_id:
            fail(f"gate {name} does not match the Nitro chain id")
        transactions = gate.get("transactions")
        if not isinstance(transactions, dict) or not transactions:
            fail(f"gate {name} must contain transactions")
        if not all(isinstance(value, str) and HEX_32.fullmatch(value)
                   for value in transactions.values()):
            fail(f"gate {name} contains a malformed transaction hash")
        artifacts = gate.get("artifacts")
        if not isinstance(artifacts, dict) or not artifacts:
            fail(f"gate {name} must contain artifact identities")
        if not all(isinstance(value, str) and SHA_256.fullmatch(value)
                   for value in artifacts.values()):
            fail(f"gate {name} contains a malformed artifact hash")
        if not isinstance(gate.get("summarySha256"), str) or not SHA_256.fullmatch(gate["summarySha256"]):
            fail(f"gate {name} summary hash is malformed")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--plan-sha256", required=True)
    parser.add_argument("--storage-sha256", required=True)
    parser.add_argument("--abi-sha256", required=True)
    parser.add_argument("--max-age-seconds", type=int, default=604800)
    parser.add_argument("--now")
    args = parser.parse_args()
    try:
        now = (datetime.datetime.fromisoformat(args.now.replace("Z", "+00:00"))
               if args.now else datetime.datetime.now(datetime.timezone.utc))
        payload = json.loads(args.input.read_text(encoding="utf-8"))
        payload = validate(payload, args.plan_sha256, args.storage_sha256,
                           args.abi_sha256, now, args.max_age_seconds)
        args.output.write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1
    print("stylus-cutover-evidence: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
