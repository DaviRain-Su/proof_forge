#!/usr/bin/env python3
"""Pure-stdlib compiler Mach-O runtime graph resolver (no FS / subprocess).

Resolves pre-inspected Mach-O load commands and rpaths into a deterministic
root-relative runtime graph for compiler entrypoints.  Intended as a D0-08
pre-freeze seam: inspections are supplied by the caller; this module never
reads the filesystem or launches tools.
"""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from typing import Deque, Dict, List, Mapping, Optional, Sequence, Set, Tuple

MAX_RUNTIME_FILES = 1024
# Pre-freeze denial-of-service guards for diamond / multi-context walks.  They
# are intentionally private and are not schema acceptance maxima.
_MAX_INHERITED_CONTEXTS_PER_IMAGE = 64
_MAX_WALK_CONTEXTS = 4096


class RuntimeGraphError(Exception):
    """Fail-closed runtime graph resolution error."""

    def __init__(self, code: str, detail: str) -> None:
        self.code = code
        self.detail = detail
        super().__init__(f"{code}: {detail}")


@dataclass(frozen=True)
class MachOInspection:
    rpaths: Tuple[str, ...]
    loads: Tuple[str, ...]


@dataclass(frozen=True)
class ResolvedMachoLoad:
    install_name: str
    resolved_path: str


@dataclass(frozen=True)
class RuntimeEntrypointGraph:
    path: str
    loads: Tuple[ResolvedMachoLoad, ...]
    reachable: Tuple[str, ...]


@dataclass(frozen=True)
class RuntimeFileGraph:
    path: str
    owners: Tuple[str, ...]
    loads: Tuple[ResolvedMachoLoad, ...]


@dataclass(frozen=True)
class CompilerRuntimeGraph:
    entrypoints: Tuple[RuntimeEntrypointGraph, ...]
    files: Tuple[RuntimeFileGraph, ...]

    def as_legacy_closures(self) -> Dict[str, Set[str]]:
        return {
            entry.path: {entry.path, *entry.reachable}
            for entry in self.entrypoints
        }


def _fail(code: str, detail: str) -> None:
    raise RuntimeGraphError(code, detail)


def _has_forbidden_controls(value: str) -> bool:
    """True if value contains NUL, other C0, DEL, or C1 controls."""

    for char in value:
        codepoint = ord(char)
        if codepoint < 0x20 or codepoint == 0x7F or 0x80 <= codepoint <= 0x9F:
            return True
    return False


def _absolute_path_segments(path: str) -> Optional[List[str]]:
    """Split a lexical absolute path into body segments, or None if invalid.

    Rejects empty / `.` / `..` body segments.  A trailing slash is allowed only
    for directory-prefix forms and is stripped before segment validation.
    """

    if not path.startswith("/"):
        return None
    if _has_forbidden_controls(path):
        return None
    body = path[1:]
    trailing_slash = body.endswith("/")
    if trailing_slash:
        body = body[:-1]
    if body == "":
        # Bare "/" — no body segments.
        return []
    parts = body.split("/")
    for part in parts:
        if part in ("", ".", ".."):
            return None
    return parts


def _is_canonical_absolute_directory_prefix(path: str) -> bool:
    """True for a non-root absolute directory prefix ending with '/'."""

    if type(path) is not str:
        return False
    if path == "/" or not path.endswith("/"):
        return False
    segments = _absolute_path_segments(path)
    if segments is None:
        return False
    # Non-root prefix must contain at least one body segment.
    return len(segments) >= 1


def _is_canonical_absolute_install_name(path: str) -> bool:
    """True for a lexical absolute install name with no dot-segments."""

    if type(path) is not str or not path.startswith("/"):
        return False
    if path.endswith("/"):
        return False
    segments = _absolute_path_segments(path)
    if segments is None:
        return False
    return len(segments) >= 1


def _is_allowed_system_install_name(
    install_name: str,
    roots: Sequence[str],
) -> bool:
    """Match only after lexical absolute canonical checks.

    Paths such as ``/usr/lib/../../tmp/x`` are not treated as system libraries
    merely because they share a string prefix with an allowed root.
    """

    if not _is_canonical_absolute_install_name(install_name):
        return False
    return any(install_name.startswith(root) for root in roots)


def _is_normalized_root_relative(path: str) -> bool:
    if type(path) is not str or not path:
        return False
    if _has_forbidden_controls(path):
        return False
    if path.startswith("/") or path.endswith("/"):
        return False
    parts = path.split("/")
    if any(part in ("", ".", "..") for part in parts):
        return False
    return True


