#!/usr/bin/env python3
"""D0-08 pre-freeze RED: stable compiler-runtime observation seam.

Future public API under test (not implemented yet -- this suite is RED):

    toolchain_assets.observe_compiler_runtime(
        *,
        lock,
        host_lock,
        root,
        macho_paths,
        tree_manifest,
    ) -> CompilerRuntimeObservation

The API is deliberately bound to the existing production inputs:

* ``lock`` owns compiler entrypoints and allowed system load roots;
* ``host_lock`` owns the exact ``otool`` selected by ``locked_otool``;
* ``macho_paths`` is the verified Mach-O set returned by ``verify_lean_tree``;
* ``tree_manifest`` is the exact ``extract_lean_zip`` witness map.

Tests monkeypatch only the existing ``locked_otool`` and ``subprocess.run``
seams.  The production API does not accept an unverified executable or an
ambient runner.  A successful observation must combine the exact typed graph
with witnesses retained across one no-follow, single-link, stable-read window.
All public failures use the real ``AssetError`` channel with a nonempty stable
``code`` (``PF-SBOM-IO`` for unsafe nodes/races and ``PF-SBOM-CLOSURE`` for
authoritative witness/graph mismatch), without leaking an unsuppressed cause.

This suite is only a pre-freeze primitive.  It does not claim TST-SBOM-002,
SBOM publication, materialize_lean integration, or TASK-D0-08 activation.
"""

from __future__ import annotations

import hashlib
import importlib.util
import os
import signal
import sys
import tempfile
from pathlib import Path
from types import ModuleType, SimpleNamespace
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple


ROOT = Path(__file__).resolve().parents[1]
ASSETS_PATH = ROOT / "scripts" / "toolchain_assets.py"

SYSTEM_ROOTS = ("/System/Library/", "/usr/lib/")
ENTRYPOINTS = ("bin/lake", "bin/lean")
RUNTIME_IMAGES = (
    "bin/lake",
    "bin/lean",
    "lib/core.dylib",
    "lib/unused.dylib",
    "lib/util.dylib",
)
NON_MACHO_FILE = "share/readme.txt"
OTOOL_MODES = ("-hv", "-l", "-L", "-D")
MACHO_MAGIC_64_LE = b"\xcf\xfa\xed\xfe"

# Every runtime payload begins with a real magic accepted by verify_lean_tree.
# The remaining bytes are distinct so a same-size content substitution cannot
# accidentally share a digest.
PAYLOADS = {
    "bin/lake": MACHO_MAGIC_64_LE + b"synthetic-lake-v1\n",
    "bin/lean": MACHO_MAGIC_64_LE + b"synthetic-lean-v1\n",
    "lib/core.dylib": MACHO_MAGIC_64_LE + b"synthetic-core-v1\n",
    "lib/unused.dylib": MACHO_MAGIC_64_LE + b"synthetic-unused-v1\n",
    "lib/util.dylib": MACHO_MAGIC_64_LE + b"synthetic-util-v1\n",
    NON_MACHO_FILE: b"not-a-mach-o-runtime-image\n",
}

EXPECTED_GRAPH = (
    (
        "entrypoints",
        (
            (
                "bin/lake",
                (("@rpath/core.dylib", "lib/core.dylib"),),
                ("lib/core.dylib", "lib/util.dylib"),
            ),
            (
                "bin/lean",
                (("@rpath/core.dylib", "lib/core.dylib"),),
                ("lib/core.dylib", "lib/util.dylib"),
            ),
        ),
    ),
    (
        "files",
        (
            (
                "lib/core.dylib",
                ("bin/lake", "bin/lean"),
                (("@rpath/util.dylib", "lib/util.dylib"),),
            ),
            (
                "lib/util.dylib",
                ("bin/lake", "bin/lean"),
                (),
            ),
        ),
    ),
)


def load_module(path: Path, name: str) -> ModuleType:
    if not path.is_file():
        raise AssertionError("required module missing: {0}".format(path))
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise AssertionError("cannot load {0}".format(path))
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def load_assets() -> ModuleType:
    return load_module(
        ASSETS_PATH,
        "proof_forge_toolchain_assets_observation_test",
    )


