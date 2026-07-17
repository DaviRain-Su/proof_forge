#!/usr/bin/env python3
"""Pre-freeze tests for single-pass Lean Mach-O discovery (D0-08 seam).

Shared API under test:

    toolchain_assets.discover_lean_macho_static(
        lock, host_lock, root, macho_paths,
    ) -> CompilerRuntimeGraph

Existing verify_lean_macho_static(lock, host_lock, root, macho_paths)
-> dict[Path, set[Path]] remains the D0-03 surface and must become a thin
legacy projection over discover (absolute Path keys/sets; each set includes
the entrypoint itself).  This suite does not claim TST-SBOM-002, publication,
or TASK-D0-08 activation.
"""

from __future__ import annotations

import importlib.util
import os
import sys
import tempfile
from pathlib import Path
from types import ModuleType, SimpleNamespace
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple


ROOT = Path(__file__).resolve().parents[1]
ASSETS_PATH = ROOT / "scripts" / "toolchain_assets.py"
GRAPH_PATH = ROOT / "scripts" / "compiler_runtime_graph.py"

SYSTEM_ROOTS = ("/System/Library/", "/usr/lib/")

# Synthetic tree layout (root-relative POSIX).
ENTRYPOINTS = ("bin/lake", "bin/lean")
# Unreachable image is present on disk and in macho_paths, but never loaded.
RUNTIME_IMAGES = (
    "bin/lake",
    "bin/lean",
    "lib/core.dylib",
    "lib/unused.dylib",
    "lib/util.dylib",
)
OTOOL_MODES = ("-hv", "-l", "-L", "-D")


def load_module(path: Path, name: str) -> ModuleType:
    if not path.is_file():
        raise AssertionError(f"required module missing: {path}")
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise AssertionError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def load_assets() -> ModuleType:
    return load_module(ASSETS_PATH, "proof_forge_toolchain_assets_discovery_test")


def load_graph() -> ModuleType:
    return load_module(GRAPH_PATH, "proof_forge_compiler_runtime_graph_discovery_test")


def require_discover(assets: ModuleType) -> Callable[..., Any]:
    discover = getattr(assets, "discover_lean_macho_static", None)
    if discover is None:
        raise AssertionError(
            "RED expected: toolchain_assets.discover_lean_macho_static is not "
            "implemented yet"
        )
    return discover


def make_lock(executables: Sequence[str] = ENTRYPOINTS) -> dict:
    return {
        "machoPolicy": {
            "allowedSystemLoadRoots": list(SYSTEM_ROOTS),
        },
        "compilerToolchain": {
            "executables": [
                {
                    "path": path,
                    "sha256": "0" * 64,
                }
                for path in executables
            ],
        },
    }


def make_host_lock() -> dict:
    # discover/verify must not consult real host fields when locked_otool is
    # monkeypatched; keep a minimal placeholder matching locked_otool shape.
    return {
        "profiles": [
            {
                "developerTools": {
                    "otoolPath": "/usr/bin/otool",
                    "otoolSha256": "a" * 64,
                }
            }
        ]
    }


def write_tree(base: Path, relatives: Sequence[str]) -> Tuple[Path, List[Path]]:
    """Create empty regular files; return resolved root and absolute macho_paths."""

    root = (base / "toolchain").resolve()
    root.mkdir(parents=True, mode=0o755)
    macho_paths: List[Path] = []
    for relative in relatives:
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"synthetic-macho")
        os.chmod(path, 0o755 if relative.startswith("bin/") or relative.startswith("sbin/")
                 else 0o644)
        macho_paths.append(path.resolve())
    return root, sorted(macho_paths, key=lambda item: str(item))


def completed(stdout: str = "", stderr: str = "", returncode: int = 0) -> SimpleNamespace:
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
        f"         path {path} (offset 12)\n"
    )


def load_lines(*install_names: str) -> str:
    header = "synthetic:\n"
    body = "".join(
        f"\t{name} (compatibility version 0.0.0, current version 0.0.0)\n"
        for name in install_names
    )
    return header + body


