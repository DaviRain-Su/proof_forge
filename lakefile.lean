import Lake
open Lake DSL

package «proof-forge» where
  version := v!"0.1.0"

require evm_semantics from git
  "https://github.com/powdr-labs/evm-semantics.git"@"ae13dbc506158f9d0c7e05634636b17e2bccf850"

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
    `ProofForge.Backend.Solana.CounterSbpfExec,
    `ProofForge.Backend.Solana.CounterSbpfRefinement,
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
    `EvmRefinement.PowdrAdapter,
    `EvmRefinement.PowdrExec,
    `EvmRefinement.PowdrExecSmoke,
    `EvmRefinement.CounterRefinement
  ]

@[default_target]
lean_exe «proof-forge» where
  root := `ProofForge.Cli
  supportInterpreter := true