def require_observe(assets: ModuleType) -> Callable[..., Any]:
    observe = getattr(assets, "observe_compiler_runtime", None)
    if observe is None:
        raise AssertionError(
            "RED expected: toolchain_assets.observe_compiler_runtime is not "
            "implemented yet"
        )
    return observe


def expect_asset_error(
    assets: ModuleType,
    expected_code: str,
    operation: Callable[[], object],
) -> None:
    """Require the real AssetError channel plus exact stable error family."""

    try:
        operation()
    except assets.AssetError as error:
        code = getattr(error, "code", None)
        if code != expected_code:
            raise AssertionError(
                "expected AssetError code {0!r}, got {1!r}: {2}".format(
                    expected_code, code, error
                )
            ) from error
        if not str(error):
            raise AssertionError("AssetError detail must be nonempty") from error
        if error.__context__ is not None and not error.__suppress_context__:
            raise AssertionError(
                "AssetError must suppress its internal exception context"
            ) from error
        return
    except Exception as error:  # noqa: BLE001 - assert sole public channel
        raise AssertionError(
            "expected AssetError({0}), got {1}: {2}".format(
                expected_code, type(error).__name__, error
            )
        ) from error
    raise AssertionError("expected AssetError({0})".format(expected_code))


def completed(
    stdout: str = "",
    stderr: str = "",
    returncode: int = 0,
) -> SimpleNamespace:
    return SimpleNamespace(stdout=stdout, stderr=stderr, returncode=returncode)


def hv_execute() -> str:
    return (
        "Mach header\n"
        "      magic cputype cpusubtype  caps    filetype ncmds sizeofcmds      flags\n"
        "MH_MAGIC_64    ARM64        ALL  0x00     EXECUTE    10       1232   NOUNDEFS\n"
    )


def hv_dylib() -> str:
    return (
        "Mach header\n"
        "      magic cputype cpusubtype  caps    filetype ncmds sizeofcmds      flags\n"
        "MH_MAGIC_64    ARM64        ALL  0x00       DYLIB    10       1232   NOUNDEFS\n"
    )


def rpath_cmd(path: str) -> str:
    return (
        "Load command 0\n"
        "      cmd LC_SEGMENT_64\n"
        "Load command 1\n"
        "          cmd LC_RPATH\n"
        "         path {0} (offset 12)\n".format(path)
    )


def load_lines(*install_names: str) -> str:
    return "synthetic:\n" + "".join(
        "\t{0} (compatibility version 0.0.0, current version 0.0.0)\n".format(
            name
        )
        for name in install_names
    )


def id_output(install_id: str) -> str:
    return "synthetic:\n{0}\n".format(install_id)


def make_lock() -> dict:
    return {
        "machoPolicy": {"allowedSystemLoadRoots": list(SYSTEM_ROOTS)},
        "compilerToolchain": {
            "executables": [
                {
                    "path": path,
                    "sha256": hashlib.sha256(PAYLOADS[path]).hexdigest(),
                }
                for path in ENTRYPOINTS
            ]
        },
    }


def make_host_lock() -> dict:
    return {
        "profiles": [
            {
                "developerTools": {
                    "otoolPath": "/fake/locked/otool",
                    "otoolSha256": "a" * 64,
                }
            }
        ]
    }


