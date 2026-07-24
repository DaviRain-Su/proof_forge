#!/usr/bin/env python3
"""Kernel-backed one-time seedRoot custody tests.

The harness statically links the production C custody component and exercises
real openat/getdents64/statx/fstat/pread/fcntl behavior. All seeds and roots are
temporary synthetic fixtures. Passing this test does not establish namespace,
seccomp, peer-process, formal qualification, or production key custody.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

_HERE = Path(__file__).resolve().parent
_ROOT = _HERE.parent
sys.path.insert(0, str(_HERE))

import bootstrap_task_producers as _BTP
import task_qualification_objects as _TQO

_BASE_SEEDS = tuple(
    hashlib.sha256(label).digest()
    for label in (
        b"pf-tq-custody-service",
        b"pf-tq-custody-role-a",
        b"pf-tq-custody-role-q",
        b"pf-tq-custody-role-s",
    )
)
_BASE_PUBLIC = tuple(_BTP.ed25519_public_key_from_seed(seed) for seed in _BASE_SEEDS)
_FIXTURE_SEED = _TQO.RFC8032_VECTOR_SEEDS[1]
_FIXTURE_PUBLIC = _BTP.ed25519_public_key_from_seed(_FIXTURE_SEED)
_NAMES = ("service.seed", "role-0.seed", "role-1.seed", "role-2.seed")


@dataclass(frozen=True)
class Case:
    name: str
    mode: int
    encoding: str = "raw"
    mutate: Callable[[Path], None] | None = None


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str = ""

    def __str__(self) -> str:
        suffix = f" — {self.detail}" if self.detail else ""
        return f"[{'PASS' if self.passed else 'FAIL'}] {self.name}{suffix}"


def _c_bytes(name: str, raw: bytes) -> str:
    return (
        f"static const unsigned char {name}[32] = {{"
        + ",".join(f"0x{value:02x}" for value in raw)
        + "};\n"
    )


def generate_driver(destination: Path) -> None:
    arrays = []
    for index, seed in enumerate(_BASE_SEEDS):
        arrays.append(_c_bytes(f"seed_{index}", seed))
        arrays.append(_c_bytes(f"public_{index}", _BASE_PUBLIC[index]))
    arrays.append(_c_bytes("fixture_public", _FIXTURE_PUBLIC))
    source = f'''#define _GNU_SOURCE
#include "task_qualification_seed_custody_v2.h"
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

{''.join(arrays)}

static int all_zero(const unsigned char *bytes, size_t size) {{
    unsigned char aggregate = 0;
    size_t index;
    for (index = 0; index < size; ++index) aggregate |= bytes[index];
    return aggregate == 0;
}}

int main(int argc, char **argv) {{
    static const char *const slots[4] = {{"service", "role-0", "role-1", "role-2"}};
    static const char *const keys[4] = {{"service", "key-architecture", "key-quality", "key-security"}};
    static const unsigned char *const seeds[4] = {{seed_0, seed_1, seed_2, seed_3}};
    static const unsigned char *const publics[4] = {{public_0, public_1, public_2, public_3}};
    pf_tq_seed_custody_config_v2 config;
    pf_tq_seed_custody_v2 custody;
    struct stat root_status;
    char error[PF_TQ_SEED_CUSTODY_V2_ERROR_BYTES];
    int root_fd;
    int occupied = -1;
    int mode;
    int rc;
    size_t index;
    if (argc != 3) return 2;
    mode = atoi(argv[2]);
    root_fd = open(argv[1], O_RDONLY | O_DIRECTORY | O_NOFOLLOW |
        (mode == 18 ? 0 : O_CLOEXEC));
    if (root_fd != 3 || fstat(root_fd, &root_status) != 0) return 3;
    memset(&config, 0, sizeof(config));
    config.seed_root_fd = root_fd;
    config.seed_root_device = root_status.st_dev;
    config.seed_root_inode = root_status.st_ino;
    config.service_uid = geteuid();
    config.service_gid = getegid();
    for (index = 0; index < 4; ++index) {{
        config.seeds[index].slot = slots[index];
        config.seeds[index].key_id = keys[index];
        config.seeds[index].fd = 4 + (int)index;
        memcpy(config.seeds[index].public_key, publics[index], 32);
    }}
    if (mode == 10) {{
        for (index = 0; index < 4; ++index) config.seeds[index].fd = 5 + (int)index;
    }}
    if (mode == 11) config.seed_root_inode ^= 1;
    if (mode == 12) config.seeds[2].public_key[0] ^= 1;
    if (mode == 19) config.seeds[0].fd = root_fd;
    if (mode == 20) memcpy(config.seeds[0].public_key, fixture_public, 32);
    if (mode == 21) memcpy(config.seeds[2].public_key, config.seeds[1].public_key, 32);
    if (mode == 22) {{
        config.seeds[1].key_id = "key-z";
        config.seeds[2].key_id = "key-a";
    }}
    if (mode == 23) {{
        occupied = open("/dev/null", O_RDONLY | O_CLOEXEC);
        if (occupied != 4) return 4;
    }}
    if (mode == 24) config.service_uid = 65534;
    if (mode == 25) config.service_uid = (uid_t)INT32_MAX + 1U;
    rc = pf_tq_seed_custody_open_v2(&config, &custody, error, sizeof(error));
    if (mode <= 2) {{
        if (rc != 0 || !custody.initialized || fcntl(root_fd, F_GETFD) != -1 ||
                errno != EBADF || error[0] != '\\0') {{
            fprintf(stderr, "positive custody failed: %s\\n", error);
            pf_tq_seed_custody_close_v2(&custody);
            return 10;
        }}
        for (index = 0; index < 4; ++index) {{
            if (custody.seeds[index].fd != 4 + (int)index ||
                    fcntl(custody.seeds[index].fd, F_GETFD) != 0 ||
                    memcmp(custody.seeds[index].seed, seeds[index], 32) != 0 ||
                    memcmp(custody.seeds[index].public_key, publics[index], 32) != 0) {{
                pf_tq_seed_custody_close_v2(&custody);
                return 11;
            }}
        }}
        pf_tq_seed_custody_close_v2(&custody);
        if (custody.initialized) return 12;
        for (index = 0; index < 4; ++index) {{
            if (custody.seeds[index].fd != -1 ||
                    !all_zero(custody.seeds[index].seed, 32) ||
                    !all_zero(custody.seeds[index].public_key, 32)) return 13;
        }}
        return 0;
    }}
    if (rc == 0 || custody.initialized || error[0] == '\\0' ||
            fcntl(root_fd, F_GETFD) != -1 || errno != EBADF) {{
        fprintf(stderr, "negative custody invariant failed mode=%d rc=%d error=%s\\n",
            mode, rc, error);
        pf_tq_seed_custody_close_v2(&custody);
        return 20;
    }}
    pf_tq_seed_custody_close_v2(&custody);
    if (occupied >= 0 && close(occupied) != 0) return 21;
    for (index = 4; index <= 8; ++index) {{
        errno = 0;
        if ((int)index == occupied) continue;
        if (fcntl((int)index, F_GETFD) != -1 || errno != EBADF) return 22;
    }}
    return 0;
}}
'''
    destination.write_text(source, encoding="utf-8")


def compile_driver(source: Path, binary: Path) -> None:
    result = subprocess.run(
        [
            "/usr/bin/cc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
            "-Wpedantic", "-static", "-no-pie", "-I", str(_HERE),
            "-o", str(binary), str(source),
            str(_HERE / "task_qualification_seed_custody_v2.c"),
            "-lcrypto", "-ldl", "-pthread",
        ],
        cwd=_ROOT,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
        check=False,
    )
    if result.returncode != 0:
        raise AssertionError(f"static seed-custody compile failed: {result.stderr}")
    elf = subprocess.run(
        ["/usr/bin/readelf", "-W", "-l", "-d", str(binary)],
        cwd=_ROOT,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=False,
    )
    if elf.returncode != 0 or elf.stderr:
        raise AssertionError(f"seed-custody ELF inspection failed: {elf.stderr}")
    if any("INTERP" in line or "(NEEDED)" in line for line in elf.stdout.splitlines()):
        raise AssertionError("seed-custody ELF contains PT_INTERP or DT_NEEDED")


def _encode(seed: bytes, encoding: str) -> bytes:
    if encoding == "raw":
        return seed
    if encoding == "hex":
        return seed.hex().encode("ascii")
    if encoding == "hex-lf":
        return seed.hex().encode("ascii") + b"\n"
    raise AssertionError(f"unknown seed encoding: {encoding}")


def _prepare_root(parent: Path, case: Case) -> Path:
    root = parent / case.name
    root.mkdir(mode=0o700)
    seeds = list(_BASE_SEEDS)
    if case.mode == 20:
        seeds[0] = _FIXTURE_SEED
    for name, seed in zip(_NAMES, seeds):
        path = root / name
        path.write_bytes(_encode(seed, case.encoding))
        path.chmod(0o400)
    if case.mutate is not None:
        case.mutate(root)
    return root


def _extra(root: Path) -> None:
    path = root / "extra.seed"
    path.write_bytes(b"x" * 32)
    path.chmod(0o400)


def _root_mode(root: Path) -> None:
    root.chmod(0o750)


def _seed_mode(root: Path) -> None:
    (root / "role-1.seed").chmod(0o600)


def _hardlink(root: Path) -> None:
    target = root / "role-0.seed"
    alias = root / "role-1.seed"
    alias.unlink()
    os.link(target, alias)


def _symlink(root: Path) -> None:
    alias = root / "role-2.seed"
    alias.unlink()
    os.symlink("role-0.seed", alias)


def _short(root: Path) -> None:
    path = root / "role-0.seed"
    path.chmod(0o600)
    path.write_bytes(_BASE_SEEDS[0][:-1])
    path.chmod(0o400)


def _long(root: Path) -> None:
    path = root / "role-0.seed"
    path.chmod(0o600)
    path.write_bytes(_BASE_SEEDS[0] + b"x")
    path.chmod(0o400)


def _uppercase(root: Path) -> None:
    path = root / "role-0.seed"
    path.chmod(0o600)
    path.write_bytes(_BASE_SEEDS[0].hex().upper().encode("ascii"))
    path.chmod(0o400)


def _wrong_seed(root: Path) -> None:
    path = root / "role-2.seed"
    path.chmod(0o600)
    path.write_bytes(hashlib.sha256(b"wrong-seed").digest())
    path.chmod(0o400)


def cases() -> tuple[Case, ...]:
    return (
        Case("positive-raw32", 0, "raw"),
        Case("positive-hex64", 1, "hex"),
        Case("positive-hex64-lf", 2, "hex-lf"),
        Case("extra-root-entry", 3, mutate=_extra),
        Case("root-mode", 4, mutate=_root_mode),
        Case("seed-mode", 5, mutate=_seed_mode),
        Case("seed-hardlink", 6, mutate=_hardlink),
        Case("seed-symlink", 7, mutate=_symlink),
        Case("seed-short", 8, mutate=_short),
        Case("seed-long", 9, mutate=_long),
        Case("fixed-fd-mismatch", 10),
        Case("root-identity-mismatch", 11),
        Case("expected-public-key-mismatch", 12),
        Case("uppercase-hex", 13, "hex", _uppercase),
        Case("seed-derived-public-mismatch", 14, mutate=_wrong_seed),
        Case("seed-root-without-cloexec", 18),
        Case("seed-fd-collides-root", 19),
        Case("fixture-public-key", 20),
        Case("expected-public-key-reuse", 21),
        Case("role-key-id-order", 22),
        Case("fixed-seed-fd-occupied", 23),
        Case("service-overflow-id", 25),
        Case("service-identity-substitution", 24),
    )


def run_case(binary: Path, root: Path, case: Case) -> Result:
    process = subprocess.run(
        [str(binary), str(root), str(case.mode)],
        cwd=_ROOT,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )
    if process.returncode != 0 or process.stdout or process.stderr:
        return Result(
            case.name, False,
            f"rc={process.returncode} stdout={process.stdout!r} stderr={process.stderr!r}",
        )
    return Result(case.name, True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scratch-root", type=Path)
    arguments = parser.parse_args()
    parent = arguments.scratch_root
    if parent is not None:
        parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="pf-tq-seed-custody-v2-",
        dir=None if parent is None else str(parent),
    ) as temporary:
        base = Path(temporary)
        source = base / "seed_custody_driver.c"
        binary = base / "pf-taskqualification-seed-custody-v2-test"
        try:
            generate_driver(source)
            compile_driver(source, binary)
            roots = base / "roots"
            roots.mkdir(mode=0o700)
            selected = cases()
            results = [
                run_case(binary, _prepare_root(roots, case), case)
                for case in selected
            ]
        except Exception as exc:
            print(f"task-qualification seed-custody-v2 self-test: PRECHECK-FAIL: {exc}")
            return 1
    passed = sum(result.passed for result in results)
    print(f"task-qualification seed-custody-v2 self-test: {passed}/{len(results)} passed")
    for result in results:
        print(result)
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
