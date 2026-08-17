---
id: PLAN-SOL-ADR-0048-NEXT
title: Solana ADR-0048 D4 certificate and concrete D5 composition closure
status: draft
owner: engineering
updated: 2026-08-15
normative: false
---

# ADR-0048 D4 certificate 与 concrete D5 composition closure

> Engineering inventory only. Does **not** close formal `TASK-D5-*`,
> Mollusk/`.so`/validator semantics, or accepted-PRD expansion.
> Does **not** invent a new `TASK-*`. Provider stays off the product `build` path
> (ADR-0048 D3).

Authority: [`0048-optional-solana-sbpf-semantics-provider.md`](../adr/0048-optional-solana-sbpf-semantics-provider.md)
D4 · [`verified-contract-authoring.md`](verified-contract-authoring.md) §5.

## Already pinned

| D4 recipe | Production subject resolver | Sparse kernel certificate | Source-derived concrete composition |
|---|---|---|---|
| `get()` | `resolveStateCellGetProductionSubjectV1` | 55-step + `runFuel` status-zero | same-state UInt64 return + empty effects + account stutter |
| `initialize(initial)` | `resolveStateCellInitializeProductionSubjectV1` | 55-step + exact initialized account window | Reference initializer → HandlerIR → provider |
| `increment(delta)` | `resolveStateCellIncrementProductionSubjectV1` | 70-step + exact account/return bytes | Reference checked-add success → HandlerIR → provider |
| increment overflow | `resolveStateCellIncrementOverflowProductionSubjectV1` | 56-step + `0x1001` + unchanged account/empty return | Reference arithmetic revert → Handler trap → provider status |

`SbpfHandlerJoinV1` already has the HandlerIR ↔ Loader invocation/observation
relation, including overflow → nonzero status. All four production subjects are
now bound and retain dedicated sparse certificates: 55 steps for `get`, 55 for
`initialize`, 70 for successful `increment`, and 56 for increment overflow.

Code facts:

- `ProofForgeV2/Targets/Solana/SbpfStateCellProductionV1.lean` contains the
  `get`, `initialize`, increment-success, and increment-overflow resolvers. All
  consume the same elaborated Source AST, production validator/canonical encoder
  binding, compiler and production `.s`; overflow reuses the private increment
  subject directly. All four subjects retain sparse provider certificates.
- Sparse certificates live in `SbpfStateCellGetV1.lean` and
  `SbpfStateCellInitializeV1.lean`, plus
  `SbpfStateCellIncrementV1.lean` for the success path and
  `SbpfStateCellIncrementOverflowV1.lean` for overflow.
- Authoring doc: still no unconditional kernel equality for the large
  production theorem; release SBOM/source-dependency stays fail closed.
- All four production resolvers now recover the validated Semantic program,
  Reference admission, exact pre-state and actual `stepReferenceSliceV1`
  outcome from the same source/compiler path. Their Boolean-gated sound
  theorems call the certified join's `referenceJoin`; they do not return two
  unrelated witnesses.
- `ProductionPreparationV1.lean` now factors the contract-independent Source →
  compile → Reference admission → Solana capability/Plan/HandlerIR → assembly →
  identity-bound artifact path. Every stage retains the exact production
  function's `.ok` equation.
- `Core/Crypto.lean` now uses one structurally recursive production SHA-256
  implementation instead of opaque `for`/`while` folds. Its generic raw/hex and
  block-trace certificates are kernel-sound against that same implementation;
  block traces retain only chaining states and always read blocks from their
  indexed input bytes. `SbpfArtifactV1.lean` replays such a certificate through
  the real canonical-digest and parser gate. A kernel `abc` block certificate,
  existing runtime padding vectors, and artifact drift tests cover the seam.
- `ProductionMethodV1.lean` now factors contract-independent Semantic callable
  and production HandlerIR lookup, plus invocation of the sole
  `stepReferenceSliceV1`. The certificate is parameterized by method identity,
  logical pre-state, arguments, context, responses and vault seed; it contains
  no StateCell field, copied IR, provider trace or second transition system.
  All four StateCell scenarios consume it as the first concrete clients.
- `ProductionProviderV1.lean` now factors the contract-independent production
  Loader V3 encoder and identity-bound provider execution equations. Artifact,
  invocation, fuel, halt status, account window, input and final machine are all
  parameters. The four StateCell scenarios consume this boundary while their
  artifact manifests, concrete input reads, sparse traces and postconditions
  remain method-specific.
