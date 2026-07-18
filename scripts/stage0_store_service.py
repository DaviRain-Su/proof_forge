#!/usr/bin/env python3
"""Authority-store service child entry for the Stage-0 activation driver.

This executable is the local-model authority-store service process: the
driver spawns it with either a pre-connected channel fd (the service end of
the handoff socketpair, inherited across exec) or a Unix socket path to
listen on.  Its own file bytes are what the service descriptor's
``serviceExecutableDigest`` pins in this development slice; the driver
recomputes that digest before spawning and fails closed on any drift.  The
service seed is read only from the explicit ``--seed-file`` path with the
signing-tool custody discipline; nothing else here touches key material.
"""

from __future__ import annotations

import importlib.util
import json
import os
import socket
import sys
import threading
from pathlib import Path
from types import ModuleType
from typing import Optional, Tuple


def _load_sibling(module_name: str, file_name: str) -> ModuleType:
    module_path = Path(__file__).resolve(strict=True)
    target_path = module_path.with_name(file_name)
    spec = importlib.util.spec_from_file_location(module_name, target_path)
    if spec is None or spec.loader is None or spec.origin is None:
        raise ImportError(f"exact sibling loader is unavailable for {file_name}")
    if Path(spec.origin).resolve(strict=True) != target_path.resolve(strict=True):
        raise ImportError(f"exact sibling origin changed for {file_name}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


_STORE = _load_sibling(
    "proof_forge_authority_store_for_service_child", "authority_store.py"
)
_SIGN_TOOL = _load_sibling(
    "proof_forge_bootstrap_sign_tool_for_service_child",
    "bootstrap_sign_tool.py",
)


def _read_file(path: str, maximum: int = 16 * 1024 * 1024) -> bytes:
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        chunks = []
        offset = 0
        while True:
            chunk = os.pread(fd, 65536, offset)
            if not chunk:
                break
            chunks.append(chunk)
            offset += len(chunk)
            if offset > maximum:
                raise ValueError("input file exceeds the maximum")
        return b"".join(chunks)
    finally:
        os.close(fd)


_USAGE = (
    "usage: stage0_store_service.py --policy <path> --seed-file <path> "
    "--descriptor <path> --run-id <id> --nonce <hex> "
    "(--fd <n> | --socket <path>)"
)


def main(argv: Optional[Tuple[str, ...]] = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    options = {
        "--policy": None,
        "--seed-file": None,
        "--descriptor": None,
        "--run-id": None,
        "--nonce": None,
        "--fd": None,
        "--socket": None,
    }
    index = 0
    while index < len(args):
        flag = args[index]
        if flag not in options or index + 1 >= len(args):
            print(_USAGE, file=sys.stderr)
            return 2
        if options[flag] is not None:
            print(_USAGE, file=sys.stderr)
            return 2
        options[flag] = args[index + 1]
        index += 2
    if (options["--fd"] is None) == (options["--socket"] is None):
        print(_USAGE, file=sys.stderr)
        return 2
    if any(options[flag] is None for flag in (
        "--policy", "--seed-file", "--descriptor", "--run-id", "--nonce",
    )):
        print(_USAGE, file=sys.stderr)
        return 2
    try:
        policy_bytes = _read_file(options["--policy"])
        descriptor_wire = json.loads(
            _read_file(options["--descriptor"]).decode("utf-8", errors="strict")
        )
        seed = _SIGN_TOOL.read_seed_file(options["--seed-file"])
        if type(descriptor_wire) is not dict:
            raise ValueError("descriptor must be an object")
        server = _STORE.AuthorityStoreServer(
            policy_bytes=policy_bytes,
            service_seed=seed,
            descriptor_id=descriptor_wire["id"],
            descriptor_version=descriptor_wire["version"],
            service_executable_digest=_STORE._CONSUMER.parse_digest(
                descriptor_wire["serviceExecutableDigest"]
            ),
            namespace_id=descriptor_wire["namespaceId"],
            expected_run_id=options["--run-id"],
            expected_nonce=options["--nonce"],
            io_timeout_seconds=30.0,
        )
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"service child setup failed: {error}", file=sys.stderr)
        return 3
    except _SIGN_TOOL.SignToolError as error:
        print(f"service seed rejected: {error.code}", file=sys.stderr)
        return 3
    except _STORE.AuthorityStoreError as error:
        print(f"service setup rejected: {error.code}", file=sys.stderr)
        return 3

    if options["--fd"] is not None:
        try:
            channel_fd = int(options["--fd"], 10)
            connection = socket.socket(fileno=channel_fd)
        except (ValueError, OSError) as error:
            print(f"service channel fd invalid: {error}", file=sys.stderr)
            return 3
        threading.Thread(
            target=server._serve_connection,
            args=(connection,),
            name="authority-store-handoff-channel",
            daemon=True,
        ).start()
    else:
        socket_path = options["--socket"]
        try:
            os.unlink(socket_path)
        except FileNotFoundError:
            pass
        except OSError as error:
            print(f"service socket setup failed: {error}", file=sys.stderr)
            return 3
        try:
            server.serve_unix(socket_path)
        except _STORE.AuthorityStoreError as error:
            print(f"service listen failed: {error.code}", file=sys.stderr)
            return 3
    print("service: ready", flush=True)
    threading.Event().wait()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
