#!/usr/bin/env python3
"""Multi-step DPN session for ProofForge *.dpn.json (shared in-memory state).

Why not shell `psy_user_cli simulate` three times?
  Each simulate process constructs a fresh InMemoryStateBackend. So
  initialize(7) / increment(5) / get() correctly become 7, 5, 0 as *independent*
  runs — that is CLI process isolation, not a StateCell bug.

This harness keeps one Session and commits Set overlays between calls, matching
the Psy IDE/WASM pattern. Engineering only — not UPS/proof/network.
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

INDEX_BITS = 32
U64 = (1 << 64) - 1


def wid(data_type: int, index: int) -> int:
    return ((int(data_type) & U64) << INDEX_BITS) | (int(index) & ((1 << INDEX_BITS) - 1))


class DpnError(Exception):
    pass


@dataclass
class Session:
    user_id: int = 1
    contract_id: int = 1
    # Official simulate reports slot_index=0 for StateCell singles.
    slots: dict[int, list[int]] = field(default_factory=dict)

    def get(self, slot: int = 0) -> list[int]:
        return list(self.slots.get(slot, [0]))

    def set(self, slot: int, value: list[int]) -> None:
        self.slots[slot] = [int(v) & U64 for v in value]


class Executor:
    def __init__(self, session: Session, fn: dict[str, Any]):
        self.s = session
        self.fn = fn
        self.v: dict[int, int] = {}
        self.cmd_res: list[list[int]] = []
        self.reads: list[dict] = []
        self.writes: list[dict] = []

    def g(self, w: int) -> int:
        w = int(w)
        if w not in self.v:
            raise DpnError(f"unbound wire {w}")
        return self.v[w]

    def p(self, dt: int, idx: int, val: int) -> None:
        self.v[wid(dt, idx)] = int(val) & U64

    def run(self, inputs: list[int]) -> dict[str, Any]:
        fn = self.fn
        cin = [int(x) for x in (fn.get("circuit_inputs") or [])]
        if len(inputs) != len(cin):
            raise DpnError(f"arity: want {len(cin)} got {len(inputs)}")
        for w, val in zip(cin, inputs):
            self.v[w] = int(val) & U64

        defs = list(fn.get("definitions") or [])
        cmds = list(fn.get("state_commands") or [])
        res = [int(x) for x in (fn.get("state_command_resolution_indices") or [])]
        if len(res) != len(cmds):
            raise DpnError("resolution_indices length mismatch")
        self.cmd_res = [[] for _ in cmds]
        done: set[int] = set()

        def run_cmd(i: int) -> None:
            if i in done:
                return
            self._cmd(i, cmds[i])
            done.add(i)

        def run_cmds_at(point: int) -> None:
            # resolution index == definition index: run Get/Set at that fence.
            for i, r in enumerate(res):
                if r == point:
                    run_cmd(i)

        for di, d in enumerate(defs):
            run_cmds_at(di)
            op = int(d["op_type"])
            dt, idx = int(d["data_type"]), int(d["index"])
            ins = [int(x) for x in (d.get("inputs") or [])]

            if op == 0:  # inputTarget
                ord_ = ins[0] if ins else idx
                self.p(dt, idx, inputs[ord_])
            elif op == 1:  # constant
                self.p(dt, idx, ins[0] if ins else 0)
            elif op == 2:
                self.p(dt, idx, 1)
            elif op == 3:
                self.p(dt, idx, 0)
            elif op == 4:  # add
                self.p(dt, idx, self.g(ins[0]) + self.g(ins[1]))
            elif op == 5:
                self.p(dt, idx, self.g(ins[0]) - self.g(ins[1]))
            elif op == 6:
                self.p(dt, idx, self.g(ins[0]) * self.g(ins[1]))
            elif op == 7:  # div
                den = self.g(ins[1])
                if den == 0:
                    raise DpnError("div by zero")
                self.p(dt, idx, self.g(ins[0]) // den)
            elif op == 8:  # boolNot
                self.p(dt, idx, 0 if self.g(ins[0]) else 1)
            elif op == 9:
                self.p(dt, idx, 1 if self.g(ins[0]) and self.g(ins[1]) else 0)
            elif op == 10:
                self.p(dt, idx, 1 if self.g(ins[0]) or self.g(ins[1]) else 0)
            elif op == 11:  # xor
                self.p(dt, idx, self.g(ins[0]) ^ self.g(ins[1]))
            elif op == 13:
                self.p(dt, idx, 1 if self.g(ins[0]) == self.g(ins[1]) else 0)
            elif op == 14:
                self.p(dt, idx, 1 if self.g(ins[0]) <= self.g(ins[1]) else 0)
            elif op == 15:
                self.p(dt, idx, 1 if self.g(ins[0]) >= self.g(ins[1]) else 0)
            elif op == 16:
                self.p(dt, idx, 1 if self.g(ins[0]) > self.g(ins[1]) else 0)
            elif op == 17:
                self.p(dt, idx, 1 if self.g(ins[0]) < self.g(ins[1]) else 0)
            elif op == 23:  # select(cond, a, b) — if cond then a else b
                self.p(dt, idx, self.g(ins[1]) if self.g(ins[0]) else self.g(ins[2]))
            elif op == 27:  # mod
                den = self.g(ins[1])
                if den == 0:
                    raise DpnError("mod by zero")
                self.p(dt, idx, self.g(ins[0]) % den)
            elif op == 31:  # castU32
                self.p(dt, idx, self.g(ins[0]) & 0xFFFFFFFF)
            elif op in (32, 33):  # u32And / const
                a = self.g(ins[0])
                b = self.g(ins[1]) if op == 32 else ins[1]
                self.p(dt, idx, (a & b) & 0xFFFFFFFF)
            elif op in (34, 35):
                a = self.g(ins[0])
                b = self.g(ins[1]) if op == 34 else ins[1]
                self.p(dt, idx, (a | b) & 0xFFFFFFFF)
            elif op in (36, 37):
                a = self.g(ins[0])
                b = self.g(ins[1]) if op == 36 else ins[1]
                self.p(dt, idx, (a ^ b) & 0xFFFFFFFF)
            elif op == 38:  # u32ShiftLeft
                self.p(dt, idx, (self.g(ins[0]) << (self.g(ins[1]) & 31)) & 0xFFFFFFFF)
            elif op == 42:  # u32ShiftRight
                self.p(dt, idx, (self.g(ins[0]) & 0xFFFFFFFF) >> (self.g(ins[1]) & 31))
            elif op == 53:  # getStateCommandResultHash — treat as single limb 0 placeholder
                ci = ins[0]
                run_cmd(ci)
                limbs = self.cmd_res[ci] or [0]
                self.p(dt, idx, limbs[0])
            elif op == 54:  # getStateCommandResultSingle — inputs[0] = cmd index
                ci = ins[0]
                run_cmd(ci)
                limbs = self.cmd_res[ci]
                if not limbs:
                    raise DpnError(f"cmd {ci} empty result for op54")
                self.p(dt, idx, limbs[0])
            elif op == 55:  # getStateCommandResultArray — take first limb
                ci = ins[0]
                run_cmd(ci)
                limbs = self.cmd_res[ci] or [0]
                self.p(dt, idx, limbs[0])
            elif op == 65:  # unaryNegative
                self.p(dt, idx, (-self.g(ins[0])) & U64)
            elif op in (66, 67, 72, 73, 74):  # u32Input/constU32/castFelt/castBool/boolInput
                if op == 67:
                    self.p(dt, idx, ins[0] if ins else 0)
                elif op == 66:
                    ord_ = ins[0] if ins else idx
                    self.p(dt, idx, inputs[ord_] & 0xFFFFFFFF)
                elif op == 74:
                    ord_ = ins[0] if ins else idx
                    self.p(dt, idx, 1 if inputs[ord_] else 0)
                else:
                    self.p(dt, idx, self.g(ins[0]))
            elif op in (68, 69, 70, 71):  # u32 arith
                a, b = self.g(ins[0]), self.g(ins[1])
                if op == 68:
                    self.p(dt, idx, (a + b) & 0xFFFFFFFF)
                elif op == 69:
                    self.p(dt, idx, (a - b) & 0xFFFFFFFF)
                elif op == 70:
                    self.p(dt, idx, (a * b) & 0xFFFFFFFF)
                else:
                    if b == 0:
                        raise DpnError("u32 div0")
                    self.p(dt, idx, (a // b) & 0xFFFFFFFF)
            else:
                raise DpnError(f"unsupported op_type {op} at def {di}")

        # resolution past last def (e.g. initialize Set at index 3 with 3 defs)
        run_cmds_at(len(defs))
        for i in range(len(cmds)):
            run_cmd(i)

        for a in fn.get("assertions") or []:
            left, right = self.g(int(a["left"])), self.g(int(a["right"]))
            if left != right:
                raise DpnError(
                    f"assert {a.get('message','')!r}: {left} != {right}"
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
            "state_delta": [
                {
                    "slot_index": w["slot_index"],
                    "old_value": w["old_value"],
                    "new_value": w["new_value"],
                }
                for w in self.writes
            ],
        }

    def _cmd(self, i: int, cmd: dict[str, Any]) -> None:
        ctype = cmd.get("type") or ""
        # Observed: psy_user_cli simulate reports slot_index=0 for StateCell
        # *SlotSingle even when package sub_slot_index is 0 or 1.
        slot = int(cmd["slot_index"]) if "slot_index" in cmd else 0
        if ctype == "GetSelfUserCurrentContractStateSlotSingle":
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
                    "old_value": old_v,
                    "new_value": new_v,
                    "condition": True,
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
            r = Executor(session, pkg[name]).run(inputs)
        except DpnError as e:
            print(f"FAIL {name}: {e}", file=sys.stderr)
            return 2
        results.append(r)
        if not args.json:
            print(
                f"OK {name}({inputs}) outputs={r['outputs']} writes={r['state_writes']}"
            )

    if args.json:
        json.dump(
            {
                "success": True,
                "calls": results,
                "slots": {str(k): v for k, v in sorted(session.slots.items())},
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
        if results[-1]["outputs"] != [12]:
            print(f"FAIL want get [12] got {results[-1]['outputs']}", file=sys.stderr)
            return 3
        if not args.json:
            print("OK session continuity: init(7)+increment(5)+get => 12")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