- The same module now has a contract-independent provider execution resolver.
  It obtains the account window from the bound production artifact, calls the
  real Loader encoder and pinned `runFuel`, and retains exact encoder/window/
  resource/run equations. Invalid input, missing window, zero or excessive
  fuel, input overflow, stuck/out-of-fuel execution and unexpected status all
  fail closed. Its replay theorem and certificate/observation projections do
  not copy a trace or introduce another evaluator.
- `SbpfHandlerJoinV1.lean` consumes that resolver through a generic certified
  HandlerIR/provider join parameterized by handler, invocation, fuel, status
  and expected artifact identity. It runs the existing HandlerIR evaluator,
  verifies invocation and final observation agreement, and retains both exact
  evaluator equations. The old StateCell sparse joins remain method-specific;
  this layer is the reusable execution skeleton for a second contract.
- `ProductionCompositionV1.lean` now factors the contract-independent,
  fail-closed resolver/Reference-checker/provider-checker gate. Its soundness
  theorem recovers the exact resolved subject and both checker equations, but
  deliberately does not interpret them as a business relation or general
  Reference→provider refinement. A second generic theorem lifts those equations
  through caller-owned Reference soundness, provider certificate soundness and
  composition functions into dependent proof witnesses. The four StateCell
  scenarios are its first consumers; their observation relations, traces and
  postconditions remain method-specific.
- The preparation and method modules now also expose certificate-replay
  theorems. An already-retained certificate proves that the original
  fail-closed preparation/method resolver returns that exact dependent value;
  the Reference wrapper has the corresponding execution replay theorem.
  `ProductionCompositionV1.lean` has the matching completeness direction:
  exact resolver and checker equations imply the generic Boolean gate is
  `true`. These theorems reuse the original resolvers and checkers; they are not
  alternate evaluators or a way to manufacture a certificate from runtime
  output.

## Completed implementation slices (serial)

These were completed serially by extending the `get` pattern, without writing a
second codegen.

1. **SOL-0048-INIT** — **done 2026-08-15**: production subject + generic
   executed HandlerIR/provider join + assembly identity vs `get`; the sparse
   55-step initialize certificate followed in slice 4.
2. **SOL-0048-INC** — **done 2026-08-15**: same generic executed join for
   pinned `41 + 1` increment success; the sparse certificate followed in slice
   5.
3. **SOL-0048-OVF** — **done 2026-08-15**: `UInt64.max + 1` generic executed
   join fixes provider status `0x1001` and exact pre-account snapshot agreement;
   the sparse certificate followed in slice 6.
4. **SOL-0048-INIT-CERT** — **done 2026-08-15**: exact 55-step initialize
   certificate binds the production artifact fetches, concrete Loader reads,
   54/55 fuel boundary, initialized account window, and certified HandlerIR /
   provider join.
5. **SOL-0048-INC-CERT** — **done 2026-08-15**: exact 70-step successful
   increment certificate binds the production artifact fetches, concrete
   Loader reads, 69/70 fuel boundary, `41 + 1` account/return bytes, and
   certified HandlerIR/provider join. Value, argument, and invocation-byte
   drift fail closed.
6. **SOL-0048-OVF-CERT** — **done 2026-08-15**: exact 56-step overflow
   certificate binds the production artifact fetches, concrete Loader reads,
   55/56 fuel boundary, status `0x1001`, unchanged account bytes, empty return
   data, and certified HandlerIR/provider join. Value, argument, input,
   invocation-byte, artifact-identity, and handler drift fail closed.
7. **SOL-0048-D5-INIT-COMPOSE** — **done 2026-08-15**: source-derived
   initializer Reference outcome is composed with the 55-step certified join.
8. **SOL-0048-D5-INC-COMPOSE** — **done 2026-08-15**: source-derived
   `increment(41, 1)` checked-add outcome is composed with the 70-step
   certified join.
9. **SOL-0048-D5-OVF-COMPOSE** — **done 2026-08-15**: source-derived
   `increment(UInt64.max, 1)` arithmetic revert is composed with Handler trap,
   account hold and the 56-step provider `0x1001` certificate.