class OtoolRunner:
    """Exact locked-tool runner with deterministic per-image observations."""

    def __init__(self, root: Path, host_lock: dict) -> None:
        self.root = root
        self.host_lock = host_lock
        self.macho_tool = Path("/fake/locked/otool")
        self.counts: Dict[Tuple[str, str], int] = {}
        self.locked_otool_calls = 0
        self.on_before_mode: Optional[Callable[[str, str], None]] = None
        self.profiles = self._default_profiles()

    def _relative(self, path: Path) -> str:
        if not path.is_absolute():
            raise AssertionError("otool target must be absolute: {0!r}".format(path))
        try:
            return path.relative_to(self.root).as_posix()
        except ValueError as error:
            raise AssertionError(
                "otool target escapes fixture root: {0!r}".format(path)
            ) from error

    @staticmethod
    def _default_profiles() -> Dict[str, Dict[str, Any]]:
        return {
            "bin/lake": {
                "hv": hv_execute(),
                "rpaths": ("@executable_path/../lib",),
                "loads": ("@rpath/core.dylib",),
                "id": None,
            },
            "bin/lean": {
                "hv": hv_execute(),
                "rpaths": ("@loader_path/../lib",),
                "loads": (
                    "@rpath/core.dylib",
                    "/usr/lib/libSystem.B.dylib",
                ),
                "id": None,
            },
            "lib/core.dylib": {
                "hv": hv_dylib(),
                "rpaths": (),
                "loads": (
                    "@rpath/core.dylib",
                    "@rpath/util.dylib",
                ),
                "id": "@rpath/core.dylib",
            },
            "lib/unused.dylib": {
                "hv": hv_dylib(),
                "rpaths": (),
                "loads": ("@rpath/util.dylib",),
                "id": "@rpath/unused.dylib",
            },
            "lib/util.dylib": {
                "hv": hv_dylib(),
                "rpaths": (),
                "loads": (),
                "id": "@rpath/util.dylib",
            },
        }

    def locked_otool(self, host_lock: dict) -> Path:
        if host_lock != self.host_lock:
            raise AssertionError("observe passed a substituted host_lock")
        self.locked_otool_calls += 1
        return self.macho_tool

    def __call__(self, args: Sequence[str], **kwargs: Any) -> SimpleNamespace:
        if type(args) is not list or len(args) != 3:
            raise AssertionError("unexpected otool argv: {0!r}".format(args))
        if Path(args[0]) != self.macho_tool:
            raise AssertionError(
                "observe did not execute the exact locked otool: {0!r}".format(
                    args[0]
                )
            )
        mode = args[1]
        if mode not in OTOOL_MODES:
            raise AssertionError("unexpected otool mode: {0!r}".format(mode))
        expected_kwargs = {
            "check": mode != "-D",
            "capture_output": True,
            "text": True,
            "env": {"LC_ALL": "C"},
            "timeout": 10,
        }
        if kwargs != expected_kwargs:
            raise AssertionError(
                "otool kwargs are not deterministic/contained: {0!r}".format(kwargs)
            )

        relative = self._relative(Path(args[2]))
        if self.on_before_mode is not None:
            self.on_before_mode(relative, mode)
        key = (relative, mode)
        self.counts[key] = self.counts.get(key, 0) + 1
        profile = self.profiles.get(relative)
        if profile is None:
            raise AssertionError("no otool profile for {0}".format(relative))
        if mode == "-hv":
            return completed(stdout=profile["hv"])
        if mode == "-l":
            chunks = [rpath_cmd(value) for value in profile["rpaths"]]
            return completed(stdout="".join(chunks) if chunks else "Load command 0\n")
        if mode == "-L":
            return completed(stdout=load_lines(*profile["loads"]))
        install_id = profile["id"]
        if install_id is None:
            return completed(returncode=1)
        return completed(stdout=id_output(install_id))

    def assert_exact_single_pass(self) -> None:
        if self.locked_otool_calls != 1:
            raise AssertionError(
                "locked_otool must be resolved exactly once, got {0}".format(
                    self.locked_otool_calls
                )
            )
        for relative in RUNTIME_IMAGES:
            for mode in OTOOL_MODES:
                count = self.counts.get((relative, mode), 0)
                if count != 1:
                    raise AssertionError(
                        "expected one otool {0} for {1}, got {2}".format(
                            mode, relative, count
                        )
                    )
        if any(relative == NON_MACHO_FILE for relative, _mode in self.counts):
            raise AssertionError("non-Mach-O tree member reached otool")


def file_mode(relative: str) -> int:
    return 0o555 if relative.startswith(("bin/", "sbin/")) else 0o444


