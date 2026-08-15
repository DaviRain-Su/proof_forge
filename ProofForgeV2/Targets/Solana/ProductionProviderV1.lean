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

/-- Contract-independent result of running the real production encoder and
    pinned provider. The account window is derived from the identity-bound
    artifact rather than supplied by a contract module. Exact equations for
    every fail-closed branch are retained so the result can be replayed and
    projected to the common provider certificate below. -/
structure ResolvedCertifiedSolanaProductionProviderExecutionV1
    (bound : BoundResolvedSbpfArtifactV1)
    (invocation : LoaderV3SingleAccountInvocationV1)
    (fuel : Nat)
    (status : Word) where
  accountDataOffset : Nat
  accountDataLength : Nat
  input : Array UInt8
  machine : Machine
  encodedInput :
    encodeLoaderV3SingleAccountInputV1 bound invocation = .ok input
  accountWindow : deriveSingleAccountExecutionWindowV1 bound =
    some (accountDataOffset, accountDataLength)
  fuelPositive : 0 < fuel
  fuelBounded : fuel ≤ maxSbpfExecutionFuelV1
  inputBounded : input.size ≤ maxSbpfInputImageBytesV1
  providerRun :
    runFuel asmDefaultHost
      (BoundResolvedSbpfArtifactV1.resolvedOf bound).program fuel
      (Machine.entry input) = (machine, Outcome.halted status)

namespace ResolvedCertifiedSolanaProductionProviderExecutionV1

/-- Project a resolved execution to the shared production certificate. This
    composes equations for the existing encoder, execution-window resolver,
    resource gates, and `runFuel`; it does not replay or copy a provider trace. -/
def certificate
    (execution : ResolvedCertifiedSolanaProductionProviderExecutionV1
      bound invocation fuel status) :
    CertifiedSolanaProductionProviderExecutionV1 bound invocation fuel status
      execution.accountDataOffset execution.accountDataLength execution.input
      execution.machine := {
  encodedInput := execution.encodedInput
  providerExecution := by
    apply executeLoaderV3SingleAccountV1_eq_ok bound invocation fuel
      execution.input _ execution.encodedInput
    exact runBoundSbpfArtifactV1_eq_ok_of_runFuel bound execution.input fuel
      execution.accountDataOffset execution.accountDataLength execution.machine
      (.halted status) execution.accountWindow execution.fuelPositive
      execution.fuelBounded execution.inputBounded execution.providerRun
}

/-- Provider observation produced by this exact resolved execution. -/
def observation
    (execution : ResolvedCertifiedSolanaProductionProviderExecutionV1
      bound invocation fuel status) : SbpfExecutionObservationV1 := {
  artifactSha256 :=
    (BoundResolvedSbpfArtifactV1.resolvedOf bound).sourceSha256
  provider := observe execution.machine (.halted status)
  finalAccountData := execution.machine.mem.readBytes
    (inputStart + BitVec.ofNat 64 execution.accountDataOffset)
    execution.accountDataLength
}

/-- The observation projection is exactly the result of the existing
    identity-bound production execution API. -/
theorem providerExecution
    (execution : ResolvedCertifiedSolanaProductionProviderExecutionV1
      bound invocation fuel status) :
    executeLoaderV3SingleAccountV1 bound invocation fuel =
      .ok execution.observation :=
  execution.certificate.providerExecution

end ResolvedCertifiedSolanaProductionProviderExecutionV1

/-- Resolve a production provider certificate without contract-specific
    traces. Missing layouts, invalid invocations, out-of-range resources,
    stuck/out-of-fuel executions, and unexpected halt statuses all fail closed.
    The only evaluator called here is the pinned provider's real `runFuel`. -/