def id_output(install_id: str) -> str:
    return f"synthetic:\n{install_id}\n"


class OtoolScript:
    """Deterministic otool answers + per-image per-mode call counters."""

    def __init__(
        self,
        root: Path,
        *,
        profiles: Optional[Dict[str, Dict[str, Any]]] = None,
    ) -> None:
        self.root = root.resolve()
        self.otool = Path("/fake/locked/otool")
        self.counts: Dict[Tuple[str, str], int] = {}
        self.profiles = profiles or self._default_profiles()

    def _rel(self, path: Path) -> str:
        return path.resolve().relative_to(self.root).as_posix()

    def _default_profiles(self) -> Dict[str, Dict[str, Any]]:
        # Shared topology: both entrypoints reach lib/core.dylib then lib/util.dylib.
        # lib/unused.dylib is present but never loaded.
        # core's install ID appears in -L and must be stripped via -D.
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
                    "@rpath/core.dylib",  # install ID echo — must be filtered
                    "@rpath/util.dylib",
                ),
                "id": "@rpath/core.dylib",
            },
            "lib/util.dylib": {
                "hv": hv_dylib(),
                "rpaths": (),
                "loads": (),
                "id": "@rpath/util.dylib",
            },
            "lib/unused.dylib": {
                "hv": hv_dylib(),
                "rpaths": (),
                "loads": ("@rpath/util.dylib",),
                "id": "@rpath/unused.dylib",
            },
        }

    def locked_otool(self, _host_lock: dict) -> Path:
        return self.otool

    def run(self, args: Sequence[str], **kwargs: Any) -> SimpleNamespace:
        if not args:
            raise AssertionError("subprocess.run called with empty args")
        executable = Path(args[0])
        if executable.name != "otool" and str(executable) != str(self.otool):
            raise AssertionError(f"unexpected executable: {args[0]!r}")
        if len(args) < 3:
            raise AssertionError(f"unexpected otool argv: {args!r}")
        mode = args[1]
        target = Path(args[2]).resolve()
        relative = self._rel(target)
        key = (relative, mode)
        self.counts[key] = self.counts.get(key, 0) + 1
        profile = self.profiles.get(relative)
        if profile is None:
            raise AssertionError(f"no otool profile for {relative}")

        if mode == "-hv":
            return completed(stdout=profile["hv"])
        if mode == "-l":
            chunks = [rpath_cmd(value) for value in profile["rpaths"]]
            return completed(stdout="".join(chunks) if chunks else "Load command 0\n")
        if mode == "-L":
            return completed(stdout=load_lines(*profile["loads"]))
        if mode == "-D":
            install_id = profile["id"]
            if install_id is None:
                return completed(stdout="", returncode=1)
            return completed(stdout=id_output(install_id), returncode=0)
        raise AssertionError(f"unexpected otool mode {mode!r} for {relative}")

    def count_for(self, relative: str, mode: str) -> int:
        return self.counts.get((relative, mode), 0)

    def assert_at_most_once(self, images: Sequence[str] = RUNTIME_IMAGES) -> None:
        for relative in images:
            for mode in OTOOL_MODES:
                count = self.count_for(relative, mode)
                if count > 1:
                    raise AssertionError(
                        f"otool {mode} ran {count} times for {relative} "
                        f"(must be at most once per discover)"
                    )

    def assert_exact_single_pass(self, images: Sequence[str] = RUNTIME_IMAGES) -> None:
        self.assert_at_most_once(images)
        for relative in images:
            for mode in OTOOL_MODES:
                count = self.count_for(relative, mode)
                if count != 1:
                    raise AssertionError(
                        f"expected exactly one otool {mode} for {relative}, got {count}"
                    )


def install_otool_mocks(assets: ModuleType, script: OtoolScript) -> Callable[[], None]:
    original_locked = assets.locked_otool
    original_run = assets.subprocess.run

    assets.locked_otool = script.locked_otool  # type: ignore[assignment]
    assets.subprocess.run = script.run  # type: ignore[assignment]

    def restore() -> None:
        assets.locked_otool = original_locked  # type: ignore[assignment]
        assets.subprocess.run = original_run  # type: ignore[assignment]

    return restore


