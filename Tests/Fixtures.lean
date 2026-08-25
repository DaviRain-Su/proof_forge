import Examples.Counter

namespace Tests.Fixtures

/-- 负向：入口类型带 `Nat`。 -/
def usesNat (n : Nat) : Nat := n + 1

/-- 负向：partial。 -/
partial def loops (n : UInt64) : UInt64 :=
  loops n

/-- 负向：sorry。 -/
def usesSorry (s : Examples.Counter.State) : UInt64 :=
  sorry

/-- 负向：IO。 -/
def usesIO : IO Unit :=
  pure ()

/-- 负向：extern（无实现，只为属性门）。 -/
@[extern "solana_lean_fixture_extern"]
opaque usesExtern : UInt64 → UInt64

/-- 负向：implemented_by 指向 unsafe。 -/
unsafe def usesImplByImpl (x : UInt64) : UInt64 := x

@[implemented_by usesImplByImpl]
def usesImplBy (x : UInt64) : UInt64 := x

/-- 负向：无保护加法，不能抽出 checkedAdd。 -/
def wrappingAdd (s : Examples.Counter.State) (delta : UInt64) :
    Except Examples.Counter.Error (Examples.Counter.State × UInt64) :=
  let next := s.value + delta
  .ok ({ value := next }, next)

def wrappingSub (s : Examples.Counter.State) (delta : UInt64) :
    Except Examples.Counter.Error (Examples.Counter.State × UInt64) :=
  let next := s.value - delta
  .ok ({ value := next }, next)

def wrappingMul (s : Examples.Counter.State) (factor : UInt64) :
    Except Examples.Counter.Error (Examples.Counter.State × UInt64) :=
  let next := s.value * factor
  .ok ({ value := next }, next)

