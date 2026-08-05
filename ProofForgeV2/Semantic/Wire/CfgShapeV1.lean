import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.Wire.ModelV1
import ProofForgeV2.Semantic.Wire.CodecV1

/-!
  ProofForgeV2.Semantic.Wire.CfgShapeV1 — CFG shape, reachability, loopBounds,
  EffectId, ValueId SSA, and dominance-of-use (SPEC §6.2 layers a–g).

  Public declarations live in namespace `ProofForgeV2.Semantic.WireV1`.
-/
namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode

/-- Switch case constants are unique as `(typeId,valueBytes)` within one
    terminator (SPEC §6). Canonical valueBytes have already been validated by
    the phase-4 callable walk before CFG validation. Sort private typed keys
    and compare adjacent entries, avoiding a quadratic scan while preserving
    source case order in the public model. Target block/args are deliberately
    absent from the key: they cannot disambiguate the same case constant. -/
def validateSwitchCaseValuesUnique (cases : Array SwitchCaseV1) :
    Except SemanticWireErrorV1 Unit := do
  let keys := cases.map fun sc => (encodeU32le sc.typeId).append sc.valueBytes
  let sorted := keys.qsort fun left right => compareByteArrayLex left right == .lt
  let mut i : Nat := 1
  while i < sorted.size do
    if compareByteArrayLex sorted[i - 1]! sorted[i]! == .eq then
      return ← err .badCfg
    i := i + 1
  pure ()

/-! ### CFG shape + reachability + block-param arity + loopBounds + EffectId + ValueId SSA def-table + dominance-of-use (SPEC §6.2 — CFG layers)

    Per-callable: entryBlock == 0, block id == array index, Switch cases
    nonempty with unique typed canonical constants, terminator target range,
    jump/branch/switch target arg arity ==
    target block params, total reachability from entry, loopBounds back-edge
    coverage, contiguous EffectId
    assignment, ValueId definition-table / exactly-once / use-existence, and
    dominance-of-use.
    All CFG-shape failures use `.badCfg`. NOT block-param TYPE,
    or terminator typing (separate later slices). Reachability is total and
    non-recursive (worklist) to stay within nesting/stack limits. -/

/-- Internal WireV1-family phase entry (not a public contract; see `validateSemanticProgramStructureV1`). -/
def checkBlockIdInRange (blockId : BlockIdV1) (blockCount : Nat) :
    Except SemanticWireErrorV1 Unit := do
  unless blockId.toNat < blockCount do
    return ← err .badCfg
  pure ()

/-- Check a single JumpTargetV1's arg arity == target block's params size.
    Only runs when the target blockId is in range — the existing terminator
    target range pass (step c) owns out-of-range reporting, so this helper
    stays silent on OOR to avoid double-reporting. Arity mismatch → `.badCfg`.
    Arg ValueId→type resolution is out of scope (needs block-param TYPE from
    a later slice; ValueId use-existence is now owned by step f). -/
def checkJumpTargetArity (blocks : Array BlockV1) (blockCount : Nat)
    (target : JumpTargetV1) : Except SemanticWireErrorV1 Unit := do
  let bid := target.blockId.toNat
  if bid < blockCount then
    match blocks[bid]? with
    | some blk =>
        unless target.args.size == blk.params.size do
          return ← err .badCfg
    | none => pure ()
  pure ()

/-- Successor blockIds of a terminator (leaf terminators return empty). -/
def terminatorSuccessors (term : TerminatorV1) : Array BlockIdV1 :=
  match term with
  | .jump target => #[target.blockId]
  | .branch _cond thenTarget elseTarget =>
      #[thenTarget.blockId, elseTarget.blockId]
  | .switch _scrut cases defaultTarget =>
      let fromCases := cases.map (·.target.blockId)
      match defaultTarget with
      | some t => fromCases.push t.blockId
      | none => fromCases
  | .return_ _ | .revert _ _ | .trap _ => #[]

/-- All JumpTargetV1s carried by a terminator (for arg-arity checks).
    Leaf terminators return empty. -/
