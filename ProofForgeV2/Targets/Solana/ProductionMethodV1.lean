import ProofForgeV2.Targets.Solana.ProductionPreparationV1

/-!
# Contract-independent Solana production method certificate

This module selects one Semantic callable and one HandlerIR row from an
existing production preparation certificate. The selected rows retain exact
lookup equations, and Reference execution is tied to the selected callable's
identity through the unique Reference machine.

The certificate is parameterized by method identity and invocation data. It
contains no contract registry, StateCell field, copied IR, provider trace, or
second business semantics.
-/

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

/-- Exact production lookup witnesses for one Semantic callable and its target
    HandlerIR row. Semantic and Handler names are separate because an
    initializer is anonymous in SemanticProgramV1 but canonically named
    `initialize` in Solana HandlerIR. -/
structure CertifiedSolanaProductionMethodV1
    {elaborated canonicalBytes expectedArtifactSha256}
    (prepared : CertifiedSolanaProductionPreparationV1
      elaborated canonicalBytes expectedArtifactSha256)
    (semanticKind : CallableKindV1)
    (semanticName : Option String)
    (handlerName : String) where
  callable : CallableV1
  callableLookup :
    prepared.data.callables.find? (fun candidate =>
      candidate.kind == semanticKind && candidate.name == semanticName) =
        some callable
  handler : HandlerIR
  handlerLookup :
    prepared.productionIR.handlers.find? (·.name == handlerName) = some handler

/-- Select one method only from values retained by the real production
    preparation. Missing or mismatched Semantic/Handler identities fail closed. -/
def resolveCertifiedSolanaProductionMethodV1
    {elaborated canonicalBytes expectedArtifactSha256}
    (prepared : CertifiedSolanaProductionPreparationV1
      elaborated canonicalBytes expectedArtifactSha256)
    (semanticKind : CallableKindV1)
    (semanticName : Option String)
    (handlerName : String) :
    Except String (CertifiedSolanaProductionMethodV1 prepared semanticKind
      semanticName handlerName) :=
  match hcallable : prepared.data.callables.find? (fun candidate =>
      candidate.kind == semanticKind && candidate.name == semanticName) with
  | none =>
      .error s!"production Semantic program has no requested callable {repr semanticName}"
  | some callable =>
      match hhandler :
          prepared.productionIR.handlers.find? (·.name == handlerName) with
      | none => .error s!"production Solana IR has no '{handlerName}' handler"
      | some handler => .ok {
          callable
          callableLookup := hcallable
          handler
          handlerLookup := hhandler
        }

/-- Replay retained callable and HandlerIR lookup equations through the real
    method resolver. Both production rows must still exist with the requested
    identities; proof irrelevance is used only after those rows agree. -/
theorem resolveCertifiedSolanaProductionMethodV1_eq_ok
    {prepared : CertifiedSolanaProductionPreparationV1
      elaborated canonicalBytes expectedArtifactSha256}
    (method : CertifiedSolanaProductionMethodV1 prepared semanticKind
      semanticName handlerName) :
    resolveCertifiedSolanaProductionMethodV1 prepared semanticKind semanticName
      handlerName = .ok method := by
  unfold resolveCertifiedSolanaProductionMethodV1
  split
  next hcallable =>
    rw [method.callableLookup] at hcallable
    contradiction
  next callable hcallable =>
    have hcallableEq : callable = method.callable := by
      exact Option.some.inj (hcallable.symm.trans method.callableLookup)
    subst callable
    split
    next hhandler =>
      rw [method.handlerLookup] at hhandler
      contradiction
    next handler hhandler =>
      have hhandlerEq : handler = method.handler := by
        exact Option.some.inj (hhandler.symm.trans method.handlerLookup)
      subst handler
      congr

/-- The sole Reference-machine result for one certified production method and
    invocation. The carrier records execution; it does not define or replay a
    transition. -/
structure CertifiedSolanaProductionMethodReferenceV1
    {elaborated canonicalBytes expectedArtifactSha256}
    {prepared : CertifiedSolanaProductionPreparationV1
      elaborated canonicalBytes expectedArtifactSha256}
    {semanticKind semanticName handlerName}
    (method : CertifiedSolanaProductionMethodV1 prepared semanticKind
      semanticName handlerName)
    (pre : LogicalStateV1)
    (args : Array ReferenceValueV1)
    (context : Array ContextInputV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1) where
  outcome : OutcomeV1
  execution :
    stepReferenceSliceV1 prepared.admitted pre {
      callableId := method.callable.id
      args
      context
    } responses vault = outcome

/-- Retain the exact result of the unique Reference machine for a certified
    method invocation. -/
def executeCertifiedSolanaProductionMethodReferenceV1
    {elaborated canonicalBytes expectedArtifactSha256}
    {prepared : CertifiedSolanaProductionPreparationV1
      elaborated canonicalBytes expectedArtifactSha256}
    {semanticKind semanticName handlerName}
    (method : CertifiedSolanaProductionMethodV1 prepared semanticKind
      semanticName handlerName)
    (pre : LogicalStateV1)
    (args : Array ReferenceValueV1)
    (context : Array ContextInputV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1) :
    CertifiedSolanaProductionMethodReferenceV1 method pre args context
      responses vault := {
  outcome := stepReferenceSliceV1 prepared.admitted pre {
    callableId := method.callable.id
    args
    context
  } responses vault
  execution := rfl
}

/-- Replay a retained Reference execution certificate through the sole
    Reference-machine wrapper. The carrier's execution equation fixes the
    outcome; no transition is rerun by this theorem. -/
theorem executeCertifiedSolanaProductionMethodReferenceV1_eq
    {prepared : CertifiedSolanaProductionPreparationV1
      elaborated canonicalBytes expectedArtifactSha256}
    {method : CertifiedSolanaProductionMethodV1 prepared semanticKind
      semanticName handlerName}
    (execution : CertifiedSolanaProductionMethodReferenceV1 method pre args
      context responses vault) :
    executeCertifiedSolanaProductionMethodReferenceV1 method pre args context
      responses vault = execution := by
  rcases execution with ⟨outcome, execution⟩
  subst outcome
  rfl

end ProofForgeV2.Targets.Solana