def write_runtime_tree(
    base: Path,
) -> Tuple[Path, List[Path], Dict[str, dict], Dict[str, bytes]]:
    """Materialize a real-magic synthetic tree and extract-shaped manifest."""

    root = (base / "toolchain").resolve()
    root.mkdir(parents=True, mode=0o755)
    tree_manifest: Dict[str, dict] = {
        "bin": {"kind": "directory", "size": 0, "mode": 0o555},
        "lib": {"kind": "directory", "size": 0, "mode": 0o555},
        "share": {"kind": "directory", "size": 0, "mode": 0o555},
    }
    payloads: Dict[str, bytes] = {}
    for relative in (*RUNTIME_IMAGES, NON_MACHO_FILE):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        payload = PAYLOADS[relative]
        path.write_bytes(payload)
        mode = file_mode(relative)
        os.chmod(path, mode)
        payloads[relative] = payload
        tree_manifest[relative] = {
            "kind": "file",
            "size": len(payload),
            "mode": mode,
            "sha256": hashlib.sha256(payload).hexdigest(),
        }
    for directory in (root / "bin", root / "lib", root / "share"):
        os.chmod(directory, 0o555)
    os.chmod(root, 0o555)
    macho_paths = [root / relative for relative in RUNTIME_IMAGES]
    return root, sorted(macho_paths, key=str), tree_manifest, payloads


def overwrite_file(root: Path, relative: str, payload: bytes, mode: int) -> None:
    path = root / relative
    parent = path.parent
    os.chmod(parent, 0o755)
    os.chmod(path, 0o600)
    path.write_bytes(payload)
    os.chmod(path, mode)
    os.chmod(parent, 0o555)


def replace_with_symlink(path: Path, target: Path) -> None:
    os.chmod(path.parent, 0o755)
    path.unlink()
    path.symlink_to(target)
    os.chmod(path.parent, 0o555)


def replace_with_fifo(path: Path) -> None:
    os.chmod(path.parent, 0o755)
    path.unlink()
    os.mkfifo(path, 0o444)
    os.chmod(path, 0o444)
    os.chmod(path.parent, 0o555)


def normalize_graph(graph: object) -> tuple:
    entrypoints = []
    for entry in getattr(graph, "entrypoints", ()):
        entrypoints.append(
            (
                entry.path,
                tuple(
                    (edge.install_name, edge.resolved_path) for edge in entry.loads
                ),
                tuple(entry.reachable),
            )
        )
    files = []
    for file_node in getattr(graph, "files", ()):
        files.append(
            (
                file_node.path,
                tuple(file_node.owners),
                tuple(
                    (edge.install_name, edge.resolved_path)
                    for edge in file_node.loads
                ),
            )
        )
    return (("entrypoints", tuple(entrypoints)), ("files", tuple(files)))


def call_observe(
    assets: ModuleType,
    *,
    lock: dict,
    host_lock: dict,
    root: Path,
    macho_paths: List[Path],
    tree_manifest: object,
    runner: OtoolRunner,
) -> object:
    """Install only the two existing discovery seams for one invocation."""

    observe = require_observe(assets)
    original_locked_otool = assets.locked_otool
    original_run = assets.subprocess.run
    assets.locked_otool = runner.locked_otool
    assets.subprocess.run = runner
    try:
        return observe(
            lock=lock,
            host_lock=host_lock,
            root=root,
            macho_paths=macho_paths,
            tree_manifest=tree_manifest,
        )
    finally:
        assets.locked_otool = original_locked_otool
        assets.subprocess.run = original_run


def bounded(operation: Callable[[], object], seconds: float = 2.0) -> object:
    """Bound FIFO/race negatives so an unsafe blocking open cannot hang CI."""

    def timeout_handler(_signum: int, _frame: object) -> None:
        raise AssertionError("observation operation exceeded {0}s".format(seconds))

    previous = signal.signal(signal.SIGALRM, timeout_handler)
    signal.setitimer(signal.ITIMER_REAL, seconds)
    try:
        return operation()
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)


