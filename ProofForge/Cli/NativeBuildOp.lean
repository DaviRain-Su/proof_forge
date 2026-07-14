namespace ProofForge.Cli

inductive NativeBuildOp
  | evmCanonicalYul
  | evmCanonicalBytecode
  | nftEvmBytecode
  | nftSolanaSbpf
  | nftNearEmitWat
  | stylusContractSource
  deriving BEq, Repr

end ProofForge.Cli