10. **SOL-0048-D5-GET-COMPOSE** — **done 2026-08-15**: source-derived
    `get(41)` same-state UInt64 result is composed with Handler account stutter
    and the 55-step certified provider join; tampered Reference outcome fails
    closed.
11. **SOL-0048-D5-DISCHARGE-SEAM** — **done 2026-08-15**: introduced a
    contract-independent, proof-producing production preparation certificate.
    It indexes arbitrary elaborated source/export bytes/artifact identity and
    retains successful equations for all ten real production stages. All three
    base StateCell resolvers now share it; source-byte and artifact-identity
    drift fail closed through the generic resolver.
12. **SOL-0048-D5-METHOD-SEAM** — **done 2026-08-15**: introduced a
    contract-independent method lookup and Reference execution certificate.
    Exact Semantic callable and production HandlerIR lookup equations are
    retained, and Reference invocation identity is forced to the selected
    callable. Wrong callable kind/name and missing HandlerIR rows fail closed;
    `get`, `initialize`, increment success and overflow now share this API.
13. **SOL-0048-D5-PROVIDER-SEAM** — **done 2026-08-15**: introduced a
    contract-independent provider execution certificate retaining the exact
    production Loader encoder and identity-bound execution equations. All four
    StateCell provider certificates now consume it; method-specific manifests,
    reads, traces and observations are deliberately not generalized away.
14. **SOL-0048-D5-COMPOSITION-SEAM** — **done 2026-08-15**: introduced a
    contract-independent production composition gate parameterized by any
    resolved subject and two caller-supplied Boolean checkers. Resolution and
    either checker fail closed; soundness recovers one shared subject plus the
    exact Reference/provider checker equations. All four StateCell D5 gates now
    consume it without moving their business relations or sparse certificates
    into the generic layer.
15. **SOL-0048-D5-WITNESS-SEAM** — **done 2026-08-15**: added generic
    dependent witness lifting over the composition gate. Callers supply the
    Reference checker soundness, provider-certificate soundness and final
    witness composition function; the theorem packages the resolved subject,
    provider certificate and composed witness. All four StateCell sound
    theorems now consume this skeleton while retaining their own UInt64
    relations and provider joins.
16. **SOL-0048-D5-CERTIFICATE-REPLAY** — **done 2026-08-15**: added the
    contract-independent completeness direction for preparation stages, the
    complete preparation resolver, method lookup, Reference execution, and the
    generic subject/composition gates. Each theorem requires the exact
    proof-carrying certificate or checker equation and replays it through the
    existing production function. Type-level fixtures quantify over arbitrary
    source, method, state, invocation, subject type, and checker pair; no
    StateCell field, transition, manifest, or trace moved into the generic
    layer.
17. **SOL-0048-D5-GENERIC-PROVIDER-RESOLVER** — **done 2026-08-15**: added a
    contract-independent resolver over the actual Loader encoder, artifact
    execution window and pinned `runFuel`, with exact certificate and replay
    projections. A generic certified HandlerIR/provider gate now consumes it
    and checks artifact identity plus invocation/final observation agreement.
    StateCell `get` is the first runtime regression; wrong status, zero fuel and
    identity drift fail closed. No sparse trace or contract relation moved into
    the generic layer.
18. **SOL-0048-D5-SECOND-CONTRACT-CONSUMER** — **done 2026-08-15**:
    `OptionState.peek` now reconstructs the actual exported Source AST,
    production Semantic/Plan/HandlerIR and identity-bound `.s` artifact through
    the same generic preparation, method, Reference execution, provider,
    composition and witness APIs. A contract-independent `Option UInt64`
    tag/payload representation relation and proof-producing checker join the
    canonical Reference value bytes to the 24-byte Solana account layout.
    Both `Some 77 → 77` and `None → 0` execute through the sole Reference
    machine, production switch HandlerIR and shared provider resolver; wrong
    method/artifact/status/fuel and malformed account length fail closed. No
    contract-name dispatch, copied trace, alternate Option interpreter or
    HandlerIR→sBPF lowering was added.
