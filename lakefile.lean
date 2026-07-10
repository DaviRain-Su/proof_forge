import Lake
open Lake DSL

package «proof-forge» where
  version := v!"0.1.0-beta.1"

require evm_semantics from git
  "https://github.com/powdr-labs/evm-semantics.git"@"ae13dbc506158f9d0c7e05634636b17e2bccf850"

/-- Opt-in Solana formal lane dependency (used by `SolanaRefinement` only).
Mirrors the powdr pin: always declared so Lake can resolve the target, while
default `ProofForge` roots do not import it. -/
require solanalib from git
  "https://github.com/solana-foundation/leanprover-solanalib.git" @ "6c115ef1ef6a0cde8dbd6fd875b7dc87d60939ec"

lean_lib ProofForge where
  roots := #[
    `Examples,
    `ProofForge,
    `ProofForge.Psy,
    `ProofForge.Target,
    `ProofForge.IR,
    `ProofForge.Contract,
    `ProofForge.Backend,
    `ProofForge.Backend.Solana.SbpfAsm,
    `ProofForge.Backend.Solana.SbpfExec,
    `ProofForge.Backend.Solana.SbpfExecSmoke,
    `ProofForge.Backend.Solana.ValueVaultSbpfExec,
    `ProofForge.Backend.Solana.CounterSbpfExec,
    `ProofForge.Backend.Solana.CounterSbpfRefinement,
    `ProofForge.Backend.Solana.BpfEncode,
    `ProofForge.Backend.Solana.LabeledSbpf,
    `ProofForge.Compiler.Yul.AST,
    `ProofForge.Compiler.Yul.Printer,
    `ProofForge.Compiler.Wasm.AST,
    `ProofForge.Compiler.Wasm.Printer,
    `ProofForge.Compiler.TS.AST,
    `ProofForge.Compiler.TS.Printer,
    `ProofForge.Compiler.TS.Emit,
    `ProofForge.Compiler.Psy.AST,
    `ProofForge.Compiler.Psy.Printer
  ]

lean_lib EvmRefinement where
  roots := #[
    `EvmRefinement.CounterRuntime,
    `EvmRefinement.HexWitness,
    `EvmRefinement.PowdrAdapter,
    `EvmRefinement.PowdrExec,
    `EvmRefinement.PowdrExecSmoke,
    `EvmRefinement.CounterRefinement
  ]

/-- Opt-in Solana formal lane: solanalib sBPF ISA + CompileCorrect pipeline.
Imports solanalib the same way `EvmRefinement` imports powdr. Default
`ProofForge` / CLI roots do not import these modules. -/
lean_lib SolanaRefinement where
  roots := #[
    `SolanaRefinement.SolanalibAdapter,
    `SolanaRefinement.LabeledToSolanalib,
    `SolanaRefinement.HostBridge,
    `SolanaRefinement.FullProgramHost,
    `SolanaRefinement.CounterHostRefinement,
    `SolanaRefinement.CoreTailHostComposition,
    `SolanaRefinement.ValueVaultHostRefinement,
    `SolanaRefinement.FullHostTargetSemantics,
    `SolanaRefinement.CompileCorrect,
    `SolanaRefinement.CompileCorrectSmoke
  ]

@[default_target]
lean_exe «proof-forge» where
  root := `ProofForge.Cli
  supportInterpreter := true
