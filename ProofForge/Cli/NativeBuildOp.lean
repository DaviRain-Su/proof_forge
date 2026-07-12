namespace ProofForge.Cli

inductive NativeBuildOp
  | nftEvmBytecode
  | nftSolanaSbpf
  | nftNearEmitWat
  deriving BEq, Repr

end ProofForge.Cli
