namespace ProofForge.Cli

inductive NativeBuildOp
  | evmCanonicalYul
  | nftEvmBytecode
  | nftSolanaSbpf
  | nftNearEmitWat
  | stylusContractSource
  deriving BEq, Repr

end ProofForge.Cli
