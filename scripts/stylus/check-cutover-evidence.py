#!/usr/bin/env python3

import argparse
import datetime
import json
import pathlib
import sys


REQUIRED_GATES = (
    "valueVault",
    "mappingEvents",
    "token",
    "remoteCall",
    "aggregate",
)


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