19. **SOL-0048-D5-OPTION-GETOPT** — **done 2026-08-15**: extended the same
    bounded HandlerIR evaluator with a contract-independent nullary aggregate
    recipe. It accepts 1..8 distinct 8-byte locals loaded from the production
    account and published in exact leaf order by `setReturnDataMulti`; wrong
    result shape, missing/reordered leaves and overwritten locals fail closed.
    A generic typed return relation permits canonical Reference bytes and
    target ABI bytes to differ while checking both actual outcomes and account
    stutter. The real `OptionState.getOpt()` consumes this boundary through a
    shared OptionState source/Plan/account preparation: `Some 77` maps Reference
    `#[1] ++ u64LE(77)` to target `u64LE(1) ++ u64LE(77)`, while `None` maps
    Reference `#[0]` to two zero words. HandlerIR and the identity-bound
    production provider return the exact target bytes and preserve the account.
    Recognition remains method-name independent; no Option interpreter, copied
    provider trace or proof-only lowering was added.
20. **SOL-0048-D5-TWO-LEAF-TARGET-THEOREM** — **done 2026-08-15**: added an
    exact, contract-independent two-leaf HandlerIR recognizer, proof-carrying
    recognition result and explicit repeated-field join to the production
    Plan. The target evaluator now has kernel theorems for both execution and
    full observation: two loaded words are returned in leaf order and the
    read-only account array stutters. The real source-derived
    `OptionState.getOpt` resolver retains this alignment certificate and has an
    unconditional theorem for its HandlerIR observation; reordered return
    sources fail at the Plan join. This is a HandlerIR target theorem, not an
    artifact/provider refinement theorem.
21. **SOL-0048-D5-SWITCH-TARGET-THEOREM** — **done 2026-08-15**: added an
    exact, contract-independent one-case UInt64 switch recognizer and retained
    every repeated local/account/layout/case/default/return field for an
    independent production Plan join. Kernel execution and full-observation
    theorems cover both selected account-load and literal-default branches;
    both stutter the read-only account array. The real source-derived
    `OptionState.peek(Some 77)` subject now retains recognition, alignment,
    discriminator and invocation equations and has an unconditional HandlerIR
    observation theorem. Renaming remains accepted, while changed selector
    local/offset, case value, default literal, return source and missing
    branches fail closed. This theorem stops at HandlerIR; the existing
    artifact/provider composition still has Boolean premises.
22. **SOL-0048-D5-SHA-CERTIFICATE-BOUNDARY** — **done 2026-08-15**: replaced
    the sole production SHA-256 implementation's imperative loops with
    structurally recursive padding, schedule, compression, block traversal and
    hex rendering. Added raw-digest and compositional block-trace certificates
    with kernel soundness back to `sha256Hex`; every transition consumes the
    indexed owner bytes rather than carrying copied blocks. The real bound
    artifact resolver now has a certificate replay theorem that still requires
    exact parser success and canonical expected hex. A kernel-checked `abc`
    block certificate and existing NIST/runtime vectors pass without
    `native_decide`, `Lean.ofReduceBool`, `run_tac` or axioms.
23. **SOL-0048-D5-EMITTER-CORE-CERTIFICATE-BOUNDARY** — **done 2026-08-15**:
    removed the kernel-opaque `partial` definitions from the sole production
    sBPF operation emitter and canonical temp-count traversal. Nested regions
    now consume an explicit node-bound fuel and fail closed if exhausted; no
    second emitter or copied assembly was introduced. The public emitter now
    delegates to one post-validation production pass and has a Prop-level
    exact-result certificate with decomposition and sound replay theorems.
    Production preparation projects this certificate from its existing
    assembly-stage equation. Runtime output and the full Solana assembly suite
    remain byte-stable. This closes the emitter core blocker, not the still
    partial `validateIR`/IR-lowering path that produces the StateCell input.
24. **SOL-0048-D5-STATECELL-SOURCE-BINDING** — **done 2026-08-15**: made the
    sole production declaration-set and qualified program-identity validators
    kernel replayable by replacing opaque `HashSet`, Array iterator and
    imperative traversals with structural recursion over the same bounded
    source lists. Exact UTF-8 component identity, diagnostic order and
    fail-closed behavior remain unchanged. The real `program StateCell` AST is
    now bound to its macro-exported canonical bytes by a kernel-checked exact
    production equation. No copied AST, contract-name dispatch or proof-only
    source validator was introduced. This closes source ownership only; the
    next failing stage is production compiler normalization.