def invoke_fixture(
    assets: ModuleType,
    root: Path,
    macho_paths: List[Path],
    tree_manifest: object,
    *,
    lock: Optional[dict] = None,
    host_lock: Optional[dict] = None,
    runner: Optional[OtoolRunner] = None,
) -> object:
    selected_host_lock = host_lock if host_lock is not None else make_host_lock()
    selected_runner = (
        runner
        if runner is not None
        else OtoolRunner(root, selected_host_lock)
    )
    return call_observe(
        assets,
        lock=lock if lock is not None else make_lock(),
        host_lock=selected_host_lock,
        root=root,
        macho_paths=macho_paths,
        tree_manifest=tree_manifest,
        runner=selected_runner,
    )


def test_api_missing_is_red(assets: ModuleType) -> None:
    require_observe(assets)


def test_happy_exact_graph_and_witnesses(assets: ModuleType) -> None:
    with tempfile.TemporaryDirectory(prefix="pf-observe-happy-") as temporary:
        root, macho_paths, tree_manifest, payloads = write_runtime_tree(
            Path(temporary)
        )
        host_lock = make_host_lock()
        runner = OtoolRunner(root, host_lock)
        observation = invoke_fixture(
            assets,
            root,
            macho_paths,
            tree_manifest,
            host_lock=host_lock,
            runner=runner,
        )

        if type(observation).__name__ != "CompilerRuntimeObservation":
            raise AssertionError(
                "observe must return CompilerRuntimeObservation, got {0!r}".format(
                    type(observation)
                )
            )
        actual_graph = normalize_graph(observation.graph)
        if actual_graph != EXPECTED_GRAPH:
            raise AssertionError(
                "full compiler runtime graph mismatch:\nactual={0!r}\nexpected={1!r}".format(
                    actual_graph, EXPECTED_GRAPH
                )
            )

        expected_paths = (
            "bin/lake",
            "bin/lean",
            "lib/core.dylib",
            "lib/util.dylib",
        )
        images = observation.images
        if tuple(image.path for image in images) != expected_paths:
            raise AssertionError("witnesses must be the exact sorted graph cover")
        for image in images:
            if type(image).__name__ != "RuntimeImageWitness":
                raise AssertionError("image witness has the wrong public type")
            expected_digest = hashlib.sha256(payloads[image.path]).hexdigest()
            expected = tree_manifest[image.path]
            actual = (image.size, image.mode, image.sha256)
            wanted = (expected["size"], expected["mode"], expected_digest)
            if actual != wanted:
                raise AssertionError(
                    "runtime witness mismatch for {0}: {1!r} != {2!r}".format(
                        image.path, actual, wanted
                    )
                )
        runner.assert_exact_single_pass()


def test_witness_content_and_mode_mismatch_fail(assets: ModuleType) -> None:
    with tempfile.TemporaryDirectory(prefix="pf-observe-mismatch-") as temporary:
        root, macho_paths, tree_manifest, payloads = write_runtime_tree(
            Path(temporary)
        )
        original = payloads["lib/core.dylib"]
        tampered = original[:-1] + bytes([original[-1] ^ 1])
        overwrite_file(root, "lib/core.dylib", tampered, 0o444)
        expect_asset_error(
            assets,
            "PF-SBOM-CLOSURE",
            lambda: invoke_fixture(assets, root, macho_paths, tree_manifest),
        )

    with tempfile.TemporaryDirectory(prefix="pf-observe-mode-") as temporary:
        root, macho_paths, tree_manifest, _payloads = write_runtime_tree(
            Path(temporary)
        )
        os.chmod(root / "bin", 0o755)
        os.chmod(root / "bin/lean", 0o444)
        os.chmod(root / "bin", 0o555)
        expect_asset_error(
            assets,
            "PF-SBOM-CLOSURE",
            lambda: invoke_fixture(assets, root, macho_paths, tree_manifest),
        )


