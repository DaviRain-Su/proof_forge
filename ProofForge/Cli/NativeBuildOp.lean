namespace ProofForge.Cli

inductive NativeBuildOp
  | nftEvmBytecode
  | nftSolanaSbpf
  | nftNearEmitWat
  | stylusContractSource
  deriving BEq, Repr

end ProofForge.Cli