def _require_exact_str_tuple(value: object, *, label: str) -> Tuple[str, ...]:
    """Demand an exact ``tuple[str, ...]``; never leak TypeError on bad input."""

    if type(value) is not tuple:
        _fail("input", f"{label} must be an exact tuple[str, ...]")
    for index, item in enumerate(value):
        if type(item) is not str:
            _fail(
                "input",
                f"{label}[{index}] must be an exact str, "
                f"got {type(item).__name__}",
            )
        if _has_forbidden_controls(item):
            _fail("input", f"{label}[{index}] contains forbidden control characters")
        # Explicit hashability gate so unhashable impostors never reach set/dict.
        try:
            hash(item)
        except TypeError:
            _fail("input", f"{label}[{index}] must be hashable str")
    return value  # type: ignore[return-value]


def _require_unique_sorted_strings(
    values: object,
    *,
    code: str,
    label: str,
) -> Tuple[str, ...]:
    if type(values) not in (tuple, list):
        _fail(code, f"{label} must be a sequence of strings")
    items_list: List[str] = []
    for index, item in enumerate(values):  # type: ignore[arg-type]
        if type(item) is not str:
            _fail(code, f"{label}[{index}] must be an exact str")
        if _has_forbidden_controls(item):
            _fail(code, f"{label}[{index}] contains forbidden control characters")
        try:
            hash(item)
        except TypeError:
            _fail(code, f"{label}[{index}] must be hashable str")
        items_list.append(item)
    items = tuple(items_list)
    if items != tuple(sorted(items)):
        _fail(code, f"{label} must be unique sorted")
    if len(items) != len(set(items)):
        _fail(code, f"{label} must be unique sorted")
    return items


def _validate_system_roots(values: object) -> Tuple[str, ...]:
    roots = _require_unique_sorted_strings(
        values,
        code="input",
        label="allowed_system_roots",
    )
    if not roots:
        _fail("input", "allowed_system_roots must not be empty")
    for root in roots:
        if root == "/":
            _fail("input", "allowed_system_roots must not contain bare '/'")
        if not _is_canonical_absolute_directory_prefix(root):
            _fail(
                "input",
                "allowed_system_roots entries must be canonical absolute "
                f"directory prefixes ending with '/': {root!r}",
            )
    return roots


def _validate_inspection(inspection: MachOInspection, *, path: str) -> MachOInspection:
    """Normalize inspection field types before any graph walk."""

    rpaths = _require_exact_str_tuple(
        inspection.rpaths,
        label=f"inspection[{path!r}].rpaths",
    )
    loads = _require_exact_str_tuple(
        inspection.loads,
        label=f"inspection[{path!r}].loads",
    )
    # loads: order preserved, duplicates forbidden (no input sort required).
    if len(loads) != len(set(loads)):
        _fail("input", f"inspection[{path!r}].loads must not contain duplicates")
    if len(rpaths) != len(set(rpaths)):
        _fail("input", f"inspection[{path!r}].rpaths must not contain duplicates")
    # Rpath order remains semantically significant; do not sort it.
    if rpaths is not inspection.rpaths or loads is not inspection.loads:
        return MachOInspection(rpaths=rpaths, loads=loads)
    return inspection


def _parent_dir(path: str) -> str:
    if "/" not in path:
        return ""
    return path.rsplit("/", 1)[0]


def _join_under_root(base_dir: str, relative: str) -> Optional[str]:
    """Join base_dir / relative and normalize `..` / `.` without leaving root."""

    parts: List[str] = []
    if base_dir:
        parts.extend(base_dir.split("/"))
    segments = [] if relative == "" else relative.split("/")
    for segment in segments:
        if segment == "":
            return None
        if segment == ".":
            continue
        if segment == "..":
            if not parts:
                return None
            parts.pop()
            continue
        parts.append(segment)
    return "/".join(parts)


def _resolve_special_base(
    raw: str,
    *,
    loader_path: str,
    entrypoint_path: str,
) -> Optional[str]:
    """Map @loader_path / @executable_path forms to a root-relative base path.

    Returns None only when ``raw`` is not a special form.  Join failures for a
    recognized special prefix raise ``RuntimeGraphError``.
    """

    if raw == "@loader_path":
        return _parent_dir(loader_path)
    if raw.startswith("@loader_path/"):
        joined = _join_under_root(
            _parent_dir(loader_path),
            raw[len("@loader_path/"):],
        )
        if joined is None:
            _fail("path", f"special path escapes root: {raw}")
        return joined
    if raw == "@executable_path":
        return _parent_dir(entrypoint_path)
    if raw.startswith("@executable_path/"):
        joined = _join_under_root(
            _parent_dir(entrypoint_path),
            raw[len("@executable_path/"):],
        )
        if joined is None:
            _fail("path", f"special path escapes root: {raw}")
        return joined
    return None