25. **SOL-0048-D5-NORMALIZER-CORE-BOUNDARY** — **done 2026-08-15**: removed
    the kernel-opaque `partial` recursion and imperative traversals reachable
    from the real StateCell source through the sole production semantic
    normalizer and S2 requirement freezer. Recursive source walks now consume a
    fixed source-depth budget and fail closed when exhausted; exact name identity
    and requirement ordering use shared UTF-8 byte operations. Invariant closure
    seeding is structural, and the sole assignment authority treats the generic
    no-invariant-root case as the exact empty-closure identity. StateCell identity,
    requirement inference/freeze, and all three body-lowering stages now replay
    independently in the kernel; no copied AST/IR or proof-only normalizer was
    added. This closes the reachable normalizer implementation blocker, not the
    still-unassembled exact whole-program normalization equation.
26. **SOL-0048-D5-STATECELL-NORMALIZER-CERTIFICATE** — **done 2026-08-16**:
    refactored the sole production normalizer itself into source-list callable
    steps and explicit finalization stages; `lowerProgramDataV1` directly calls
    those stages, so no proof-side implementation exists. The real exported
    StateCell source now has separate kernel equations for declaration tables,
    `initialize`, `increment`, `get`, invariant/type finalization, S2 freeze and
    wire-owned requirement merge. Those equations construct an unconditional
    `CertifiedProgramLoweringV1`, whose generic theorem replays the exact whole
    `lowerProgramDataV1 = .ok data` result. No expected Semantic AST, runtime
    Boolean, contract-name branch or copied IR is accepted. This closes
    ProgramV1→SemanticProgramDataV1 ownership; CheckV1 acceptance, carrier
    encoding and compiler identity mint remain the next production compiler
    boundary.
27. **SOL-0048-D5-STATECELL-RESOLUTION-CALLGRAPH** — **done 2026-08-16**:
    made the sole production name resolver and site-bearing call-edge collector
    kernel replayable with validated-source-bounded total recursion and
    fail-closed exhaustion drafts. Both production passes now use structural
    source-list drivers and per-item steps called by their public authorities.
    The exact real StateCell source has kernel equations for all four table,
    resolution and call-edge item steps, plus the final empty edge/SCC/cycle
    result. No contract-name shortcut, copied AST, second resolver/callgraph or
    proof-only checker was added. This closes the first two Typed phases only;
    TypeCheck and the remaining analysis phases still gate whole CheckV1
    acceptance.
28. **SOL-0048-D5-STATECELL-TYPED-CERTIFICATE** — **done 2026-08-16**:
    made every StateCell-reachable recursive walk in the sole production
    TypeCheck, EffectCheck, BoundCheck, DisclosureCheck and
    ContextExtensionCheck bounded-total. Fuel exhaustion is represented by the
    production result and forces `analysisComplete = false` and `ok = false`;
    no exhausted walk is projected to an empty successful result. The real
    exported StateCell declaration now has exact kernel equations for those
    five phases plus the existing AuthorityCustodyCheck, name-resolution and
    call-graph phases. Their production composition proves the complete
    `checkProgramTypedResultV1` result is exactly empty diagnostics, `ok = true`
    and `analysisComplete = true` for any canonical binding of that source. No
    expected AST, second checker, contract-name branch or runtime Boolean is
    accepted. This closes the production Typed gate; canonical carrier encoding
    and the compiler identity mint are the next boundary.
29. **SOL-0048-D5-STATECELL-SEMANTIC-STRUCTURE-CERTIFICATE** — **done
    2026-08-17**: composed the exact data produced by the sole StateCell
    normalizer through every real `validateSemanticProgramStructureV1` phase.
    The certificate covers production TypeKey/type-table checks, declaration
    names and callable signatures, CFG reachability, SSA definition/use and
    dominance, CFG typing/generic phases, invariant closure, requirement and
    context gates. Two generic TypeKey lemmas expose only the existing
    validators' allocation-free branch when their exact container scans are
    empty, and a generic closed-table certificate composes the production
    anonymous rank for `#[UInt64, Unit]`; none is an alternate validator. The
    real lowering certificate is retained as one reusable
    `CertifiedProgramLoweringV1`, and a generic
    `normalizeProgramV1_eq_ok_of_stages` seam now composes exact successes of
    the sole Typed/lowering/carrier functions without implementing another
    normalizer. No expected Semantic AST/IR, contract-name dispatch or runtime
    Boolean was introduced. This closes `SemanticProgramDataV1` structure
    acceptance; exact canonical field-byte resource certificates, carrier
    encoding and compiler identity mint remain open.
