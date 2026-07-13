#!/usr/bin/env python3

import json
from pathlib import Path
import subprocess
import sys
import tempfile


root = Path(__file__).resolve().parents[2]
assembler = root / "scripts/stylus/assemble-nitro-evidence.py"
revision = "62f6cae30942f82958695697d3de8b4e1447ea7f"
with tempfile.TemporaryDirectory() as directory:
    work = Path(directory)
    artifact = work / "artifact.json"
    doctor = work / "doctor.json"
    evidence = work / "evidence"
    output = work / "final.json"
    sha = "1" * 64
    artifact.write_text(json.dumps({
        "target": "wasm-arbitrum-stylus",
        "artifactBundle": {"outputs": [
            {"kind": "stylus-plan", "sha256": sha},
            {"kind": "stylus-storage-layout", "sha256": sha},
            {"kind": "solidity-abi", "sha256": sha},
        ]},
    }))
    doctor.write_text(json.dumps({
        "ready": True,
        "nitroRevision": revision,
        "rpcEndpoint": "http://127.0.0.1:8547",
        "rpcChainId": "412346",
    }))
    paths = {
        "valueVault": "value-vault/summary.json",
        "mappingEvents": "token/mapping-events-summary.json",
        "token": "token/summary.json",
        "remoteCall": "remote-call/summary.json",
        "aggregate": "aggregate/summary.json",
    }
    gate = {
        "schema": "proof-forge.stylus.nitro-gate.v1",
        "state": "passed",
        "skipped": False,
        "provenance": "nitro-testnode",
        "chainId": 412346,
        "transactions": {"scenario": "0x" + "2" * 64},
        "artifacts": {"wasmSha256": "3" * 64},
    }
    for name, relative in paths.items():
        path = evidence / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({**gate, "gate": name}))

    command = [
        sys.executable, str(assembler), "--artifact", str(artifact),
        "--doctor", str(doctor), "--evidence-root", str(evidence),
        "--output", str(output),
    ]
    assert subprocess.run(command, check=False).returncode == 0
    payload = json.loads(output.read_text())
    assert set(payload["gates"]) == set(paths)
    assert payload["nitro"]["revision"] == revision

    remote = evidence / paths["remoteCall"]
    broken = json.loads(remote.read_text())
    broken["skipped"] = True
    remote.write_text(json.dumps(broken))
    assert subprocess.run(command, check=False).returncode == 1
    assert not output.exists()

print("stylus-nitro-evidence-self-test: ok")