def _absolute_under_system_roots(path: str, roots: Sequence[str]) -> bool:
    """True when a lexical-canonical absolute path sits under a system root."""

    if path.endswith("/"):
        if not _is_canonical_absolute_directory_prefix(path):
            return False
        return any(path.startswith(root) or path == root for root in roots)
    if not _is_canonical_absolute_install_name(path):
        return False
    return any(path.startswith(root) for root in roots)


def _resolve_rpath_dir(
    raw: str,
    *,
    loader_path: str,
    entrypoint_path: str,
    allowed_system_roots: Sequence[str],
) -> str:
    if type(raw) is not str:
        _fail("input", f"rpath must be str on {loader_path}")
    if _has_forbidden_controls(raw):
        _fail("rpath", f"rpath contains forbidden control characters: {raw!r}")

    # Absolute rpaths are never internal.  Non-canonical forms (including
    # ``/usr/lib/../..``) are rejected before any system-prefix startswith check.
    if raw.startswith("/"):
        canonical_dir = _is_canonical_absolute_directory_prefix(raw)
        canonical_file = _is_canonical_absolute_install_name(raw)
        if not canonical_dir and not canonical_file:
            _fail("rpath", f"non-canonical absolute rpath: {raw}")
        if _absolute_under_system_roots(raw, allowed_system_roots):
            _fail("rpath", f"system rpath is not an internal runpath: {raw}")
        _fail("rpath", f"absolute rpath outside allowed system roots: {raw}")

    special = _resolve_special_base(
        raw,
        loader_path=loader_path,
        entrypoint_path=entrypoint_path,
    )
    if special is not None:
        # Empty string is the synthetic root directory and is allowed as a join base.
        if special == "" or _is_normalized_root_relative(special):
            return special
        _fail("rpath", f"rpath does not normalize under root: {raw}")

    _fail("rpath", f"unsupported rpath form: {raw}")
    raise AssertionError("unreachable")


def _resolve_load_target(
    install_name: str,
    *,
    loader_path: str,
    entrypoint_path: str,
    active_rpaths: Sequence[str],
    known_images: Mapping[str, MachOInspection],
    allowed_system_roots: Sequence[str],
) -> Optional[str]:
    """Return root-relative image path, None for allowed system, else fail."""

    if type(install_name) is not str:
        _fail("input", f"install name must be str on {loader_path}")
    if _has_forbidden_controls(install_name):
        _fail(
            "load",
            f"install name contains forbidden control characters on "
            f"{loader_path}: {install_name!r}",
        )

    if install_name.startswith("/"):
        # Lexical gate first: /usr/lib/../../tmp/... is never a system hit.
        if _is_allowed_system_install_name(install_name, allowed_system_roots):
            return None
        if not _is_canonical_absolute_install_name(install_name):
            _fail(
                "outside",
                f"non-canonical absolute load: {loader_path} -> {install_name}",
            )
        _fail(
            "outside",
            f"absolute load outside allowed system roots: "
            f"{loader_path} -> {install_name}",
        )

    if install_name.startswith("@rpath/"):
        suffix = install_name[len("@rpath/"):]
        if not suffix or any(part in ("", ".", "..") for part in suffix.split("/")):
            _fail("load", f"invalid @rpath suffix: {install_name}")
        if _has_forbidden_controls(suffix):
            _fail("load", f"invalid @rpath suffix controls: {install_name}")
        for runpath in active_rpaths:
            candidate = _join_under_root(runpath, suffix)
            if candidate is None:
                continue
            if not _is_normalized_root_relative(candidate):
                continue
            if candidate in known_images:
                return candidate
        _fail(
            "unresolved",
            f"reachable load is unresolved: {loader_path} -> {install_name}",
        )

    special = _resolve_special_base(
        install_name,
        loader_path=loader_path,
        entrypoint_path=entrypoint_path,
    )
    if special is not None:
        if not _is_normalized_root_relative(special):
            _fail(
                "unresolved",
                f"reachable load is unresolved: {loader_path} -> {install_name}",
            )
        if special not in known_images:
            _fail(
                "unresolved",
                f"reachable load is unresolved: {loader_path} -> {install_name}",
            )
        return special

    if _is_normalized_root_relative(install_name):
        if install_name in known_images:
            return install_name
        _fail(
            "unresolved",
            f"reachable load is unresolved: {loader_path} -> {install_name}",
        )

    _fail("load", f"unsupported load form: {loader_path} -> {install_name}")
    raise AssertionError("unreachable")


