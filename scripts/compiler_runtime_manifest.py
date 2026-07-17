#!/usr/bin/env python3
"""Pure-stdlib bind of observed compiler runtime graph witnesses to tree manifest.

No filesystem or subprocess.  Validates a structural CompilerRuntimeGraph plus
same-observation image witnesses, then hard-joins them to an extract_lean_zip
tree_manifest.  The current pre-freeze profile accepts ASCII runtime identities
only, so it never consults host Unicode data.  This is not full pinned-Unicode
support, SBOM publication, or TST-SBOM-002.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, Dict, List, Sequence, Set, Tuple

_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
_FILE_RECORD_KEYS = frozenset({"kind", "size", "mode", "sha256"})
_ALLOWED_MODES = frozenset({0o444, 0o555})
_MAX_SIZE = (2 ** 53) - 1
_MAX_RUNTIME_FILES = 1024
_MAX_PATH_UTF8 = 1024


class RuntimeManifestError(Exception):
    """Fail-closed runtime manifest bind error (sole public failure channel)."""

    def __init__(self, code: str, detail: str) -> None:
        self.code = code
        self.detail = detail
        super().__init__("{0}: {1}".format(code, detail))


@dataclass(frozen=True)
class RuntimeImageWitness:
    path: str
    size: int
    mode: int
    sha256: str


@dataclass(frozen=True)
class CompilerRuntimeObservation:
    graph: Any
    images: Tuple[RuntimeImageWitness, ...]


@dataclass(frozen=True)
class BoundCompilerRuntimeGraph:
    graph: Any
    images: Tuple[RuntimeImageWitness, ...]


def _fail(code: str, detail: str) -> None:
    raise RuntimeManifestError(code, detail)


def _has_controls(value: str) -> bool:
    for char in value:
        codepoint = ord(char)
        if codepoint < 0x20 or codepoint == 0x7F or 0x80 <= codepoint <= 0x9F:
            return True
    return False


def _require_ascii_runtime_path(path: object, *, label: str) -> str:
    """Require the current ASCII-only runtime ProjectRelativePath profile."""

    if type(path) is not str or not path:
        _fail("input", "{0} must be a nonempty str".format(label))
    try:
        encoded = path.encode("ascii")
    except UnicodeEncodeError:
        _fail(
            "unicode-profile",
            "{0} must use the pre-freeze ASCII runtime profile".format(label),
        )
    if "\\" in path or path.startswith("/"):
        _fail("input", "{0} is not a normalized relative path".format(label))
    if (
        len(path) >= 3
        and ("A" <= path[0] <= "Z" or "a" <= path[0] <= "z")
        and path[1:3] == ":/"
    ):
        # Reject only an ASCII drive prefix; ':' is otherwise a valid POSIX byte.
        _fail("input", "{0} must not use an ASCII drive prefix".format(label))
    if len(encoded) > _MAX_PATH_UTF8:
        _fail("input", "{0} exceeds 1024 bytes".format(label))
    if _has_controls(path):
        _fail("input", "{0} contains forbidden control characters".format(label))
    if path.endswith("/"):
        _fail("input", "{0} must not end with '/'".format(label))
    parts = path.split("/")
    if any(part in ("", ".", "..") for part in parts):
        _fail("input", "{0} contains an empty or dot segment".format(label))
    return path


def _require_ascii_runtime_string(value: object, *, label: str) -> str:
    if type(value) is not str or not value:
        _fail("input", "{0} must be a nonempty str".format(label))
    try:
        value.encode("ascii")
    except UnicodeEncodeError:
        _fail(
            "unicode-profile",
            "{0} must use the pre-freeze ASCII runtime profile".format(label),
        )
    if _has_controls(value):
        _fail("input", "{0} contains forbidden control characters".format(label))
    return value


def _ascii_casefold_key(value: str) -> bytes:
    """ASCII case-insensitive key without host Unicode tables."""

    return value.encode("ascii").lower()


def _require_unique_sorted_strs(
    values: object,
    *,
    label: str,
) -> Tuple[str, ...]:
    if type(values) is not tuple:
        _fail("input", "{0} must be an exact tuple".format(label))
    items: List[str] = []
    for index, item in enumerate(values):
        if type(item) is not str:
            _fail(
                "input",
                "{0}[{1}] must be str".format(label, index),
            )
        items.append(item)
    as_tuple = tuple(items)
    if as_tuple != tuple(sorted(as_tuple)):
        _fail("input", "{0} must be unique sorted".format(label))
    if len(as_tuple) != len(set(as_tuple)):
        _fail("input", "{0} must be unique sorted".format(label))
    return as_tuple


def _safe_key_list(keys: Set[object]) -> List[object]:
    try:
        return sorted(keys)  # type: ignore[type-var]
    except TypeError:
        return list(keys)


def _require_exact_file_record(path: str, record: object) -> RuntimeImageWitness:
    if type(record) is not dict:
        _fail("record", "tree_manifest[{0!r}] must be an exact dict".format(path))
    keys = set(record.keys())
    if keys != _FILE_RECORD_KEYS:
        _fail(
            "record",
            "tree_manifest[{0!r}] fields must be exactly "
            "{{kind, size, mode, sha256}}, got {1}".format(
                path, _safe_key_list(keys)
            ),
        )

    kind = record["kind"]
    size = record["size"]
    mode = record["mode"]
    digest = record["sha256"]

    if kind != "file":
        _fail(
            "record",
            "tree_manifest[{0!r}].kind must be 'file', got {1!r}".format(path, kind),
        )
    if type(size) is not int:
        _fail(
            "record",
            "tree_manifest[{0!r}].size must be an exact int, got {1}".format(
                path, type(size).__name__
            ),
        )
    if size < 0 or size > _MAX_SIZE:
        _fail(
            "record",
            "tree_manifest[{0!r}].size out of range [0, 2^53-1]: {1}".format(
                path, size
            ),
        )
    if type(mode) is not int:
        _fail(
            "record",
            "tree_manifest[{0!r}].mode must be an exact int, got {1}".format(
                path, type(mode).__name__
            ),
        )
    if mode not in _ALLOWED_MODES:
        _fail(
            "record",
            "tree_manifest[{0!r}].mode must be 0o444 or 0o555, got {1:#o}".format(
                path, mode
            ),
        )
    if type(digest) is not str:
        _fail(
            "record",
            "tree_manifest[{0!r}].sha256 must be str, got {1}".format(
                path, type(digest).__name__
            ),
        )
    if _SHA256_RE.fullmatch(digest) is None:
        _fail(
            "record",
            "tree_manifest[{0!r}].sha256 must be 64 lowercase hex digits".format(
                path
            ),
        )

    return RuntimeImageWitness(
        path=path,
        size=size,
        mode=mode,
        sha256=digest,
    )


def _require_witness_fields(image: RuntimeImageWitness, *, label: str) -> None:
    if type(image) is not RuntimeImageWitness:
        _fail("observation", "{0} must be RuntimeImageWitness".format(label))
    _require_ascii_runtime_path(image.path, label="{0}.path".format(label))
    if type(image.size) is not int or image.size < 0 or image.size > _MAX_SIZE:
        _fail(
            "observation",
            "{0}.size must be int in [0, 2^53-1]".format(label),
        )
    if type(image.mode) is not int or image.mode not in _ALLOWED_MODES:
        _fail(
            "observation",
            "{0}.mode must be 0o444 or 0o555".format(label),
        )
    if type(image.sha256) is not str or _SHA256_RE.fullmatch(image.sha256) is None:
        _fail(
            "observation",
            "{0}.sha256 must be 64 lowercase hex digits".format(label),
        )


def _parse_loads(
    loads: object,
    *,
    label: str,
    file_paths: Set[str],
) -> Tuple[Tuple[str, str], ...]:
    if type(loads) is not tuple:
        _fail("input", "{0} must be an exact tuple".format(label))
    parsed: List[Tuple[str, str]] = []
    for index, edge in enumerate(loads):
        install_name = getattr(edge, "install_name", None)
        resolved_path = getattr(edge, "resolved_path", None)
        install_name = _require_ascii_runtime_string(
            install_name,
            label="{0}[{1}].install_name".format(label, index),
        )
        resolved_path = _require_ascii_runtime_path(
            resolved_path,
            label="{0}[{1}].resolved_path".format(label, index),
        )
        if resolved_path not in file_paths:
            _fail(
                "topology",
                "{0}[{1}] target not in graph.files: {2}".format(
                    label, index, resolved_path
                ),
            )
        parsed.append((install_name, resolved_path))
    as_tuple = tuple(parsed)
    if as_tuple != tuple(sorted(as_tuple)):
        _fail("input", "{0} must be unique sorted by (installName, resolvedPath)".format(label))
    if len(as_tuple) != len(set(as_tuple)):
        _fail("input", "{0} must be unique sorted".format(label))
    return as_tuple


def _compute_transitive(
    entry_path: str,
    entry_loads: Sequence[Tuple[str, str]],
    file_loads: Dict[str, Tuple[Tuple[str, str], ...]],
) -> Tuple[str, ...]:
    pending: List[str] = [target for _, target in entry_loads]
    seen: Set[str] = set()
    while pending:
        node = pending.pop()
        if node in seen:
            continue
        seen.add(node)
        for _, target in file_loads[node]:
            if target not in seen:
                pending.append(target)
    return tuple(sorted(seen))


def _validate_graph(graph: object) -> Tuple[str, ...]:
    """Structural graph validator; returns unique sorted path cover."""

    if graph is None:
        _fail("input", "graph is required")

    entrypoints = getattr(graph, "entrypoints", None)
    files = getattr(graph, "files", None)
    if type(entrypoints) is not tuple:
        _fail("input", "graph.entrypoints must be an exact tuple")
    if type(files) is not tuple:
        _fail("input", "graph.files must be an exact tuple")
    if len(entrypoints) == 0:
        _fail("input", "graph.entrypoints must be nonempty")
    if len(files) > _MAX_RUNTIME_FILES:
        _fail(
            "limit",
            "graph.files length exceeds maximum {0}".format(_MAX_RUNTIME_FILES),
        )

    entry_paths: List[str] = []
    for index, entry in enumerate(entrypoints):
        path = _require_ascii_runtime_path(
            getattr(entry, "path", None),
            label="graph.entrypoints[{0}].path".format(index),
        )
        entry_paths.append(path)

    file_paths: List[str] = []
    for index, file_node in enumerate(files):
        path = _require_ascii_runtime_path(
            getattr(file_node, "path", None),
            label="graph.files[{0}].path".format(index),
        )
        file_paths.append(path)

    all_paths = entry_paths + file_paths
    if len(all_paths) != len(set(all_paths)):
        _fail("duplicate", "graph entrypoint/file paths are not unique")

    # ASCII-casefold uniqueness for the current narrowed runtime profile.
    casefold_keys: List[bytes] = []
    for path in all_paths:
        casefold_keys.append(_ascii_casefold_key(path))
    if len(casefold_keys) != len(set(casefold_keys)):
        _fail("duplicate", "graph paths are not ASCII-casefold unique")

    file_path_set = set(file_paths)
    entry_path_set = set(entry_paths)

    # Entrypoints must themselves be unique sorted (stable graph convention).
    if tuple(entry_paths) != tuple(sorted(entry_paths)):
        _fail("input", "graph.entrypoints paths must be unique sorted")
    if tuple(file_paths) != tuple(sorted(file_paths)):
        _fail("input", "graph.files paths must be unique sorted")

    entry_load_map: Dict[str, Tuple[Tuple[str, str], ...]] = {}
    entry_reachable: Dict[str, Tuple[str, ...]] = {}
    for index, entry in enumerate(entrypoints):
        path = entry_paths[index]
        loads = _parse_loads(
            getattr(entry, "loads", None),
            label="graph.entrypoints[{0}].loads".format(index),
            file_paths=file_path_set,
        )
        reachable = _require_unique_sorted_strs(
            getattr(entry, "reachable", None),
            label="graph.entrypoints[{0}].reachable".format(index),
        )
        for target in reachable:
            _require_ascii_runtime_path(
                target,
                label="graph.entrypoints[{0}].reachable target".format(index),
            )
            if target not in file_path_set:
                _fail(
                    "topology",
                    "reachable path not in graph.files: {0}".format(target),
                )
        entry_load_map[path] = loads
        entry_reachable[path] = reachable

    file_load_map: Dict[str, Tuple[Tuple[str, str], ...]] = {}
    file_owners: Dict[str, Tuple[str, ...]] = {}
    for index, file_node in enumerate(files):
        path = file_paths[index]
        loads = _parse_loads(
            getattr(file_node, "loads", None),
            label="graph.files[{0}].loads".format(index),
            file_paths=file_path_set,
        )
        owners = _require_unique_sorted_strs(
            getattr(file_node, "owners", None),
            label="graph.files[{0}].owners".format(index),
        )
        for owner in owners:
            if owner not in entry_path_set:
                _fail(
                    "topology",
                    "owner is not an entrypoint: {0}".format(owner),
                )
        file_load_map[path] = loads
        file_owners[path] = owners

    # Transitive reachable must match declared reachable.
    for path in entry_paths:
        computed = _compute_transitive(
            path, entry_load_map[path], file_load_map
        )
        if computed != entry_reachable[path]:
            _fail(
                "topology",
                "entrypoint {0!r} reachable mismatch: declared={1!r} "
                "computed={2!r}".format(path, entry_reachable[path], computed),
            )

    # Owners <-> reachable bidirectional consistency.
    for path in file_paths:
        expected_owners = tuple(
            sorted(
                entry
                for entry in entry_paths
                if path in entry_reachable[entry]
            )
        )
        if not expected_owners:
            _fail(
                "topology",
                "graph.files contains an unreachable runtime file: {0!r}".format(
                    path
                ),
            )
        if file_owners[path] != expected_owners:
            _fail(
                "topology",
                "file {0!r} owners mismatch: declared={1!r} expected={2!r}".format(
                    path, file_owners[path], expected_owners
                ),
            )

    return tuple(sorted(all_paths))


def _validate_observation(
    observation: object,
    graph_paths: Tuple[str, ...],
) -> Tuple[RuntimeImageWitness, ...]:
    if type(observation) is not CompilerRuntimeObservation:
        _fail(
            "observation",
            "observation must be an exact CompilerRuntimeObservation",
        )
    images = observation.images
    if type(images) is not tuple:
        _fail("observation", "observation.images must be an exact tuple")

    for index, image in enumerate(images):
        _require_witness_fields(
            image, label="observation.images[{0}]".format(index)
        )

    image_paths = tuple(image.path for image in images)
    if image_paths != graph_paths:
        _fail(
            "observation",
            "observation.images paths must be unique sorted exact graph cover",
        )
    if len(image_paths) != len(set(image_paths)):
        _fail("observation", "observation.images paths must be unique")

    return images


def _bind_impl(
    *,
    observation: object,
    tree_manifest: object,
) -> BoundCompilerRuntimeGraph:
    if type(observation) is not CompilerRuntimeObservation:
        _fail(
            "observation",
            "observation must be an exact CompilerRuntimeObservation",
        )
    if type(tree_manifest) is not dict:
        _fail("input", "tree_manifest must be an exact dict")

    graph = observation.graph
    graph_paths = _validate_graph(graph)
    images = _validate_observation(observation, graph_paths)

    for image in images:
        path = image.path
        if path not in tree_manifest:
            _fail("missing", "tree_manifest missing graph path: {0}".format(path))
        tree_witness = _require_exact_file_record(path, tree_manifest[path])
        if (
            tree_witness.path != image.path
            or tree_witness.size != image.size
            or tree_witness.mode != image.mode
            or tree_witness.sha256 != image.sha256
        ):
            _fail(
                "mismatch",
                "observation witness does not match tree_manifest for {0}".format(
                    path
                ),
            )

    return BoundCompilerRuntimeGraph(graph=graph, images=images)


def bind_compiler_runtime_observation(
    *,
    observation: object,
    tree_manifest: object,
) -> BoundCompilerRuntimeGraph:
    """Validate observation+graph and hard-join witnesses to tree_manifest.

    Every exception at this public boundary becomes RuntimeManifestError
    with ``from None`` (no TypeError/KeyError/AttributeError leakage).
    """

    try:
        return _bind_impl(
            observation=observation,
            tree_manifest=tree_manifest,
        )
    except RuntimeManifestError as error:
        raise RuntimeManifestError(error.code, error.detail) from None
    except Exception:
        raise RuntimeManifestError(
            "internal",
            "compiler runtime observation bind failed",
        ) from None


__all__ = (
    "BoundCompilerRuntimeGraph",
    "CompilerRuntimeObservation",
    "RuntimeImageWitness",
    "RuntimeManifestError",
    "bind_compiler_runtime_observation",
)
