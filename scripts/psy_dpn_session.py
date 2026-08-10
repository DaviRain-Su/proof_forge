#!/usr/bin/env python3
"""Multi-step DPN session for ProofForge *.dpn.json (shared in-memory state).

Why not shell `psy_user_cli simulate` three times?
  Each simulate process constructs a fresh InMemoryStateBackend. So
  initialize(7) / increment(5) / get() correctly become 7, 5, 0 as *independent*
  runs — that is CLI process isolation, not a StateCell bug.

This harness keeps one Session and commits Set overlays between calls, matching
the Psy IDE/WASM pattern. Engineering only — not UPS/proof/network.

State-command scheduling (official psy_vm simulate):
  * `state_command_resolution_indices[i]` = definition **step** at which cmd i runs
    (before evaluating definitions[step]; res==len(defs) means after all defs).
  * GetState ops (54/53/55) also force their cmd if not yet run (defensive).
  * Before a Get, earlier ready Sets are committed (write-then-reload).

Slot model (aligned with official psy_vm simulate resolve()):
  * state cmd `sub_slot_index` / `value` are **wire ids**; physical leaf =
    Constant wire's literal (general multi-leaf path).
  * Counter golden keeps bare 0/1 indices that collapse to storage slot 0.
  * Multi-leaf programs use physical leaves 0..n-1.
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

INDEX_BITS = 32
INDEX_MASK = (1 << INDEX_BITS) - 1
U64 = (1 << 64) - 1

DT_TARGET = 0
DT_BOOL = 1
DT_U32 = 2


def encode_id(data_type: int, index: int) -> int:
    return ((int(data_type) & U64) << INDEX_BITS) | (int(index) & INDEX_MASK)


def decode_id(w: int) -> tuple[int, int]:
    w = int(w) & U64
    return w >> INDEX_BITS, w & INDEX_MASK


class DpnError(Exception):
    pass


@dataclass
class Session:
    user_id: int = 1
    contract_id: int = 1
    slots: dict[int, list[int]] = field(default_factory=dict)

    def get(self, slot: int = 0) -> list[int]:
        return list(self.slots.get(slot, [0]))

    def set(self, slot: int, value: list[int]) -> None:
        self.slots[slot] = [int(v) & U64 for v in value]


def decode_wire_literal_from_defs(defs: list[dict], wire_ref: int) -> int | None:
    """If wire_ref is a Target Constant, return its literal; else None."""
    wire_ref = int(wire_ref) & U64
    # bare target index or encoded target id
    if wire_ref > INDEX_MASK:
        dt, idx = decode_id(wire_ref)
        if dt != DT_TARGET:
            return None
    else:
        idx = wire_ref
    for d in defs:
        if int(d.get("data_type", -1)) == DT_TARGET and int(d.get("index", -1)) == idx:
            if int(d.get("op_type", -1)) == 1:  # constant
                ins = d.get("inputs") or [0]
                return int(ins[0]) & U64
            return None
    return None


def package_physical_leaves(pkg: dict[str, dict]) -> set[int]:
    """Physical storage leaves referenced by Get/Set cmds (after wire resolve)."""
    leaves: set[int] = set()
    for fn in pkg.values():
        defs = list(fn.get("definitions") or [])
        for c in fn.get("state_commands") or []:
            if "sub_slot_index" in c:
                ref = int(c["sub_slot_index"])
                lit = decode_wire_literal_from_defs(defs, ref)
                leaves.add(ref if lit is None else lit)
            elif "slot_index" in c:
                leaves.add(int(c["slot_index"]))
    return leaves


def physical_slot_from_cmd(cmd: dict, defs: list[dict], leaves: set[int]) -> int:
    """Map cmd sub_slot wire → physical leaf for session storage.

    Official simulate: slot = resolve(sub_slot_index wire).
    Counter golden uses bare 0/1 that resolve via target wires to slot 0 values
    in product packages we collapse {0,1}-only packages historically — but with
    wire-resolved leaves, multi-leaf packages use 0..n-1 directly.
    """
    if "sub_slot_index" in cmd:
        ref = int(cmd["sub_slot_index"])
        lit = decode_wire_literal_from_defs(defs, ref)
        if lit is not None:
            return int(lit)
        # bare index (Counter template): treat as physical leaf; {0,1}-only
        # single-field programs collapse both to 0 for get@0/set@1 golden.
        if leaves <= {0, 1}:
            return 0
        return ref if ref <= INDEX_MASK else decode_id(ref)[1]
    if "slot_index" in cmd:
        return int(cmd["slot_index"])
    return 0


class Executor:
    def __init__(self, session: Session, fn: dict[str, Any], leaves: set[int]):
        self.s = session
        self.fn = fn
        self.leaves = leaves
        self.v: dict[int, int] = {}
        self.cmd_res: list[list[int]] = []
        self.reads: list[dict] = []
        self.writes: list[dict] = []
        self.events: list[dict] = []
        self.user_id = session.user_id
        self.contract_id = session.contract_id
        self.checkpoint_id = 100  # matches psy_user_cli simulate default context
        self.cmds: list[dict] = []
        self.done: set[int] = set()

    def put(self, dt: int, idx: int, val: int) -> None:
        self.v[encode_id(dt, idx)] = int(val) & U64

    def resolve(self, ref: int) -> int:
        ref = int(ref) & U64
        if ref in self.v:
            return self.v[ref]
        dt, idx = decode_id(ref)
        enc = encode_id(dt, idx)
        if enc in self.v:
            return self.v[enc]
        if ref <= INDEX_MASK:
            for cand_dt in (DT_TARGET, DT_BOOL, DT_U32):
                enc2 = encode_id(cand_dt, ref)
                if enc2 in self.v:
                    return self.v[enc2]
        raise DpnError(f"unbound wire {ref} (dt={dt}, idx={idx})")

    def g(self, ref: int) -> int:
        return self.resolve(ref)

    def _is_set(self, c: dict) -> bool:
        t = c.get("type") or ""
        return t.startswith("Set") or t.startswith("Invoke")

    def _is_get(self, c: dict) -> bool:
        t = c.get("type") or ""
        return t.startswith("Get")

    def _set_ready(self, i: int) -> bool:
        c = self.cmds[i]
        try:
            if "condition" in c:
                self.g(int(c["condition"]))
            if "value" in c:
                val = c["value"]
                if isinstance(val, list):
                    for x in val:
                        self.g(int(x))
                else:
                    self.g(int(val))
            for x in c.get("input_args") or []:
                self.g(int(x))
            return True
        except DpnError:
            return False

    def run_cmd(self, i: int) -> None:
        if i in self.done:
            return
        c = self.cmds[i]
        if self._is_get(c):
            for j in range(i):
                if j not in self.done and self._is_set(self.cmds[j]) and self._set_ready(j):
                    self.run_cmd(j)
        if self._is_set(c) and not self._set_ready(i):
            raise DpnError(f"state cmd {i} Set not ready (unbound condition/value)")
        self._cmd(i, c)
        self.done.add(i)

    def run(self, inputs: list[int]) -> dict[str, Any]:
        fn = self.fn
        cin = [int(x) for x in (fn.get("circuit_inputs") or [])]
        if len(inputs) != len(cin):
            raise DpnError(f"arity: want {len(cin)} got {len(inputs)}")
        for w, val in zip(cin, inputs):
            self.v[int(w) & U64] = int(val) & U64
            dt, idx = decode_id(int(w))
            self.put(dt, idx, val)

        defs = list(fn.get("definitions") or [])
        self.cmds = list(fn.get("state_commands") or [])
        res = [int(x) for x in (fn.get("state_command_resolution_indices") or [])]
        if len(res) != len(self.cmds):
            raise DpnError("resolution_indices length mismatch")
        self.cmd_res = [[] for _ in self.cmds]
        self.done = set()

        # Official psy_vm: resolution index = definition step. Cmds with
        # res==step run *before* evaluating definitions[step].
        def run_cmds_at_step(step: int) -> None:
            for i, r in enumerate(res):
                if r == step and i not in self.done:
                    self.run_cmd(i)

        for di, d in enumerate(defs):
            run_cmds_at_step(di)
            op = int(d["op_type"])
            dt, idx = int(d["data_type"]), int(d["index"])
            ins = [int(x) for x in (d.get("inputs") or [])]

            if op == 0:
                ord_ = ins[0] if ins else idx
                if ord_ >= len(inputs):
                    raise DpnError(f"inputTarget ord {ord_} out of range")
                self.put(dt, idx, inputs[ord_])
            elif op == 1:
                self.put(dt, idx, ins[0] if ins else 0)
            elif op == 2:
                self.put(dt, idx, 1)
            elif op == 3:
                self.put(dt, idx, 0)
            elif op == 4:
                self.put(dt, idx, self.g(ins[0]) + self.g(ins[1]))
            elif op == 5:
                self.put(dt, idx, (self.g(ins[0]) - self.g(ins[1])) & U64)
            elif op == 6:
                self.put(dt, idx, (self.g(ins[0]) * self.g(ins[1])) & U64)
            elif op == 7:
                den = self.g(ins[1])
                if den == 0:
                    raise DpnError("div by zero")
                self.put(dt, idx, self.g(ins[0]) // den)
            elif op == 8:
                self.put(dt, idx, 0 if self.g(ins[0]) else 1)
            elif op == 9:
                self.put(dt, idx, 1 if self.g(ins[0]) and self.g(ins[1]) else 0)
            elif op == 10:
                self.put(dt, idx, 1 if self.g(ins[0]) or self.g(ins[1]) else 0)
            elif op == 11:
                self.put(dt, idx, self.g(ins[0]) ^ self.g(ins[1]))
            elif op == 12:
                self.put(dt, idx, 0 if (self.g(ins[0]) or self.g(ins[1])) else 1)
            elif op == 13:
                self.put(dt, idx, 1 if self.g(ins[0]) == self.g(ins[1]) else 0)
            elif op == 14:
                self.put(dt, idx, 1 if self.g(ins[0]) <= self.g(ins[1]) else 0)
            elif op == 15:
                self.put(dt, idx, 1 if self.g(ins[0]) >= self.g(ins[1]) else 0)
            elif op == 16:
                self.put(dt, idx, 1 if self.g(ins[0]) > self.g(ins[1]) else 0)
            elif op == 17:
                self.put(dt, idx, 1 if self.g(ins[0]) < self.g(ins[1]) else 0)
            elif op == 23:
                self.put(dt, idx, self.g(ins[1]) if self.g(ins[0]) else self.g(ins[2]))
            elif op == 27:
                den = self.g(ins[1])
                if den == 0:
                    raise DpnError("mod by zero")
                self.put(dt, idx, self.g(ins[0]) % den)
            elif op == 31:
                self.put(dt, idx, self.g(ins[0]) & 0xFFFFFFFF)
            elif op in (32, 33):
                a = self.g(ins[0])
                b = self.g(ins[1]) if op == 32 else int(ins[1])
                self.put(dt, idx, (a & b) & 0xFFFFFFFF)
            elif op in (34, 35):
                a = self.g(ins[0])
                b = self.g(ins[1]) if op == 34 else int(ins[1])
                self.put(dt, idx, (a | b) & 0xFFFFFFFF)
            elif op in (36, 37):
                a = self.g(ins[0])
                b = self.g(ins[1]) if op == 36 else int(ins[1])
                self.put(dt, idx, (a ^ b) & 0xFFFFFFFF)
            elif op == 38:
                self.put(dt, idx, (self.g(ins[0]) << (self.g(ins[1]) & 31)) & 0xFFFFFFFF)
            elif op == 40:
                self.put(dt, idx, (self.g(ins[0]) << (int(ins[1]) & 31)) & 0xFFFFFFFF)
            elif op == 42:
                self.put(dt, idx, (self.g(ins[0]) & 0xFFFFFFFF) >> (self.g(ins[1]) & 31))
            elif op == 43:
                self.put(dt, idx, (self.g(ins[0]) & 0xFFFFFFFF) >> (int(ins[1]) & 31))
            elif op == 46:
                self.put(dt, idx, self.user_id)
            elif op == 47:
                self.put(dt, idx, self.contract_id)
            elif op == 48:
                self.put(dt, idx, self.checkpoint_id)
            elif op in (53, 54, 55):
                ci = int(ins[0])
                self.run_cmd(ci)
                limbs = self.cmd_res[ci] or [0]
                self.put(dt, idx, limbs[0])
            elif op == 64:
                raise DpnError(
                    "unsupported op_type 64 unaryInverse (use official psy_user_cli simulate)"
                )
            elif op == 65:
                self.put(dt, idx, (-self.g(ins[0])) & U64)
            elif op == 66:
                ord_ = ins[0] if ins else idx
                self.put(dt, idx, inputs[ord_] & 0xFFFFFFFF)
            elif op == 67:
                self.put(dt, idx, (ins[0] if ins else 0) & 0xFFFFFFFF)
            elif op in (68, 69, 70, 71):
                a, b = self.g(ins[0]), self.g(ins[1])
                if op == 68:
                    self.put(dt, idx, (a + b) & 0xFFFFFFFF)
                elif op == 69:
                    self.put(dt, idx, (a - b) & 0xFFFFFFFF)
                elif op == 70:
                    self.put(dt, idx, (a * b) & 0xFFFFFFFF)
                else:
                    if b == 0:
                        raise DpnError("u32 div0")
                    self.put(dt, idx, (a // b) & 0xFFFFFFFF)
            elif op == 72:
                self.put(dt, idx, self.g(ins[0]))
            elif op == 73:
                self.put(dt, idx, 1 if self.g(ins[0]) else 0)
            elif op == 74:
                ord_ = ins[0] if ins else idx
                self.put(dt, idx, 1 if inputs[ord_] else 0)
            elif op == 75:
                b = self.g(ins[1])
                if b == 0:
                    raise DpnError("u32 mod0")
                self.put(dt, idx, (self.g(ins[0]) % b) & 0xFFFFFFFF)
            else:
                raise DpnError(f"unsupported op_type {op} at def {di}")

        # State cmds resolving after last definition (res == len(defs)).
        run_cmds_at_step(len(defs))
        # Any remaining ready cmds (defensive).
        for i in range(len(self.cmds)):
            if i not in self.done and self._set_ready(i):
                self.run_cmd(i)

        for a in fn.get("assertions") or []:
            left, right = self.g(int(a["left"])), self.g(int(a["right"]))
            if left != right:
                raise DpnError(f"assert {a.get('message', '')!r}: {left} != {right}")

        # PARTIAL events: filter by condition; resolve identity + data wires.
        for ev in fn.get("events") or []:
            cond = int(ev.get("condition", 0))
            try:
                if not self.g(cond):
                    continue
            except DpnError:
                continue
            def _rid(ref: int) -> int:
                try:
                    return self.g(int(ref))
                except DpnError:
                    return int(ref)
            self.events.append(
                {
                    "checkpoint_id": _rid(ev.get("checkpoint_id", 0)),
                    "user_id": _rid(ev.get("user_id", self.user_id)),
                    "contract_id": _rid(ev.get("contract_id", self.contract_id)),
                    "data": [_rid(x) for x in (ev.get("data") or [])],
                }
            )

        outs = [self.g(int(w)) for w in (fn.get("circuit_outputs") or [])]
        return {
            "success": True,
            "method": fn.get("name"),
            "method_id": fn.get("method_id"),
            "inputs": inputs,
            "outputs": outs,
            "state_reads": self.reads,
            "state_writes": self.writes,
            "events": self.events,
            "state_delta": [
                {
                    "slot_index": w["slot_index"],
                    "old_value": w["old_value"],
                    "new_value": w["new_value"],
                }
                for w in self.writes
            ],
        }

    def _slot_key(self, cmd: dict[str, Any]) -> int:
        defs = list(self.fn.get("definitions") or [])
        return physical_slot_from_cmd(cmd, defs, self.leaves)

    def _cmd(self, i: int, cmd: dict[str, Any]) -> None:
        ctype = cmd.get("type") or ""
        slot = self._slot_key(cmd)
        if ctype == "GetSelfUserCurrentContractStateSlotSingle":
            val = self.s.get(slot)
            self.cmd_res[i] = val
            self.reads.append(
                {
                    "command_index": i,
                    "command_type": ctype,
                    "slot_index": slot,
                    "sub_slot_index": cmd.get("sub_slot_index"),
                    "value": val,
                }
            )
        elif ctype == "SetContractStateSlotSingle":
            if "condition" in cmd and not self.g(int(cmd["condition"])):
                self.cmd_res[i] = []
                return
            new_v = [self.g(int(cmd["value"]))]
            old_v = self.s.get(slot)
            self.s.set(slot, new_v)
            self.cmd_res[i] = new_v
            self.writes.append(
                {
                    "command_index": i,
                    "command_type": ctype,
                    "slot_index": slot,
                    "sub_slot_index": cmd.get("sub_slot_index"),
                    "old_value": old_v,
                    "new_value": new_v,
                    "condition": True,
                }
            )
        elif ctype == "GetSelfUserCurrentContractStateSlotHash":
            val = self.s.get(slot)
            self.cmd_res[i] = val
            self.reads.append(
                {
                    "command_index": i,
                    "command_type": ctype,
                    "slot_index": slot,
                    "value": val,
                }
            )
        elif ctype == "SetContractStateSlotHash":
            if "condition" in cmd and not self.g(int(cmd["condition"])):
                self.cmd_res[i] = []
                return
            raw = cmd.get("value") or []
            new_v = [self.g(int(x)) for x in raw]
            old_v = self.s.get(slot)
            self.s.set(slot, new_v)
            self.cmd_res[i] = new_v
            self.writes.append(
                {
                    "command_index": i,
                    "command_type": ctype,
                    "slot_index": slot,
                    "old_value": old_v,
                    "new_value": new_v,
                    "condition": True,
                }
            )
        elif ctype == "InvokeExternalContractFunctionSync":
            if "condition" in cmd and not self.g(int(cmd["condition"])):
                self.cmd_res[i] = []
                return
            self.cmd_res[i] = []
            self.writes.append(
                {
                    "command_index": i,
                    "command_type": ctype,
                    "slot_index": slot,
                    "contract_id": cmd.get("contract_id"),
                    "method_id": cmd.get("method_id"),
                    "input_args": [self.g(int(x)) for x in (cmd.get("input_args") or [])],
                    "note": "PARTIAL: invoke recorded, not executed",
                }
            )
        else:
            raise DpnError(f"unsupported state cmd {ctype}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dpn", type=Path, required=True)
    ap.add_argument(
        "--call",
        action="append",
        default=[],
        help="METHOD or METHOD:arg,arg (repeatable). Default: initialize:7 increment:5 get",
    )
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    calls = args.call or ["initialize:7", "increment:5", "get"]

    pkg_list = json.loads(args.dpn.read_text())
    pkg = {d["name"]: d for d in pkg_list}
    leaves = package_physical_leaves(pkg)
    session = Session()
    results = []

    for spec in calls:
        if ":" in spec:
            name, rest = spec.split(":", 1)
            inputs = [int(x) for x in rest.split(",") if x != ""]
        else:
            name, inputs = spec, []
        if name not in pkg:
            print(f"unknown method {name}; have {sorted(pkg)}", file=sys.stderr)
            return 1
        try:
            r = Executor(session, pkg[name], leaves).run(inputs)
        except DpnError as e:
            print(f"FAIL {name}: {e}", file=sys.stderr)
            return 2
        results.append(r)
        if not args.json:
            print(
                f"OK {name}({inputs}) outputs={r['outputs']} writes={len(r['state_writes'])}"
            )

    if args.json:
        json.dump(
            {
                "success": True,
                "calls": results,
                "slots": {str(k): v for k, v in sorted(session.slots.items())},
                "physical_leaves_in_package": sorted(leaves),
            },
            sys.stdout,
            indent=2,
        )
        print()
    else:
        print(f"FINAL slots={dict(sorted(session.slots.items()))}")

    if calls == ["initialize:7", "increment:5", "get"]:
        if session.get(0) != [12]:
            print(f"FAIL want slot0=[12] got {session.get(0)}", file=sys.stderr)
            return 3
        if results[1]["outputs"] != [12]:
            print(f"FAIL want increment [12] got {results[1]['outputs']}", file=sys.stderr)
            return 3
        if results[-1]["outputs"] != [12]:
            print(f"FAIL want get [12] got {results[-1]['outputs']}", file=sys.stderr)
            return 3
        if not args.json:
            print("OK session continuity: init(7)+increment(5)+get => 12")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