def terminatorJumpTargets (term : TerminatorV1) :
    Array JumpTargetV1 :=
  match term with
  | .jump target => #[target]
  | .branch _cond thenTarget elseTarget => #[thenTarget, elseTarget]
  | .switch _scrut cases defaultTarget =>
      let fromCases := cases.map (·.target)
      match defaultTarget with
      | some t => fromCases.push t
      | none => fromCases
  | .return_ _ | .revert _ _ | .trap _ => #[]

/-- CFG back edges as `(header, backEdgeFrom)` pairs (SPEC §6). SPEC assigns
    block IDs via preorder DFS from entry, so an edge `i -> s` is a back edge
    iff `s.toNat <= i`. We do not need a separate DFS/dominance pass — ID order
    already encodes preorder. Each distinct `(header, backEdgeFrom)` pair is
    reported once per occurrence; callers dedup by pair. Bounded,
    non-recursive. Only in-range successors are considered (out-of-range
    targets are owned by the terminator target range pass). -/
def cfgBackEdges (blocks : Array BlockV1) (blockCount : Nat) :
    Array (BlockIdV1 × BlockIdV1) := Id.run do
  let mut acc : Array (BlockIdV1 × BlockIdV1) := #[]
  let mut i : Nat := 0
  for b in blocks do
    for succ in terminatorSuccessors (BlockV1.terminator b) do
      let s := succ.toNat
      if s < blockCount && s <= i then
        acc := acc.push (succ, UInt32.ofNat i)
    i := i + 1
  pure acc

/-- One fixed-point pass: for each visited block, mark its successors visited.
    Returns the updated visited array. -/
private def cfgReachPass (blocks : Array BlockV1) (blockCount : Nat)
    (visited : Array Bool) : Array Bool := Id.run do
  let mut v : Array Bool := visited
  let mut i : Nat := 0
  for b in blocks do
    if v[i]! then
      for succ in terminatorSuccessors (BlockV1.terminator b) do
        let s := succ.toNat
        if s < blockCount && v[s]? == some false then
          v := v.set! s true
    i := i + 1
  pure v

/-- Reachability fixed point: repeat passes until no change or blockCount
    passes (blockCount passes suffice for a finite graph). Bounded, no
    unbounded recursion or worklist dequeue. -/
def cfgReachFixpoint (blocks : Array BlockV1) (blockCount : Nat)
    : (fuel : Nat) → (visited : Array Bool) → Array Bool
  | 0, visited => visited
  | fuel + 1, visited =>
    let next := cfgReachPass blocks blockCount visited
    if next == visited then next
    else cfgReachFixpoint blocks blockCount fuel next

/-- Per-callable loopBounds back-edge coverage (SPEC §6 / §6.2). Validates:
    a) each loopBound header/backEdgeFrom < blockCount (range owned here, not
       `.badReference`, because these are CFG-internal),
    b) maxIterations <= maxLoopIterationsV1 (4096),
    c) loopBounds strictly ascending and unique by (header, backEdgeFrom)
       lexicographic order,
    d) exact coverage: the multiset of (header, backEdgeFrom) pairs in
       loopBounds equals the multiset of actual CFG back edges (computed by
       `cfgBackEdges`), with duplicate actual edges to the same (header,
       backEdgeFrom) treated as a single back edge (SPEC says each pair is
       unique ascending). All failures → `.badCfg`. Bounded, total. -/
