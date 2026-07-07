# RFC 0005: Solana sBPF Assembly Backend (Direct Codegen)

Status: **Accepted**

Date: 2026-07-01

## Summary

This RFC proposes a new Solana backend route alongside the existing
`solana-sbpf-linker` (Zig) route. The proposed route emits sBPF assembly
text (`.s`) directly from the portable contract IR, and delegates to the
[blueshift-gg/sbpf](https://github.com/blueshift-gg/sbpf) assembler, linker,
and test runner to produce a Solana loader‑compatible ELF.

```
Lean → LCNF → Portable Contract IR → sBPF assembly (.s) → sbpf build → ELF
```

This route avoids the main risk of the Zig route — linking the full Lean
runtime under `bpfel-freestanding` — by generating sBPF instructions directly
from the IR with no Lean runtime at all.

## Motivation

The Zig/sbpf-linker route (RFC 0002 § Binary toolchain targets) has known risks:

1. Lean's Zig runtime was not designed for the 4 KB stack limit imposed by the
   Solana BPF loader.
2. `.rodata`, `.bss`, `.data`, panic, allocator, and libc assumptions embedded
   in the Lean runtime may cause SBpf loader rejection.
3. Debuggability is limited to the raw binary.

The blueshift-gg/sbpf toolchain provides an assembler that accepts human‑readable
sBPF assembly (`.s`) and produces ELF So files. By generating `.s` text directly,
ProofForge can:

- Own register allocation, stack frames, and compute‑unit budget end to end.
- Match the EVM/Solang pattern (intermediate text + external packager).
- Gain free observability via the sbpf disassembler, debugger, and Mollusk test
  runner.

## Proposed Route

The new target id is **`solana-sbpf-asm`** (profile in `Target/Registry.lean`).

### Build pipeline

1. **IR extraction:** Lean contract source → LCNF → `ProofForge.IR.Contract.Module`.
2. **Capability check:** Validate all IR effects against the `solana-sbpf-asm`
   profile; reject unsupported capabilities.
3. **State layout:** Compute per‑account field offsets from the instruction
   manifest and IR state declarations.
4. **Codegen** (`ProofForge.Backend.Solana.SbpfAsm`):
   - Emit entrypoint adapter: parse serialized accounts, dispatch on instruction discriminant.
   - For each entrypoint: lower IR statements/expressions to sBPF instructions.
   - Emit `.equ` constants for account‑data field offsets.
5. **Assembly + packaging:** `sbpf build` turns the `.s` into `deploy/<name>.so`.
6. **Artifact metadata:** `proof-forge-artifact.json`.

### Scope of codegen (Phase 1 = Counter)

- Scalar u64 storage via account‑data offsets.
- Instruction dispatch (first‑byte discriminant).
- Account validation (signer, writable, owner checks).
- Expressions: literals, locals, add/sub/subs, comparisons.
- Statements: letBind, assign, ifElse, return, assert.
- Capability set: `storage.scalar`, `account.explicit`, `control.conditional`.

Out of scope for Phase 1: CPI, PDA, maps, struct types, events, bounded loops,
Borsh serialization, SPL Token helpers. These are deferred to Phase 2–3.

## Relationship to the existing sbpf-linker route

The Zig/sbpf-linker route (`solana-sbpf-linker`) is **superseded** by this route
(D-026). It remains in the registry as historical reference but is no longer the
preferred codegen target. The table below captures why the assembly route was chosen:

| Dimension | sbpf-linker (Zig, superseded) | sbpf-asm (canonical) |
|---|---|---|
| Runtime | Lean Zig runtime linked into binary | No Lean runtime at all |
| Code control | Limited — Lean compiler controls codegen | Full — ProofForge emits every instruction |
| Toolchain | Zig + sbpf-linker | `cargo install sbpf` (one tool) |
| Developer ergonomics | Generated Zig is human‑readable but not easily debugged | sbpf debugger/disassembler give per‑instruction visibility |
| Primary risk | Stack / section rejection by Solana loader | Scope of codegen (a full backend in Lean) |

## IR extensions

CPI and PDA derivation are Solana‑specific and **do not** enter the portable IR
(D-027). The portable `ProofForge.IR.Contract.Effect` remains chain‑neutral.

Solana‑specific effects live in `ProofForge.Backend.Solana.Effects`:

- `cpiInvoke (programId : ...) (discriminant : ...) (accounts : ...) (data : ...)`
- `cpiInvokeSigned (programId : ...) (discriminant : ...) (accounts : ...) (data : ...) (signerSeeds : ...)`
- `pdaDerive (seeds : ...) (programId : ...)` → `(address, bump)`

These are gated by the existing `crosscall.cpi` and `storage.pda` capability
IDs already registered in `Target/Capability.lean`. No new portable IR
constructors are needed.

## CLI

```text
proof-forge --emit-sbpf-asm [-o output.s] input.lean  # emit .s only
proof-forge --solana-elf [--root DIR] [--solana-sbpf-arch v0|v3] input.lean
```

`--solana-elf` invokes `sbpf build` as a subprocess (like `--evm-bytecode`
invokes `solc`). `--solana-sbpf-arch` is forwarded to `sbpf build --arch` and
recorded in artifact metadata.

## Test gates

| Gate | Criterion |
|---|---|
| V-GATE-SOLANA-01 | `--emit-sbpf-asm` produces valid `.s` → `sbpf build` succeeds |
| V-GATE-SOLANA-02 | `sbpf disassemble` round‑trips the ELF |
| V-GATE-SOLANA-03 | Counter scenario passes `sbpf test` (Mollusk) |
| V-GATE-SOLANA-04 | Counter scenario passes Surfpool/Rust live deploy/invoke smoke (optional) |
| V-GATE-SOLANA-05 | Capability checker rejects unsupported effects with target‑id diagnostic |
| V-GATE-SOLANA-06 | `proof-forge-artifact.json` contains `target: "solana-sbpf-asm"` |

## Decisions

- **Adopt `solana-sbpf-asm` as the canonical Solana route** (D-026).
  The direct-assembly route supersedes `solana-sbpf-linker`. The Zig route
  remains in the registry as historical reference only — codegen targets the
  assembly route.
- **CPI and PDA effects stay in a Solana‑specific layer, not the portable IR**
  (D-027). The portable IR (`ProofForge.IR.Contract.Effect`) remains
  chain‑neutral. `cpiInvoke`, `cpiInvokeSigned`, and `pdaDerive` live in
  `ProofForge.Backend.Solana.Effects`, gated by the existing `crosscall.cpi`
  and `storage.pda` capabilities. This follows the capability‑gating pattern
  already in use: new Effect constructors only enter the portable IR when
  ≥2 target families share the same semantic shape.

## References

- [Solana sBPF Assembly Backend design doc](../targets/solana-sbpf-asm.md)
- [blueshift-gg/sbpf](https://github.com/blueshift-gg/sbpf)
- [RFC 0002 (target families)](./0002-target-implementation-design.md)
- [Existing solana-sbf.md target note](../targets/solana-sbf.md)