def test_symlink_root_and_ancestor_fail(assets: ModuleType) -> None:
    with tempfile.TemporaryDirectory(prefix="pf-observe-root-link-") as temporary:
        base = Path(temporary)
        root, _macho_paths, tree_manifest, _payloads = write_runtime_tree(base)
        alias = base / "toolchain-link"
        alias.symlink_to(root, target_is_directory=True)
        alias_paths = [alias / relative for relative in RUNTIME_IMAGES]
        expect_asset_error(
            assets,
            "PF-SBOM-IO",
            lambda: invoke_fixture(assets, alias, alias_paths, tree_manifest),
        )

    with tempfile.TemporaryDirectory(prefix="pf-observe-ancestor-link-") as temporary:
        base = Path(temporary)
        root, macho_paths, tree_manifest, _payloads = write_runtime_tree(base)
        original = root / "lib-real"
        os.chmod(root, 0o755)
        (root / "lib").rename(original)
        (root / "lib").symlink_to(original.name, target_is_directory=True)
        os.chmod(root, 0o555)
        expect_asset_error(
            assets,
            "PF-SBOM-IO",
            lambda: invoke_fixture(assets, root, macho_paths, tree_manifest),
        )


def test_symlink_hardlink_and_fifo_leaf_fail(assets: ModuleType) -> None:
    with tempfile.TemporaryDirectory(prefix="pf-observe-leaf-link-") as temporary:
        base = Path(temporary)
        root, macho_paths, tree_manifest, payloads = write_runtime_tree(base)
        outside = base / "outside-core.dylib"
        outside.write_bytes(payloads["lib/core.dylib"])
        os.chmod(outside, 0o444)
        replace_with_symlink(root / "lib/core.dylib", outside)
        expect_asset_error(
            assets,
            "PF-SBOM-IO",
            lambda: invoke_fixture(assets, root, macho_paths, tree_manifest),
        )

    with tempfile.TemporaryDirectory(prefix="pf-observe-leaf-hard-") as temporary:
        base = Path(temporary)
        root, macho_paths, tree_manifest, _payloads = write_runtime_tree(base)
        os.link(root / "lib/core.dylib", base / "second-hardlink")
        expect_asset_error(
            assets,
            "PF-SBOM-IO",
            lambda: invoke_fixture(assets, root, macho_paths, tree_manifest),
        )

    with tempfile.TemporaryDirectory(prefix="pf-observe-leaf-fifo-") as temporary:
        base = Path(temporary)
        root, macho_paths, tree_manifest, _payloads = write_runtime_tree(base)
        replace_with_fifo(root / "lib/core.dylib")
        expect_asset_error(
            assets,
            "PF-SBOM-IO",
            lambda: bounded(
                lambda: invoke_fixture(assets, root, macho_paths, tree_manifest)
            ),
        )


def test_traversal_and_bad_structural_inputs_fail(assets: ModuleType) -> None:
    with tempfile.TemporaryDirectory(prefix="pf-observe-traversal-") as temporary:
        base = Path(temporary)
        root, macho_paths, tree_manifest, _payloads = write_runtime_tree(base)
        escaped = root / ".." / "escaped.dylib"
        escaped.write_bytes(MACHO_MAGIC_64_LE + b"escaped\n")
        attacked = list(macho_paths)
        attacked[attacked.index(root / "lib/core.dylib")] = escaped
        expect_asset_error(
            assets,
            "PF-SBOM-IO",
            lambda: invoke_fixture(assets, root, attacked, tree_manifest),
        )

        expect_asset_error(
            assets,
            "PF-SBOM-CLOSURE",
            lambda: invoke_fixture(
                assets,
                root,
                macho_paths,
                ["not", "a", "manifest"],
            ),
        )
        expect_asset_error(
            assets,
            "PF-SBOM-CLOSURE",
            lambda: invoke_fixture(assets, root, [], tree_manifest),
        )