def validateCallableLoopBounds (c : CallableV1) :
    Except SemanticWireErrorV1 Unit := do
  let blockCount := c.blocks.size
  -- a) range check on header / backEdgeFrom
  for lb in c.loopBounds do
    unless lb.header.toNat < blockCount do
      return ← err .badCfg
    unless lb.backEdgeFrom.toNat < blockCount do
      return ← err .badCfg
  -- b) maxIterations <= 4096
  for lb in c.loopBounds do
    unless lb.maxIterations <= maxLoopIterationsV1 do
      return ← err .badCfg
  -- c) strictly ascending + unique by (header, backEdgeFrom) lexicographic.
  --   Compare adjacent pairs by (header, backEdgeFrom) lexicographic order;
  --   equal or out-of-order → `.badCfg`.
  let mut i : Nat := 0
  for lb in c.loopBounds do
    if i + 1 < c.loopBounds.size then
      match c.loopBounds[i + 1]? with
      | some next =>
          let ch := lb.header.toNat
          let cb := lb.backEdgeFrom.toNat
          let nh := next.header.toNat
          let nb := next.backEdgeFrom.toNat
          let ok := ch < nh || (ch == nh && cb < nb)
          unless ok do
            return ← err .badCfg
      | none => pure ()
    i := i + 1
  -- d) exact coverage. Build deduped actual back-edge pair list, then compare
  --   sizes and membership (blockCount is small; bounded Array membership).
  let actualAll := cfgBackEdges c.blocks blockCount
  let mut actual : Array (Nat × Nat) := #[]
  for p in actualAll do
    let key := (p.1.toNat, p.2.toNat)
    unless actual.any (· == key) do
      actual := actual.push key
  unless actual.size == c.loopBounds.size do
    return ← err .badCfg
  for lb in c.loopBounds do
    let key := (lb.header.toNat, lb.backEdgeFrom.toNat)
    unless actual.any (· == key) do
      return ← err .badCfg
  pure ()

/-! ### EffectId canonical assignment (SPEC §6 — CFG layer e.5)

    Within each callable, Emit/ExternalCall/Schedule instructions receive
    contiguous EffectIds 0..n-1 in BlockId/instruction order. Block IDs have
    already been checked against array index, so nested array traversal is the
    exact canonical order. IDs reset per callable. Any gap, duplicate, wrong
    start, or reordering fails `.badCfg`. Bounded, non-recursive, total. -/
/-- Internal WireV1-family phase entry (not a public contract; see `validateSemanticProgramStructureV1`). -/
def validateCallableEffectIds (c : CallableV1) :
    Except SemanticWireErrorV1 Unit := do
  let mut next : Nat := 0
  for b in c.blocks do
    for instr in b.instructions do
      let effectId? : Option EffectIdV1 :=
        match instr.op with
        | .emit effectId _ _ => some effectId
        | .externalCall effectId _ _ => some effectId
        | .schedule effectId _ _ => some effectId
        | _ => none
      match effectId? with
      | none => pure ()
      | some effectId =>
          unless effectId.toNat == next do return ← err .badCfg
          next := next + 1
  pure ()