def expect_fail(assets: ModuleType, operation: Callable[[], object]) -> None:
    try:
        operation()
    except assets.AssetError:
        return
    except Exception as error:  # noqa: BLE001 — assert the public typed channel
        raise AssertionError(
            f"expected fail-closed AssetError, got {error!r}"
        ) from error
    raise AssertionError("expected fail-closed error")


def test_discover_api_exists(assets: ModuleType) -> None:
    """The typed single-pass discovery entrypoint must exist."""

    require_discover(assets)


def test_cached_graph_module_requires_complete_api(assets: ModuleType) -> None:
    """A same-name or cached partial module must fail before discovery."""

    incomplete = ModuleType("compiler_runtime_graph")
    incomplete.resolve_compiler_runtime_graph = lambda **_kwargs: None  # type: ignore[attr-defined]
    original = assets._COMPILER_RUNTIME_GRAPH
    assets._COMPILER_RUNTIME_GRAPH = incomplete
    try:
        expect_fail(assets, assets._load_compiler_runtime_graph)
    finally:
        assets._COMPILER_RUNTIME_GRAPH = original


def test_happy_shared_graph_single_otool_pass(assets: ModuleType) -> None:
    discover = require_discover(assets)
    graph_mod = load_graph()
    with tempfile.TemporaryDirectory(prefix="pf-macho-discover-") as temporary:
        root, macho_paths = write_tree(Path(temporary), RUNTIME_IMAGES)
        script = OtoolScript(root)
        restore = install_otool_mocks(assets, script)
        try:
            graph = discover(make_lock(), make_host_lock(), root, macho_paths)
        finally:
            restore()

        if type(graph).__name__ != "CompilerRuntimeGraph":
            raise AssertionError(
                f"discover must return CompilerRuntimeGraph, got {type(graph)!r}"
            )

        # Single discovery: every provided runtime image, each otool mode ≤1,
        # and for this fixture exactly once (full classification of macho_paths).
        script.assert_exact_single_pass()

        if tuple(ep.path for ep in graph.entrypoints) != ENTRYPOINTS:
            raise AssertionError(
                f"entrypoints must be unique sorted {ENTRYPOINTS!r}, "
                f"got {tuple(ep.path for ep in graph.entrypoints)!r}"
            )
        if tuple(f.path for f in graph.files) != ("lib/core.dylib", "lib/util.dylib"):
            raise AssertionError(
                "files must be sorted reachable runtime dylibs only; "
                f"got {tuple(f.path for f in graph.files)!r}"
            )

        lake, lean = graph.entrypoints
        core, util = graph.files
        load = graph_mod.ResolvedMachoLoad

        # Install ID must not remain as a direct load after -D filtering.
        for node in (lake, lean, core, util):
            for edge in node.loads:
                if edge.install_name == "@rpath/core.dylib" and (
                    edge.resolved_path == "@rpath/core.dylib"
                ):
                    raise AssertionError(
                        "install ID @rpath/core.dylib was not filtered from loads"
                    )

        # Direct loads: system load excluded; install-id self-load filtered on core.
        if lake.loads != (load("@rpath/core.dylib", "lib/core.dylib"),):
            raise AssertionError(f"lake direct loads mismatch: {lake.loads!r}")
        if lean.loads != (load("@rpath/core.dylib", "lib/core.dylib"),):
            raise AssertionError(
                f"lean direct loads must exclude system load only: {lean.loads!r}"
            )
        if core.loads != (load("@rpath/util.dylib", "lib/util.dylib"),):
            raise AssertionError(
                "core must load util via inherited rpath and drop install ID: "
                f"{core.loads!r}"
            )
        if util.loads != ():
            raise AssertionError(f"util must be a leaf: {util.loads!r}")

        for ep in (lake, lean):
            if ep.reachable != ("lib/core.dylib", "lib/util.dylib"):
                raise AssertionError(
                    f"transitive reachable mismatch for {ep.path}: {ep.reachable!r}"
                )

        if core.owners != ENTRYPOINTS or util.owners != ENTRYPOINTS:
            raise AssertionError(
                f"shared owners must be both entrypoints; "
                f"core={core.owners!r} util={util.owners!r}"
            )

        # Unreachable image must not appear in the typed graph.
        if any(f.path == "lib/unused.dylib" for f in graph.files):
            raise AssertionError("unreachable dylib must be excluded from graph.files")
        if any(ep.path == "lib/unused.dylib" for ep in graph.entrypoints):
            raise AssertionError("unreachable dylib must not be an entrypoint")