def test_file_mutate_restore_race_fails_and_fires(assets: ModuleType) -> None:
    with tempfile.TemporaryDirectory(prefix="pf-observe-file-race-") as temporary:
        root, macho_paths, tree_manifest, payloads = write_runtime_tree(
            Path(temporary)
        )
        host_lock = make_host_lock()
        runner = OtoolRunner(root, host_lock)
        original = payloads["lib/core.dylib"]
        tampered = original[:-1] + bytes([original[-1] ^ 1])
        fired = {"count": 0}

        def mutate_once(relative: str, mode: str) -> None:
            if relative == "lib/core.dylib" and mode == "-hv" and not fired["count"]:
                fired["count"] += 1
                overwrite_file(root, "lib/core.dylib", tampered, 0o444)
                overwrite_file(root, "lib/core.dylib", original, 0o444)

        runner.on_before_mode = mutate_once
        expect_asset_error(
            assets,
            "PF-SBOM-IO",
            lambda: invoke_fixture(
                assets,
                root,
                macho_paths,
                tree_manifest,
                host_lock=host_lock,
                runner=runner,
            ),
        )
        if fired["count"] != 1:
            raise AssertionError(
                "file race callback must fire exactly once, got {0}".format(
                    fired["count"]
                )
            )


def test_ancestor_replace_restore_race_fails_and_fires(
    assets: ModuleType,
) -> None:
    with tempfile.TemporaryDirectory(prefix="pf-observe-dir-race-") as temporary:
        root, macho_paths, tree_manifest, _payloads = write_runtime_tree(
            Path(temporary)
        )
        host_lock = make_host_lock()
        runner = OtoolRunner(root, host_lock)
        fired = {"count": 0}

        def replace_once(relative: str, mode: str) -> None:
            if relative == "lib/core.dylib" and mode == "-hv" and not fired["count"]:
                fired["count"] += 1
                original = root / "lib-original"
                os.chmod(root, 0o755)
                (root / "lib").rename(original)
                (root / "lib").mkdir(mode=0o555)
                (root / "lib").rmdir()
                original.rename(root / "lib")
                os.chmod(root, 0o555)

        runner.on_before_mode = replace_once
        expect_asset_error(
            assets,
            "PF-SBOM-IO",
            lambda: invoke_fixture(
                assets,
                root,
                macho_paths,
                tree_manifest,
                host_lock=host_lock,
                runner=runner,
            ),
        )
        if fired["count"] != 1:
            raise AssertionError(
                "ancestor race callback must fire exactly once, got {0}".format(
                    fired["count"]
                )
            )


def test_root_replace_restore_race_fails_and_fires(assets: ModuleType) -> None:
    with tempfile.TemporaryDirectory(prefix="pf-observe-root-race-") as temporary:
        base = Path(temporary)
        root, macho_paths, tree_manifest, _payloads = write_runtime_tree(base)
        host_lock = make_host_lock()
        runner = OtoolRunner(root, host_lock)
        fired = {"count": 0}

        def replace_once(relative: str, mode: str) -> None:
            if relative == "lib/core.dylib" and mode == "-hv" and not fired["count"]:
                fired["count"] += 1
                original = base / "toolchain-original"
                root.rename(original)
                root.mkdir(mode=0o555)
                root.rmdir()
                original.rename(root)

        runner.on_before_mode = replace_once
        expect_asset_error(
            assets,
            "PF-SBOM-IO",
            lambda: invoke_fixture(
                assets,
                root,
                macho_paths,
                tree_manifest,
                host_lock=host_lock,
                runner=runner,
            ),
        )
        if fired["count"] != 1:
            raise AssertionError(
                "root race callback must fire exactly once, got {0}".format(
                    fired["count"]
                )
            )


def main() -> int:
    assets = load_assets()
    tests = (
        test_api_missing_is_red,
        test_happy_exact_graph_and_witnesses,
        test_witness_content_and_mode_mismatch_fail,
        test_symlink_root_and_ancestor_fail,
        test_symlink_hardlink_and_fifo_leaf_fail,
        test_traversal_and_bad_structural_inputs_fail,
        test_file_mutate_restore_race_fails_and_fires,
        test_ancestor_replace_restore_race_fails_and_fires,
        test_root_replace_restore_race_fails_and_fires,
    )
    for test in tests:
        try:
            test(assets)
        except AssertionError as error:
            print(
                "compiler-runtime-observation-self-test: FAIL {0}: {1}".format(
                    test.__name__, error
                ),
                file=sys.stderr,
            )
            return 1
    print("compiler-runtime-observation-self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