def _resolve_image_loads(
    path: str,
    inspection: MachOInspection,
    *,
    entrypoint_path: str,
    inherited_rpaths: Tuple[str, ...],
    known_images: Mapping[str, MachOInspection],
    entrypoint_set: Set[str],
    allowed_system_roots: Sequence[str],
) -> Tuple[Tuple[ResolvedMachoLoad, ...], Tuple[str, ...]]:
    own_rpaths: List[str] = []
    for raw in inspection.rpaths:
        own_rpaths.append(
            _resolve_rpath_dir(
                raw,
                loader_path=path,
                entrypoint_path=entrypoint_path,
                allowed_system_roots=allowed_system_roots,
            )
        )
    active_rpaths = tuple(own_rpaths) + inherited_rpaths

    resolved: List[ResolvedMachoLoad] = []
    for install_name in inspection.loads:
        target = _resolve_load_target(
            install_name,
            loader_path=path,
            entrypoint_path=entrypoint_path,
            active_rpaths=active_rpaths,
            known_images=known_images,
            allowed_system_roots=allowed_system_roots,
        )
        if target is None:
            continue
        if target in entrypoint_set:
            _fail(
                "entrypoint-edge",
                f"entrypoint-to-entrypoint load edge: {path} -> {target}",
            )
        resolved.append(
            ResolvedMachoLoad(install_name=install_name, resolved_path=target)
        )

    resolved.sort(key=lambda item: (item.install_name, item.resolved_path))
    install_names = [item.install_name for item in resolved]
    if len(install_names) != len(set(install_names)):
        _fail("duplicate", f"duplicate resolved install names on {path}")
    return tuple(resolved), active_rpaths


def _note_runtime_file(
    *,
    path: str,
    entrypoint: str,
    owners: Dict[str, Set[str]],
    unique_runtime: Set[str],
) -> None:
    """Record a unique non-entrypoint; fail immediately at the 1025th."""

    if path not in unique_runtime:
        if len(unique_runtime) >= MAX_RUNTIME_FILES:
            _fail(
                "limit",
                f"runtime file count would exceed maximum {MAX_RUNTIME_FILES} "
                f"at {path}",
            )
        unique_runtime.add(path)
    owners.setdefault(path, set()).add(entrypoint)


