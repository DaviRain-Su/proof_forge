/-
  Tests.Semantic.NormalizeV1 — S1 Semantic normalizer vertical contract suite.

  The executable suite body and `run` live in `Tests/Typed/CheckV1.lean` under
  absolute namespace `Tests.Semantic.NormalizeV1` so Lake builds them as part of
  the already-registered CI root `Tests.Typed.CheckV1` (ordinary `just ci` /
  proof_forge_next_tests). That root already imports ParserSession; hosting the
  suite inside WireV1 is avoided because Language syntax keywords would break
  WireV1 identifiers such as `programWithState`.

  `Tests.Typed.CheckV1.run` and `Tests.Fast` both invoke
  `Tests.Semantic.NormalizeV1.run`.

  Contract:
    * source text → Loader V1 → Typed.CheckV1.ok → NormalizeV1 →
      WireV1 validate / decodeSemanticProgramV1 byte identity / semanticHashV1
    * N-INVARIANT-IR: `invariant name : BoolExpr` → `.invariant` callable +
      dense InvariantDecl; exact invariantSteps via sole Wire compute;
      provenance covers `.invariant`; `.proof` stays certification-only
    * N-CONST-REF: body bare const places → `Op.Constant`; constants table
      complete before bodies (forward ref); provenance `.constant` + place;
      suite `Tests.Semantic.NormalizeConst`
    * Counter-like public legal-UInt state + init/entry/view with exact CFG ops
      (UInt64 golden bytes unchanged; multi-width UInt/Int covered in suite)
    * T2 named Struct/Enum Pass0 registration (contiguous named prefix; nested
      /forward named fields; Field/Map field types still fail closed)
    * S2 exact ProgramRequirementsV1 freeze (SPEC wire order; engineering
      digests; empty predicates) before encode/hash
    * S2 complete SemanticProvenanceV1 companion: authority is
      NormalizeV1.normalizeProgramWithProvenanceV1 / validateSemanticProvenanceV1 /
      semanticProvenanceDigestV1 over source+path+spans only (rebuild inventory
      internally; no caller inventory); exact path attribution; coordinated
      path/span mutation rejected; Wire/Provenance build helpers low-level only
    * state-after-init positive; param-shadow assign negative
    * repeated normalization deterministic (canonicalBytes + semanticHash)
    * typed-not-ok and unsupported ProgramV1 shapes fail closed (no carrier)
    * no alpha Typed.Program / Semantic.Program bridge
-/
import ProofForgeV2.Semantic.NormalizeV1

namespace Tests.Semantic.NormalizeV1Doc
end Tests.Semantic.NormalizeV1Doc
