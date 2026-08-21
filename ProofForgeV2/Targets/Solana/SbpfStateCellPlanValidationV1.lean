import ProofForgeV2.Targets.Solana.SbpfStateCellPlanCertificateV1
import ProofForgeV2.Targets.Solana.ValidatePlanV1

/-!
# StateCell Solana production Plan validation certificate

Kernel replay of the sole production `validatePlan` function over the Plan
retained by `CertifiedPlanLoweringV1`. `StateCell` is only a concrete business
carrier used to exercise the generic validator; validation never dispatches on
the contract or callable names.
-/

namespace ProofForgeV2.Targets.Solana

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellStateAccountValidationV1 :
    validateStateAccount StateCellPlanCertificateV1.expectedTargetAccount =
      .ok () := by
  have hmarker := stateCellPlanLayoutMarkerV1
  simp only [stateCellPlanStateFieldV1] at hmarker
  have howner :
      (OwnerPolicy.currentProgram == OwnerPolicy.currentProgram) = true := by
    decide
  have hpayload :
      (PayloadInitializationPolicy.zeroAllFields ==
        PayloadInitializationPolicy.zeroAllFields) = true := by
    decide
  have hendian : (Endianness.little == Endianness.little) = true := by
    decide
  have hname : "count".utf8ByteSize ≤ 240 := by decide
  unfold validateStateAccount
  simp [StateCellPlanCertificateV1.expectedTargetAccount,
    StateCellPlanCertificateV1.expectedStateAccount, stateCellPlanStateFieldV1,
    hmarker, stateHeaderBytes, maxStateFields, slotPitchOfByteWidth,
    howner, hpayload, hendian, hname,
    ProofForgeV2.Targets.EnvelopeV1.hasDuplicates,
    isIdentifier, maxIdentifierBytes,
    ProofForgeV2.Targets.EnvelopeV1.isAsciiIdentifier,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellInitializerParamsValidationV1 :
    validateParams "handler 'initialize'"
      #[StateCellPlanCertificateV1.expectedParam] = .ok () := by
  have hendian : (Endianness.little == Endianness.little) = true := by
    decide
  have hname : "initial".utf8ByteSize ≤ 240 := by decide
  unfold validateParams
  simp [StateCellPlanCertificateV1.expectedParam, maxParams,
    discriminatorBytes, slotPitchOfByteWidth,
    ProofForgeV2.Targets.EnvelopeV1.hasDuplicates,
    isIdentifier, maxIdentifierBytes,
    ProofForgeV2.Targets.EnvelopeV1.isAsciiIdentifier,
    hendian, hname, Pure.pure, Except.pure, Bind.bind, Except.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellIncrementParamsValidationV1 :
    validateParams "handler 'increment'"
      #[StateCellPlanCertificateV1.incrementParam] = .ok () := by
  have hendian : (Endianness.little == Endianness.little) = true := by
    decide
  have hname : "delta".utf8ByteSize ≤ 240 := by decide
  unfold validateParams
  simp [StateCellPlanCertificateV1.incrementParam, maxParams,
    discriminatorBytes, slotPitchOfByteWidth,
    ProofForgeV2.Targets.EnvelopeV1.hasDuplicates,
    isIdentifier, maxIdentifierBytes,
    ProofForgeV2.Targets.EnvelopeV1.isAsciiIdentifier,
    hendian, hname, Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem stateCellGetParamsValidationV1 :
    validateParams "handler 'get'" #[] = .ok () := by
  unfold validateParams
  simp [ProofForgeV2.Targets.EnvelopeV1.hasDuplicates,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellInitializerBodyValidationV1 :
    checkHandlerStatementsV1
      StateCellPlanCertificateV1.expectedTargetAccount true false true
      0 #[] 0 #[] #[] #[StateCellPlanCertificateV1.expectedParam]
      StateCellPlanCertificateV1.expectedBody 11 = .ok (13, true) := by
  unfold checkHandlerStatementsV1
  simp [StateCellPlanCertificateV1.expectedTargetAccount,
    StateCellPlanCertificateV1.expectedStateAccount,
    StateCellPlanCertificateV1.expectedBody,
    StateCellPlanCertificateV1.expectedStore,
    StateCellPlanCertificateV1.expectedParam,
    stateCellPlanStateFieldV1, addPlanExprNodes, planExprNodes?,
    maxPlanNodes, maxExprDepth,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellIncrementBodyValidationV1 :
    checkHandlerStatementsV1
      StateCellPlanCertificateV1.expectedTargetAccount false false false
      0 #[] 0 #[] #[] #[StateCellPlanCertificateV1.incrementParam]
      StateCellPlanCertificateV1.incrementBody 13 = .ok (17, true) := by
  unfold checkHandlerStatementsV1
  simp [StateCellPlanCertificateV1.expectedTargetAccount,
    StateCellPlanCertificateV1.expectedStateAccount,
    StateCellPlanCertificateV1.incrementBody,
    StateCellPlanCertificateV1.incrementStore,
    StateCellPlanCertificateV1.incrementParam,
    StateCellPlanCertificateV1.incrementValue2,
    StateCellPlanCertificateV1.incrementValue3,
    stateCellPlanStateFieldV1, addPlanExprNodes, planExprNodes?,
    maxPlanNodes, maxExprDepth,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellGetBodyValidationV1 :
    checkHandlerStatementsV1
      StateCellPlanCertificateV1.expectedTargetAccount false true false
      0 #[] 0 #[] #[] #[] StateCellPlanCertificateV1.getBody 17 =
        .ok (18, true) := by
  unfold checkHandlerStatementsV1
  simp [StateCellPlanCertificateV1.expectedTargetAccount,
    StateCellPlanCertificateV1.expectedStateAccount,
    StateCellPlanCertificateV1.getBody,
    StateCellPlanCertificateV1.getValue,
    stateCellPlanStateFieldV1, addPlanExprNodes, planExprNodes?,
    maxPlanNodes, maxExprDepth,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem stateCellInitializerDiscriminatorInputV1 :
    (discriminatorDomain ++ signature "initialize"
      #[StateCellPlanCertificateV1.expectedParam]).toUTF8 =
        "proof-forge-solana-v1:initialize(u64)".toUTF8 := by
  unfold discriminatorDomain signature abiParamTypeString
    StateCellPlanCertificateV1.expectedParam
  decide

private abbrev stateCellInitializerDiscriminatorFinalStateV1 :
    ProofForgeV2.Crypto.Sha256State := #[
  0x5e494767, 0xa7582864, 0x360517ed, 0x94a67890,
  0x6051f81a, 0x8a5ca9ed, 0xeb814923, 0x4caac945]

set_option maxHeartbeats 5000000 in
set_option maxRecDepth 100000 in
private def stateCellInitializerDiscriminatorCertificateV1 :
    ProofForgeV2.Crypto.Sha256BlockCertificate
      "proof-forge-solana-v1:initialize(u64)".toUTF8
      "5e494767a7582864360517ed94a678906051f81a8a5ca9edeb8149234caac945" := {
  finalState := stateCellInitializerDiscriminatorFinalStateV1
  trace := .step 0 0 ProofForgeV2.Crypto.sha256InitialState
    stateCellInitializerDiscriminatorFinalStateV1
    stateCellInitializerDiscriminatorFinalStateV1
    (by decide) (.done 64 stateCellInitializerDiscriminatorFinalStateV1)
  hex_eq := by decide
}

theorem stateCellInitializerDiscriminatorValueV1 :
    instructionDiscriminator "initialize"
      #[StateCellPlanCertificateV1.expectedParam] = "5e494767a7582864" := by
  unfold instructionDiscriminator
  rw [stateCellInitializerDiscriminatorInputV1,
    stateCellInitializerDiscriminatorCertificateV1.sound]
  decide

theorem stateCellIncrementDiscriminatorInputV1 :
    (discriminatorDomain ++ signature "increment"
      #[StateCellPlanCertificateV1.incrementParam]).toUTF8 =
        "proof-forge-solana-v1:increment(u64)".toUTF8 := by
  unfold discriminatorDomain signature abiParamTypeString
    StateCellPlanCertificateV1.incrementParam
  decide

private abbrev stateCellIncrementDiscriminatorFinalStateV1 :
    ProofForgeV2.Crypto.Sha256State := #[
  0x9dc79703, 0xd1db3e22, 0xeb256f4a, 0x5c72cad8,
  0xa307ff4c, 0xf4e0dc31, 0x1aa1de5c, 0xbf0689e2]

set_option maxHeartbeats 5000000 in
set_option maxRecDepth 100000 in
private def stateCellIncrementDiscriminatorCertificateV1 :
    ProofForgeV2.Crypto.Sha256BlockCertificate
      "proof-forge-solana-v1:increment(u64)".toUTF8
      "9dc79703d1db3e22eb256f4a5c72cad8a307ff4cf4e0dc311aa1de5cbf0689e2" := {
  finalState := stateCellIncrementDiscriminatorFinalStateV1
  trace := .step 0 0 ProofForgeV2.Crypto.sha256InitialState
    stateCellIncrementDiscriminatorFinalStateV1
    stateCellIncrementDiscriminatorFinalStateV1
    (by decide) (.done 64 stateCellIncrementDiscriminatorFinalStateV1)
  hex_eq := by decide
}

theorem stateCellIncrementDiscriminatorValueV1 :
    instructionDiscriminator "increment"
      #[StateCellPlanCertificateV1.incrementParam] = "9dc79703d1db3e22" := by
  unfold instructionDiscriminator
  rw [stateCellIncrementDiscriminatorInputV1,
    stateCellIncrementDiscriminatorCertificateV1.sound]
  decide

theorem stateCellGetDiscriminatorInputV1 :
    (discriminatorDomain ++ signature "get" #[]).toUTF8 =
      "proof-forge-solana-v1:get()".toUTF8 := by
  unfold discriminatorDomain signature
  decide

private abbrev stateCellGetDiscriminatorFinalStateV1 :
    ProofForgeV2.Crypto.Sha256State := #[
  0xa4a276b0, 0xd690dd37, 0xc1f433ea, 0x0a7bcc65,
  0xf877f495, 0xa22b061d, 0x28295c45, 0x87bc50b0]

set_option maxHeartbeats 5000000 in
set_option maxRecDepth 100000 in
private def stateCellGetDiscriminatorCertificateV1 :
    ProofForgeV2.Crypto.Sha256BlockCertificate
      "proof-forge-solana-v1:get()".toUTF8
      "a4a276b0d690dd37c1f433ea0a7bcc65f877f495a22b061d28295c4587bc50b0" := {
  finalState := stateCellGetDiscriminatorFinalStateV1
  trace := .step 0 0 ProofForgeV2.Crypto.sha256InitialState
    stateCellGetDiscriminatorFinalStateV1 stateCellGetDiscriminatorFinalStateV1
    (by decide) (.done 64 stateCellGetDiscriminatorFinalStateV1)
  hex_eq := by decide
}

theorem stateCellGetDiscriminatorValueV1 :
    instructionDiscriminator "get" #[] = "a4a276b0d690dd37" := by
  unfold instructionDiscriminator
  rw [stateCellGetDiscriminatorInputV1,
    stateCellGetDiscriminatorCertificateV1.sound]
  decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellInitializerDiscriminatorValidV1 :
    validDiscriminator (instructionDiscriminator "initialize"
      #[StateCellPlanCertificateV1.expectedParam]) = true := by
  exact instructionDiscriminator_isValid _ _

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellIncrementDiscriminatorValidV1 :
    validDiscriminator (instructionDiscriminator "increment"
      #[StateCellPlanCertificateV1.incrementParam]) = true := by
  exact instructionDiscriminator_isValid _ _

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellGetDiscriminatorValidV1 :
    validDiscriminator (instructionDiscriminator "get" #[]) = true := by
  exact instructionDiscriminator_isValid _ _

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellInitializerHandlerValidationV1 :
    validateHandler StateCellPlanCertificateV1.expectedTargetAccount true
      #[] #[] #[] 11 StateCellPlanCertificateV1.expectedInitializerHandler =
        .ok 13 := by
  have hname : "initialize".utf8ByteSize ≤ maxIdentifierBytes := by decide
  have hbodyNonempty :
      StateCellPlanCertificateV1.expectedBody.isEmpty = false := by
    unfold StateCellPlanCertificateV1.expectedBody
    decide
  have hbodySize :
      StateCellPlanCertificateV1.expectedBody.size ≤ maxBodyStatements := by
    unfold StateCellPlanCertificateV1.expectedBody maxBodyStatements
    decide
  have hbodyTooLarge :
      ¬maxBodyStatements < StateCellPlanCertificateV1.expectedBody.size :=
    Nat.not_lt_of_ge hbodySize
  have hmode : (HandlerMode.initialize == HandlerMode.initialize) = true := by decide
  have hview : (HandlerMode.initialize == HandlerMode.view) = false := by decide
  have haccess :
      (accessFor StateCellPlanCertificateV1.expectedTargetAccount HandlerMode.initialize ==
        accessFor StateCellPlanCertificateV1.expectedTargetAccount HandlerMode.initialize) = true :=
    by
      unfold accessFor StateCellPlanCertificateV1.expectedTargetAccount
        StateCellPlanCertificateV1.expectedStateAccount
      decide
  have hparams :
      validateParams (toString "handler '" ++ toString "initialize" ++ toString "'")
        #[StateCellPlanCertificateV1.expectedParam] = .ok () := by
    have hlabel :
        toString "handler '" ++ toString "initialize" ++ toString "'" =
          "handler 'initialize'" := by decide
    rw [hlabel]
    exact stateCellInitializerParamsValidationV1
  unfold validateHandler
  simp [StateCellPlanCertificateV1.expectedInitializerHandler,
    stateCellInitializerDiscriminatorValidV1,
    hparams,
    stateCellInitializerBodyValidationV1,
    hname, hbodyNonempty, hbodyTooLarge, hmode, hview, haccess,
    expectedAccess, isIdentifier,
    ProofForgeV2.Targets.EnvelopeV1.isAsciiIdentifier,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellIncrementHandlerValidationV1 :
    validateHandler StateCellPlanCertificateV1.expectedTargetAccount false
      #[] #[] #[] 13 StateCellPlanCertificateV1.expectedIncrementHandler =
        .ok 17 := by
  have hname : "increment".utf8ByteSize ≤ maxIdentifierBytes := by decide
  have hbodyNonempty :
      StateCellPlanCertificateV1.incrementBody.isEmpty = false := by
    unfold StateCellPlanCertificateV1.incrementBody
    decide
  have hbodySize :
      StateCellPlanCertificateV1.incrementBody.size ≤ maxBodyStatements := by
    unfold StateCellPlanCertificateV1.incrementBody maxBodyStatements
    decide
  have hbodyTooLarge :
      ¬maxBodyStatements < StateCellPlanCertificateV1.incrementBody.size :=
    Nat.not_lt_of_ge hbodySize
  have hmode : (HandlerMode.mutate == HandlerMode.initialize) = false := by decide
  have hview : (HandlerMode.mutate == HandlerMode.view) = false := by decide
  have haccess :
      (accessFor StateCellPlanCertificateV1.expectedTargetAccount HandlerMode.mutate ==
        accessFor StateCellPlanCertificateV1.expectedTargetAccount HandlerMode.mutate) = true :=
    by
      unfold accessFor StateCellPlanCertificateV1.expectedTargetAccount
        StateCellPlanCertificateV1.expectedStateAccount
      decide
  have hparams :
      validateParams (toString "handler '" ++ toString "increment" ++ toString "'")
        #[StateCellPlanCertificateV1.incrementParam] = .ok () := by
    have hlabel :
        toString "handler '" ++ toString "increment" ++ toString "'" =
          "handler 'increment'" := by decide
    rw [hlabel]
    exact stateCellIncrementParamsValidationV1
  unfold validateHandler
  simp [StateCellPlanCertificateV1.expectedIncrementHandler,
    stateCellIncrementDiscriminatorValidV1,
    hparams,
    stateCellIncrementBodyValidationV1,
    hname, hbodyNonempty, hbodyTooLarge, hmode, hview, haccess,
    expectedAccess, isIdentifier,
    ProofForgeV2.Targets.EnvelopeV1.isAsciiIdentifier,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellGetHandlerValidationV1 :
    validateHandler StateCellPlanCertificateV1.expectedTargetAccount false
      #[] #[] #[] 17 StateCellPlanCertificateV1.expectedGetHandler = .ok 18 := by
  have hname : "get".utf8ByteSize ≤ maxIdentifierBytes := by decide
  have hbodyNonempty : StateCellPlanCertificateV1.getBody.isEmpty = false := by
    unfold StateCellPlanCertificateV1.getBody
    decide
  have hbodySize : StateCellPlanCertificateV1.getBody.size ≤ maxBodyStatements := by
    unfold StateCellPlanCertificateV1.getBody maxBodyStatements
    decide
  have hbodyTooLarge : ¬maxBodyStatements < StateCellPlanCertificateV1.getBody.size :=
    Nat.not_lt_of_ge hbodySize
  have hmode : (HandlerMode.view == HandlerMode.initialize) = false := by decide
  have hview : (HandlerMode.view == HandlerMode.view) = true := by decide
  have haccess :
      (accessFor StateCellPlanCertificateV1.expectedTargetAccount HandlerMode.view ==
        accessFor StateCellPlanCertificateV1.expectedTargetAccount HandlerMode.view) = true :=
    by
      unfold accessFor StateCellPlanCertificateV1.expectedTargetAccount
        StateCellPlanCertificateV1.expectedStateAccount
      decide
  have hparams :
      validateParams (toString "handler '" ++ toString "get" ++ toString "'") #[] =
        .ok () := by
    have hlabel : toString "handler '" ++ toString "get" ++ toString "'" =
        "handler 'get'" := by decide
    rw [hlabel]
    exact stateCellGetParamsValidationV1
  unfold validateHandler
  simp [StateCellPlanCertificateV1.expectedGetHandler,
    stateCellGetDiscriminatorValidV1,
    hparams,
    stateCellGetBodyValidationV1,
    hname, hbodyNonempty, hbodyTooLarge, hmode, hview, haccess,
    expectedAccess, isIdentifier,
    ProofForgeV2.Targets.EnvelopeV1.isAsciiIdentifier,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
/-- The exact Plan retained after production Semantic lowering passes the sole
    target-owned Plan validator. -/
theorem stateCellPlanValidationV1 :
    validatePlan stateCellCertifiedPlanV1.plan = .ok () := by
  let result := validatePlan stateCellCertifiedPlanV1.plan
  have hbase :
      StateCellPlanCertificateV1.expectedTargetAccount.fields.size + 3 +
          (StateCellPlanCertificateV1.expectedInitializerHandler.params.size +
            (StateCellPlanCertificateV1.expectedIncrementHandler.params.size +
              StateCellPlanCertificateV1.expectedGetHandler.params.size)) +
        (StateCellPlanCertificateV1.expectedInitializerHandler.body.size +
          (StateCellPlanCertificateV1.expectedIncrementHandler.body.size +
            StateCellPlanCertificateV1.expectedGetHandler.body.size)) = 11 := by
    unfold StateCellPlanCertificateV1.expectedTargetAccount
      StateCellPlanCertificateV1.expectedStateAccount
      StateCellPlanCertificateV1.expectedInitializerHandler
      StateCellPlanCertificateV1.expectedIncrementHandler
      StateCellPlanCertificateV1.expectedGetHandler
      StateCellPlanCertificateV1.expectedBody
      StateCellPlanCertificateV1.incrementBody
      StateCellPlanCertificateV1.getBody
    decide
  have hprogramName : "StateCell".utf8ByteSize ≤ 240 := by decide
  have hprogramStem : ¬230 < "StateCell".utf8ByteSize := by decide
  have success : result.toOption.isSome = true := by
    dsimp only [result]
    rw [stateCellCertifiedPlanValueV1]
    unfold stateCellLoweredPlanV1 StateCellPlanCertificateV1.projectedPlan
    rw [StateCellPlanCertificateV1.contextValue]
    unfold finishPlanLoweringV1 StateCellPlanCertificateV1.expectedCallableState
      StateCellPlanCertificateV1.expectedContext
    simp only [Pure.pure, Except.pure, Bind.bind, Except.bind, Except.toOption,
      Option.get_some]
    simp [validatePlan,
      hbase,
      stateCellStateAccountValidationV1,
      stateCellInitializerHandlerValidationV1,
      stateCellIncrementHandlerValidationV1,
      stateCellGetHandlerValidationV1,
      maxArtifactStemBytes, maxEntries, maxPlanNodes,
      ProofForgeV2.Targets.EnvelopeV1.hasDuplicates,
      isIdentifier, maxIdentifierBytes,
      ProofForgeV2.Targets.EnvelopeV1.isAsciiIdentifier,
      Pure.pure, Except.pure, Bind.bind, Except.bind]
    simp [StateCellPlanCertificateV1.expectedInitializerHandler,
      StateCellPlanCertificateV1.expectedIncrementHandler,
      StateCellPlanCertificateV1.expectedGetHandler,
      stateCellInitializerDiscriminatorValueV1,
      stateCellIncrementDiscriminatorValueV1,
      stateCellGetDiscriminatorValueV1,
      hprogramName, hprogramStem]
  simpa only [result] using exceptToOptionGetSuccessV1 result success

end ProofForgeV2.Targets.Solana
