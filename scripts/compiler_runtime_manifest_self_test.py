#!/usr/bin/env python3
"""Pre-freeze RED tests for scripts/compiler_runtime_manifest.py (D0-08 seam).

Frozen pure-join API under test (production module not required to exist yet —
this suite is expected RED until it lands):

    RuntimeManifestError(code, detail)                    [frozen]
    RuntimeImageWitness(path, size, mode, sha256)          [frozen]
    CompilerRuntimeObservation(graph, images)              [frozen]
    BoundCompilerRuntimeGraph(graph, images)               [frozen]
    bind_compiler_runtime_observation(*, observation, tree_manifest)
        -> BoundCompilerRuntimeGraph

bind hard-joins an observed CompilerRuntimeGraph plus same-observation image
witnesses to the verified extract_lean_zip tree_manifest.  Observation images
must exactly cover graph entrypoints and files (root-relative, unique, sorted),
and every observed witness must equal the corresponding tree record.
tree_manifest may contain extra tree members; every graph path must exist as
kind=file with exact fields {kind, size, mode, sha256}.  Production module must
not touch FS or subprocess.  The caller remains responsible for constructing
the observation from one stable filesystem snapshot.

This suite does not claim TST-SBOM-002, SBOM publication, domain digest
wiring, or TASK-D0-08 activation.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType
from typing import Any, Callable, Dict, Mapping, Sequence, Tuple


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "scripts" / "compiler_runtime_manifest.py"
GRAPH_PATH = ROOT / "scripts" / "compiler_runtime_graph.py"

SHA_A = "a" * 64
SHA_B = "b" * 64
SHA_C = "c" * 64
SHA_D = "d" * 64


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


def load_graph() -> ModuleType:
    return load_module(GRAPH_PATH, "proof_forge_compiler_runtime_graph_for_manifest_test")


def load_manifest() -> ModuleType:
    if not MANIFEST_PATH.is_file():
        raise AssertionError(
            "RED expected: scripts/compiler_runtime_manifest.py is not "
            "implemented yet"
        )
    return load_module(
        MANIFEST_PATH,
        "proof_forge_compiler_runtime_manifest_self_test",
    )


def require_bind(module: ModuleType) -> Callable[..., Any]:
    bind = getattr(module, "bind_compiler_runtime_observation", None)
    if bind is None:
        raise AssertionError(
            "RED expected: bind_compiler_runtime_observation is not implemented"
        )
    return bind


def expect_fail(module: ModuleType, operation: Callable[[], object]) -> None:
    """All malformed join inputs use one stable typed error channel."""

    try:
        operation()
    except module.RuntimeManifestError:
        return
    except Exception as error:  # noqa: BLE001 — assert the public typed channel
        raise AssertionError(
            f"expected RuntimeManifestError, got {error!r}"
        ) from error
    raise AssertionError("expected RuntimeManifestError")


def file_record(
    *,
    size: object = 16,
    mode: object = 0o555,
    sha256: object = SHA_A,
    kind: object = "file",
    extra: Mapping[str, object] | None = None,
) -> dict:
    record: Dict[str, object] = {
        "kind": kind,
        "size": size,
        "mode": mode,
        "sha256": sha256,
    }
    if extra:
        record.update(extra)
    return record


def dir_record(*, mode: int = 0o555) -> dict:
    # extract_lean_zip directory records have no sha256 field.
    return {"kind": "directory", "size": 0, "mode": mode}


def make_shared_graph(graph_mod: ModuleType) -> Any:
    """Independently constructed graph: lake+lean → core → util."""

    load = graph_mod.ResolvedMachoLoad
    return graph_mod.CompilerRuntimeGraph(
        entrypoints=(
            graph_mod.RuntimeEntrypointGraph(
                path="bin/lake",
                loads=(load("@rpath/core.dylib", "lib/core.dylib"),),
                reachable=("lib/core.dylib", "lib/util.dylib"),
            ),
            graph_mod.RuntimeEntrypointGraph(
                path="bin/lean",
                loads=(load("@rpath/core.dylib", "lib/core.dylib"),),
                reachable=("lib/core.dylib", "lib/util.dylib"),
            ),
        ),
        files=(
            graph_mod.RuntimeFileGraph(
                path="lib/core.dylib",
                owners=("bin/lake", "bin/lean"),
                loads=(load("@rpath/util.dylib", "lib/util.dylib"),),
            ),
            graph_mod.RuntimeFileGraph(
                path="lib/util.dylib",
                owners=("bin/lake", "bin/lean"),
                loads=(),
            ),
        ),
    )


def happy_tree_manifest() -> Dict[str, dict]:
    """Full compiler tree: graph paths + unrelated extra members."""

    return {
        "bin": dir_record(),
        "bin/lake": file_record(size=10, mode=0o555, sha256=SHA_A),
        "bin/lean": file_record(size=11, mode=0o555, sha256=SHA_B),
        "lib": dir_record(),
        "lib/core.dylib": file_record(size=20, mode=0o444, sha256=SHA_C),
        "lib/util.dylib": file_record(size=21, mode=0o444, sha256=SHA_D),
        # Unrelated / unreachable tree members are allowed.
        "lib/unused.dylib": file_record(
            size=99, mode=0o444, sha256="e" * 64,
        ),
        "notes.txt": file_record(size=0, mode=0o444, sha256="f" * 64),
    }


def make_observation(
    module: ModuleType,
    graph: object,
    tree_manifest: Mapping[str, Mapping[str, object]],
) -> object:
    paths = sorted({
        *(entry.path for entry in graph.entrypoints),
        *(file_node.path for file_node in graph.files),
    })
    images = []
    for path in paths:
        record = tree_manifest[path]
        images.append(module.RuntimeImageWitness(
            path=path,
            size=record["size"],
            mode=record["mode"],
            sha256=record["sha256"],
        ))
    return module.CompilerRuntimeObservation(
        graph=graph,
        images=tuple(images),
    )


def test_production_module_missing_is_red() -> None:
    """Primary RED gate: production module must exist."""

    load_manifest()


def test_api_surface(module: ModuleType) -> None:
    for name in (
        "RuntimeManifestError",
        "RuntimeImageWitness",
        "CompilerRuntimeObservation",
        "BoundCompilerRuntimeGraph",
        "bind_compiler_runtime_observation",
    ):
        if not hasattr(module, name):
            raise AssertionError(f"missing public symbol: {name}")
    for name in (
        "RuntimeImageWitness",
        "CompilerRuntimeObservation",
        "BoundCompilerRuntimeGraph",
    ):
        params = getattr(getattr(module, name), "__dataclass_params__", None)
        if params is None or not params.frozen:
            raise AssertionError(f"{name} must be a frozen dataclass")


def test_happy_exact_cover_sorted_witnesses(
    module: ModuleType,
    graph_mod: ModuleType,
) -> None:
    bind = require_bind(module)
    graph = make_shared_graph(graph_mod)
    tree = happy_tree_manifest()
    observation = make_observation(module, graph, tree)
    bound = bind(observation=observation, tree_manifest=tree)

    if type(bound).__name__ != "BoundCompilerRuntimeGraph":
        raise AssertionError(
            f"bind must return BoundCompilerRuntimeGraph, got {type(bound)!r}"
        )
    if bound.graph is not graph and bound.graph != graph:
        raise AssertionError("bound.graph must retain the input graph")

    expected_paths = ("bin/lake", "bin/lean", "lib/core.dylib", "lib/util.dylib")
    if tuple(image.path for image in bound.images) != expected_paths:
        raise AssertionError(
            f"images must be unique sorted exact cover of graph paths, "
            f"got {tuple(image.path for image in bound.images)!r}"
        )

    by_path = {image.path: image for image in bound.images}
    expectations: Sequence[Tuple[str, int, int, str]] = (
        ("bin/lake", 10, 0o555, SHA_A),
        ("bin/lean", 11, 0o555, SHA_B),
        ("lib/core.dylib", 20, 0o444, SHA_C),
        ("lib/util.dylib", 21, 0o444, SHA_D),
    )
    for path, size, mode, digest in expectations:
        image = by_path[path]
        if type(image).__name__ != "RuntimeImageWitness":
            raise AssertionError(
                f"image must be RuntimeImageWitness, got {type(image)!r}"
            )
        if (image.size, image.mode, image.sha256) != (size, mode, digest):
            raise AssertionError(
                f"witness mismatch for {path}: "
                f"{(image.size, image.mode, image.sha256)!r} != "
                f"{(size, mode, digest)!r}"
            )

    # Extra tree members must not appear in images.
    if any(image.path == "lib/unused.dylib" for image in bound.images):
        raise AssertionError("unreachable tree member must not enter images")
    if any(image.path == "notes.txt" for image in bound.images):
        raise AssertionError("non-graph tree member must not enter images")
    if bound.images != observation.images:
        raise AssertionError("bound images must preserve the exact observation witnesses")


def test_missing_graph_path_fails(
    module: ModuleType,
    graph_mod: ModuleType,
) -> None:
    bind = require_bind(module)
    graph = make_shared_graph(graph_mod)
    tree = happy_tree_manifest()
    observation = make_observation(module, graph, tree)
    del tree["lib/util.dylib"]
    expect_fail(
        module,
        lambda: bind(observation=observation, tree_manifest=tree),
    )


def test_directory_record_fails(
    module: ModuleType,
    graph_mod: ModuleType,
) -> None:
    bind = require_bind(module)
    graph = make_shared_graph(graph_mod)
    tree = happy_tree_manifest()
    observation = make_observation(module, graph, tree)
    tree["lib/core.dylib"] = dir_record()
    expect_fail(
        module,
        lambda: bind(observation=observation, tree_manifest=tree),
    )


def test_missing_field_fails(
    module: ModuleType,
    graph_mod: ModuleType,
) -> None:
    bind = require_bind(module)
    graph = make_shared_graph(graph_mod)
    tree = happy_tree_manifest()
    observation = make_observation(module, graph, tree)
    del tree["bin/lean"]["sha256"]
    expect_fail(
        module,
        lambda: bind(observation=observation, tree_manifest=tree),
    )


def test_extra_field_fails(
    module: ModuleType,
    graph_mod: ModuleType,
) -> None:
    bind = require_bind(module)
    graph = make_shared_graph(graph_mod)
    tree = happy_tree_manifest()
    observation = make_observation(module, graph, tree)
    tree["bin/lean"] = file_record(
        size=11, mode=0o555, sha256=SHA_B, extra={"unexpected": True},
    )
    expect_fail(
        module,
        lambda: bind(observation=observation, tree_manifest=tree),
    )


def test_bad_hash_fails(
    module: ModuleType,
    graph_mod: ModuleType,
) -> None:
    bind = require_bind(module)
    graph = make_shared_graph(graph_mod)
    tree = happy_tree_manifest()
    observation = make_observation(module, graph, tree)
    # Uppercase hex is not the lowercase-64 wire form used by extract_lean_zip.
    tree["bin/lake"] = file_record(size=10, mode=0o555, sha256="A" * 64)
    expect_fail(
        module,
        lambda: bind(observation=observation, tree_manifest=tree),
    )
    tree["bin/lake"] = file_record(size=10, mode=0o555, sha256="a" * 63)
    expect_fail(
        module,
        lambda: bind(observation=observation, tree_manifest=tree),
    )


def test_bool_and_negative_size_fail(
    module: ModuleType,
    graph_mod: ModuleType,
) -> None:
    bind = require_bind(module)
    graph = make_shared_graph(graph_mod)
    tree = happy_tree_manifest()
    observation = make_observation(module, graph, tree)
    # bool is a subclass of int; must still be rejected (exact int gate).
    tree["bin/lake"] = file_record(size=True, mode=0o555, sha256=SHA_A)
    expect_fail(
        module,
        lambda: bind(observation=observation, tree_manifest=tree),
    )
    tree["bin/lake"] = file_record(size=-1, mode=0o555, sha256=SHA_A)
    expect_fail(
        module,
        lambda: bind(observation=observation, tree_manifest=tree),
    )


def test_bad_mode_fails(
    module: ModuleType,
    graph_mod: ModuleType,
) -> None:
    bind = require_bind(module)
    graph = make_shared_graph(graph_mod)
    tree = happy_tree_manifest()
    observation = make_observation(module, graph, tree)
    tree["lib/core.dylib"] = file_record(size=20, mode=0o644, sha256=SHA_C)
    expect_fail(
        module,
        lambda: bind(observation=observation, tree_manifest=tree),
    )
    tree["lib/core.dylib"] = file_record(size=20, mode=0o755, sha256=SHA_C)
    expect_fail(
        module,
        lambda: bind(observation=observation, tree_manifest=tree),
    )


def test_observation_tree_substitution_fails(
    module: ModuleType,
    graph_mod: ModuleType,
) -> None:
    """A valid but different tree witness cannot be joined by path alone."""

    bind = require_bind(module)
    graph = make_shared_graph(graph_mod)
    original = happy_tree_manifest()
    observation = make_observation(module, graph, original)
    substituted = happy_tree_manifest()
    substituted["lib/core.dylib"] = file_record(
        size=20,
        mode=0o444,
        sha256="9" * 64,
    )
    expect_fail(
        module,
        lambda: bind(observation=observation, tree_manifest=substituted),
    )


def test_observation_cover_and_order_fail(
    module: ModuleType,
    graph_mod: ModuleType,
) -> None:
    bind = require_bind(module)
    graph = make_shared_graph(graph_mod)
    tree = happy_tree_manifest()
    observation = make_observation(module, graph, tree)
    observation_type = module.CompilerRuntimeObservation

    mutations = (
        observation_type(graph=graph, images=observation.images[:-1]),
        observation_type(graph=graph, images=tuple(reversed(observation.images))),
        observation_type(
            graph=graph,
            images=observation.images + (observation.images[-1],),
        ),
        observation_type(
            graph=graph,
            images=observation.images + (
                module.RuntimeImageWitness(
                    path="notes.txt",
                    size=0,
                    mode=0o444,
                    sha256="f" * 64,
                ),
            ),
        ),
        observation_type(graph=graph, images=list(observation.images)),
    )
    for mutation in mutations:
        expect_fail(
            module,
            lambda mutation=mutation: bind(
                observation=mutation,
                tree_manifest=tree,
            ),
        )


def test_observation_witness_and_size_bound_fail(
    module: ModuleType,
    graph_mod: ModuleType,
) -> None:
    bind = require_bind(module)
    graph = make_shared_graph(graph_mod)
    tree = happy_tree_manifest()
    observation = make_observation(module, graph, tree)

    first = observation.images[0]
    changed = module.RuntimeImageWitness(
        path=first.path,
        size=first.size,
        mode=first.mode,
        sha256="8" * 64,
    )
    mismatch = module.CompilerRuntimeObservation(
        graph=graph,
        images=(changed, *observation.images[1:]),
    )
    expect_fail(
        module,
        lambda: bind(observation=mismatch, tree_manifest=tree),
    )

    too_large_tree = happy_tree_manifest()
    too_large_tree["bin/lake"] = file_record(
        size=2 ** 53,
        mode=0o555,
        sha256=SHA_A,
    )
    too_large = make_observation(module, graph, too_large_tree)
    expect_fail(
        module,
        lambda: bind(observation=too_large, tree_manifest=too_large_tree),
    )


def test_error_channel_does_not_leak_builtin_exceptions(
    module: ModuleType,
    graph_mod: ModuleType,
) -> None:
    bind = require_bind(module)
    graph = make_shared_graph(graph_mod)
    tree = happy_tree_manifest()
    observation = make_observation(module, graph, tree)
    tree["bin/lean"][1] = "mixed-key"
    expect_fail(
        module,
        lambda: bind(observation=observation, tree_manifest=tree),
    )

    class HostileGraph:
        @property
        def entrypoints(self) -> object:
            raise KeyError("hostile entrypoints")

        files = ()

    hostile = module.CompilerRuntimeObservation(
        graph=HostileGraph(),
        images=(),
    )
    expect_fail(
        module,
        lambda: bind(observation=hostile, tree_manifest={}),
    )


def test_noncanonical_graph_paths_fail(
    module: ModuleType,
    graph_mod: ModuleType,
) -> None:
    bind = require_bind(module)
    invalid_paths = (
        "/bin/lean",
        "C:/bin/lean",
        "bin\\lean",
        "bin/../lean",
        "bin/e\u0301lean",
        "x" * 1025,
        "bin/\u0001lean",
    )
    for path in invalid_paths:
        graph = graph_mod.CompilerRuntimeGraph(
            entrypoints=(
                graph_mod.RuntimeEntrypointGraph(
                    path=path,
                    loads=(),
                    reachable=(),
                ),
            ),
            files=(),
        )
        tree = {path: file_record(size=1, mode=0o555, sha256=SHA_A)}
        observation = module.CompilerRuntimeObservation(
            graph=graph,
            images=(
                module.RuntimeImageWitness(
                    path=path,
                    size=1,
                    mode=0o555,
                    sha256=SHA_A,
                ),
            ),
        )
        expect_fail(
            module,
            lambda observation=observation, tree=tree: bind(
                observation=observation,
                tree_manifest=tree,
            ),
        )


def test_graph_casefold_and_topology_drift_fail(
    module: ModuleType,
    graph_mod: ModuleType,
) -> None:
    bind = require_bind(module)
    casefold_graph = graph_mod.CompilerRuntimeGraph(
        entrypoints=(
            graph_mod.RuntimeEntrypointGraph("bin/A", (), ()),
            graph_mod.RuntimeEntrypointGraph("bin/a", (), ()),
        ),
        files=(),
    )
    casefold_tree = {
        "bin/A": file_record(size=1, mode=0o555, sha256=SHA_A),
        "bin/a": file_record(size=1, mode=0o555, sha256=SHA_B),
    }
    casefold_observation = make_observation(
        module,
        casefold_graph,
        casefold_tree,
    )
    expect_fail(
        module,
        lambda: bind(
            observation=casefold_observation,
            tree_manifest=casefold_tree,
        ),
    )

    load = graph_mod.ResolvedMachoLoad
    dangling_graph = graph_mod.CompilerRuntimeGraph(
        entrypoints=(
            graph_mod.RuntimeEntrypointGraph(
                "bin/lean",
                (load("@rpath/missing.dylib", "lib/missing.dylib"),),
                (),
            ),
        ),
        files=(),
    )
    dangling_tree = {
        "bin/lean": file_record(size=1, mode=0o555, sha256=SHA_A),
    }
    dangling_observation = make_observation(
        module,
        dangling_graph,
        dangling_tree,
    )
    expect_fail(
        module,
        lambda: bind(
            observation=dangling_observation,
            tree_manifest=dangling_tree,
        ),
    )

    owner_graph = graph_mod.CompilerRuntimeGraph(
        entrypoints=(
            graph_mod.RuntimeEntrypointGraph(
                "bin/lean",
                (load("@rpath/core.dylib", "lib/core.dylib"),),
                ("lib/core.dylib",),
            ),
        ),
        files=(graph_mod.RuntimeFileGraph("lib/core.dylib", (), ()),),
    )
    owner_tree = {
        "bin/lean": file_record(size=1, mode=0o555, sha256=SHA_A),
        "lib/core.dylib": file_record(size=2, mode=0o444, sha256=SHA_B),
    }
    owner_observation = make_observation(module, owner_graph, owner_tree)
    expect_fail(
        module,
        lambda: bind(
            observation=owner_observation,
            tree_manifest=owner_tree,
        ),
    )

    non_nfc_graph = graph_mod.CompilerRuntimeGraph(
        entrypoints=(
            graph_mod.RuntimeEntrypointGraph(
                "bin/lean",
                (load("@rpath/e\u0301.dylib", "lib/core.dylib"),),
                ("lib/core.dylib",),
            ),
        ),
        files=(
            graph_mod.RuntimeFileGraph(
                "lib/core.dylib",
                ("bin/lean",),
                (),
            ),
        ),
    )
    non_nfc_tree = {
        "bin/lean": file_record(size=1, mode=0o555, sha256=SHA_A),
        "lib/core.dylib": file_record(size=2, mode=0o444, sha256=SHA_B),
    }
    non_nfc_observation = make_observation(
        module,
        non_nfc_graph,
        non_nfc_tree,
    )
    expect_fail(
        module,
        lambda: bind(
            observation=non_nfc_observation,
            tree_manifest=non_nfc_tree,
        ),
    )


def test_empty_and_oversized_graph_fail(
    module: ModuleType,
    graph_mod: ModuleType,
) -> None:
    bind = require_bind(module)
    empty_graph = graph_mod.CompilerRuntimeGraph(entrypoints=(), files=())
    empty_observation = module.CompilerRuntimeObservation(
        graph=empty_graph,
        images=(),
    )
    expect_fail(
        module,
        lambda: bind(observation=empty_observation, tree_manifest={}),
    )

    load = graph_mod.ResolvedMachoLoad
    paths = tuple(f"lib/{index:04d}.dylib" for index in range(1025))
    oversized_graph = graph_mod.CompilerRuntimeGraph(
        entrypoints=(
            graph_mod.RuntimeEntrypointGraph(
                "bin/lean",
                tuple(load(path, path) for path in paths),
                paths,
            ),
        ),
        files=tuple(
            graph_mod.RuntimeFileGraph(path, ("bin/lean",), ())
            for path in paths
        ),
    )
    oversized_tree = {
        "bin/lean": file_record(size=1, mode=0o555, sha256=SHA_A),
        **{
            path: file_record(size=1, mode=0o444, sha256=SHA_B)
            for path in paths
        },
    }
    oversized_observation = make_observation(
        module,
        oversized_graph,
        oversized_tree,
    )
    expect_fail(
        module,
        lambda: bind(
            observation=oversized_observation,
            tree_manifest=oversized_tree,
        ),
    )


def test_duplicate_graph_path_fails(
    module: ModuleType,
    graph_mod: ModuleType,
) -> None:
    """Graph path multiset must be unique before join (entrypoint/file collision)."""

    bind = require_bind(module)
    load = graph_mod.ResolvedMachoLoad
    # Manual graph with the same path appearing twice among files.
    graph = graph_mod.CompilerRuntimeGraph(
        entrypoints=(
            graph_mod.RuntimeEntrypointGraph(
                path="bin/lean",
                loads=(load("@rpath/core.dylib", "lib/core.dylib"),),
                reachable=("lib/core.dylib",),
            ),
        ),
        files=(
            graph_mod.RuntimeFileGraph(
                path="lib/core.dylib",
                owners=("bin/lean",),
                loads=(),
            ),
            graph_mod.RuntimeFileGraph(
                path="lib/core.dylib",
                owners=("bin/lean",),
                loads=(),
            ),
        ),
    )
    tree = {
        "bin/lean": file_record(size=11, mode=0o555, sha256=SHA_B),
        "lib/core.dylib": file_record(size=20, mode=0o444, sha256=SHA_C),
    }
    observation = make_observation(module, graph, tree)
    expect_fail(
        module,
        lambda: bind(observation=observation, tree_manifest=tree),
    )


def test_entrypoint_file_path_collision_fails(
    module: ModuleType,
    graph_mod: ModuleType,
) -> None:
    """An entrypoint path must not also appear as a runtime file path."""

    bind = require_bind(module)
    graph = graph_mod.CompilerRuntimeGraph(
        entrypoints=(
            graph_mod.RuntimeEntrypointGraph(
                path="bin/lean",
                loads=(),
                reachable=(),
            ),
        ),
        files=(
            graph_mod.RuntimeFileGraph(
                path="bin/lean",
                owners=("bin/lean",),
                loads=(),
            ),
        ),
    )
    tree = {
        "bin/lean": file_record(size=11, mode=0o555, sha256=SHA_B),
    }
    observation = make_observation(module, graph, tree)
    expect_fail(
        module,
        lambda: bind(observation=observation, tree_manifest=tree),
    )


def main() -> int:
    # Primary RED: production module absence.
    try:
        module = load_manifest()
    except AssertionError as error:
        print(
            f"compiler-runtime-manifest-self-test: FAIL "
            f"test_production_module_missing_is_red: {error}",
            file=sys.stderr,
        )
        raise SystemExit(1) from error

    graph_mod = load_graph()
    tests: Sequence[Tuple[str, Callable[..., None]]] = (
        ("test_api_surface", lambda: test_api_surface(module)),
        (
            "test_happy_exact_cover_sorted_witnesses",
            lambda: test_happy_exact_cover_sorted_witnesses(module, graph_mod),
        ),
        (
            "test_missing_graph_path_fails",
            lambda: test_missing_graph_path_fails(module, graph_mod),
        ),
        (
            "test_directory_record_fails",
            lambda: test_directory_record_fails(module, graph_mod),
        ),
        (
            "test_missing_field_fails",
            lambda: test_missing_field_fails(module, graph_mod),
        ),
        (
            "test_extra_field_fails",
            lambda: test_extra_field_fails(module, graph_mod),
        ),
        (
            "test_bad_hash_fails",
            lambda: test_bad_hash_fails(module, graph_mod),
        ),
        (
            "test_bool_and_negative_size_fail",
            lambda: test_bool_and_negative_size_fail(module, graph_mod),
        ),
        (
            "test_bad_mode_fails",
            lambda: test_bad_mode_fails(module, graph_mod),
        ),
        (
            "test_observation_tree_substitution_fails",
            lambda: test_observation_tree_substitution_fails(module, graph_mod),
        ),
        (
            "test_observation_cover_and_order_fail",
            lambda: test_observation_cover_and_order_fail(module, graph_mod),
        ),
        (
            "test_observation_witness_and_size_bound_fail",
            lambda: test_observation_witness_and_size_bound_fail(module, graph_mod),
        ),
        (
            "test_error_channel_does_not_leak_builtin_exceptions",
            lambda: test_error_channel_does_not_leak_builtin_exceptions(
                module,
                graph_mod,
            ),
        ),
        (
            "test_noncanonical_graph_paths_fail",
            lambda: test_noncanonical_graph_paths_fail(module, graph_mod),
        ),
        (
            "test_graph_casefold_and_topology_drift_fail",
            lambda: test_graph_casefold_and_topology_drift_fail(module, graph_mod),
        ),
        (
            "test_empty_and_oversized_graph_fail",
            lambda: test_empty_and_oversized_graph_fail(module, graph_mod),
        ),
        (
            "test_duplicate_graph_path_fails",
            lambda: test_duplicate_graph_path_fails(module, graph_mod),
        ),
        (
            "test_entrypoint_file_path_collision_fails",
            lambda: test_entrypoint_file_path_collision_fails(module, graph_mod),
        ),
    )
    for name, test in tests:
        try:
            test()
        except AssertionError as error:
            print(
                f"compiler-runtime-manifest-self-test: FAIL {name}: {error}",
                file=sys.stderr,
            )
            raise SystemExit(1) from error
    print("compiler-runtime-manifest-self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