/-! ### ValueId SSA definition-table + dominance-of-use (SPEC §6.2)

    Implements the 'each ValueId is defined exactly once' portion plus
    use-existence (every used ValueId has a def site) plus dominance-of-use
    (every use is in a block dominated by its def's block). All SSA-def-table
    and dominance failures use `.badCfg`. Bounded, non-recursive, total. -/

/-- Collect every ValueId definition site in the three global allocation
    passes required by SPEC §6: callable params first; then every block param
    in BlockId/array order; then every instruction result in
    BlockId/instruction order. This is deliberately not per-block
    param/result interleaving. CFG step b has already established
    `block.id == array index` before production consumes this order. Returns
    `(valueId, definingBlockId)` pairs. Bounded, non-recursive. -/
def collectValueDefSites (c : CallableV1) : Array (ValueIdV1 × BlockIdV1) :=
  Id.run do
    let mut sites : Array (ValueIdV1 × BlockIdV1) := #[]
    let entryBlock := c.entryBlock
    for p in c.params do
      sites := sites.push (p.valueId, entryBlock)
    for b in c.blocks do
      for bp in b.params do
        sites := sites.push (bp.valueId, b.id)
    for b in c.blocks do
      for instr in b.instructions do
        match instr.result with
        | some vdef => sites := sites.push (vdef.valueId, b.id)
        | none => pure ()
    pure sites

/-- Enforce canonical per-callable ValueId assignment over the exact
    `collectValueDefSites` traversal: encountered IDs are `0,1,...,n-1`.
    This single O(definitions)-time/O(1)-extra-space check subsumes duplicate,
    gap, wrong-start, and reordered-definition rejection. It does not claim
    whole-CFG validation is linear; later ValueId lookups retain their existing
    bounded complexity. Any mismatch → `.badCfg`. -/
def checkValueIdCanonicalAssignment
    (defSites : Array (ValueIdV1 × BlockIdV1)) :
    Except SemanticWireErrorV1 Unit := do
  let mut next : Nat := 0
  for (valueId, _) in defSites do
    unless valueId.toNat == next do
      return ← err .badCfg
    next := next + 1
  pure ()

/-- Every ValueId referenced by a `SemanticOpV1` (uses only; defs are owned by
    `collectValueDefSites`). Bounded, total. -/
def opValueUses (op : SemanticOpV1) : Array ValueIdV1 :=
  match op with
  | .literal _ _ | .constant _ | .stateLoad _ | .contextRead _ => #[]
  | .envRead _ args => args
  | .stateStore _ v => #[v]
  | .construct _ _ args => args
  | .fieldGet base _ => #[base]
  | .fieldSet base _ value => #[base, value]
  | .variantTag base => #[base]
  | .variantPayload base _ _ => #[base]
  | .indexGet base index => #[base, index]
  | .indexSet base index value => #[base, index, value]
  | .checkedCast value _ => #[value]
  | .unary _ operand => #[operand]
  | .binary _ lhs rhs => #[lhs, rhs]
  | .pureCall _ args => args
  | .commit value => #[value]
  | .assert_ cond _ args => #[cond] ++ args
  | .emit _ _ args => args
  | .externalCall _ _ args => args
  | .schedule _ _ args => args

/-- Every ValueId referenced by a `TerminatorV1` (condition / scrutinee /
    return / revert args / jump-target args). Leaf `trap` returns empty.
    Bounded, total. -/
def terminatorValueUses (term : TerminatorV1) : Array ValueIdV1 :=
  match term with
  | .jump target => target.args
  | .branch cond thenTarget elseTarget =>
      #[cond] ++ thenTarget.args ++ elseTarget.args
  | .switch scrut cases default =>
      let caseArgs := cases.flatMap (·.target.args)
      let defArgs := match default with
        | some t => t.args
        | none => #[]
      #[scrut] ++ caseArgs ++ defArgs
  | .return_ (some v) => #[v]
  | .return_ none => #[]
  | .revert _ args => args
  | .trap _ => #[]

/-- Check that every ValueId use (in ops and terminators) has a corresponding
    def site. Missing def → `.badCfg`. Bounded, total. -/
def checkValueIdUsesExist (c : CallableV1)
    (defSites : Array (ValueIdV1 × BlockIdV1)) :
    Except SemanticWireErrorV1 Unit := do
  let defIds : Array ValueIdV1 := defSites.map (·.1)
  let isDef (vid : ValueIdV1) : Bool := defIds.any (· == vid)
  for b in c.blocks do
    for instr in b.instructions do
      for use in opValueUses instr.op do
        unless isDef use do
          return ← err .badCfg
    for use in terminatorValueUses b.terminator do
      unless isDef use do
        return ← err .badCfg
  pure ()

/-- A canonical one-block callable whose sole operand-free instruction defines
    ValueId 0 and returns it passes the production use-existence scan. -/
theorem checkValueIdUsesExist_single_local_return_eq_ok
    (c : CallableV1) (instr : InstructionV1)
    (hblocks : c.blocks = #[{
      id := 0
      params := #[]
      instructions := #[instr]
      terminator := .return_ (some 0)
    }])
    (hopUses : opValueUses instr.op = #[]) :
    checkValueIdUsesExist c #[(0, 0)] = .ok () := by
  simp [checkValueIdUsesExist, hblocks, hopUses, terminatorValueUses,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

/-- Per-callable ValueId SSA def-table: canonical contiguous assignment plus
    use-existence. Builds `defSites` once via the SPEC §6 three-pass collector,
    validates `0..n-1`, then checks uses against the same array. Canonical
    assignment subsumes exactly-once. Dominance remains step g. -/
def validateCallableValueIdSsa (c : CallableV1) :
    Except SemanticWireErrorV1 Unit := do
  let defSites := collectValueDefSites c
  checkValueIdCanonicalAssignment defSites
  checkValueIdUsesExist c defSites

/-! ### Dominance-of-use (SPEC §6.2 — CFG layer g)

    A block D dominates block B iff every path from entry (block 0) to B
    passes through D. After step f (ValueId SSA def-table: exactly-once +
    use-existence), enforce that every ValueId USE is in a block dominated by
    the def's block. Failure → `.badCfg`. Bounded, non-recursive, total. -/

/-- For each block id b in [0, blockCount), the sorted-ascending unique list of
    predecessor block ids whose terminator lists b as an in-range successor
    (uses `terminatorSuccessors`). Bounded, non-recursive. -/
private def cfgPredecessors (blocks : Array BlockV1) (blockCount : Nat) :
    Array (Array Nat) := Id.run do
  let mut preds : Array (Array Nat) := Array.mk (List.replicate blockCount #[])
  let mut i : Nat := 0
  for b in blocks do
    for succ in terminatorSuccessors (BlockV1.terminator b) do
      let s := succ.toNat
      if s < blockCount then
        match preds[s]? with
        | some ps =>
            -- dedup + keep ascending (i is monotonically increasing, so a
            -- fresh predecessor is always larger than any already recorded;
            -- a single linear scan preserves uniqueness + ordering).
            unless ps.any (· == i) do
              preds := preds.set! s (ps.push i)
        | none => pure ()
    i := i + 1
  pure preds

/-- Iterative dataflow dominator computation. `dom[0] = {0}` if `reachable[0]`.
    For reachable b != 0: `dom[b]` initialized to all-true, then fixed-point
    `dom[b] = {b} ∪ (∩ over reachable preds p of dom[p])`. For unreachable b:
    `dom[b] = all-false`. Iterates up to `blockCount+1` passes or until stable.
    Bounded, non-recursive. -/
private def computeDominators (blocks : Array BlockV1) (blockCount : Nat)
    (reachable : Array Bool) : Array (Array Bool) := Id.run do
  -- The singleton fixed point is exactly the entry reachability bit. Keep
  -- this mathematically trivial case out of the general iterative pass.
  if blockCount == 1 then return #[#[reachable[0]!]]
  if blockCount == 0 then pure #[] else do
    let preds := cfgPredecessors blocks blockCount
    -- Initial dominator sets (each row is full blockCount-sized for uniform
    -- indexing in the fixed-point intersection).
    let allTrue : Array Bool := Array.mk (List.replicate blockCount true)
    let allFalse : Array Bool := Array.mk (List.replicate blockCount false)
    let entryDom : Array Bool := allFalse.set! 0 true
    let mut dom : Array (Array Bool) := Array.empty
    let mut j : Nat := 0
    for _ in [:blockCount] do
      if j == 0 then
        dom := dom.push (if reachable[0]! then entryDom else allFalse)
      else if reachable[j]! then
        dom := dom.push allTrue
      else
        dom := dom.push allFalse
      j := j + 1
    -- Fixed-point: at most blockCount+1 passes suffice for a finite graph.
    let mut fuel : Nat := blockCount + 1
    let mut stable : Bool := false
    while !stable && fuel > 0 do
      fuel := fuel - 1
      stable := true
      let mut b : Nat := 0
      while b < blockCount do
        if b == 0 then
          b := b + 1
        else if !reachable[b]! then
          b := b + 1
        else
          -- dom[b] := {b} ∪ (∩ over reachable preds p of dom[p])
          match preds[b]? with
          | some ps =>
              if ps.size == 0 then
                -- Reachable but no predecessors: only the entry can be so, and
                -- entry is handled above. Treat as no dominator info beyond
                -- self; keep all-false except self to force a use here to fail
                -- dominance (consistent with reachability already pinning
                -- entry==0). Set dom[b] = {b} only.
                let selfOnly := allFalse.set! b true
                unless dom[b]! == selfOnly do
                  dom := dom.set! b selfOnly
                  stable := false
              else
                let mut inter : Array Bool := allTrue
                for p in ps do
                  if reachable[p]! then
                    let dp := dom[p]!
                    let mut k : Nat := 0
                    let mut acc : Array Bool := Array.empty
                    for _ in [:blockCount] do
                      acc := acc.push (inter[k]! && dp[k]!)
                      k := k + 1
                    inter := acc
                let selfInter := inter.set! b true
                unless dom[b]! == selfInter do
                  dom := dom.set! b selfInter
                  stable := false
          | none => pure ()
          b := b + 1
    pure dom

private theorem computeDominators_singleton_unreachable_eq
    (blocks : Array BlockV1) :
    computeDominators blocks 1 #[false] = #[#[false]] := by
  simp [computeDominators]

/-- Check that every ValueId use (op uses + terminator uses) in each reachable
    block B is dominated by its def's block D. `defSites` is already
    exactly-once (step f), so a ValueId maps to a single def block. Missing
    def site is step f's responsibility (already caught); to stay total, treat
    a missing def as `.badCfg`. Requires `dom[B][D.toNat] == true` else
    `.badCfg`. Unreachable blocks are skipped (step d owns those). -/
private def checkDominanceOfUse (c : CallableV1)
    (defSites : Array (ValueIdV1 × BlockIdV1))
    (dom : Array (Array Bool)) (reachable : Array Bool) :
    Except SemanticWireErrorV1 Unit := do
  let blockCount := c.blocks.size
  -- Bounded ValueId→defBlockId lookup (defSites is exactly-once by step f).
  let defBlock (vid : ValueIdV1) : Option BlockIdV1 := Id.run do
    let mut r : Option BlockIdV1 := none
    for (v, b) in defSites do
      if v == vid then
        r := some b
        break
    pure r
  let mut b : Nat := 0
  for blk in c.blocks do
    if reachable[b]! then
      -- op uses
      for instr in blk.instructions do
        for use in opValueUses instr.op do
          match defBlock use with
          | none => return ← err .badCfg
          | some d =>
              let dn := d.toNat
              unless dn < blockCount do
                return ← err .badCfg
              match dom[b]? with
              | some row =>
                  unless row[dn]! do
                    return ← err .badCfg
              | none => return ← err .badCfg
      -- terminator uses
      for use in terminatorValueUses blk.terminator do
        match defBlock use with
        | none => return ← err .badCfg
        | some d =>
            let dn := d.toNat
            unless dn < blockCount do
              return ← err .badCfg
            match dom[b]? with
            | some row =>
                unless row[dn]! do
                  return ← err .badCfg
            | none => return ← err .badCfg
    b := b + 1
  pure ()

/-- Per-callable dominance-of-use: compute predecessors + dominators from the
    reachability array (already produced by step d), then check every use is
    dominated by its def's block. Failure → `.badCfg`. -/
def validateCallableDominanceOfUse (c : CallableV1)
    (defSites : Array (ValueIdV1 × BlockIdV1)) (reachable : Array Bool) :
    Except SemanticWireErrorV1 Unit := do
  let blockCount := c.blocks.size
  let dom := computeDominators c.blocks blockCount reachable
  checkDominanceOfUse c defSites dom reachable

/-- A canonical one-block callable whose sole instruction has no operands and
    whose return uses its sole local definition satisfies the production
    dominator/checker path. -/
theorem validateCallableDominanceOfUse_single_local_return_eq_ok
    (c : CallableV1) (instr : InstructionV1)
    (hblocks : c.blocks = #[{
      id := 0
      params := #[]
      instructions := #[instr]
      terminator := .return_ (some 0)
    }])
    (hopUses : opValueUses instr.op = #[]) :
    validateCallableDominanceOfUse c #[(0, 0)] #[true] = .ok () := by
  simp [validateCallableDominanceOfUse, computeDominators, checkDominanceOfUse,
    hblocks, hopUses, terminatorValueUses, Id.run, Pure.pure,
    Except.pure, Bind.bind, Except.bind]

end ProofForgeV2.Semantic.WireV1