30. **SOL-0048-D5-STATECELL-CARRIER-RESOURCE-CERTIFICATE** — **done
    2026-08-17**: composed the real StateCell lowering result through production
    field encoders into an exact canonical wire success and resource bound. The
    root certificate still invokes the sole `encodeSemanticProgramDataV1`; it
    neither materializes/copies the 1523-byte carrier nor introduces a second
    encoder. `stateCellCanonicalCarrierCertificateV1` then supplies the same
    source binding, complete Typed certificate, production lowering and wire
    certificate to the sole `normalizeProgramV1`, closing source → exact
    canonical carrier. Codec support is limited to generic six-element array and
    one/two-field fold-size seams with no StateCell data. This closes carrier
    encoding; `CompiledSemanticV1` identity mint, Solana Plan/IR, exact emitter
    equation, SHA trace and unconditional `get` remain open.

D4's four pinned sparse certificates and all four concrete D5 compositions are
complete, and the generic seam now has a second real contract/HandlerIR shape
consumer plus its first multiword typed return. The generic bytes→SHA→artifact
identity proof boundary and a kernel-reducible production emitter core are now
present. Source binding, the complete production Typed gate, exact
ProgramV1→SemanticProgramDataV1 normalization, the complete production Semantic
structure gate and canonical carrier encoding are now kernel-certified from the
real StateCell declaration. The remaining compiler boundary is the
`CompiledSemanticV1` identity mint from that carrier; target ownership then
continues through the reachable `LowerSemanticV1`/`EmitIRV1` path and
`validateIR = .ok ()`.
Until compiler/IR ownership closes, the post-validation emission equation cannot
be owner-bound to the real source pipeline, so a SHA trace alone still cannot
establish emitter ownership. Runtime output `true` and a certificate over copied
or materialized assembly remain unacceptable.

Next formalization slices, in order:

1. **SOL-0048-D5-GET-EMITTER-CERTIFICATE**: make the real production emission
   stage fully proof-producing/kernel-replayable for its exact result. The
   emitter core, certificate boundary, real StateCell source binding and
   exact whole-program data normalization certificate are done; the complete
   production Typed gate, Semantic structure gate and compositional canonical
   carrier certificate are now also discharged. Next close the compiler identity
   mint from those same production values; after that totalize/replay
   `LowerSemanticV1`, `EmitIRV1` and `validateIR`,
   and discharge the StateCell exact post-validation emission equation. Keep
   traversal contract-independent and do not add a proof-only compiler, emitter
   or copied assembly.
2. **SOL-0048-D5-GET-UNCONDITIONAL**: build the 103-block SHA trace directly
   over that exact emitter result, replay it through `resolveBoundSbpfArtifactV1`
   and preparation replay, then discharge the existing StateCell `get` gate.
3. While emission replay is being extended, continue target-owned
   structural/execution theorems for additional production HandlerIR recipes.
   Each real subject must retain a recognizer/Plan alignment certificate as
   `OptionState.getOpt` and `OptionState.peek` now do; do not add contract-name
   dispatch.
4. Apply the discharge pattern to initialize, increment success and overflow
   only after `get` closes without a one-off proof-only evaluator.
5. Do not add `native_decide`, `Lean.ofReduceBool`, `run_tac`, an axiom, a
   copied AST/IR/provider program, or a proof-only HandlerIR→sBPF lowering.
6. Keep ELF/linker/loader and validator/SVM runtime refinement as a separate
   later boundary; prefer an external semantics provider rather than building a
   second runtime model inside ProofForge.

Hashed-QN CallGate/ScheduleGate last-20 pin is done; binding stays
`B-CALL-SEM` ([`evm-call-addr-gap.md`](evm-call-addr-gap.md)).

Each slice: allowlist under `ProofForgeV2/Targets/Solana/Sbpf*` + focused
Solana asm/provider tests + SBOM if `ProofForgeV2/**` changes.

## Non-claims

Concrete Boolean-gated D5 composition is complete, but formal TASK-D5 is not
closed until its premises are kernel-discharged. Not ELF/Mollusk/SVM. Not
CPI/multi-account. Not product `build` consuming the provider. Not EVM
lighthouse progress.