/-- Negative: an unknown CPI result must not be silently modeled as zero. -/
def unknownCpiResult (_s : Examples.Counter.State) :
    Except Examples.Counter.Error (Examples.Counter.State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    let result := ProofForge.Svm.Runtime.invoke 1 #[] #[.u8le 99]
    .ok ({ value := result }, result)
  else
    .error .overflow

/-- Two independently indexed Token CPIs followed by a real state transition. The second call
uses the common `[literal, state key, account key, bump]` PDA authority shape. -/
def multiSeedTransfer (_s : Examples.Counter.State) (amount : UInt64) :
    Except Examples.Counter.Error (Examples.Counter.State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    let _ := ProofForge.Svm.Runtime.tokenTransferCheckedIx 8 1 3 5 0 amount 6
    let seeds : Array ProofForge.Svm.Runtime.PdaSeed :=
      #[.ascii "vault", .stateKey, .accKey 3]
    let _ := ProofForge.Svm.Runtime.tokenTransferCheckedSignedIx
      8 5 3 1 7 amount 6 seeds (ProofForge.Svm.Runtime.findPdaSeeds seeds)
    .ok ({ value := amount }, amount)
  else
    .error .overflow

/-- One ignored unsigned CPI must preserve the following state transition. -/
def singleInvokeTransfer (_s : Examples.Counter.State) (amount : UInt64) :
    Except Examples.Counter.Error (Examples.Counter.State × UInt64) :=
  let _ := ProofForge.Svm.Runtime.tokenTransferCheckedIx 8 1 3 5 0 amount 6
  .ok ({ value := amount }, amount)

/-- A statically indexed TransferChecked wrapper models its source-level amount even when the
wrapper result is consumed; the external token-program position is not fixed to account 4. -/
def indexedTransferResult (_s : Examples.Counter.State) (amount : UInt64) :
    Except Examples.Counter.Error (Examples.Counter.State × UInt64) :=
  let result := ProofForge.Svm.Runtime.tokenTransferCheckedIx 8 1 3 5 0 amount 6
  .ok ({ value := result }, result)

/-- One heterogeneous signed CPI must preserve the state transition after its ignored result. -/
def singleMultiSeedTransfer (_s : Examples.Counter.State) (amount : UInt64) :
    Except Examples.Counter.Error (Examples.Counter.State × UInt64) :=
  let seeds : Array ProofForge.Svm.Runtime.PdaSeed :=
    #[.ascii "vault", .stateKey, .accKey 3]
  let _ := ProofForge.Svm.Runtime.tokenTransferCheckedSignedIx
    8 5 3 1 7 amount 6 seeds (ProofForge.Svm.Runtime.findPdaSeeds seeds)
  .ok ({ value := amount }, amount)

/-- Dynamic integer CPI words are serialized at their exact Borsh widths without changing the
contract's scalar `UInt64` model. -/
def dynamicCpiWords (_s : Examples.Counter.State) (value : UInt64) :
    Except Examples.Counter.Error (Examples.Counter.State × UInt64) :=
  let _ := ProofForge.Svm.Runtime.invoke 1 #[]
    #[.u8le value, .u16le value, .u32le value, .u64le value]
  .ok ({ value }, value)

/-- Full-key canonical PDA check for a statically indexed external account. -/
def checkMultiSeedPda (_s : Examples.Counter.State) : UInt64 :=
  let seeds : Array ProofForge.Svm.Runtime.PdaSeed :=
    #[.ascii "vault", .stateKey, .accKey 3]
  ProofForge.Svm.Runtime.checkPdaSeeds 5 seeds

/-- 负向：state 含 Float，不是支持的叶子。 -/
structure FlagState where
  value : UInt64
  flag : Float
  deriving Repr, Inhabited

def initFlag (initial : UInt64) : FlagState :=
  { value := initial, flag := 0 }

/-- 负向：不定长 Array，不是 Vector。 -/
structure BagState where
  items : Array UInt64
  deriving Repr

def initBag (_seed : UInt64) : BagState :=
  { items := #[] }

def getBagHead (_s : BagState) : UInt64 :=
  0

def setBagHead (s : BagState) (n : UInt64) :
    Except Examples.Counter.Error (BagState × UInt64) :=
  .ok ({ items := #[n] }, n)

/-- Narrow vector leaves exercise physical indexed loads and stores in both backends. -/
structure NarrowState where
  cells : Vector UInt8 2
  deriving Repr, DecidableEq

def initNarrow (initial : UInt8) : NarrowState :=
  { cells := #v[initial, 0] }

def setNarrow (s : NarrowState) (i : UInt64) (value : UInt8) :
    Except Examples.Counter.Error (NarrowState × UInt64) :=
  if h : i.toNat < 2 then
    .ok ({ cells := s.cells.set i.toNat value }, value.toUInt64)
  else
    .error .overflow

def getNarrow (s : NarrowState) (i : UInt64) : UInt64 :=
  if i < 2 then s.cells[i.toNat]!.toUInt64 else 0

/-- `Nat.sub` saturates: index zero stays zero instead of wrapping to `UInt64.max`. -/
def getNarrowPrevious (s : NarrowState) (i : UInt64) : UInt64 :=
  s.cells[(i.toNat - 1) % 2]!.toUInt64

/-- Adversarial vector-element layout: familiar tree field names deliberately have noncanonical
byte offsets, so extraction must use the typed schema rather than names. -/
structure LayoutNode where
  marker : UInt64
  left : UInt64
  color : UInt64
  deriving Repr, DecidableEq, Inhabited

structure LayoutState where
  entries : Vector LayoutNode 2
  count : UInt64
  deriving Repr, DecidableEq

def emptyLayoutNode : LayoutNode :=
  { marker := 0, left := 0, color := 0 }

def initLayout (_seed : UInt64) : LayoutState :=
  { entries := #v[emptyLayoutNode, emptyLayoutNode], count := 0 }

def setLayout (s : LayoutState) (i value : UInt64) :
    Except Examples.Counter.Error (LayoutState × UInt64) :=
  if h : i.toNat < 2 then
    .ok ({ s with entries := s.entries.set i.toNat {
      s.entries[i.toNat]! with left := value, color := 1 } }, value)
  else
    .error .overflow

def getLayout (s : LayoutState) (i : UInt64) : UInt64 :=
  if i < 2 then s.entries[i.toNat]!.left else 0

/-- Nested vector owners retain their complete flattened schema path for dynamic reads and writes. -/
structure NestedVectorBook where
  root : UInt64
  right : Vector UInt64 2
  deriving Repr, DecidableEq

structure NestedVectorState where
  tag : UInt64
  book : NestedVectorBook
  deriving Repr, DecidableEq

def initNestedVector (_seed : UInt64) : NestedVectorState :=
  { tag := 0, book := { root := 0, right := #v[0, 0] } }

def setNestedVector (s : NestedVectorState) (i value : UInt64) :
    Except Examples.Counter.Error (NestedVectorState × UInt64) :=
  if h : i.toNat < 2 then
    .ok ({ s with book := { s.book with right := s.book.right.set i.toNat value } }, value)
  else
    .error .overflow

def getNestedVector (s : NestedVectorState) (i : UInt64) : UInt64 :=
  if i < 2 then s.book.right[i.toNat]! else 0

def stageNestedOuter (s : NestedVectorState) (value : UInt64) : NestedVectorState :=
  { s with tag := value }

def stageNestedBook (book : NestedVectorBook) (i value : UInt64) : NestedVectorBook :=
  if h : i.toNat < 2 then
    { book with root := value, right := book.right.set i.toNat value }
  else book

def stageNestedState (s : NestedVectorState) (i value : UInt64) : NestedVectorState :=
  let outer := stageNestedOuter s value
  { outer with book := stageNestedBook outer.book i outer.tag }

attribute [pf_inline] stageNestedOuter stageNestedBook stageNestedState

/-- A nested helper may consume a scalar from an already-applied outer transition. The outer
write must stay root-qualified while the nested helper's fields use their complete schema path. -/
def setStagedNestedVector (s : NestedVectorState) (i value : UInt64) :
    Except Examples.Counter.Error (NestedVectorState × UInt64) :=
  .ok (stageNestedState s i value, value)

/-- 正向：单构造子、单个 `UInt64` payload 是无 tag 的 representational newtype。 -/
inductive Tagged where
  | wrap (n : UInt64)
  deriving Repr

structure TaggedState where
  tag : Tagged
  deriving Repr

def initTagged (n : UInt64) : TaggedState :=
  { tag := .wrap n }

def getTagged (s : TaggedState) : UInt64 :=
  match s.tag with
  | .wrap n => n

def setTagged (s : TaggedState) (n : UInt64) :
    Except Examples.Counter.Error (TaggedState × UInt64) :=
  .ok ({ tag := .wrap n }, n)

/-- Fixed-layout tagged union: one discriminant slot plus one shared `UInt64` payload slot. -/
inductive Event where
  | idle
  | fill (n : UInt64)
  | cancel (n : UInt64)
  deriving Repr

structure EventState where
  event : Event
  deriving Repr

def initEvent (n : UInt64) : EventState :=
  { event := .fill n }

def setEventCancel (_s : EventState) (n : UInt64) :
    Except Examples.Counter.Error (EventState × UInt64) :=
  .ok ({ event := .cancel n }, n)

def getEvent (s : EventState) : UInt64 :=
  match s.event with
  | .idle => 0
  | .fill n => n
  | .cancel n => n

/-- Bounded analogue of Phoenix's internal event union, with a shared five-word payload. -/
inductive MarketEvent where
  | uninitialized
  | fill (maker sequence price filled remaining : UInt64)
  | place (sequence client price size : UInt64)
  | fee (amount : UInt64)
  deriving Repr, Inhabited

structure MarketEventState where
  marketEvent : MarketEvent
  deriving Repr

def initMarketEvent (maker sequence price filled remaining : UInt64) : MarketEventState :=
  { marketEvent := .fill maker sequence price filled remaining }

def setMarketFee (_s : MarketEventState) (amount : UInt64) :
    Except Examples.Counter.Error (MarketEventState × UInt64) :=
  .ok ({ marketEvent := .fee amount }, amount)

def marketEventValue (s : MarketEventState) : UInt64 :=
  match s.marketEvent with
  | .uninitialized => 0
  | .fill maker sequence price filled remaining =>
      maker + sequence + price + filled + remaining
  | .place sequence client price size => sequence + client + price + size
  | .fee amount => amount

/-- Fixed-capacity event storage exercises dynamic writes of a multi-leaf variant element. -/
structure MarketEventBatchState where
  events : Vector MarketEvent 4
  eventCount : UInt64
  lastEvent : MarketEvent
  deriving Repr

def initMarketEventBatch (_seed : UInt64) : MarketEventBatchState :=
  { events := #v[.uninitialized, .uninitialized, .uninitialized, .uninitialized]
    eventCount := 0
    lastEvent := .uninitialized }

def setMarketEventAt (s : MarketEventBatchState)
    (i maker sequence price filled remaining : UInt64) :
    Except Examples.Counter.Error (MarketEventBatchState × UInt64) :=
  if h : i.toNat < 4 then
    .ok ({ s with
      events := s.events.set i.toNat (.fill maker sequence price filled remaining) }, filled)
  else
    .error .overflow

/-- Dynamic vector writes must preserve an explicit return distinct from every payload leaf. -/
def setMarketEventReturningIndex (s : MarketEventBatchState)
    (i maker sequence price filled remaining : UInt64) :
    Except Examples.Counter.Error (MarketEventBatchState × UInt64) :=
  if h : i.toNat < 4 then
    .ok ({ s with
      events := s.events.set i.toNat (.fill maker sequence price filled remaining) }, i)
  else
    .error .overflow

/-- A root State-returning helper must retain both its dynamic variant write and scalar update. -/
private def appendMarketEvent (s : MarketEventBatchState) (event : MarketEvent) :
    MarketEventBatchState :=
  if h : s.eventCount.toNat < 4 then
    { s with
      events := s.events.set s.eventCount.toNat event
      eventCount := s.eventCount + 1
      lastEvent := event }
  else
    s

attribute [pf_inline] appendMarketEvent

private def activeMarketSeat (s : MarketEventBatchState) (address : UInt64) : Bool :=
  if address = 0 || 4 < address then false else s.eventCount ≠ 0

private def marketMaker (s : MarketEventBatchState) (address : UInt64) : UInt64 :=
  if activeMarketSeat s address then s.eventCount else address

attribute [pf_inline] activeMarketSeat marketMaker

def appendMarketEventInFold (s : MarketEventBatchState)
    (maker sequence price filled remaining : UInt64) :
    Except Examples.Counter.Error (MarketEventBatchState × UInt64) := Id.run do
  let mut st := s
  for _ in [:1] do
    let staged := { st with eventCount := st.eventCount + 1 }
    st := appendMarketEvent st
      (.fill (marketMaker st maker) staged.eventCount price filled remaining)
  .ok (st, st.eventCount)

def firstMarketEventValue (s : MarketEventBatchState) : UInt64 :=
  match s.events[0]! with
  | .uninitialized => 0
  | .fill maker sequence price filled remaining =>
      maker + sequence + price + filled + remaining
  | .place sequence client price size => sequence + client + price + size
  | .fee amount => amount

def getFlagValue (s : FlagState) : UInt64 :=
  s.value

def creditFlag (s : FlagState) (delta : UInt64) :
    Except Examples.Counter.Error (FlagState × UInt64) :=
  if s.value ≤ Examples.Counter.u64Max - delta then
    let next := s.value + delta
    .ok ({ value := next, flag := s.flag }, next)
  else
    .error .overflow

/-- 正向：target-neutral value arithmetic inside a state-carrying bounded fold. -/
structure FoldState where
  product : UInt64
  quotient : UInt64
  remainder : UInt64
  deriving Repr, DecidableEq

def initFold (_seed : UInt64) : FoldState :=
  { product := 0, quotient := 0, remainder := 0 }

def runFold (s : FoldState) (lhs rhs : UInt64) :
    Except Examples.Counter.Error (FoldState × UInt64) := Id.run do
  let mut st := s
  for i in [:2] do
    if i = 0 then
      st := { st with product := lhs * rhs }
    else
      st := { st with quotient := lhs / rhs, remainder := lhs % rhs }
  .ok (st, st.product)

/-- A state-carrying loop must preserve the explicit mutable accumulator initializer. -/
def runInitializedFold (s : FoldState) (lhs : UInt64) :
    Except Examples.Counter.Error (FoldState × UInt64) := Id.run do
  let mut st := { s with product := lhs }
  for _ in [:1] do
    st := { st with remainder := lhs }
  .ok (st, st.product)

/-- An ignored CPI inside a state-carrying loop must remain ordered before that iteration's write. -/
def runInvokeFold (s : FoldState) (value : UInt64) :
    Except Examples.Counter.Error (FoldState × UInt64) := Id.run do
  let mut st := s
  for i in [:2] do
    if i = 0 then
      let _ := ProofForge.Svm.Runtime.invoke 1 #[] #[.u64le value]
      st := { st with product := value }
  .ok (st, st.product)

/-- A state-field snapshot captured before a CPI must not be reloaded after the state write. -/
def runInvokeSnapshot (s : FoldState) :
    Except Examples.Counter.Error (FoldState × UInt64) :=
  let before := s.product
  let _ := ProofForge.Svm.Runtime.invoke 1 #[] #[.u64le before]
  .ok ({ s with product := 0 }, before)

def foldProduct (s : FoldState) : UInt64 :=
  s.product

/--
A state loop nested under an entry guard must stay in that branch. The intentionally deep value
expression also ensures every vector read derived from the callback index becomes `loopIx` without
rewriting captured method parameters.
-/
structure GuardedLoopState where
  cells : Vector UInt64 4
  selected : UInt64
  deriving Repr, DecidableEq

def initGuardedLoop (_seed : UInt64) : GuardedLoopState :=
  { cells := #v[0, 0, 0, 0], selected := 0 }

private def resetGuardedLoop (s : GuardedLoopState) : GuardedLoopState :=
  { s with selected := 0 }

attribute [pf_inline] resetGuardedLoop

def runGuardedLoop (s : GuardedLoopState) (needle qty replacement : UInt64) :
    Except Examples.Counter.Error (GuardedLoopState × UInt64) :=
  let s := resetGuardedLoop s
  if qty = 0 then
    .ok (s, 0)
  else Id.run do
    let mut st := s
    for i in [0:4] do
      if st.selected = 0 then
        let j : Nat := i
        let current := st.cells[j]!
        if current = needle then
          let mixed := current ^^^ replacement ^^^ 1 ^^^ 2 ^^^ 3 ^^^ 4 ^^^ 5 ^^^ 6 ^^^ 7
          st := { st with cells := st.cells.set (j % 4) mixed, selected := current }
    .ok (st, st.selected)

def guardedLoopSelected (s : GuardedLoopState) : UInt64 :=
  s.selected

/-- A State-returning inline helper used before another update in the same loop iteration. -/
private def stageFold (s : FoldState) (delta : UInt64) : FoldState :=
  if delta < 10 then { s with product := s.product + delta }
  else { s with quotient := delta }

attribute [pf_inline] stageFold

/--
Lean represents the second assignment as projections from `stageFold`; extraction must keep
the helper transition before the outer `remainder` write instead of silently dropping it.
-/
def runComposedFold (s : FoldState) (delta : UInt64) :
    Except Examples.Counter.Error (FoldState × UInt64) := Id.run do
  let mut st := s
  for _ in [:1] do
    st := stageFold st delta
    st := { st with remainder := delta }
  .ok (st, st.product)

/-- A second inline helper wrapping a composed update must not replay the first helper. -/
private def finishFoldStage (s : FoldState) : FoldState :=
  if s.remainder < 100 then { s with quotient := s.quotient + 1 } else s

attribute [pf_inline] finishFoldStage

def runNestedComposedFold (s : FoldState) (delta : UInt64) :
    Except Examples.Counter.Error (FoldState × UInt64) := Id.run do
  let mut st := s
  for _ in [:1] do
    st := stageFold st delta
    let staged := { st with remainder := delta }
    st := finishFoldStage staged
  .ok (st, st.product)

/-- Minimal topology state for a helper sequenced after a mutable walk. -/
structure PostLoopTopologyState where
  nodes : Vector UInt64 2
  root : UInt64
  count : UInt64
  cursor : UInt64
  deriving Repr, DecidableEq

def initPostLoopTopology (_seed : UInt64) : PostLoopTopologyState :=
  { nodes := #v[0, 0], root := 0, count := 0, cursor := 0 }

private def topologyKeyBeforeAt (s : PostLoopTopologyState) (key address : UInt64) : Bool :=
  let i := (address.toNat - 1) % 2
  key < s.nodes[i]!

private def insertPostLoopTopology
    (s : PostLoopTopologyState) (key address : UInt64) : PostLoopTopologyState :=
  let i := (address.toNat - 1) % 2
  let linked := if s.root = 0 then { s with root := address } else s
  if s.root = 0 then
    { linked with nodes := linked.nodes.set i key }
  else if topologyKeyBeforeAt s key s.root then
    { linked with nodes := linked.nodes.set i key }
  else
    { linked with nodes := linked.nodes.set i (key + 1) }

attribute [pf_inline] topologyKeyBeforeAt insertPostLoopTopology

/--
The loop continuation must sequence the marked topology helper and then retain the scalar
allocation update. In particular, it must not collapse to the pair's return value.
-/
def runPostLoopTopology (s : PostLoopTopologyState) (key : UInt64) :
    Except Examples.Counter.Error (PostLoopTopologyState × UInt64) := Id.run do
  let mut st := { s with cursor := s.root }
  for _ in [:1] do
    if st.cursor ≠ 0 then
      st := { st with cursor := 0 }
  let address := st.count + 1
  let allocated := { st with count := address }
  let topology := insertPostLoopTopology st key address
  .ok ({ allocated with root := topology.root, nodes := topology.nodes }, key)

def postLoopTopologyRoot (s : PostLoopTopologyState) : UInt64 :=
  s.root

/-- Checked continuations preserve an explicit scalar snapshot across state writeback. -/
structure SnapshotState where
  total : UInt64
  pending : UInt64
  last : UInt64
  deriving Repr, DecidableEq

def initSnapshot (_seed : UInt64) : SnapshotState :=
  { total := 0, pending := 0, last := 0 }

private def settleSnapshot (s : SnapshotState) (amount : UInt64) : SnapshotState :=
  { s with total := s.total + amount, pending := 0, last := amount }

attribute [pf_inline] settleSnapshot

def collectSnapshot (s : SnapshotState) :
    Except Examples.Counter.Error (SnapshotState × UInt64) :=
  if s.total ≤ Examples.Counter.u64Max - s.pending then
    let amount := s.pending
    .ok (settleSnapshot s amount, amount)
  else
    .error .overflow

def snapshotTotal (s : SnapshotState) : UInt64 :=
  s.total

/-- Pure conditional values stay shared instead of duplicating the mutation continuation. -/
structure ChoiceState where
  chosen : UInt64
  deriving Repr, DecidableEq

def initChoice (_seed : UInt64) : ChoiceState :=
  { chosen := 0 }

def choose (s : ChoiceState) (lhs rhs : UInt64) :
    Except Examples.Counter.Error (ChoiceState × UInt64) :=
  let chosen : UInt64 := if lhs < rhs then lhs else rhs
  .ok ({ s with chosen }, chosen)

def getChosen (s : ChoiceState) : UInt64 :=
  s.chosen

/-- A fallible scalar producer with two successful paths and one terminal error. -/
private def chooseBelow (lhs rhs limit : UInt64) : Except Examples.Counter.Error UInt64 :=
  if lhs < limit then .ok lhs
  else if rhs < limit then .ok rhs
  else .error .overflow

attribute [pf_inline] chooseBelow

/-- The successful producer value must join before this mutation continuation. -/
def bindChoice (s : ChoiceState) (lhs rhs limit delta : UInt64) :
    Except Examples.Counter.Error (ChoiceState × UInt64) := do
  let chosen ← chooseBelow lhs rhs limit
  if chosen ≤ Examples.Counter.u64Max - delta then
    let total := chosen + delta
    .ok ({ s with chosen := total }, total)
  else
    .error .overflow

/-- Compound Boolean guards must retain every comparison when the else branch is an error. -/
def compoundChoice (s : ChoiceState) (a b c d e : UInt64) :
    Except Examples.Counter.Error (ChoiceState × UInt64) :=
  if a = b && b = c && c = d && d = e then
    .ok ({ s with chosen := a }, a)
  else
    .error .overflow

end Tests.Fixtures
