#!/usr/bin/env python3
"""Pre-freeze RED tests for scripts/compiler_runtime_graph.py (TASK-D0-08 seam).

Shared interface under test (does not exist yet — this suite is expected RED
until the production module lands):

    RuntimeGraphError(code, detail)
    MachOInspection(rpaths: tuple[str, ...], loads: tuple[str, ...])   [frozen]
    ResolvedMachoLoad(install_name, resolved_path)
    RuntimeEntrypointGraph(path, loads, reachable)
    RuntimeFileGraph(path, owners, loads)
    CompilerRuntimeGraph(entrypoints, files) with as_legacy_closures()
    resolve_compiler_runtime_graph(*, entrypoints, inspections,
                                   allowed_system_roots)

All goldens below are derived independently from dyld semantics and
SPEC-TOOL-001 (entrypoint/owner/load ordering, system-load exclusion,
reachable non-system closure) — not from any production implementation.  This
suite is a pure pre-freeze seam test: it does not claim TST-SBOM-002 closure,
publication acceptance, or TASK-D0-08 activation.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType
from typing import Callable

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "scripts" / "compiler_runtime_graph.py"

SYSTEM_ROOTS = ("/System/Library/", "/usr/lib/")


def load_core() -> ModuleType:
    if not CORE.is_file():
        raise AssertionError(
            "RED expected: scripts/compiler_runtime_graph.py does not exist yet"
        )
    spec = importlib.util.spec_from_file_location(
        "proof_forge_compiler_runtime_graph", CORE
    )
    if spec is None or spec.loader is None:
        raise AssertionError("cannot load compiler_runtime_graph.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def expect_error(module: ModuleType, operation: Callable[[], object]) -> None:
    try:
        operation()
    except module.RuntimeGraphError:
        return
    raise AssertionError("expected RuntimeGraphError")


def expect_limit_error(module: ModuleType, operation: Callable[[], object]) -> None:
    try:
        operation()
    except module.RuntimeGraphError as error:
        code = str(getattr(error, "code", ""))
        if "limit" not in code.lower():
            raise AssertionError(
                f"expected a limit-class RuntimeGraphError code, got {code!r}"
            ) from error
        return
    raise AssertionError("expected RuntimeGraphError")


def inspection(module: ModuleType, rpaths=(), loads=()):
    return module.MachOInspection(rpaths=tuple(rpaths), loads=tuple(loads))


def resolved(module: ModuleType, install_name: str, resolved_path: str):
    return module.ResolvedMachoLoad(
        install_name=install_name, resolved_path=resolved_path
    )


def resolve(module: ModuleType, entrypoints, inspections, roots=SYSTEM_ROOTS):
    return module.resolve_compiler_runtime_graph(
        entrypoints=tuple(entrypoints),
        inspections=tuple(inspections),
        allowed_system_roots=tuple(roots),
    )


def shared_toolchain_inspections(module: ModuleType):
    """Two entrypoints sharing one dylib; transitive load via inherited rpath.

    bin/lake uses an @executable_path rpath entry, bin/lean an @loader_path
    entry; both lexically resolve to lib/.  libcore has no own rpaths, so its
    libutil load resolves only through the inherited entrypoint rpath.
    libunused is inspected but unreachable and must be excluded.
    """

    def insp(rpaths, loads):
        return inspection(module, rpaths, loads)

    return (
        ("bin/lake", insp(("@executable_path/../lib",), ("@rpath/libcore.dylib",))),
        (
            "bin/lean",
            insp(
                ("@loader_path/../lib",),
                ("@rpath/libcore.dylib", "/usr/lib/libSystem.B.dylib"),
            ),
        ),
        ("lib/libcore.dylib", insp((), ("@rpath/libutil.dylib",))),
        ("lib/libunused.dylib", insp((), ())),
        ("lib/libutil.dylib", insp((), ())),
    )


def test_shared_graph(module: ModuleType) -> None:
    entrypoints = ("bin/lake", "bin/lean")
    graph = resolve(module, entrypoints, shared_toolchain_inspections(module))

    if tuple(ep.path for ep in graph.entrypoints) != entrypoints:
        raise AssertionError("entrypoints are not sorted by path")
    if tuple(f.path for f in graph.files) != (
        "lib/libcore.dylib",
        "lib/libutil.dylib",
    ):
        raise AssertionError(
            "runtime files must exclude the unreachable image and stay sorted"
        )

    lake, lean = graph.entrypoints
    if lake.loads != (
        resolved(module, "@rpath/libcore.dylib", "lib/libcore.dylib"),
    ):
        raise AssertionError("lake direct internal edges mismatch")
    if lean.loads != (
        resolved(module, "@rpath/libcore.dylib", "lib/libcore.dylib"),
    ):
        raise AssertionError(
            "lean direct edges must exclude the allowed-system load only"
        )
    for ep in (lake, lean):
        if ep.reachable != ("lib/libcore.dylib", "lib/libutil.dylib"):
            raise AssertionError(
                "transitive reachable set must contain shared and nested dylibs"
            )

    core, util = graph.files
    if core.owners != ("bin/lake", "bin/lean"):
        raise AssertionError("shared dylib owners must be both entrypoints")
    if core.loads != (
        resolved(module, "@rpath/libutil.dylib", "lib/libutil.dylib"),
    ):
        raise AssertionError("dylib direct edge resolved via inherited rpath")
    if util.owners != ("bin/lake", "bin/lean") or util.loads != ():
        raise AssertionError("transitively shared leaf dylib mismatch")


def test_legacy_closure_projection(module: ModuleType) -> None:
    graph = resolve(
        module, ("bin/lake", "bin/lean"), shared_toolchain_inspections(module)
    )
    legacy = graph.as_legacy_closures()
    # The shared interface pins the projection, not its container type:
    # normalize any mapping or pair iterable to {entrypoint: set(reachable)}.
    if hasattr(legacy, "items"):
        normalized = {key: set(value) for key, value in legacy.items()}
    else:
        normalized = {key: set(value) for key, value in legacy}
    expected = {
        "bin/lake": {"bin/lake", "lib/libcore.dylib", "lib/libutil.dylib"},
        "bin/lean": {"bin/lean", "lib/libcore.dylib", "lib/libutil.dylib"},
    }
    if normalized != expected:
        raise AssertionError(
            f"legacy closure projection mismatch: {normalized!r}"
        )


def test_unresolved_load_fails(module: ModuleType) -> None:
    expect_error(
        module,
        lambda: resolve(
            module,
            ("bin/lean",),
            (("bin/lean", inspection(module, ("@loader_path/../lib",),
                                      ("@rpath/libmissing.dylib",))),),
        ),
    )


def test_outside_absolute_load_fails(module: ModuleType) -> None:
    expect_error(
        module,
        lambda: resolve(
            module,
            ("bin/lean",),
            (("bin/lean", inspection(module, (),
                                      ("/opt/homebrew/lib/libfoo.dylib",))),),
        ),
    )


def test_context_dependent_load_fails(module: ModuleType) -> None:
    # Shared dylib loads via @executable_path while the two entrypoints live in
    # different directories; both candidate images exist, so resolution would
    # depend on which entrypoint loads it.  This must fail closed.
    def insp(rpaths, loads):
        return inspection(module, rpaths, loads)

    expect_error(
        module,
        lambda: resolve(
            module,
            ("bin/lean", "sbin/lake"),
            (
                ("bin/lean", insp(("@loader_path/../lib",),
                                   ("@rpath/libcore.dylib",))),
                ("lib/libcore.dylib", insp((), ("@executable_path/libplug.dylib",))),
                ("sbin/lake", insp(("@loader_path/../lib",),
                                    ("@rpath/libcore.dylib",))),
                ("bin/libplug.dylib", insp((), ())),
                ("sbin/libplug.dylib", insp((), ())),
            ),
        ),
    )


def test_diamond_context_propagation(module: ModuleType) -> None:
    """A shared parent must propagate every inherited context downstream."""

    images = (
        ("bin/entry", inspection(module, (), ("lib/x", "lib/y"))),
        ("lib/a", inspection(module, (), ("lib/b",))),
        ("lib/b", inspection(module, (), ("@rpath/plugin.dylib",))),
        ("lib/x", inspection(module, ("@loader_path/../x",), ("lib/a",))),
        ("lib/y", inspection(module, ("@loader_path/../y",), ("lib/a",))),
        ("x/plugin.dylib", inspection(module)),
        ("y/plugin.dylib", inspection(module)),
    )
    expect_error(
        module,
        lambda: resolve(module, ("bin/entry",), images),
    )


def test_system_path_and_inspection_shape_fail_closed(module: ModuleType) -> None:
    expect_error(
        module,
        lambda: resolve(
            module,
            ("bin/lean",),
            (("bin/lean", inspection(module)),),
            ("/",),
        ),
    )
    expect_error(
        module,
        lambda: resolve(
            module,
            ("bin/lean",),
            (("bin/lean", inspection(
                module,
                (),
                ("/usr/lib/../../tmp/evil.dylib",),
            )),),
            ("/usr/lib/",),
        ),
    )
    malformed = module.MachOInspection(rpaths=(), loads=["not-a-tuple"])
    expect_error(
        module,
        lambda: resolve(
            module,
            ("bin/lean",),
            (("bin/lean", malformed),),
        ),
    )
    expect_error(module, lambda: resolve(module, (), ()))


def test_duplicate_load_fails(module: ModuleType) -> None:
    expect_error(
        module,
        lambda: resolve(
            module,
            ("bin/lean",),
            (
                ("bin/lean", inspection(module, ("@loader_path/../lib",),
                                         ("@rpath/libcore.dylib",
                                          "@rpath/libcore.dylib"))),
                ("lib/libcore.dylib", inspection(module)),
            ),
        ),
    )


def test_entrypoint_to_entrypoint_edge_fails(module: ModuleType) -> None:
    expect_error(
        module,
        lambda: resolve(
            module,
            ("bin/lake", "bin/lean"),
            (
                ("bin/lake", inspection(module)),
                ("bin/lean", inspection(module, ("@loader_path",),
                                         ("@loader_path/lake",))),
            ),
        ),
    )


def test_input_order_and_uniqueness(module: ModuleType) -> None:
    insp = shared_toolchain_inspections(module)
    entrypoints = ("bin/lake", "bin/lean")
    expect_error(module, lambda: resolve(module, ("bin/lean", "bin/lake"), insp))
    expect_error(module, lambda: resolve(module, ("bin/lean", "bin/lean"), insp))
    expect_error(module, lambda: resolve(module, entrypoints, tuple(reversed(insp))))
    expect_error(
        module,
        lambda: resolve(
            module,
            entrypoints,
            insp + (("lib/libutil.dylib", inspection(module)),),
        ),
    )
    expect_error(
        module,
        lambda: resolve(module, entrypoints, insp,
                        ("/usr/lib/", "/System/Library/")),
    )
    expect_error(
        module,
        lambda: resolve(module, entrypoints, insp, ("/usr/lib/", "/usr/lib/")),
    )
    # Every entrypoint must carry an inspection.
    expect_error(
        module,
        lambda: resolve(
            module,
            entrypoints,
            tuple(item for item in insp if item[0] != "bin/lake"),
        ),
    )
    # Non-normalized or absolute image paths are rejected.
    for bad_path in ("lib//libcore.dylib", "lib/./libcore.dylib",
                     "bin/../bin/lean", "/bin/lean"):
        expect_error(
            module,
            lambda bad_path=bad_path: resolve(
                module,
                ("bin/lean",),
                (("bin/lean", inspection(module)),
                 (bad_path, inspection(module))),
            ),
        )


def test_runtime_file_count_boundary(module: ModuleType) -> None:
    def chain(count: int, terminal_loads=()):
        images = [
            (
                "bin/lean",
                inspection(
                    module,
                    ("@loader_path/../lib",),
                    ("@rpath/d0000.dylib",),
                ),
            )
        ]
        for index in range(count):
            loads = ()
            if index + 1 < count:
                loads = (f"@loader_path/d{index + 1:04d}.dylib",)
            elif terminal_loads:
                loads = terminal_loads
            images.append((f"lib/d{index:04d}.dylib", inspection(module, (), loads)))
        images.sort(key=lambda item: item[0])
        return tuple(images)

    graph = resolve(module, ("bin/lean",), chain(1024))
    if len(graph.files) != 1024:
        raise AssertionError("1024 runtime files must be accepted")
    expect_limit_error(module, lambda: resolve(module, ("bin/lean",), chain(1025)))
    expect_limit_error(
        module,
        lambda: resolve(
            module,
            ("bin/lean",),
            chain(1025, ("@loader_path/missing.dylib",)),
        ),
    )


def main() -> int:
    module = load_core()
    test_shared_graph(module)
    test_legacy_closure_projection(module)
    test_unresolved_load_fails(module)
    test_outside_absolute_load_fails(module)
    test_context_dependent_load_fails(module)
    test_diamond_context_propagation(module)
    test_system_path_and_inspection_shape_fail_closed(module)
    test_duplicate_load_fails(module)
    test_entrypoint_to_entrypoint_edge_fails(module)
    test_input_order_and_uniqueness(module)
    test_runtime_file_count_boundary(module)
    print("compiler-runtime-graph-self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
