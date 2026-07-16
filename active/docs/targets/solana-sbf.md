# Solana sBPF Target (Superseded)

> **Superseded by [`solana-sbpf-asm`](solana-sbpf-asm.md)** (D-026).
> The direct sBPF assembly route (`solana-sbpf-asm`) is the canonical Solana
> backend. This Zig/sbpf-linker route remains as historical reference only.

Canonical target id: **`solana-sbpf-linker`** (superseded). This filename
(`solana-sbf.md`) is a short alias for navigation only.

Solana is the most important non-EVM target for proving that ProofForge's
portable core is not secretly EVM-shaped. The state model is explicit accounts,
not implicit contract storage.

## Contract Model

Solana programs expose one entrypoint:

```zig
export fn entrypoint(input: [*]u8) callconv(.c) u64
```

The runtime input contains:

- account count
- serialized accounts
- instruction data
- program id

The program must parse accounts and instruction data, validate signer and
writable flags, mutate account data, and optionally perform CPI.

## Preferred Pipeline: sbpf-linker

The `zignocchio` project demonstrates a no-fork route:

```text
generated Zig
  -> zig build-lib -target bpfel-freestanding -femit-llvm-bc=entrypoint.bc
  -> sbpf-linker --cpu v2 --export entrypoint -o program.so entrypoint.bc
  -> Solana loader-compatible ELF
```

Why this should be the first ProofForge route:

- It uses stock Zig instead of a Solana-specific Zig fork.
- It fits a platform product better because dependencies are explicit tools.
- It resembles the EVM/Solang pattern of producing an intermediate artifact and
  calling a target packager.

Risks:

- Lean Zig runtime may not link under `bpfel-freestanding`.
- 4KB stack pressure may make normal Lean runtime paths too expensive.
- `.rodata`, `.bss`, `.data`, panic, allocator, and libc assumptions may break
  the Solana loader.
- Artifact size and compute units may force a restricted runtime subset.

## Reference Pipeline: solana-zig Fork

The `solana-sdk-mono` repository demonstrates another path:

```text
generated Zig
  -> solana-zig .sbf/.solana target
  -> dynamic `.so`
  -> Mollusk tests
```

This route has a richer SDK reference for:

- account parsing
- typed accounts
- CPI
- PDA helpers
- events
- Mollusk tests

It should remain a reference and fallback while `sbpf-linker` is validated.

## Instruction Manifest

Solana needs explicit account schemas. A sidecar manifest should describe
instruction dispatch and accounts.

Example:

```toml
[[instruction]]
name = "initialize"
tag = 0
handler = "l_Counter_initialize"
accounts = [
  { name = "authority", index = 0, signer = true, writable = true },
  { name = "counter", index = 1, signer = false, writable = true, owner = "program" },
  { name = "system_program", index = 2, signer = false, writable = false }
]

[[instruction]]
name = "increment"
tag = 1
handler = "l_Counter_increment"
accounts = [
  { name = "authority", index = 0, signer = true, writable = false },
  { name = "counter", index = 1, signer = false, writable = true, owner = "program" }
]
```

This manifest should be target metadata, not embedded into generic Lean source.

## Lean SDK Sketch

First version:

```lean
namespace Solana

structure Pubkey where
  bytes : ByteArray

structure AccountRef where
  index : UInt8

opaque instructionData : IO ByteArray
opaque programId : IO Pubkey
opaque accountKey : AccountRef -> IO Pubkey
opaque accountOwner : AccountRef -> IO Pubkey
opaque isSigner : AccountRef -> IO Bool
opaque isWritable : AccountRef -> IO Bool
opaque dataLen : AccountRef -> IO UInt64
opaque readData : AccountRef -> IO ByteArray
opaque writeData : AccountRef -> ByteArray -> IO Unit
opaque lamports : AccountRef -> IO UInt64
opaque log : String -> IO Unit
opaque setReturnData : ByteArray -> IO Unit

end Solana
```

Later:

- PDA derivation.
- CPI wrappers.
- SPL Token helpers.
- typed account codecs.
- event encoding.

## Generated Root Adapter

The root adapter owns Solana ABI mechanics:

```zig
export fn entrypoint(input: [*]u8) callconv(.c) u64 {
    var ctx = solana.deserialize(input);
    lean_rt.lean_initialize_runtime_module();
    return dispatch(&ctx);
}
```

Dispatch choices:

- instruction first byte as tag
- generated `switch`
- generated account validation before calling Lean handler
- Lean handler receives either account refs or an implicit context

Initial recommendation: generated validation in Zig, Lean handler receives
account refs and instruction bytes. This keeps Solana's account model visible.

## Runtime Validation Plan

Spike 1: raw Zig entrypoint

- Generated `entrypoint` logs and returns success.
- Build with stock Zig + `sbpf-linker`.
- Run in `solana-test-validator` or Mollusk.

Spike 2: Lean runtime link

- Link minimal generated Lean Zig with runtime.
- No accounts, just return success or log.
- Record linker errors and unsupported sections.

Spike 3: account state

- Counter account with explicit account manifest.
- `initialize`, `increment`, `get`.
- No CPI.

Spike 4: CPI

- System Program transfer or account creation.
- PDA signing.

Spike 5: SPL Token

- Token transfer CPI.
- This should wait until syscall and account abstractions stabilize.

## Test Strategy

Use both styles:

- Mollusk for deterministic fast program tests.
- `solana-test-validator --bpf-program` for deployment-shaped smoke.

CI should make Solana tests optional until the toolchain is installed.

## Open Questions

- Full Lean runtime or restricted Solana runtime subset?
- Can generated Lean Zig avoid large stack frames?
- Should account manifests be `.toml`, `.json`, or Lean declarations?
- Should the first Solana POC use zignocchio SDK code directly or copy only the
  minimal syscall/account pieces?
- Can Foundry-like smoke ergonomics be built around Mollusk for developers?