def test_legacy_verify_projection_includes_entrypoint_self(
    assets: ModuleType,
) -> None:
    discover = require_discover(assets)
    with tempfile.TemporaryDirectory(prefix="pf-macho-legacy-") as temporary:
        root, macho_paths = write_tree(Path(temporary), RUNTIME_IMAGES)
        script = OtoolScript(root)
        restore = install_otool_mocks(assets, script)
        try:
            graph = discover(make_lock(), make_host_lock(), root, macho_paths)
            # Reset counters: legacy verify must not re-run a full second discovery
            # otool pass (thin projection may call discover once only).
            first_counts = dict(script.counts)
            script.counts.clear()
            closures = assets.verify_lean_macho_static(
                make_lock(), make_host_lock(), root, macho_paths,
            )
            second_counts = dict(script.counts)
        finally:
            restore()

        if not isinstance(closures, dict):
            raise AssertionError("verify_lean_macho_static must return a dict")
        for key, value in closures.items():
            if not isinstance(key, Path):
                raise AssertionError(f"closure key must be Path, got {type(key)!r}")
            if not key.is_absolute():
                raise AssertionError(f"closure key must be absolute Path, got {key!r}")
            if not isinstance(value, set):
                raise AssertionError(f"closure value must be set, got {type(value)!r}")
            if not all(isinstance(item, Path) for item in value):
                raise AssertionError("closure set members must be Path")
            if not all(item.is_absolute() for item in value):
                raise AssertionError("closure set members must be absolute Path")

        for relative in ENTRYPOINTS:
            entry_abs = (root / relative).resolve()
            if entry_abs not in closures:
                raise AssertionError(f"missing legacy closure for {relative}")
            closure = closures[entry_abs]
            # D0-03 freeze: each set includes the entrypoint itself.
            if entry_abs not in closure:
                raise AssertionError(
                    f"D0-03 freeze: legacy set for {relative} must include "
                    f"entrypoint itself"
                )
            expected = {
                entry_abs,
                (root / "lib/core.dylib").resolve(),
                (root / "lib/util.dylib").resolve(),
            }
            if closure != expected:
                raise AssertionError(
                    f"legacy closure for {relative} mismatch: {closure!r} "
                    f"!= {expected!r}"
                )

        # Thin projection: at most one otool pass when verify runs alone.
        # If verify delegates to discover, counts equal a single pass; never 2×.
        if second_counts:
            for (relative, mode), count in second_counts.items():
                if count > 1:
                    raise AssertionError(
                        f"legacy verify re-ran otool {mode} {count} times on "
                        f"{relative} (must not double-discover)"
                    )

        # Graph from discover and legacy projection must agree on non-self reachability.
        for ep in graph.entrypoints:
            entry_abs = (root / ep.path).resolve()
            projected = {path for path in closures[entry_abs] if path != entry_abs}
            expected = {(root / rel).resolve() for rel in ep.reachable}
            if projected != expected:
                raise AssertionError(
                    f"legacy projection drift for {ep.path}: "
                    f"{projected!r} != {expected!r}"
                )

        if not first_counts:
            raise AssertionError("discover produced no otool traffic")