def resolveCertifiedSolanaProductionProviderExecutionV1
    (bound : BoundResolvedSbpfArtifactV1)
    (invocation : LoaderV3SingleAccountInvocationV1)
    (fuel : Nat)
    (status : Word) :
    Except String (ResolvedCertifiedSolanaProductionProviderExecutionV1
      bound invocation fuel status) :=
  match hencode : encodeLoaderV3SingleAccountInputV1 bound invocation with
  | .error error => .error error.render
  | .ok input =>
      match hwindow : deriveSingleAccountExecutionWindowV1 bound with
      | none =>
          .error
            "production provider artifact has no single-account execution window"
      | some (accountDataOffset, accountDataLength) =>
          if hfuelPositive : 0 < fuel then
            if hfuelBounded : fuel ≤ maxSbpfExecutionFuelV1 then
              if hinputBounded : input.size ≤ maxSbpfInputImageBytesV1 then
                match hrun : runFuel asmDefaultHost
                    (BoundResolvedSbpfArtifactV1.resolvedOf bound).program fuel
                    (Machine.entry input) with
                | (machine, .halted actualStatus) =>
                    if hstatus : actualStatus = status then
                      .ok {
                        accountDataOffset
                        accountDataLength
                        input
                        machine
                        encodedInput := hencode
                        accountWindow := hwindow
                        fuelPositive := hfuelPositive
                        fuelBounded := hfuelBounded
                        inputBounded := hinputBounded
                        providerRun := by simpa [hstatus] using hrun
                      }
                    else
                      .error
                        "production provider halted with an unexpected status"
                | (_, .stuck) => .error "production provider became stuck"
                | (_, .outOfFuel) =>
                    .error "production provider exhausted fuel"
              else
                .error "production provider input exceeds its resource bound"
            else .error "production provider fuel exceeds its resource bound"
          else .error "production provider fuel must be positive"

/-- Replay all equations retained by a resolved execution through the same
    fail-closed resolver. This is a completeness theorem for the resolver, not
    a new provider evaluation or a Reference-to-provider refinement theorem. -/
theorem resolveCertifiedSolanaProductionProviderExecutionV1_eq_ok
    (execution : ResolvedCertifiedSolanaProductionProviderExecutionV1
      bound invocation fuel status) :
    resolveCertifiedSolanaProductionProviderExecutionV1 bound invocation fuel
      status = .ok execution := by
  rcases execution with ⟨accountDataOffset, accountDataLength, input, machine,
    hencode, hwindow, hfuelPositive, hfuelBounded, hinputBounded, hrun⟩
  unfold resolveCertifiedSolanaProductionProviderExecutionV1
  split
  next h => rw [hencode] at h; contradiction
  next resolvedInput hresolvedInput =>
    have hinput : resolvedInput = input :=
      Except.ok.inj (hresolvedInput.symm.trans hencode)
    subst resolvedInput
    split
    next h => rw [hwindow] at h; contradiction
    next resolvedOffset resolvedLength hresolvedWindow =>
      have hwindowEq := Option.some.inj (hresolvedWindow.symm.trans hwindow)
      simp only [Prod.mk.injEq] at hwindowEq
      rcases hwindowEq with ⟨hoffset, hlength⟩
      subst resolvedOffset
      subst resolvedLength
      simp only [hfuelPositive, hfuelBounded, hinputBounded, ↓reduceDIte]
      split
      next finalMachine actualStatus hproviderRun =>
        have houtcome : (finalMachine, Outcome.halted actualStatus) =
            (machine, Outcome.halted status) := hproviderRun.symm.trans hrun
        simp only [Prod.mk.injEq, Outcome.halted.injEq] at houtcome
        rcases houtcome with ⟨hmachine, hstatus⟩
        subst finalMachine
        subst actualStatus
        split
        next => congr
        next h => contradiction
      next finalMachine hproviderRun =>
        have houtcome : Outcome.stuck = Outcome.halted status :=
          congrArg Prod.snd (hproviderRun.symm.trans hrun)
        contradiction
      next finalMachine hproviderRun =>
        have houtcome : Outcome.outOfFuel = Outcome.halted status :=
          congrArg Prod.snd (hproviderRun.symm.trans hrun)
        contradiction

end ProofForgeV2.Targets.Solana
