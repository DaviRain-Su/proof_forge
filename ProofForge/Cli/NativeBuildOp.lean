namespace ProofForge.Cli

inductive NativeBuildOp
  | nftEvmBytecode
  | nftSolanaSbpf
  | nftNearEmitWat
  | stylusRustSdk
  deriving BEq, Repr

end ProofForge.Cli