def test_legacy_verify_does_not_double_discover_when_wrapped(
    assets: ModuleType,
) -> None:
    """verify must call discover at most once (thin legacy projection)."""

    require_discover(assets)
    calls = {"n": 0}
    original = assets.discover_lean_macho_static

    def counting_discover(*args: Any, **kwargs: Any) -> Any:
        calls["n"] += 1
        return original(*args, **kwargs)

    with tempfile.TemporaryDirectory(prefix="pf-macho-once-") as temporary:
        root, macho_paths = write_tree(Path(temporary), RUNTIME_IMAGES)
        script = OtoolScript(root)
        restore = install_otool_mocks(assets, script)
        assets.discover_lean_macho_static = counting_discover  # type: ignore[assignment]
        try:
            assets.verify_lean_macho_static(
                make_lock(), make_host_lock(), root, macho_paths,
            )
        finally:
            assets.discover_lean_macho_static = original  # type: ignore[assignment]
            restore()

        if calls["n"] == 0:
            # Still acceptable only if verify was not yet wired; after the slice
            # lands it must be exactly 1.
            raise AssertionError(
                "RED/GREEN target: verify_lean_macho_static must invoke "
                "discover_lean_macho_static exactly once (got 0)"
            )
        if calls["n"] != 1:
            raise AssertionError(
                f"verify must call discover exactly once, got {calls['n']}"
            )
        script.assert_at_most_once()
        # Full classification still expected on the single delegated pass.
        script.assert_exact_single_pass()


def test_outside_load_fails_closed(assets: ModuleType) -> None:
    discover = require_discover(assets)
    with tempfile.TemporaryDirectory(prefix="pf-macho-outside-") as temporary:
        images = ("bin/lean",)
        root, macho_paths = write_tree(Path(temporary), images)
        script = OtoolScript(
            root,
            profiles={
                "bin/lean": {
                    "hv": hv_execute(),
                    "rpaths": (),
                    "loads": ("/opt/homebrew/lib/libfoo.dylib",),
                    "id": None,
                },
            },
        )
        restore = install_otool_mocks(assets, script)
        try:
            expect_fail(
                assets,
                lambda: discover(
                    make_lock(("bin/lean",)),
                    make_host_lock(),
                    root,
                    macho_paths,
                ),
            )
        finally:
            restore()


def test_unresolved_load_fails_closed(assets: ModuleType) -> None:
    discover = require_discover(assets)
    with tempfile.TemporaryDirectory(prefix="pf-macho-unresolved-") as temporary:
        images = ("bin/lean",)
        root, macho_paths = write_tree(Path(temporary), images)
        script = OtoolScript(
            root,
            profiles={
                "bin/lean": {
                    "hv": hv_execute(),
                    "rpaths": ("@loader_path/../lib",),
                    "loads": ("@rpath/missing.dylib",),
                    "id": None,
                },
            },
        )
        restore = install_otool_mocks(assets, script)
        try:
            expect_fail(
                assets,
                lambda: discover(
                    make_lock(("bin/lean",)),
                    make_host_lock(),
                    root,
                    macho_paths,
                ),
            )
        finally:
            restore()


def test_unreachable_system_prefix_traversal_fails_closed(
    assets: ModuleType,
) -> None:
    """Unreachable images must not bypass canonical system-root checks."""

    discover = require_discover(assets)
    attacks = (
        {
            "rpaths": (),
            "loads": ("/usr/lib/../../tmp/evil.dylib",),
        },
        {
            "rpaths": ("/usr/lib/../../tmp",),
            "loads": (),
        },
    )
    for index, attack in enumerate(attacks):
        with tempfile.TemporaryDirectory(
            prefix=f"pf-macho-system-traversal-{index}-",
        ) as temporary:
            images = ("bin/lean", "lib/unused.dylib")
            root, macho_paths = write_tree(Path(temporary), images)
            script = OtoolScript(
                root,
                profiles={
                    "bin/lean": {
                        "hv": hv_execute(),
                        "rpaths": (),
                        "loads": (),
                        "id": None,
                    },
                    "lib/unused.dylib": {
                        "hv": hv_dylib(),
                        "rpaths": attack["rpaths"],
                        "loads": attack["loads"],
                        "id": "@rpath/unused.dylib",
                    },
                },
            )
            restore = install_otool_mocks(assets, script)
            try:
                expect_fail(
                    assets,
                    lambda: discover(
                        make_lock(("bin/lean",)),
                        make_host_lock(),
                        root,
                        macho_paths,
                    ),
                )
            finally:
                restore()