def resolve_compiler_runtime_graph(
    *,
    entrypoints: Sequence[str],
    inspections: Sequence[Tuple[str, MachOInspection]],
    allowed_system_roots: Sequence[str],
) -> CompilerRuntimeGraph:
    """Resolve a pure in-memory compiler runtime graph.

    All image paths are normalized root-relative POSIX paths.  Inputs and
    system roots must already be unique sorted; violations fail closed.
    """

    roots = _validate_system_roots(allowed_system_roots)

    entrypoint_tuple = _require_unique_sorted_strings(
        entrypoints,
        code="input",
        label="entrypoints",
    )
    if not entrypoint_tuple:
        _fail("input", "entrypoints must not be empty")
    for path in entrypoint_tuple:
        if not _is_normalized_root_relative(path):
            _fail("input", f"entrypoint path is not normalized root-relative: {path}")

    if type(inspections) not in (tuple, list):
        _fail("input", "inspections must be a sequence of (path, MachOInspection)")

    inspection_paths: List[str] = []
    known: Dict[str, MachOInspection] = {}
    for index, item in enumerate(inspections):
        if type(item) is not tuple or len(item) != 2:
            _fail(
                "input",
                f"inspections[{index}] must be a (path, MachOInspection) pair",
            )
        path, inspection = item
        if type(path) is not str:
            _fail("input", f"inspections[{index}] path must be an exact str")
        if _has_forbidden_controls(path):
            _fail("input", f"inspections[{index}] path has forbidden controls")
        if type(inspection) is not MachOInspection:
            _fail(
                "input",
                f"inspections[{index}] inspection must be MachOInspection",
            )
        if not _is_normalized_root_relative(path):
            _fail("input", f"image path is not normalized root-relative: {path}")
        inspection_paths.append(path)
        if path in known:
            _fail("input", f"duplicate inspection path: {path}")
        known[path] = _validate_inspection(inspection, path=path)

    if inspection_paths != sorted(inspection_paths):
        _fail("input", "inspections must be unique sorted by path")
    if len(inspection_paths) != len(set(inspection_paths)):
        _fail("input", "inspections must be unique sorted by path")

    entrypoint_set = set(entrypoint_tuple)
    for path in entrypoint_tuple:
        if path not in known:
            _fail("input", f"entrypoint missing inspection: {path}")

    # Finalized load edges per image; must be context-independent.
    finalized_loads: Dict[str, Tuple[ResolvedMachoLoad, ...]] = {}
    owners: Dict[str, Set[str]] = {}
    unique_runtime: Set[str] = set()
    entrypoint_graphs: List[RuntimeEntrypointGraph] = []

    for entrypoint in entrypoint_tuple:
        # Context key is the *inherited* rpath tuple used when entering a node.
        # A new inherited context is always re-expanded even if direct loads match,
        # so diamond descendants can still surface context-dependent resolution.
        seen_inherited: Dict[str, Set[Tuple[str, ...]]] = {}
        walk_contexts = 0
        reachable_nodes: Set[str] = set()
        pending: Deque[Tuple[str, Tuple[str, ...]]] = deque()
        pending.append((entrypoint, ()))

        while pending:
            node, inherited = pending.popleft()
            prior_contexts = seen_inherited.setdefault(node, set())
            if inherited in prior_contexts:
                # Exact (node, inherited) pair already expanded — cycle / requeue.
                continue
            if len(prior_contexts) >= _MAX_INHERITED_CONTEXTS_PER_IMAGE:
                _fail(
                    "limit",
                    f"inherited context count for {node} exceeds "
                    f"{_MAX_INHERITED_CONTEXTS_PER_IMAGE}",
                )
            walk_contexts += 1
            if walk_contexts > _MAX_WALK_CONTEXTS:
                _fail(
                    "limit",
                    f"walk context count exceeds {_MAX_WALK_CONTEXTS} "
                    f"for entrypoint {entrypoint}",
                )
            prior_contexts.add(inherited)

            if node != entrypoint:
                # Count the reachable node before inspecting or expanding it;
                # the 1025th unique runtime file must fail at first contact.
                _note_runtime_file(
                    path=node,
                    entrypoint=entrypoint,
                    owners=owners,
                    unique_runtime=unique_runtime,
                )

            inspection = known[node]
            loads, active_rpaths = _resolve_image_loads(
                node,
                inspection,
                entrypoint_path=entrypoint,
                inherited_rpaths=inherited,
                known_images=known,
                entrypoint_set=entrypoint_set,
                allowed_system_roots=roots,
            )

            previous = finalized_loads.get(node)
            if previous is not None and previous != loads:
                _fail(
                    "context",
                    f"context-dependent resolution for {node}",
                )
            finalized_loads[node] = loads
            reachable_nodes.add(node)

            # Always propagate this active context to descendants, including when
            # the node was already visited under a different inherited rpath set
            # that produced the same direct loads.
            for edge in loads:
                target = edge.resolved_path
                if target not in known:
                    _fail(
                        "unresolved",
                        f"reachable load is unresolved: {node} -> "
                        f"{edge.install_name}",
                    )
                pending.append((target, active_rpaths))

        reachable = tuple(
            sorted(path for path in reachable_nodes if path != entrypoint)
        )
        entrypoint_graphs.append(
            RuntimeEntrypointGraph(
                path=entrypoint,
                loads=finalized_loads[entrypoint],
                reachable=reachable,
            )
        )

    runtime_paths = tuple(sorted(owners.keys()))
    files = tuple(
        RuntimeFileGraph(
            path=path,
            owners=tuple(sorted(owners[path])),
            loads=finalized_loads[path],
        )
        for path in runtime_paths
    )

    return CompilerRuntimeGraph(
        entrypoints=tuple(entrypoint_graphs),
        files=files,
    )


__all__ = (
    "CompilerRuntimeGraph",
    "MAX_RUNTIME_FILES",
    "MachOInspection",
    "ResolvedMachoLoad",
    "RuntimeEntrypointGraph",
    "RuntimeFileGraph",
    "RuntimeGraphError",
    "resolve_compiler_runtime_graph",
)
