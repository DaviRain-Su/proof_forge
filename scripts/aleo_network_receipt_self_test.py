#!/usr/bin/env python3
"""Focused no-network tests for the Aleo deploy/receipt engine."""

from __future__ import annotations

import contextlib
import hashlib
import importlib.util
import io
import json
import os
import shutil
import stat
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODULE_PATH = ROOT / "scripts" / "aleo_network_receipt.py"


def load_module():
    spec = importlib.util.spec_from_file_location("proof_forge_aleo_network_receipt", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {MODULE_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def expect_raises(error_type, thunk, label: str) -> None:
    try:
        thunk()
    except error_type:
        return
    raise AssertionError(f"expected {error_type.__name__}: {label}")


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_regular(path: Path, data: bytes, mode: int = 0o600) -> None:
    path.write_bytes(data)
    path.chmod(mode)


def build_output_fixture(root: Path) -> tuple[Path, str]:
    out = root / "output"
    out.mkdir(mode=0o700)
    program_id = "receiptprobe.aleo"
    instructions = (
        b"program receiptprobe.aleo;\n\n"
        b"function initialize:\n    input r0 as u64.public;\n    finalize r0;\n"
    )
    program_meta = {
        "program": program_id,
        "version": "0.1.0",
        "description": "",
        "license": "",
        "leo": "4.0.2",
        "dependencies": None,
        "dev_dependencies": None,
    }
    program_meta_bytes = (json.dumps(program_meta, indent=2) + "\n").encode("utf-8")
    files = {
        "receiptprobe.aleo": ("materialized-base", instructions),
        "receiptprobe.compiled.aleo": ("finalized-extra", instructions),
        "receiptprobe.leo-program.json": ("finalized-extra", program_meta_bytes),
    }
    descriptors = []
    for name, (role, data) in files.items():
        write_regular(out / name, data, 0o644)
        descriptors.append(
            {
                "role": role,
                "path": name,
                "size": len(data),
                "contentSha256": sha256_hex(data),
            }
        )
    manifest = {
        "schemaVersion": "proof-forge.output.v1",
        "target": "aleo",
        "codegenProfile": "aleo-leo-4.0.2-u64-compile-v1",
        "artifactProgramName": "ReceiptProbe",
        "sourceHash": "01" * 32,
        "semanticHash": "02" * 32,
        "buildIdentityDigest": "03" * 32,
        "planDigest": "04" * 32,
        "supportClaimDigest": "05" * 32,
        "engineeringRegistryRootDigest": "06" * 32,
        "outputSetDigest": "07" * 32,
        "evidenceSha256": "08" * 32,
        "deployable": False,
        "files": descriptors,
    }
    write_regular(out / "manifest.json", (json.dumps(manifest, indent=2) + "\n").encode(), 0o644)
    return out, program_id


def run() -> None:
    m = load_module()

    dev = m.normalize_endpoint("devnet", "http://127.0.0.1:3030/")
    assert dev.base_url == "http://127.0.0.1:3030"
    assert dev.rest_network == "testnet"
    public = m.normalize_endpoint("testnet", "https://api.explorer.provable.com/v2")
    assert public.base_url == "https://api.explorer.provable.com/v2"
    expect_raises(m.NetworkConfigError, lambda: m.normalize_endpoint("mainnet", "https://example.com"), "mainnet disabled")
    expect_raises(m.NetworkConfigError, lambda: m.normalize_endpoint("devnet", "http://192.0.2.1:3030"), "devnet must be loopback")
    expect_raises(m.NetworkConfigError, lambda: m.normalize_endpoint("testnet", "http://example.com"), "testnet requires https")
    expect_raises(m.NetworkConfigError, lambda: m.normalize_endpoint("testnet", "https://user@example.com/v2"), "userinfo rejected")
    expect_raises(m.NetworkConfigError, lambda: m.normalize_endpoint("testnet", "https://example.com/v2?q=1"), "query rejected")

    with tempfile.TemporaryDirectory(
        prefix="pf-aleo-network-self-test.",
        dir=Path(tempfile.gettempdir()).resolve(),
    ) as td:
        tmp = Path(td)
        key = tmp / "account.key"
        write_regular(key, b"not-a-real-private-key\n", 0o600)
        signer = m.validate_signer("testnet", private_key_file=key, dev_key=None)
        assert signer.tool_args == ()
        assert signer.private_key_path == key.resolve()
        assert signer.receipt_kind == "private-key-file-via-inherited-fd"
        assert str(key) not in json.dumps(signer.public_receipt)
        signer_fd, child_args = m.open_signer_for_children(signer)
        assert signer_fd is not None
        try:
            assert child_args[0] == "--private-key-file"
            assert child_args[1].endswith(f"/{signer_fd}")
            assert str(key) not in child_args[1]
        finally:
            os.close(signer_fd)

        replace_key = tmp / "replace-account.key"
        write_regular(replace_key, b"first-key-material\n", 0o600)
        replace_signer = m.validate_signer("testnet", private_key_file=replace_key, dev_key=None)
        original_key = tmp / "replace-account.original"
        replace_key.rename(original_key)
        write_regular(replace_key, b"other-key-material\n", 0o600)
        expect_raises(
            m.NetworkConfigError,
            lambda: m.open_signer_for_children(replace_signer),
            "private key replacement after validation",
        )

        key.chmod(0o644)
        expect_raises(m.NetworkConfigError, lambda: m.validate_signer("testnet", private_key_file=key, dev_key=None), "private key permissions")
        key.chmod(0o600)
        link = tmp / "key-link"
        link.symlink_to(key)
        expect_raises(m.NetworkConfigError, lambda: m.validate_signer("testnet", private_key_file=link, dev_key=None), "private key symlink")
        hard = tmp / "key-hard"
        os.link(key, hard)
        expect_raises(m.NetworkConfigError, lambda: m.validate_signer("testnet", private_key_file=key, dev_key=None), "private key hardlink")
        hard.unlink()
        assert m.validate_signer("devnet", private_key_file=None, dev_key=0).receipt_kind == "dev-key"
        expect_raises(m.NetworkConfigError, lambda: m.validate_signer("devnet", private_key_file=key, dev_key=None), "devnet uses dev key")
        expect_raises(m.NetworkConfigError, lambda: m.validate_signer("testnet", private_key_file=None, dev_key=0), "testnet uses key file")

        pinned_snarkos = tmp / "snarkos-pinned"
        write_regular(
            pinned_snarkos,
            b"#!/bin/sh\nprintf '%s\\n' 'snarkos 4.9.0 test features=[default]'\n",
            0o700,
        )
        pinned_digest = sha256_hex(pinned_snarkos.read_bytes())
        snarkos_snapshot = tmp / "snarkos-snapshot"
        tool_snapshot = m.prepare_snarkos_snapshot(
            str(pinned_snarkos), "testnet", pinned_digest, snarkos_snapshot, probe_home=tmp
        )
        try:
            assert tool_snapshot.path == snarkos_snapshot.resolve()
            assert tool_snapshot.path.read_bytes() == pinned_snarkos.read_bytes()
            assert tool_snapshot.version_line.startswith("snarkos 4.9.0")
            assert tool_snapshot.content_sha256 == pinned_digest
            retained_original = tmp / "snarkos-snapshot-retained-original"
            snarkos_snapshot.rename(retained_original)
            write_regular(
                snarkos_snapshot,
                b"#!/bin/sh\nprintf '%s\\n' 'snarkos 0.0.0 replacement'\n",
                0o500,
            )
            if Path("/proc/self/fd").is_dir():
                assert tool_snapshot.exec_path != str(tool_snapshot.path)
            else:
                assert tool_snapshot.exec_path == str(tool_snapshot.path)
            expect_raises(
                m.ToolchainError,
                lambda: m._verify_retained_snarkos(tool_snapshot),
                "retained snarkos fails closed after its published path is replaced",
            )
        finally:
            os.close(tool_snapshot.fd)
        expect_raises(
            m.ToolchainError,
            lambda: m.prepare_snarkos_snapshot(
                str(pinned_snarkos), "testnet", None, tmp / "missing-pin-snapshot", probe_home=tmp
            ),
            "testnet requires an explicit snarkos digest pin",
        )
        pinned_snarkos.chmod(0o720)
        expect_raises(
            m.ToolchainError,
            lambda: m.prepare_snarkos_snapshot(
                str(pinned_snarkos), "testnet", pinned_digest, tmp / "bad-mode-snapshot", probe_home=tmp
            ),
            "testnet rejects group-writable snarkos",
        )
        pinned_snarkos.chmod(0o700)

        output_dir, program_id = build_output_fixture(tmp)
        snapshot_dir = tmp / "output-snapshot"
        copied = m.snapshot_output_tree(output_dir, snapshot_dir)
        assert copied == snapshot_dir
        assert (snapshot_dir / "manifest.json").read_bytes() == (output_dir / "manifest.json").read_bytes()
        assert stat.S_IMODE((snapshot_dir / "manifest.json").stat().st_mode) == 0o600
        symlinked_output = tmp / "output-with-link"
        shutil.copytree(output_dir, symlinked_output)
        (symlinked_output / "bad-link").symlink_to(output_dir / "manifest.json")
        expect_raises(m.OutputInputError, lambda: m.snapshot_output_tree(symlinked_output, tmp / "bad-snapshot"), "snapshot rejects symlink")
        expect_raises(m.ReceiptError, lambda: m._reject_output_receipt_overlap(output_dir.resolve(), (output_dir / "receipt").resolve(strict=False)), "receipt descendant overlap")
        symlink_parent = tmp / "receipt-parent-link"
        symlink_parent.symlink_to(tmp)
        expect_raises(m.ReceiptError, lambda: m.reserve_receipt_destination(symlink_parent / "receipt"), "receipt symlink parent")
        expect_raises(m.ReceiptError, lambda: m.reserve_receipt_destination(tmp / "missing-parent" / "receipt"), "receipt parent must preexist")
        writable_parent = tmp / "group-writable-receipt-parent"
        writable_parent.mkdir(mode=0o770)
        writable_parent.chmod(0o770)
        expect_raises(
            m.ReceiptError,
            lambda: m.reserve_receipt_destination(writable_parent / "receipt"),
            "receipt parent writable by group",
        )
        existing_receipt = tmp / "existing-receipt"
        existing_receipt.mkdir()
        expect_raises(m.ReceiptError, lambda: m.reserve_receipt_destination(existing_receipt), "receipt destination collision")
        receipt_link = tmp / "receipt-link"
        receipt_link.symlink_to(existing_receipt, target_is_directory=True)
        expect_raises(m.ReceiptError, lambda: m.reserve_receipt_destination(receipt_link), "receipt destination symlink")
        expect_raises(m.NetworkConfigError, lambda: m._parse_args(["--private-key=secret-value"]), "raw private key prescan")
        try:
            m._parse_args(["--private-key", "secret-value"])
        except m.NetworkConfigError as error:
            assert "secret-value" not in str(error)
        else:
            raise AssertionError("raw private key pair should fail closed")
        try:
            m._parse_args(["--definitely-secret-unknown=secret-value"])
        except m.NetworkConfigError as error:
            assert "secret-value" not in str(error)
        else:
            raise AssertionError("unknown argument should fail closed")

        original_popen = m.subprocess.Popen
        original_selector = m.selectors.DefaultSelector
        captured_processes = []
        class InterruptSelector:
            def register(self, *_args, **_kwargs):
                return None
            def select(self, *_args, **_kwargs):
                raise KeyboardInterrupt()
            def close(self):
                return None
        def capturing_popen(*args, **kwargs):
            process = original_popen(*args, **kwargs)
            captured_processes.append(process)
            return process
        try:
            m.subprocess.Popen = capturing_popen
            m.selectors.DefaultSelector = InterruptSelector
            expect_raises(
                KeyboardInterrupt,
                lambda: m.run_bounded_process(
                    ["/bin/sh", "-c", "sleep 30"],
                    cwd=None,
                    env={"PATH": "/usr/bin:/bin"},
                    timeout_seconds=30,
                ),
                "KeyboardInterrupt terminates and reaps process group",
            )
            assert captured_processes and captured_processes[0].poll() is not None
        finally:
            m.subprocess.Popen = original_popen
            m.selectors.DefaultSelector = original_selector

        try:
            m.run_bounded_process(
                [
                    "/bin/sh",
                    "-c",
                    "sleep 30 & printf '%s\\n' descendant-held-stdout; exit 0",
                ],
                cwd=None,
                env={"PATH": "/usr/bin:/bin"},
                timeout_seconds=1,
            )
        except m.ProcessRunError as error:
            assert error.timed_out is True
            assert "descendant-held-stdout" in error.output
        else:
            raise AssertionError("descendant-held stdout should hit the bounded deadline")

        failed_txid = "at1" + "f" * 58
        try:
            m._run_snarkos_action(
                "NETWORK-FAIL-EVIDENCE",
                [
                    "/bin/sh",
                    "-c",
                    f"printf '%s\\n' 'Transaction ID: {failed_txid}'; exit 9",
                ],
                cwd=tmp,
                env={"PATH": "/usr/bin:/bin"},
                process_timeout=5,
                redactions=(),
            )
        except m.SnarkosActionError as error:
            assert error.returncode == 9
            assert error.timed_out is False
            assert m.extract_transaction_id(error.output) == failed_txid
        else:
            raise AssertionError("failed snarkOS action should preserve output evidence")

        unrenderable_private_key = "private-key-bytes-must-not-render"
        suppressed_output = io.StringIO()
        with contextlib.redirect_stdout(suppressed_output):
            m._print_safe_action_tail(
                "NETWORK-TESTNET-SUPPRESSED",
                f"secret={unrenderable_private_key}\nTransaction ID: {failed_txid}\n",
                (),
                render_raw_tail=False,
            )
        suppressed_text = suppressed_output.getvalue()
        assert unrenderable_private_key not in suppressed_text
        assert "raw tail suppressed" in suppressed_text
        assert failed_txid in suppressed_text

        expect_raises(
            m.NetworkConfigError,
            lambda: m.run([
                "--output-dir", str(tmp / "missing-output"),
                "--receipt-dir", str(tmp / "missing-receipt"),
                "--network", "mainnet",
                "--broadcast",
            ]),
            "mainnet rejected before path/tool validation",
        )

        deployment_input = m.load_deployment_input(snapshot_dir)
        assert deployment_input.program_id == program_id
        assert deployment_input.build_deployable is False
        package = tmp / "package"
        m.stage_snarkos_package(deployment_input, package)
        assert (package / "main.aleo").read_bytes() == (output_dir / "receiptprobe.aleo").read_bytes()
        assert json.loads((package / "program.json").read_text())["program"] == program_id

        txid = "at1" + "q" * 58
        assert m.extract_transaction_id(f"Transaction ID: {txid}\n") == txid
        assert m.extract_transaction_id("no transaction id here") is None

        tool = tmp / "snarkos"
        write_regular(tool, b"fake-snarkos-binary", 0o700)
        captured_tool_digest = sha256_hex(tool.read_bytes())
        write_regular(tool, b"mutated-after-capture", 0o700)
        deploy_log = f"Created deployment\nTransaction ID: {txid}\n"
        endpoint = m.normalize_endpoint("devnet", "http://127.0.0.1:3030")
        payload = m.build_receipt_payload(
            deployment_input=deployment_input,
            endpoint=endpoint,
            signer_public={"kind": "dev-key", "index": 0, "secretRecorded": False},
            priority_fee_microcredits=200000,
            snarkos_version_line="snarkos 4.9.0 test features=[test_network]",
            snarkos_content_sha256=captured_tool_digest,
            deploy_log=deploy_log,
            deploy_tool_exit_code=0,
            execution_logs=[
                m.ExecutionLog("initialize", ("1u64",), "confirmed", deploy_log, 0)
            ],
            observations=[{"kind": "mapping", "path": "pf_state_0/0u8", "value": "3u64"}],
        )
        identity_parent = tmp / "receipt-identity-parent"
        identity_parent.mkdir(mode=0o700)
        identity_parent.chmod(0o700)
        identity_reservation = m.reserve_receipt_destination(identity_parent / "receipt")
        moved_parent = tmp / "receipt-identity-parent-moved"
        identity_parent.rename(moved_parent)
        identity_parent.mkdir()
        expect_raises(
            m.ReceiptError,
            lambda: m.publish_reserved_receipt(identity_reservation, payload),
            "receipt publication retains parent identity",
        )
        m.abandon_receipt_reservation(identity_reservation)

        collision_parent = tmp / "receipt-collision-parent"
        collision_parent.mkdir(mode=0o700)
        collision_parent.chmod(0o700)
        collision_destination = collision_parent / "receipt"
        collision_reservation = m.reserve_receipt_destination(collision_destination)
        collision_destination.mkdir(mode=0o700)
        expect_raises(
            m.ReceiptError,
            lambda: m.publish_reserved_receipt(collision_reservation, payload),
            "atomic no-replace publication rejects a late destination",
        )
        m.abandon_receipt_reservation(collision_reservation)
        shutil.rmtree(collision_destination)

        interrupted_receipt = tmp / "receipt-interrupted-after-rename"
        original_rename = m._rename_directory_noreplace
        def rename_then_interrupt(parent_fd, source, destination):
            original_rename(parent_fd, source, destination)
            raise KeyboardInterrupt()
        try:
            m._rename_directory_noreplace = rename_then_interrupt
            expect_raises(
                KeyboardInterrupt,
                lambda: m.write_receipt_atomic(interrupted_receipt, payload),
                "interrupt after atomic rename preserves the committed receipt",
            )
        finally:
            m._rename_directory_noreplace = original_rename
        assert (interrupted_receipt / "receipt.json").is_file()

        receipt_dir = tmp / "receipt"
        receipt_path = m.write_receipt_atomic(receipt_dir, payload)
        receipt = json.loads(receipt_path.read_text())
        rendered = receipt_path.read_text()
        assert receipt["schema"] == "proof-forge.aleo-deployment-receipt.engineering.v1"
        assert receipt["networkProfile"]["registrationStatus"] == "unregistered-engineering"
        assert receipt["build"]["outputSetDigest"] == "07" * 32
        assert receipt["deployment"]["transactionId"] == txid
        assert receipt["tool"]["lockStatus"] == "outside-tool-lock"
        assert receipt["tool"]["contentSha256"] == captured_tool_digest
        assert "not-a-real-private-key" not in rendered
        assert str(key) not in rendered
        expect_raises(m.ReceiptError, lambda: m.write_receipt_atomic(receipt_dir, payload), "receipt collision")

        partial_receipt_dir = tmp / "partial-receipt"
        original_inspect = m._inspect_output
        original_wait = m._wait_program_visible
        original_action = m._run_snarkos_action
        try:
            m._inspect_output = lambda root, output: None
            m._wait_program_visible = lambda endpoint, program_id, timeout: False
            failed_deploy_log = (
                "simulated failed deployment\n"
                f"Transaction ID: {failed_txid}\n"
            )
            def fail_after_spawn(_label, command, **kwargs):
                key_option = command.index("--private-key-file")
                inherited_key_reference = command[key_option + 1]
                assert str(key.resolve()) not in command
                assert inherited_key_reference in kwargs["redactions"]
                assert inherited_key_reference.startswith(("/proc/self/fd/", "/dev/fd/"))
                assert kwargs["render_raw_tail"] is False
                raise m.SnarkosActionError(
                    "NETWORK-DEPLOY",
                    output=failed_deploy_log,
                    returncode=9,
                    timed_out=False,
                )
            m._run_snarkos_action = fail_after_spawn
            try:
                m.run([
                    "--output-dir", str(output_dir),
                    "--receipt-dir", str(partial_receipt_dir),
                    "--network", "testnet",
                    "--endpoint", "https://api.explorer.provable.com/v2",
                    "--broadcast",
                    "--private-key-file", str(key.resolve()),
                    "--snarkos", str(pinned_snarkos.resolve()),
                    "--snarkos-sha256", pinned_digest,
                ])
            except m.DeploymentError:
                pass
            else:
                raise AssertionError("simulated deployment failure should propagate")
        finally:
            m._inspect_output = original_inspect
            m._wait_program_visible = original_wait
            m._run_snarkos_action = original_action
        partial = json.loads((partial_receipt_dir / "receipt.json").read_text())
        assert partial["deployment"]["status"] == "attempted-unobserved"
        assert partial["deployment"]["transactionId"] == failed_txid
        assert partial["deployment"]["toolExitCode"] == 9
        assert partial["deployment"]["toolOutputBytes"] == len(failed_deploy_log.encode())
        assert partial["deployment"]["toolOutputSha256"] == sha256_hex(
            failed_deploy_log.encode()
        )
        assert partial["failure"].startswith("PF-NETWORK-DEPLOY:")
        assert str(key) not in json.dumps(partial)

        mode = stat.S_IMODE(receipt_path.stat().st_mode)
        assert mode == 0o644

    print("aleo-network-self-test: ok")


if __name__ == "__main__":
    run()
