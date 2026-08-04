/-
  Compatibility re-export of `ProofForgeV2.Core.RequirementIdsV1` for consumers
  that still import the pre-CPI-epic Semantic path. Sole spelling authority is
  Core; do not add new ids here.
-/
import ProofForgeV2.Core.RequirementIdsV1

namespace ProofForgeV2.Semantic.RequirementIdsV1

export ProofForgeV2.Core.RequirementIdsV1 (
  s2EffectAsyncWorkflowIdV1
  s2EffectEventIdV1
  s2EffectSyncCallIdV1
  s2FailureAtomicRollbackIdV1
  s2StatePersistentIdV1
  s2ValueBoolIdV1
  s2ValueCheckedArithmeticIdV1
  s2CatalogIdsWireOrderListV1
  s2CatalogIdsWireOrderV1
  wireContextUnixTimeSecondsIdV1
  wireContextCallerIdV1
  wireCommitmentDisclosureIdV1
  solanaCpiAccountsExtensionSourceIdV1
  solanaCpiAccountsExtensionVersionV1
  solanaCpiAccountsExtensionDigestV1
  wireExtensionSolanaCpiAccountsIdV1
  pfAssetsExtensionSourceIdV1
  pfAssetsExtensionVersionV1
  pfAssetsExtensionDigestV1
  wireExtensionPfAssetsIdV1
  pfAssetsCatalogQualifiedNamesV1
  EngineeringExtensionIdentityV1
  solanaCpiAccountsExtensionIdentityV1
  pfAssetsExtensionIdentityV1
  engineeringExtensionIdentitiesV1
  findEngineeringExtensionBySourceIdV1
  isExactEngineeringExtensionTripleV1
  wireRequirementIdOfExactExtensionTripleV1
  wireOwnedRequirementIdsV1
  inferDisclosurePrivateWitnessIdV1
  inferDisclosureCommitmentIdV1
  inferDisclosurePrivateStateIdV1
  inferDisclosureCommitmentStateIdV1
  inferValueFieldBn254FrIdV1
  inferValueFieldBls12377FrIdV1
  inferValueFieldGoldilocksIdV1
  inferOnlyRequirementIdsV1
)

end ProofForgeV2.Semantic.RequirementIdsV1