def test_duplicate_macho_input_fails_before_double_inspection(
    assets: ModuleType,
) -> None:
    """One image identity may not consume two otool passes."""

    discover = require_discover(assets)
    with tempfile.TemporaryDirectory(prefix="pf-macho-duplicate-") as temporary:
        root, macho_paths = write_tree(Path(temporary), ("bin/lean",))
        script = OtoolScript(
            root,
            profiles={
                "bin/lean": {
                    "hv": hv_execute(),
                    "rpaths": (),
                    "loads": (),
                    "id": None,
                },
            },
        )
        restore = install_otool_mocks(assets, script)
        try:
            expect_fail(
                assets,
                lambda: discover(
                    make_lock(("bin/lean",)),
                    make_host_lock(),
                    root,
                    [macho_paths[0], macho_paths[0]],
                ),
            )
        finally:
            restore()
        script.assert_at_most_once(("bin/lean",))


def test_context_dependent_load_fails_closed(assets: ModuleType) -> None:
    """Shared dylib resolves @executable_path differently per entrypoint dir."""

    discover = require_discover(assets)
    images = (
        "bin/lean",
        "bin/libplug.dylib",
        "lib/core.dylib",
        "sbin/lake",
        "sbin/libplug.dylib",
    )
    with tempfile.TemporaryDirectory(prefix="pf-macho-context-") as temporary:
        root, macho_paths = write_tree(Path(temporary), images)
        script = OtoolScript(
            root,
            profiles={
                "bin/lean": {
                    "hv": hv_execute(),
                    "rpaths": ("@loader_path/../lib",),
                    "loads": ("@rpath/core.dylib",),
                    "id": None,
                },
                "sbin/lake": {
                    "hv": hv_execute(),
                    "rpaths": ("@loader_path/../lib",),
                    "loads": ("@rpath/core.dylib",),
                    "id": None,
                },
                "lib/core.dylib": {
                    "hv": hv_dylib(),
                    "rpaths": (),
                    "loads": ("@executable_path/libplug.dylib",),
                    "id": "@rpath/core.dylib",
                },
                "bin/libplug.dylib": {
                    "hv": hv_dylib(),
                    "rpaths": (),
                    "loads": (),
                    "id": None,
                },
                "sbin/libplug.dylib": {
                    "hv": hv_dylib(),
                    "rpaths": (),
                    "loads": (),
                    "id": None,
                },
            },
        )
        restore = install_otool_mocks(assets, script)
        try:
            expect_fail(
                assets,
                lambda: discover(
                    make_lock(("bin/lean", "sbin/lake")),
                    make_host_lock(),
                    root,
                    macho_paths,
                ),
            )
        finally:
            restore()


def main() -> int:
    assets = load_assets()
    tests = (
        test_discover_api_exists,
        test_cached_graph_module_requires_complete_api,
        test_happy_shared_graph_single_otool_pass,
        test_legacy_verify_projection_includes_entrypoint_self,
        test_legacy_verify_does_not_double_discover_when_wrapped,
        test_outside_load_fails_closed,
        test_unresolved_load_fails_closed,
        test_unreachable_system_prefix_traversal_fails_closed,
        test_duplicate_macho_input_fails_before_double_inspection,
        test_context_dependent_load_fails_closed,
    )
    for test in tests:
        try:
            test(assets)
        except AssertionError as error:
            print(
                f"compiler-runtime-discovery-self-test: FAIL {test.__name__}: {error}",
                file=sys.stderr,
            )
            raise
    print("compiler-runtime-discovery-self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
