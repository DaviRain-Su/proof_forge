import ProofForgeV2.Targets.Solana.SbpfExecutionV1

/-!
# Contract-independent Solana production provider execution certificate

This module records the common boundary shared by method-specific provider
certificates: the real Loader V3 encoder and the real identity-bound provider
execution equation. Method-specific modules remain responsible for proving
their artifact manifest, concrete input reads, exact trace, and postcondition.

The carrier is parameterized by fuel, halt status, account window, input, and
machine. It defines no provider evaluator, contract registry, or business
transition.
-/

namespace ProofForgeV2.Targets.Solana

open SbpfSemantics

/-- Exact production encoder and provider equations shared by all certified
    single-account method traces. -/
structure CertifiedSolanaProductionProviderExecutionV1
    (bound : BoundResolvedSbpfArtifactV1)
    (invocation : LoaderV3SingleAccountInvocationV1)
    (fuel : Nat)
    (status : Word)
    (accountDataOffset accountDataLength : Nat)
    (input : Array UInt8)
    (machine : Machine) where
  encodedInput :
    encodeLoaderV3SingleAccountInputV1 bound invocation = .ok input
  providerExecution :
    executeLoaderV3SingleAccountV1 bound invocation fuel = .ok {
      artifactSha256 :=
        (BoundResolvedSbpfArtifactV1.resolvedOf bound).sourceSha256
      provider := observe machine (.halted status)
      finalAccountData := machine.mem.readBytes
        (inputStart + BitVec.ofNat 64 accountDataOffset) accountDataLength
    }

end ProofForgeV2.Targets.Solana
