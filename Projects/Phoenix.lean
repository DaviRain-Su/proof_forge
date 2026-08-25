import ProofForge

/-!
Phoenix v1 `src/state` 在本仓剖面下的摊平。

官方 `FIFOMarket` 是三棵红黑树 + 泛型 trader key。抽出器不认不定长树，
所以这里把官方 *记录* 摊成平行 `UInt64` 向量，并为三棵树持久化 bounded N=4 拓扑：

  FIFOOrderId          → priceTicks / sequences
  FIFORestingOrder     → traders / sizes / lastSlots / lastTimes
  TraderState          → traderQuoteLocked / traderQuoteFree / traderBaseLocked / traderBaseFree
  MatchingEngineResponse → match*（bounded fold scratch）
  MarketEvent          → events（固定容量 batch）+ lastEvent（兼容投影）
  OrderPacket.client_order_id → little-endian UInt64 × UInt64
  traders tree         → 4×Pubkey limbs + allocator metadata + persisted links/colors + per-seat TraderState

每边 N=4。ask 中序按价格升序、bid 中序按价格降序，同价均为 FIFO；payload 的
1-based 物理地址在删除前保持稳定。bid/ask 和 trader registry 都持久化 root、
left/right/parent、color、allocator 与 free-list。free-funds 挂单、驱逐、按 ID reduce/cancel、
三种 self-trade 和 fee collection 已进入 bounded 模型。trader registry 保留
Sokoban 的 1-based address、bump 分配与 LIFO free-list；withdraw 和 zero-state
seat eviction 已接入，订单仍只存内部 address。
-/
namespace Projects.Phoenix

open ProofForge.Svm.Runtime

/-- 官方 `Side`。 -/
inductive Side where
  | bid
  | ask
  deriving Repr, DecidableEq, Inhabited, BEq

/-- 官方 `SelfTradeBehavior`；链上 ABI 用 0/1/2 编码。 -/
inductive SelfTradeBehavior where
  | abort
  | cancelProvide
  | decrementTake
  deriving Repr, DecidableEq, Inhabited, BEq

/--
官方 `PhoenixMarketEvent` 的 bounded typed 形状。`header` 只保留 Borsh ordinal 1；
真实 `AuditLogHeader` 是 recorder 的独立 batch prefix，不写进本向量。maker-bearing
event 在构造前把内部 seat resolve 成四 limb Pubkey。官方 u16 event index 在这里以
UInt64 保存，但 `appendEvent` 在第 6 条时 fail-closed；wire adapter 再收窄成 little-endian u16。
-/
inductive MarketEvent where
  | uninitialized
  | header
  | fill (index maker0 maker1 maker2 maker3 orderSequence price filled remaining : UInt64)
  /-- `clientOrderIdLo` then `clientOrderIdHi` is the little-endian two-limb form of Phoenix's u128. -/
  | place (index orderSequence clientOrderIdLo clientOrderIdHi price placed : UInt64)
  | reduce (index orderSequence price removed remaining : UInt64)
  | evict (index maker0 maker1 maker2 maker3 orderSequence price evicted : UInt64)
  | fillSummary (index clientOrderIdLo clientOrderIdHi totalBase totalQuote totalFee : UInt64)
  | fee (index feesCollected : UInt64)
  | timeInForce (index orderSequence lastValidSlot lastValidTime : UInt64)
  | expiredOrder (index maker0 maker1 maker2 maker3 orderSequence price removed : UInt64)
  deriving Repr, DecidableEq, Inhabited

/--
One bounded Sokoban allocator and red-black topology. Payload remains in the side-specific parallel
vectors below; every address is 1-based and stable until removal, while 0 is the black sentinel.
-/
structure BookTree4 where
  root : UInt64
  count : UInt64
  bumpIndex : UInt64
  freeHead : UInt64
  nextFree : Vector UInt64 4
  left : Vector UInt64 4
  right : Vector UInt64 4
  parent : Vector UInt64 4
  color : Vector UInt64 4
  deriving Repr, DecidableEq, Inhabited

def emptyBookTree : BookTree4 :=
  { root := 0, count := 0, bumpIndex := 1, freeHead := 1
    nextFree := #v[0, 0, 0, 0]
    left := #v[0, 0, 0, 0]
    right := #v[0, 0, 0, 0]
    parent := #v[0, 0, 0, 0]
    color := #v[0, 0, 0, 0] }

/--
摊平后的账户状态。字段名跟官方记录对齐，不是自己发明的 6 槽。

`_padding` 官方 32×u64，这里不存。
`collectedQuoteLotFees` / `unclaimedQuoteLotFees` 官方是 QuoteLots。
TIF 哨兵：`lastSlots[i] = 0` / `lastTimes[i] = 0` 表示不过期。
-/
structure State where
  baseLotsPerBaseUnit : UInt64
  tickSize : UInt64
  sequence : UInt64
  takerFeeBps : UInt64
  collectedFees : UInt64
  unclaimedFees : UInt64
  priceTicks : Vector UInt64 4
  sequences : Vector UInt64 4
  traders : Vector UInt64 4
  sizes : Vector UInt64 4
  lastSlots : Vector UInt64 4
  lastTimes : Vector UInt64 4
  bidPriceTicks : Vector UInt64 4
  bidSequences : Vector UInt64 4
  bidTraders : Vector UInt64 4
  bidSizes : Vector UInt64 4
  bidLastSlots : Vector UInt64 4
  bidLastTimes : Vector UInt64 4
  /-- Persisted allocator/topology for the ask and bid order trees. -/
  askBook : BookTree4
  bidBook : BookTree4
  /--
  官方 traders 红黑树的 bounded allocator。address 0 是 sentinel，1..4 是 seat；
  `traderFreeHead = traderBumpIndex` 表示从 bump 区分配，否则弹 LIFO free-list。
  -/
  traderCount : UInt64
  traderBumpIndex : UInt64
  traderFreeHead : UInt64
  traderNextFree : Vector UInt64 4
  /-- Persisted Sokoban red-black topology for the four trader seats. -/
  traderRoot : UInt64
  traderLeft : Vector UInt64 4
  traderRight : Vector UInt64 4
  traderParent : Vector UInt64 4
  traderColor : Vector UInt64 4
  traderUsed : Vector UInt64 4
  /-- Solana Pubkey 的四个 little-endian UInt64 limbs，按 seat 平行存放。 -/
  traderKey0 : Vector UInt64 4
  traderKey1 : Vector UInt64 4
  traderKey2 : Vector UInt64 4
  traderKey3 : Vector UInt64 4
  /-- 官方 `TraderState`；每个余额都按内部 seat address 索引。 -/
  traderQuoteLocked : Vector UInt64 4
  traderQuoteFree : Vector UInt64 4
  traderBaseLocked : Vector UInt64 4
  traderBaseFree : Vector UInt64 4
  /-- 旧撮合路径保留的 market-wide 兼容投影；接入 per-seat 结算后再删。 -/
  quoteLocked : UInt64
  quoteFree : UInt64
  baseLocked : UInt64
  baseFree : UInt64
  /-- 最近一次 IOC 的瞬时响应；入口开始时清零，循环体用作有界 fold accumulator。 -/
  matchFilled : UInt64
  matchQuote : UInt64
  matchMakerQuote : UInt64
  matchExpired : UInt64
  matchStopped : UInt64
  matchError : UInt64
  matchLevel : UInt64
  matchWant : UInt64
  matchLimit : UInt64
  /-- 当前 instruction 的 fixed-capacity event batch；`eventCount` 之前的元素有效。 -/
  events : Vector MarketEvent 5
  eventCount : UInt64
  /-- 最近一个 bounded market event，保留为事件 batch 的兼容投影。 -/
  lastEvent : MarketEvent
  deriving Repr, DecidableEq

inductive Error where
  | overflow
  | unauthorized
  | full
  | selfTrade
  deriving Repr, DecidableEq, Inhabited, BEq

/-- Fold / state-machine error codes. `0` is success. -/
def matchOverflow : UInt64 := 1
def matchFull : UInt64 := 2
def matchSelfTrade : UInt64 := 3
def matchUnauthorized : UInt64 := 4

private def errorOfMatch (code : UInt64) : Error :=
  if code = matchFull then .full
  else if code = matchSelfTrade then .selfTrade
  else if code = matchUnauthorized then .unauthorized
  else .overflow

/-- Extractable: the extractor only lowers concrete `.error .ctor` leaves. -/
private def throwMatch (code : UInt64) : Except Error (State × UInt64) :=
  if code = matchFull then .error .full
  else if code = matchSelfTrade then .error .selfTrade
  else if code = matchUnauthorized then .error .unauthorized
  else .error .overflow

def u64Max : UInt64 := ~~~(0 : UInt64)

def empty4 : Vector UInt64 4 := #v[0, 0, 0, 0]

def emptyEvents : Vector MarketEvent 5 :=
  #v[.uninitialized, .uninitialized, .uninitialized, .uninitialized, .uninitialized]

/-- 每个 instruction 覆盖上一批事件；旧 payload 无需清零，`eventCount` 决定有效前缀。 -/
private def beginEvents (s : State) : State :=
  { s with eventCount := 0, lastEvent := .uninitialized }

/-- Host accumulator 在保存前按 instruction 内顺序覆盖每个 wire event 的 u16 index。 -/
private def MarketEvent.withIndex (event : MarketEvent) (index : UInt64) : MarketEvent :=
  match event with
  | .uninitialized => .uninitialized
  | .header => .header
  | .fill _ maker0 maker1 maker2 maker3 sequence price filled remaining =>
      .fill index maker0 maker1 maker2 maker3 sequence price filled remaining
  | .place _ sequence clientLo clientHi price placed =>
      .place index sequence clientLo clientHi price placed
  | .reduce _ sequence price removed remaining =>
      .reduce index sequence price removed remaining
  | .evict _ maker0 maker1 maker2 maker3 sequence price evicted =>
      .evict index maker0 maker1 maker2 maker3 sequence price evicted
  | .fillSummary _ clientLo clientHi totalBase totalQuote totalFee =>
      .fillSummary index clientLo clientHi totalBase totalQuote totalFee
  | .fee _ fees => .fee index fees
  | .timeInForce _ sequence slot time => .timeInForce index sequence slot time
  | .expiredOrder _ maker0 maker1 maker2 maker3 sequence price removed =>
      .expiredOrder index maker0 maker1 maker2 maker3 sequence price removed

/--
写满后把 `matchError` 标成 `matchFull`，不丢事件假装成功。
调用点用当前 `eventCount` 构造 wire index。
不在这里二次 match event，因为动态 variant 已摊平成 State 的 tag/payload leaves。
-/
def appendEvent (s : State) (event : MarketEvent) : State :=
  if h : s.eventCount.toNat < 5 then
    { s with
      events := s.events.set s.eventCount.toNat event
      eventCount := s.eventCount + 1
      lastEvent := event }
  else
    { s with matchError := matchFull }

/--
Expand directly to the generic SVM CPI primitive so extraction retains the effect even when the
host stub's result is ignored. External account 8 is the executable current program and account 9
is the readonly `"log"` authority PDA. `tail` is one canonical Borsh event or empty for a
header-only successful instruction.
-/
macro "recordPhoenix!(" state:term ", " origin:term ", " total:term "; " tail:term,* ")" : term =>
  `(invokeSigned 8
      #[{ acc := 9, signer := true, writable := false }]
      #[.selfEntry 15 "log", .u8le 1, .u8le $origin,
        .u64le ($state).sequence, .u64le unixTime, .u64le clockSlot,
        .u64le (accKeyWord 0 0), .u64le (accKeyWord 0 1),
        .u64le (accKeyWord 0 2), .u64le (accKeyWord 0 3),
        .accKey 0, .u16le $total, $tail,*]
      "log" (findPda "log"))

private def finishWithEvent (s : State) (event : MarketEvent) (ret : UInt64) :
    Except Error (State × UInt64) :=
  let next := appendEvent s event
  if next.matchError ≠ 0 then .error (errorOfMatch next.matchError)
  else .ok ({ next with matchStopped := 0, matchError := 0, matchLevel := 0 }, ret)

attribute [pf_inline] beginEvents MarketEvent.withIndex appendEvent
  finishWithEvent errorOfMatch throwMatch

private def bookColorAt (tree : BookTree4) (address : UInt64) : UInt64 :=
  if address = 0 then 0 else tree.color[(address.toNat - 1) % 4]!

private def paintBook (tree : BookTree4) (address color : UInt64) : BookTree4 :=
  if address = 0 then tree
  else { tree with color := tree.color.set ((address.toNat - 1) % 4) color }

private def rotateBookLeft (tree : BookTree4) (xAddress : UInt64) : BookTree4 :=
  let xi := (xAddress.toNat - 1) % 4
  let yAddress := tree.right[xi]!
  if yAddress = 0 then tree
  else
    let yi := (yAddress.toNat - 1) % 4
    let innerAddress := tree.left[yi]!
    let parentAddress := tree.parent[xi]!
    let right1 := tree.right.set xi innerAddress
    let parent1 := tree.parent.set xi yAddress
    let parent2 :=
      if innerAddress = 0 then parent1
      else parent1.set ((innerAddress.toNat - 1) % 4) xAddress
    let left1 := tree.left.set yi xAddress
    let parent3 := parent2.set yi parentAddress
    if parentAddress = 0 then
      { tree with root := yAddress, left := left1, right := right1, parent := parent3 }
    else
      let pi := (parentAddress.toNat - 1) % 4
      if tree.left[pi]! = xAddress then
        { tree with left := left1.set pi yAddress, right := right1, parent := parent3 }
      else
        { tree with left := left1, right := right1.set pi yAddress, parent := parent3 }

private def rotateBookRight (tree : BookTree4) (xAddress : UInt64) : BookTree4 :=
  let xi := (xAddress.toNat - 1) % 4
  let yAddress := tree.left[xi]!
  if yAddress = 0 then tree
  else
    let yi := (yAddress.toNat - 1) % 4
    let innerAddress := tree.right[yi]!
    let parentAddress := tree.parent[xi]!
    let left1 := tree.left.set xi innerAddress
    let parent1 := tree.parent.set xi yAddress
    let parent2 :=
      if innerAddress = 0 then parent1
      else parent1.set ((innerAddress.toNat - 1) % 4) xAddress
    let right1 := tree.right.set yi xAddress
    let parent3 := parent2.set yi parentAddress
    if parentAddress = 0 then
      { tree with root := yAddress, left := left1, right := right1, parent := parent3 }
    else
      let pi := (parentAddress.toNat - 1) % 4
      if tree.left[pi]! = xAddress then
        { tree with left := left1.set pi yAddress, right := right1, parent := parent3 }
      else
        { tree with left := left1, right := right1.set pi yAddress, parent := parent3 }

private def fixBookInserted
    (tree : BookTree4) (nodeAddress parentAddress : UInt64) : BookTree4 :=
  if parentAddress = 0 then paintBook tree nodeAddress 0
  else if bookColorAt tree parentAddress = 0 then paintBook tree tree.root 0
  else
    let pi := (parentAddress.toNat - 1) % 4
    let grandAddress := tree.parent[pi]!
    if grandAddress = 0 then paintBook tree parentAddress 0
    else
      let gi := (grandAddress.toNat - 1) % 4
      if tree.left[gi]! = parentAddress then
        let uncleAddress := tree.right[gi]!
        if bookColorAt tree uncleAddress = 1 then
          paintBook (paintBook (paintBook tree parentAddress 0) uncleAddress 0) grandAddress 0
        else if tree.right[pi]! = nodeAddress then
          let rotated := rotateBookLeft tree parentAddress
          rotateBookRight (paintBook (paintBook rotated nodeAddress 0) grandAddress 1)
            grandAddress
        else
          rotateBookRight (paintBook (paintBook tree parentAddress 0) grandAddress 1)
            grandAddress
      else
        let uncleAddress := tree.left[gi]!
        if bookColorAt tree uncleAddress = 1 then
          paintBook (paintBook (paintBook tree parentAddress 0) uncleAddress 0) grandAddress 0
        else if tree.left[pi]! = nodeAddress then
          let rotated := rotateBookRight tree parentAddress
          rotateBookLeft (paintBook (paintBook rotated nodeAddress 0) grandAddress 1)
            grandAddress
        else
          rotateBookLeft (paintBook (paintBook tree parentAddress 0) grandAddress 1)
            grandAddress

private def nextBookAddress (tree : BookTree4) : UInt64 :=
  if tree.count = 4 then 0 else tree.freeHead

/-- Allocate one exact address, link it under `parentAddress`, and repair insertion colors. -/
private def insertBookAddress (tree : BookTree4)
    (address parentAddress direction : UInt64) : BookTree4 :=
  let i := (address.toNat - 1) % 4
  let fresh := tree.freeHead = tree.bumpIndex
  let freeNext := tree.nextFree[i]!
  let allocated : BookTree4 :=
    { tree with
      count := tree.count + 1
      bumpIndex := if fresh then tree.bumpIndex + 1 else tree.bumpIndex
      freeHead := if fresh then tree.bumpIndex + 1 else freeNext
      nextFree := tree.nextFree.set i 0
      left := tree.left.set i 0
      right := tree.right.set i 0
      parent := tree.parent.set i parentAddress
      color := tree.color.set i (if tree.root = 0 then 0 else 1) }
  if tree.root = 0 then { allocated with root := address }
  else
    let pi := (parentAddress.toNat - 1) % 4
    let linked :=
      if direction = 0 then { allocated with left := allocated.left.set pi address }
      else { allocated with right := allocated.right.set pi address }
    fixBookInserted linked address parentAddress

private def transplantBook
    (tree : BookTree4) (removed replacement : UInt64) : BookTree4 :=
  let ri := (removed.toNat - 1) % 4
  let parentAddress := tree.parent[ri]!
  let parentLinked :=
    if parentAddress = 0 then { tree with root := replacement }
    else
      let pi := (parentAddress.toNat - 1) % 4
      if tree.left[pi]! = removed then { tree with left := tree.left.set pi replacement }
      else { tree with right := tree.right.set pi replacement }
  if replacement = 0 then parentLinked
  else
    { parentLinked with
      parent := parentLinked.parent.set ((replacement.toNat - 1) % 4) parentAddress }

private def linkBookLeft (tree : BookTree4) (parent child : UInt64) : BookTree4 :=
  let pi := (parent.toNat - 1) % 4
  let linked := { tree with left := tree.left.set pi child }
  if child = 0 then linked
  else { linked with parent := linked.parent.set ((child.toNat - 1) % 4) parent }

private def linkBookRight (tree : BookTree4) (parent child : UInt64) : BookTree4 :=
  let pi := (parent.toNat - 1) % 4
  let linked := { tree with right := tree.right.set pi child }
  if child = 0 then linked
  else { linked with parent := linked.parent.set ((child.toNat - 1) % 4) parent }

private def moveBookSuccessor (tree : BookTree4)
    (removed successor replacement : UInt64) : BookTree4 :=
  let ri := (removed.toNat - 1) % 4
  let si := (successor.toNat - 1) % 4
  let successorParent := tree.parent[si]!
  if successorParent = removed then
    let moved := transplantBook tree removed successor
    paintBook (linkBookLeft moved successor tree.left[ri]!) successor tree.color[ri]!
  else
    let detached := transplantBook tree successor replacement
    let withRight := linkBookRight detached successor tree.right[ri]!
    let moved := transplantBook withRight removed successor
    paintBook (linkBookLeft moved successor tree.left[ri]!) successor tree.color[ri]!

private def fixBookDeleted
    (tree : BookTree4) (xAddress parentAddress : UInt64) : BookTree4 :=
  if xAddress = tree.root then paintBook tree xAddress 0
  else if bookColorAt tree xAddress = 1 then paintBook tree xAddress 0
  else if parentAddress = 0 then paintBook tree xAddress 0
  else
    let pi := (parentAddress.toNat - 1) % 4
    if tree.left[pi]! = xAddress then
      let firstSibling := tree.right[pi]!
      let afterRedSibling :=
        if bookColorAt tree firstSibling = 1 then
          rotateBookLeft (paintBook (paintBook tree firstSibling 0) parentAddress 1)
            parentAddress
        else tree
      let sibling := afterRedSibling.right[pi]!
      let si := (sibling.toNat - 1) % 4
      let nearChild := afterRedSibling.left[si]!
      let farChild := afterRedSibling.right[si]!
      if bookColorAt afterRedSibling nearChild = 0 &&
          bookColorAt afterRedSibling farChild = 0 then
        paintBook (paintBook afterRedSibling sibling 1) parentAddress 0
      else
        let aligned :=
          if bookColorAt afterRedSibling farChild = 0 then
            rotateBookRight
              (paintBook (paintBook afterRedSibling nearChild 0) sibling 1) sibling
          else afterRedSibling
        let alignedSibling := aligned.right[pi]!
        let asi := (alignedSibling.toNat - 1) % 4
        let alignedFar := aligned.right[asi]!
        rotateBookLeft
          (paintBook
            (paintBook (paintBook aligned alignedSibling
              (bookColorAt aligned parentAddress)) parentAddress 0) alignedFar 0)
          parentAddress
    else
      let firstSibling := tree.left[pi]!
      let afterRedSibling :=
        if bookColorAt tree firstSibling = 1 then
          rotateBookRight (paintBook (paintBook tree firstSibling 0) parentAddress 1)
            parentAddress
        else tree
      let sibling := afterRedSibling.left[pi]!
      let si := (sibling.toNat - 1) % 4
      let nearChild := afterRedSibling.right[si]!
      let farChild := afterRedSibling.left[si]!
      if bookColorAt afterRedSibling nearChild = 0 &&
          bookColorAt afterRedSibling farChild = 0 then
        paintBook (paintBook afterRedSibling sibling 1) parentAddress 0
      else
        let aligned :=
          if bookColorAt afterRedSibling farChild = 0 then
            rotateBookLeft
              (paintBook (paintBook afterRedSibling nearChild 0) sibling 1) sibling
          else afterRedSibling
        let alignedSibling := aligned.left[pi]!
        let asi := (alignedSibling.toNat - 1) % 4
        let alignedFar := aligned.left[asi]!
        rotateBookRight
          (paintBook
            (paintBook (paintBook aligned alignedSibling
              (bookColorAt aligned parentAddress)) parentAddress 0) alignedFar 0)
          parentAddress

/-- Detach one order and push its stable address onto this side's exact LIFO free-list. -/
private def removeBookAddress (tree : BookTree4) (removedAddress : UInt64) : BookTree4 :=
  if removedAddress = 0 then tree
  else
    let ri := (removedAddress.toNat - 1) % 4
    let left := tree.left[ri]!
    let right := tree.right[ri]!
    let successorRoot := right
    let sr := (successorRoot.toNat - 1) % 4
    let successorLeft1 := tree.left[sr]!
    let sl1 := (successorLeft1.toNat - 1) % 4
    let successorLeft2 := if successorLeft1 = 0 then 0 else tree.left[sl1]!
    let successorAddress :=
      if left = 0 || right = 0 then removedAddress
      else if successorLeft2 ≠ 0 then successorLeft2
      else if successorLeft1 ≠ 0 then successorLeft1
      else successorRoot
    let si := (successorAddress.toNat - 1) % 4
    let removedColor := tree.color[si]!
    let replacementAddress :=
      if tree.left[si]! ≠ 0 then tree.left[si]! else tree.right[si]!
    let replacementParent :=
      if successorAddress = removedAddress then tree.parent[ri]!
      else if tree.parent[si]! = removedAddress then successorAddress
      else tree.parent[si]!
    let moved :=
      if left = 0 then transplantBook tree removedAddress right
      else if right = 0 then transplantBook tree removedAddress left
      else moveBookSuccessor tree removedAddress successorAddress replacementAddress
    let fixed :=
      if removedColor = 0 then fixBookDeleted moved replacementAddress replacementParent else moved
    let rootBlack := paintBook fixed fixed.root 0
    { rootBlack with
      count := rootBlack.count - 1
      freeHead := removedAddress
      nextFree := rootBlack.nextFree.set ri rootBlack.freeHead
      left := rootBlack.left.set ri 0
      right := rootBlack.right.set ri 0
      parent := rootBlack.parent.set ri 0
      color := rootBlack.color.set ri 0 }

private def minBookAddress (tree : BookTree4) : UInt64 :=
  let a0 := tree.root
  let a1 := if a0 = 0 then 0 else tree.left[(a0.toNat - 1) % 4]!
  let a2 := if a1 = 0 then 0 else tree.left[(a1.toNat - 1) % 4]!
  let a3 := if a2 = 0 then 0 else tree.left[(a2.toNat - 1) % 4]!
  if a3 ≠ 0 then a3 else if a2 ≠ 0 then a2 else if a1 ≠ 0 then a1 else a0

private def maxBookAddress (tree : BookTree4) : UInt64 :=
  let a0 := tree.root
  let a1 := if a0 = 0 then 0 else tree.right[(a0.toNat - 1) % 4]!
  let a2 := if a1 = 0 then 0 else tree.right[(a1.toNat - 1) % 4]!
  let a3 := if a2 = 0 then 0 else tree.right[(a2.toNat - 1) % 4]!
  if a3 ≠ 0 then a3 else if a2 ≠ 0 then a2 else if a1 ≠ 0 then a1 else a0

private def nextBookInOrder (tree : BookTree4) (address : UInt64) : UInt64 :=
  if address = 0 then 0
  else
    let i := (address.toNat - 1) % 4
    let right := tree.right[i]!
    if right ≠ 0 then
      let a1 := tree.left[(right.toNat - 1) % 4]!
      let a2 := if a1 = 0 then 0 else tree.left[(a1.toNat - 1) % 4]!
      let a3 := if a2 = 0 then 0 else tree.left[(a2.toNat - 1) % 4]!
      if a3 ≠ 0 then a3 else if a2 ≠ 0 then a2 else if a1 ≠ 0 then a1 else right
    else
      let p1 := tree.parent[i]!
      let p2 := if p1 = 0 then 0 else tree.parent[(p1.toNat - 1) % 4]!
      let p3 := if p2 = 0 then 0 else tree.parent[(p2.toNat - 1) % 4]!
      if p1 ≠ 0 && tree.left[(p1.toNat - 1) % 4]! = address then p1
      else if p2 ≠ 0 && tree.left[(p2.toNat - 1) % 4]! = p1 then p2
      else if p3 ≠ 0 && tree.left[(p3.toNat - 1) % 4]! = p2 then p3
      else 0

private def pruneBook
    (tree : BookTree4) (before after : Vector UInt64 4) : BookTree4 :=
  let t0 := if before[0]! ≠ 0 && after[0]! = 0 then removeBookAddress tree 1 else tree
  let t1 := if before[1]! ≠ 0 && after[1]! = 0 then removeBookAddress t0 2 else t0
  let t2 := if before[2]! ≠ 0 && after[2]! = 0 then removeBookAddress t1 3 else t1
  if before[3]! ≠ 0 && after[3]! = 0 then removeBookAddress t2 4 else t2

attribute [pf_inline] bookColorAt paintBook rotateBookLeft rotateBookRight fixBookInserted
  nextBookAddress insertBookAddress transplantBook linkBookLeft linkBookRight
  moveBookSuccessor fixBookDeleted removeBookAddress minBookAddress maxBookAddress
  nextBookInOrder pruneBook

/-- 官方 taker fee 默认常用 5 bps。 -/
def defaultFeeBps : UInt64 := 5

/-- 不做 `n + d - 1`，避免上取整本身溢出。`d = 0` fail-closed 为 0。 -/
def ceilDiv (n d : UInt64) : UInt64 :=
  if d = 0 then 0
  else
    let q := n / d
    if n % d = 0 then q else q + 1

/--
UInt64 剖面的 bps 上取整。官方用 u128；本模型要求乘积留在 UInt64。
撮合入口会在调用前检查这个条件。
-/
def feeOfBps (qty feeBps : UInt64) : UInt64 :=
  ceilDiv (qty * feeBps) 10000

def feeOf (qty : UInt64) : UInt64 :=
  feeOfBps qty defaultFeeBps

@[pf_entry]
def init (tick : UInt64) : State :=
  let state : State :=
    { baseLotsPerBaseUnit := 1
      tickSize := tick
      sequence := 1
      takerFeeBps := defaultFeeBps
      collectedFees := 0
      unclaimedFees := 0
      priceTicks := empty4
      sequences := empty4
      traders := empty4
      sizes := empty4
      lastSlots := empty4
      lastTimes := empty4
      bidPriceTicks := empty4
      bidSequences := empty4
      bidTraders := empty4
      bidSizes := empty4
      bidLastSlots := empty4
      bidLastTimes := empty4
      askBook := emptyBookTree
      bidBook := emptyBookTree
      traderCount := 0
      traderBumpIndex := 1
      traderFreeHead := 1
      traderNextFree := empty4
      traderRoot := 0
      traderLeft := empty4
      traderRight := empty4
      traderParent := empty4
      traderColor := empty4
      traderUsed := empty4
      traderKey0 := empty4
      traderKey1 := empty4
      traderKey2 := empty4
      traderKey3 := empty4
      traderQuoteLocked := empty4
      traderQuoteFree := empty4
      traderBaseLocked := empty4
      traderBaseFree := empty4
      quoteLocked := 0
      quoteFree := 0
      baseLocked := 0
      baseFree := 0
      matchFilled := 0
      matchQuote := 0
      matchMakerQuote := 0
      matchExpired := 0
      matchStopped := 0
      matchError := 0
      matchLevel := 0
      matchWant := 0
      matchLimit := 0
      events := emptyEvents
      eventCount := 0
      lastEvent := .uninitialized }
  let _ := recordPhoenix!(state, 100, 0; )
  state

/-!
The trader registry now persists the same mutable topology as the bounded Sokoban refinement.
Payload and allocator vectors remain parallel so the account layout still exposes Phoenix's
TraderState directly; tree links use 1-based addresses and 0 as the black sentinel.
-/

private def traderKeyBefore
    (a0 a1 a2 a3 b0 b1 b2 b3 : UInt64) : Bool :=
  a0 < b0 || (a0 = b0 &&
    (a1 < b1 || (a1 = b1 && (a2 < b2 || (a2 = b2 && a3 < b3)))))

private def traderKeyEqualsAt
    (s : State) (address key0 key1 key2 key3 : UInt64) : Bool :=
  if address = 0 then false
  else
    let i := (address.toNat - 1) % 4
    s.traderUsed[i]! ≠ 0 && s.traderKey0[i]! = key0 && s.traderKey1[i]! = key1 &&
      s.traderKey2[i]! = key2 && s.traderKey3[i]! = key3

private def traderKeyBeforeAt
    (s : State) (key0 key1 key2 key3 address : UInt64) : Bool :=
  let i := (address.toNat - 1) % 4
  traderKeyBefore key0 key1 key2 key3
    s.traderKey0[i]! s.traderKey1[i]! s.traderKey2[i]! s.traderKey3[i]!

private def traderColorAt (s : State) (address : UInt64) : UInt64 :=
  if address = 0 then 0 else s.traderColor[(address.toNat - 1) % 4]!

private def paintTrader (s : State) (address color : UInt64) : State :=
  if address = 0 then s
  else
    { s with traderColor := s.traderColor.set ((address.toNat - 1) % 4) color }

private def rotateTraderLeft (s : State) (xAddress : UInt64) : State :=
  let xi := (xAddress.toNat - 1) % 4
  let yAddress := s.traderRight[xi]!
  if yAddress = 0 then s
  else
    let yi := (yAddress.toNat - 1) % 4
    let innerAddress := s.traderLeft[yi]!
    let parentAddress := s.traderParent[xi]!
    let right1 := s.traderRight.set xi innerAddress
    let parent1 := s.traderParent.set xi yAddress
    let parent2 :=
      if innerAddress = 0 then parent1
      else parent1.set ((innerAddress.toNat - 1) % 4) xAddress
    let left1 := s.traderLeft.set yi xAddress
    let parent3 := parent2.set yi parentAddress
    if parentAddress = 0 then
      { s with
        traderRoot := yAddress, traderLeft := left1, traderRight := right1,
        traderParent := parent3 }
    else
      let pi := (parentAddress.toNat - 1) % 4
      if s.traderLeft[pi]! = xAddress then
        { s with
          traderLeft := left1.set pi yAddress, traderRight := right1,
          traderParent := parent3 }
      else
        { s with
          traderLeft := left1, traderRight := right1.set pi yAddress,
          traderParent := parent3 }

private def rotateTraderRight (s : State) (xAddress : UInt64) : State :=
  let xi := (xAddress.toNat - 1) % 4
  let yAddress := s.traderLeft[xi]!
  if yAddress = 0 then s
  else
    let yi := (yAddress.toNat - 1) % 4
    let innerAddress := s.traderRight[yi]!
    let parentAddress := s.traderParent[xi]!
    let left1 := s.traderLeft.set xi innerAddress
    let parent1 := s.traderParent.set xi yAddress
    let parent2 :=
      if innerAddress = 0 then parent1
      else parent1.set ((innerAddress.toNat - 1) % 4) xAddress
    let right1 := s.traderRight.set yi xAddress
    let parent3 := parent2.set yi parentAddress
    if parentAddress = 0 then
      { s with
        traderRoot := yAddress, traderLeft := left1, traderRight := right1,
        traderParent := parent3 }
    else
      let pi := (parentAddress.toNat - 1) % 4
      if s.traderLeft[pi]! = xAddress then
        { s with
          traderLeft := left1.set pi yAddress, traderRight := right1,
          traderParent := parent3 }
      else
        { s with
          traderLeft := left1, traderRight := right1.set pi yAddress,
          traderParent := parent3 }

private def fixTraderInserted (s : State) (nodeAddress parentAddress : UInt64) : State :=
  if parentAddress = 0 then paintTrader s nodeAddress 0
  else if traderColorAt s parentAddress = 0 then paintTrader s s.traderRoot 0
  else
    let pi := (parentAddress.toNat - 1) % 4
    let grandAddress := s.traderParent[pi]!
    if grandAddress = 0 then paintTrader s parentAddress 0
    else
      let gi := (grandAddress.toNat - 1) % 4
      if s.traderLeft[gi]! = parentAddress then
        let uncleAddress := s.traderRight[gi]!
        if traderColorAt s uncleAddress = 1 then
          paintTrader (paintTrader (paintTrader s parentAddress 0) uncleAddress 0)
            grandAddress 0
        else if s.traderRight[pi]! = nodeAddress then
          let rotated := rotateTraderLeft s parentAddress
          let recolored := paintTrader (paintTrader rotated nodeAddress 0) grandAddress 1
          rotateTraderRight recolored grandAddress
        else
          let recolored := paintTrader (paintTrader s parentAddress 0) grandAddress 1
          rotateTraderRight recolored grandAddress
      else
        let uncleAddress := s.traderLeft[gi]!
        if traderColorAt s uncleAddress = 1 then
          paintTrader (paintTrader (paintTrader s parentAddress 0) uncleAddress 0)
            grandAddress 0
        else if s.traderLeft[pi]! = nodeAddress then
          let rotated := rotateTraderRight s parentAddress
          let recolored := paintTrader (paintTrader rotated nodeAddress 0) grandAddress 1
          rotateTraderLeft recolored grandAddress
        else
          let recolored := paintTrader (paintTrader s parentAddress 0) grandAddress 1
          rotateTraderLeft recolored grandAddress

/-- Link a newly allocated key into the bounded trader tree and repair its colors. -/
private def insertTraderTopology
    (s : State) (address parentAddress key0 key1 key2 key3 : UInt64) : State :=
  let i := (address.toNat - 1) % 4
  if s.traderRoot = 0 then
    { s with
      traderRoot := address
      traderLeft := s.traderLeft.set i 0
      traderRight := s.traderRight.set i 0
      traderParent := s.traderParent.set i 0
      traderColor := s.traderColor.set i 0 }
  else
    let pi := (parentAddress.toNat - 1) % 4
    let goesLeft := traderKeyBeforeAt s key0 key1 key2 key3 parentAddress
    let linked :=
      if goesLeft then
        { s with
          traderLeft := (s.traderLeft.set pi address).set i 0
          traderRight := s.traderRight.set i 0
          traderParent := s.traderParent.set i parentAddress
          traderColor := s.traderColor.set i 1 }
      else
        { s with
          traderLeft := s.traderLeft.set i 0
          traderRight := (s.traderRight.set pi address).set i 0
          traderParent := s.traderParent.set i parentAddress
          traderColor := s.traderColor.set i 1 }
    fixTraderInserted linked address parentAddress

private def transplantTrader (s : State) (removed replacement : UInt64) : State :=
  let ri := (removed.toNat - 1) % 4
  let parentAddress := s.traderParent[ri]!
  let parentLinked :=
    if parentAddress = 0 then { s with traderRoot := replacement }
    else
      let pi := (parentAddress.toNat - 1) % 4
      if s.traderLeft[pi]! = removed then
        { s with traderLeft := s.traderLeft.set pi replacement }
      else
        { s with traderRight := s.traderRight.set pi replacement }
  if replacement = 0 then parentLinked
  else
    { parentLinked with
      traderParent := parentLinked.traderParent.set
        ((replacement.toNat - 1) % 4) parentAddress }

private def linkTraderLeft (s : State) (parent child : UInt64) : State :=
  let pi := (parent.toNat - 1) % 4
  let linked := { s with traderLeft := s.traderLeft.set pi child }
  if child = 0 then linked
  else
    { linked with
      traderParent := linked.traderParent.set ((child.toNat - 1) % 4) parent }

private def linkTraderRight (s : State) (parent child : UInt64) : State :=
  let pi := (parent.toNat - 1) % 4
  let linked := { s with traderRight := s.traderRight.set pi child }
  if child = 0 then linked
  else
    { linked with
      traderParent := linked.traderParent.set ((child.toNat - 1) % 4) parent }

private def moveTraderSuccessor
    (s : State) (removed successor replacement : UInt64) : State :=
  let ri := (removed.toNat - 1) % 4
  let si := (successor.toNat - 1) % 4
  let successorParent := s.traderParent[si]!
  if successorParent = removed then
    let moved := transplantTrader s removed successor
    let withLeft := linkTraderLeft moved successor s.traderLeft[ri]!
    paintTrader withLeft successor s.traderColor[ri]!
  else
    let detached := transplantTrader s successor replacement
    let withRight := linkTraderRight detached successor s.traderRight[ri]!
    let moved := transplantTrader withRight removed successor
    let withLeft := linkTraderLeft moved successor s.traderLeft[ri]!
    paintTrader withLeft successor s.traderColor[ri]!

private def fixTraderDeleted (s : State) (xAddress parentAddress : UInt64) : State :=
  if xAddress = s.traderRoot then paintTrader s xAddress 0
  else if traderColorAt s xAddress = 1 then paintTrader s xAddress 0
  else if parentAddress = 0 then paintTrader s xAddress 0
  else
    let pi := (parentAddress.toNat - 1) % 4
    if s.traderLeft[pi]! = xAddress then
      let firstSibling := s.traderRight[pi]!
      let afterRedSibling :=
        if traderColorAt s firstSibling = 1 then
          rotateTraderLeft (paintTrader (paintTrader s firstSibling 0) parentAddress 1)
            parentAddress
        else s
      let sibling := afterRedSibling.traderRight[pi]!
      let si := (sibling.toNat - 1) % 4
      let nearChild := afterRedSibling.traderLeft[si]!
      let farChild := afterRedSibling.traderRight[si]!
      if traderColorAt afterRedSibling nearChild = 0 &&
          traderColorAt afterRedSibling farChild = 0 then
        paintTrader (paintTrader afterRedSibling sibling 1) parentAddress 0
      else
        let aligned :=
          if traderColorAt afterRedSibling farChild = 0 then
            rotateTraderRight
              (paintTrader (paintTrader afterRedSibling nearChild 0) sibling 1) sibling
          else afterRedSibling
        let alignedSibling := aligned.traderRight[pi]!
        let asi := (alignedSibling.toNat - 1) % 4
        let alignedFar := aligned.traderRight[asi]!
        let recolored :=
          paintTrader
            (paintTrader (paintTrader aligned alignedSibling
              (traderColorAt aligned parentAddress)) parentAddress 0) alignedFar 0
        rotateTraderLeft recolored parentAddress
    else
      let firstSibling := s.traderLeft[pi]!
      let afterRedSibling :=
        if traderColorAt s firstSibling = 1 then
          rotateTraderRight (paintTrader (paintTrader s firstSibling 0) parentAddress 1)
            parentAddress
        else s
      let sibling := afterRedSibling.traderLeft[pi]!
      let si := (sibling.toNat - 1) % 4
      let nearChild := afterRedSibling.traderRight[si]!
      let farChild := afterRedSibling.traderLeft[si]!
      if traderColorAt afterRedSibling nearChild = 0 &&
          traderColorAt afterRedSibling farChild = 0 then
        paintTrader (paintTrader afterRedSibling sibling 1) parentAddress 0
      else
        let aligned :=
          if traderColorAt afterRedSibling farChild = 0 then
            rotateTraderLeft
              (paintTrader (paintTrader afterRedSibling nearChild 0) sibling 1) sibling
          else afterRedSibling
        let alignedSibling := aligned.traderLeft[pi]!
        let asi := (alignedSibling.toNat - 1) % 4
        let alignedFar := aligned.traderLeft[asi]!
        let recolored :=
          paintTrader
            (paintTrader (paintTrader aligned alignedSibling
              (traderColorAt aligned parentAddress)) parentAddress 0) alignedFar 0
        rotateTraderRight recolored parentAddress

/-- Detach one seat while preserving every surviving address and red-black invariant. -/
private def removeTraderTopology (s : State) (removedAddress : UInt64) : State :=
  let ri := (removedAddress.toNat - 1) % 4
  let left := s.traderLeft[ri]!
  let right := s.traderRight[ri]!
  let successorRoot := right
  let sr := (successorRoot.toNat - 1) % 4
  let successorLeft1 := s.traderLeft[sr]!
  let sl1 := (successorLeft1.toNat - 1) % 4
  let successorLeft2 := if successorLeft1 = 0 then 0 else s.traderLeft[sl1]!
  let successorAddress :=
    if left = 0 || right = 0 then removedAddress
    else if successorLeft2 ≠ 0 then successorLeft2
    else if successorLeft1 ≠ 0 then successorLeft1
    else successorRoot
  let si := (successorAddress.toNat - 1) % 4
  let removedColor := s.traderColor[si]!
  let replacementAddress :=
    if s.traderLeft[si]! ≠ 0 then s.traderLeft[si]! else s.traderRight[si]!
  let replacementParent :=
    if successorAddress = removedAddress then s.traderParent[ri]!
    else if s.traderParent[si]! = removedAddress then successorAddress
    else s.traderParent[si]!
  let moved :=
    if left = 0 then transplantTrader s removedAddress right
    else if right = 0 then transplantTrader s removedAddress left
    else moveTraderSuccessor s removedAddress successorAddress replacementAddress
  let fixed :=
    if removedColor = 0 then fixTraderDeleted moved replacementAddress replacementParent else moved
  paintTrader fixed fixed.traderRoot 0

attribute [pf_inline] traderKeyBefore traderKeyEqualsAt traderKeyBeforeAt traderColorAt
  paintTrader rotateTraderLeft rotateTraderRight fixTraderInserted insertTraderTopology
  transplantTrader linkTraderLeft linkTraderRight moveTraderSuccessor fixTraderDeleted
  removeTraderTopology

/-- Full four-limb Pubkey lookup; the persisted topology is maintained independently below. -/
private def traderAddressFor (s : State) (key0 key1 key2 key3 : UInt64) : UInt64 :=
  if s.traderUsed[0]! ≠ 0 && s.traderKey0[0]! = key0 && s.traderKey1[0]! = key1 &&
      s.traderKey2[0]! = key2 && s.traderKey3[0]! = key3 then 1
  else if s.traderUsed[1]! ≠ 0 && s.traderKey0[1]! = key0 && s.traderKey1[1]! = key1 &&
      s.traderKey2[1]! = key2 && s.traderKey3[1]! = key3 then 2
  else if s.traderUsed[2]! ≠ 0 && s.traderKey0[2]! = key0 && s.traderKey1[2]! = key1 &&
      s.traderKey2[2]! = key2 && s.traderKey3[2]! = key3 then 3
  else if s.traderUsed[3]! ≠ 0 && s.traderKey0[3]! = key0 && s.traderKey1[3]! = key1 &&
      s.traderKey2[3]! = key2 && s.traderKey3[3]! = key3 then 4
  else 0

attribute [pf_inline] traderAddressFor

/-- Signer lookup for take-only paths: unlike free-funds entries, a missing seat maps to sentinel max. -/
private def optionalTraderAddress (s : State) (key0 key1 key2 key3 : UInt64) :
    Except Error UInt64 :=
  if s.traderUsed[0]! ≠ 0 && s.traderKey0[0]! = key0 && s.traderKey1[0]! = key1 &&
      s.traderKey2[0]! = key2 && s.traderKey3[0]! = key3 then .ok 1
  else if s.traderUsed[1]! ≠ 0 && s.traderKey0[1]! = key0 && s.traderKey1[1]! = key1 &&
      s.traderKey2[1]! = key2 && s.traderKey3[1]! = key3 then .ok 2
  else if s.traderUsed[2]! ≠ 0 && s.traderKey0[2]! = key0 && s.traderKey1[2]! = key1 &&
      s.traderKey2[2]! = key2 && s.traderKey3[2]! = key3 then .ok 3
  else if s.traderUsed[3]! ≠ 0 && s.traderKey0[3]! = key0 && s.traderKey1[3]! = key1 &&
      s.traderKey2[3]! = key2 && s.traderKey3[3]! = key3 then .ok 4
  else .ok u64Max

attribute [pf_inline] optionalTraderAddress

/-- Stateful callers use an `Except` producer so the bounded lookup joins into a CFG local. -/
private def requireTraderAddress (s : State) (key0 key1 key2 key3 : UInt64) :
    Except Error UInt64 :=
  if s.traderUsed[0]! ≠ 0 && s.traderKey0[0]! = key0 && s.traderKey1[0]! = key1 &&
      s.traderKey2[0]! = key2 && s.traderKey3[0]! = key3 then .ok 1
  else if s.traderUsed[1]! ≠ 0 && s.traderKey0[1]! = key0 && s.traderKey1[1]! = key1 &&
      s.traderKey2[1]! = key2 && s.traderKey3[1]! = key3 then .ok 2
  else if s.traderUsed[2]! ≠ 0 && s.traderKey0[2]! = key0 && s.traderKey1[2]! = key1 &&
      s.traderKey2[2]! = key2 && s.traderKey3[2]! = key3 then .ok 3
  else if s.traderUsed[3]! ≠ 0 && s.traderKey0[3]! = key0 && s.traderKey1[3]! = key1 &&
      s.traderKey2[3]! = key2 && s.traderKey3[3]! = key3 then .ok 4
  else .error .unauthorized

attribute [pf_inline] requireTraderAddress

/-- Host/view lookup；返回官方 1-based trader index，0 表示未注册。 -/
@[pf_entry]
def traderIndexOf (s : State) (key0 key1 key2 key3 : UInt64) : UInt64 :=
  traderAddressFor s key0 key1 key2 key3

/-- 读取某 seat 的 base-free；无效或未分配 address fail-closed 为 0。 -/
@[pf_entry]
def traderBaseFreeAt (s : State) (address : UInt64) : UInt64 :=
  if address = 0 || 4 < address then 0
  else
    let i := address.toNat - 1
    if s.traderUsed[i]! = 0 then 0 else s.traderBaseFree[i]!

/--
官方 deposit 的 bounded state transition：先按完整 Pubkey 查 seat；缺失时走
Sokoban allocator 注册，再分别增加该 seat 的 base/quote free。重复注册幂等，
容量满和余额溢出都 fail closed。返回 1-based trader index。

四轮 state-carrying walk 沿持久化 links 前进；这既给抽取器一个显式有界 CFG，也避免
恢复成按物理 slot 的线性扫描。
-/
def depositFundsFor (s : State) (key0 key1 key2 key3 baseLots quoteLots : UInt64) :
    Except Error (State × UInt64) := Id.run do
  let mut st := { s with matchStopped := 0, matchLevel := s.traderRoot, matchWant := 0 }
  for _ in [0:4] do
    if st.matchStopped = (0 : UInt64) then
      let address := st.matchLevel
      if address ≠ (0 : UInt64) then
        let i := (address.toNat - 1) % 4
        if st.traderUsed[i]! ≠ (0 : UInt64) && st.traderKey0[i]! = key0 &&
            st.traderKey1[i]! = key1 && st.traderKey2[i]! = key2 &&
            st.traderKey3[i]! = key3 then
          st := { st with matchStopped := address }
        else
          if traderKeyBefore key0 key1 key2 key3 st.traderKey0[i]!
              st.traderKey1[i]! st.traderKey2[i]! st.traderKey3[i]! then
            st := { st with matchWant := address, matchLevel := st.traderLeft[i]! }
          else
            st := { st with matchWant := address, matchLevel := st.traderRight[i]! }
  if st.baseFree > u64Max - baseLots then
    .error .overflow
  else if st.quoteFree > u64Max - quoteLots then
    .error .overflow
  else if st.matchStopped ≠ (0 : UInt64) then
    let address := st.matchStopped
    let i := address.toNat - 1
    if h : i < 4 then
      if st.traderBaseFree[i]! ≤ u64Max - baseLots then
        if st.traderQuoteFree[i]! ≤ u64Max - quoteLots then
          .ok ({ st with
                  baseFree := st.baseFree + baseLots
                  quoteFree := st.quoteFree + quoteLots
                  traderBaseFree := st.traderBaseFree.set i (st.traderBaseFree[i]! + baseLots)
                  traderQuoteFree :=
                    st.traderQuoteFree.set i (st.traderQuoteFree[i]! + quoteLots) },
            st.matchStopped)
        else
          .error .overflow
      else
        .error .overflow
    else
      .error .overflow
  else if st.traderCount < (4 : UInt64) then
    if st.traderFreeHead = st.traderBumpIndex then
      if st.traderBumpIndex = (0 : UInt64) then
        .error .overflow
      else if st.traderBumpIndex < (5 : UInt64) then
        let address := st.traderBumpIndex
        let i := address.toNat - 1
        let allocated := { st with
                traderCount := st.traderCount + 1
                traderBumpIndex := st.traderBumpIndex + 1
                traderFreeHead := st.traderBumpIndex + 1
                traderNextFree := st.traderNextFree.set (i % 4) 0
                traderUsed := st.traderUsed.set (i % 4) 1
                traderKey0 := st.traderKey0.set (i % 4) key0
                traderKey1 := st.traderKey1.set (i % 4) key1
                traderKey2 := st.traderKey2.set (i % 4) key2
                traderKey3 := st.traderKey3.set (i % 4) key3
                traderQuoteLocked := st.traderQuoteLocked.set (i % 4) 0
                traderQuoteFree := st.traderQuoteFree.set (i % 4) quoteLots
                traderBaseLocked := st.traderBaseLocked.set (i % 4) 0
                traderBaseFree := st.traderBaseFree.set (i % 4) baseLots
                quoteFree := st.quoteFree + quoteLots
                baseFree := st.baseFree + baseLots
                matchStopped := address }
        let topology := insertTraderTopology st address st.matchWant key0 key1 key2 key3
        .ok ({ allocated with
          traderRoot := topology.traderRoot
          traderLeft := topology.traderLeft
          traderRight := topology.traderRight
          traderParent := topology.traderParent
          traderColor := topology.traderColor }, address)
      else
        .error .overflow
    else if st.traderFreeHead = (0 : UInt64) then
      .error .overflow
    else if st.traderFreeHead < (5 : UInt64) then
      let address := st.traderFreeHead
      let i := address.toNat - 1
      let next := st.traderNextFree[i]!
      let allocated := { st with
              traderCount := st.traderCount + 1
              traderFreeHead := next
              traderNextFree := st.traderNextFree.set (i % 4) 0
              traderUsed := st.traderUsed.set (i % 4) 1
              traderKey0 := st.traderKey0.set (i % 4) key0
              traderKey1 := st.traderKey1.set (i % 4) key1
              traderKey2 := st.traderKey2.set (i % 4) key2
              traderKey3 := st.traderKey3.set (i % 4) key3
              traderQuoteLocked := st.traderQuoteLocked.set (i % 4) 0
              traderQuoteFree := st.traderQuoteFree.set (i % 4) quoteLots
              traderBaseLocked := st.traderBaseLocked.set (i % 4) 0
              traderBaseFree := st.traderBaseFree.set (i % 4) baseLots
              quoteFree := st.quoteFree + quoteLots
              baseFree := st.baseFree + baseLots
              matchStopped := address }
      let topology := insertTraderTopology st address st.matchWant key0 key1 key2 key3
      .ok ({ allocated with
        traderRoot := topology.traderRoot
        traderLeft := topology.traderLeft
        traderRight := topology.traderRight
        traderParent := topology.traderParent
        traderColor := topology.traderColor }, address)
    else
      .error .overflow
  else
    .error .full

attribute [pf_inline] depositFundsFor

/--
SVM adapter：market 是 account 0，trader signer 是 account 1。`signerKey 1`
同时验证签名并返回 Pubkey 的第 0 limb；其余 limbs 走同一 account-header view。
-/
@[pf_entry]
def depositFunds (s : State) (baseLots quoteLots : UInt64) :
    Except Error (State × UInt64) :=
  let _ := recordPhoenix!(s, 13, 0; )
  let baseSeeds : Array PdaSeed := #[.ascii "vault", .stateKey, .accKey 3]
  let quoteSeeds : Array PdaSeed := #[.ascii "vault", .stateKey, .accKey 4]
  if checkPdaSeeds 5 baseSeeds ≠ 0 then
    .error .unauthorized
  else if checkPdaSeeds 6 quoteSeeds ≠ 0 then
    .error .unauthorized
  else if (0 : UInt64) ≠ 1 then
    let _ := tokenTransferCheckedIx 7 1 3 5 0 baseLots 6
    let _ := tokenTransferCheckedIx 7 2 4 6 0 quoteLots 6
    depositFundsFor s (signerKey 1) (accKeyWord 1 1) (accKeyWord 1 2) (accKeyWord 1 3)
      baseLots quoteLots
  else
    .error .overflow

/--
从一个已注册 seat 提取 base free funds。官方语义是 `min(requested, free)`；
返回实际可提取的 base lots，找不到完整 Pubkey 时 fail closed。
-/
def withdrawBaseFor (s : State) (key0 key1 key2 key3 requested : UInt64) :
    Except Error (State × UInt64) := do
  let address ← requireTraderAddress s key0 key1 key2 key3
  let i := address.toNat - 1
  let available := s.traderBaseFree[i]!
  let amount := if requested < available then requested else available
  if amount > s.baseFree then
    .error .overflow
  else
    .ok ({ s with
            baseFree := s.baseFree - amount
            traderBaseFree := s.traderBaseFree.set (i % 4) (available - amount) }, amount)

/-- Quote-lot 版本；单独入口避免把 base/quote 两种单位混进一个 UInt64 返回值。 -/
def withdrawQuoteFor (s : State) (key0 key1 key2 key3 requested : UInt64) :
    Except Error (State × UInt64) := do
  let address ← requireTraderAddress s key0 key1 key2 key3
  let i := address.toNat - 1
  let available := s.traderQuoteFree[i]!
  let amount := if requested < available then requested else available
  if amount > s.quoteFree then
    .error .overflow
  else
    .ok ({ s with
            quoteFree := s.quoteFree - amount
            traderQuoteFree := s.traderQuoteFree.set (i % 4) (available - amount) }, amount)

/--
只有 `TraderState` 四类余额都为零时才释放 seat。释放后的 1-based address 压入
Sokoban LIFO free-list；bump index 不回退，下一次注册优先复用 free-list 头。
-/
def evictSeatFor (s : State) (key0 key1 key2 key3 : UInt64) :
    Except Error (State × UInt64) := do
  let address ← requireTraderAddress s key0 key1 key2 key3
  let i := address.toNat - 1
  if s.traderQuoteLocked[i]! = 0 && s.traderQuoteFree[i]! = 0 &&
      s.traderBaseLocked[i]! = 0 && s.traderBaseFree[i]! = 0 then
    if s.traderCount = 0 then
      .error .overflow
    else
      let _ := recordPhoenix!(s, 106, 0; )
      let detached := removeTraderTopology s address
      .ok ({ detached with
              traderCount := detached.traderCount - 1
              traderFreeHead := address
              traderNextFree := detached.traderNextFree.set (i % 4) s.traderFreeHead
              traderLeft := detached.traderLeft.set (i % 4) 0
              traderRight := detached.traderRight.set (i % 4) 0
              traderParent := detached.traderParent.set (i % 4) 0
              traderColor := detached.traderColor.set (i % 4) 0
              traderUsed := detached.traderUsed.set (i % 4) 0
              traderKey0 := detached.traderKey0.set (i % 4) 0
              traderKey1 := detached.traderKey1.set (i % 4) 0
              traderKey2 := detached.traderKey2.set (i % 4) 0
              traderKey3 := detached.traderKey3.set (i % 4) 0 }, address)
  else
    .error .overflow

attribute [pf_inline] withdrawBaseFor withdrawQuoteFor evictSeatFor

/-- SVM base-vault adapter；account 1 必须签名并以完整 Pubkey 拥有目标 seat。 -/
@[pf_entry]
def withdrawBase (s : State) (requested : UInt64) : Except Error (State × UInt64) := do
  let _ := recordPhoenix!(s, 12, 0; )
  let key0 := signerKey 1
  let key1 := accKeyWord 1 1
  let key2 := accKeyWord 1 2
  let key3 := accKeyWord 1 3
  let address ← requireTraderAddress s key0 key1 key2 key3
  let i := address.toNat - 1
  let available := s.traderBaseFree[i]!
  let amount := if requested < available then requested else available
  if amount > s.baseFree then
    .error .overflow
  else
    let seeds : Array PdaSeed := #[.ascii "vault", .stateKey, .accKey 3]
    let _ := tokenTransferCheckedSignedIx 7 5 3 1 5 amount 6 seeds (findPdaSeeds seeds)
    .ok ({ s with
            baseFree := s.baseFree - amount
            traderBaseFree := s.traderBaseFree.set (i % 4) (available - amount) }, amount)

/-- SVM quote-vault adapter；返回实际提取的 quote lots。 -/
@[pf_entry]
def withdrawQuote (s : State) (requested : UInt64) : Except Error (State × UInt64) := do
  let _ := recordPhoenix!(s, 12, 0; )
  let key0 := signerKey 1
  let key1 := accKeyWord 1 1
  let key2 := accKeyWord 1 2
  let key3 := accKeyWord 1 3
  let address ← requireTraderAddress s key0 key1 key2 key3
  let i := address.toNat - 1
  let available := s.traderQuoteFree[i]!
  let amount := if requested < available then requested else available
  if amount > s.quoteFree then
    .error .overflow
  else
    let seeds : Array PdaSeed := #[.ascii "vault", .stateKey, .accKey 4]
    let _ := tokenTransferCheckedSignedIx 7 6 4 2 6 amount 6 seeds (findPdaSeeds seeds)
    .ok ({ s with
            quoteFree := s.quoteFree - amount
            traderQuoteFree := s.traderQuoteFree.set (i % 4) (available - amount) }, amount)

/-- SVM seat eviction adapter；非空 TraderState 或未注册 signer 都拒绝。 -/
@[pf_entry]
def evictSeat (s : State) : Except Error (State × UInt64) :=
  evictSeatFor s (signerKey 1) (accKeyWord 1 1) (accKeyWord 1 2) (accKeyWord 1 3)

/-- 官方 FIFORestingOrder 是否过期。0 是哨兵。 -/
def expired (lastSlot lastTime nowSlot nowTime : UInt64) : Bool :=
  (lastSlot ≠ 0 && lastSlot < nowSlot) ||
    (lastTime ≠ 0 && lastTime < nowTime)

/-- Phoenix 给自然 sequence 留半个 `u64` 空间；bid 用按位取反编码另一半。 -/
def maxOrderSequence : UInt64 := u64Max / 2

private def registeredSeat (s : State) (address : UInt64) : Bool :=
  if address = 0 || 4 < address then false
  else s.traderUsed[address.toNat - 1]! ≠ 0

/-- Resolve a resting order's internal trader-tree address before constructing a wire event. -/
private def makerKey0 (s : State) (address : UInt64) : UInt64 :=
  if registeredSeat s address then s.traderKey0[address.toNat - 1]! else address

private def makerKey1 (s : State) (address : UInt64) : UInt64 :=
  if registeredSeat s address then s.traderKey1[address.toNat - 1]! else 0

private def makerKey2 (s : State) (address : UInt64) : UInt64 :=
  if registeredSeat s address then s.traderKey2[address.toNat - 1]! else 0

private def makerKey3 (s : State) (address : UInt64) : UInt64 :=
  if registeredSeat s address then s.traderKey3[address.toNat - 1]! else 0

/--
Apply the base-ledger part of posting an ask. `oldSize = 0` is an ordinary insertion;
otherwise the old maker is unlocked before the new owner is locked. Registered orders
update the authoritative per-seat ledger and the temporary aggregate projection atomically.
Unregistered addresses retain the host-reference aggregate path and are unreachable through
the authenticated instruction adapter.
-/
private def postAskFunds
    (s : State) (trader oldTrader oldSize size : UInt64) : State :=
  if oldSize > s.baseLocked then
    { s with matchError := 1 }
  else if s.baseFree > u64Max - oldSize then
    { s with matchError := 1 }
  else
    let aggregateFree := s.baseFree + oldSize
    let aggregateLocked := s.baseLocked - oldSize
    if size > aggregateFree then
      { s with matchError := 1 }
    else if aggregateLocked > u64Max - size then
      { s with matchError := 1 }
    else
      let aggregate := { s with
        baseLocked := aggregateLocked + size
        baseFree := aggregateFree - size }
      if registeredSeat s trader then
        let traderIndex := trader.toNat - 1
        if oldSize = 0 then
          if size > s.traderBaseFree[traderIndex]! then
            { s with matchError := 1 }
          else if s.traderBaseLocked[traderIndex]! > u64Max - size then
            { s with matchError := 1 }
          else
            { aggregate with
              traderBaseLocked := s.traderBaseLocked.set (traderIndex % 4)
                (s.traderBaseLocked[traderIndex]! + size)
              traderBaseFree := s.traderBaseFree.set (traderIndex % 4)
                (s.traderBaseFree[traderIndex]! - size) }
        else if registeredSeat s oldTrader then
          let oldIndex := oldTrader.toNat - 1
          if oldTrader = trader then
            if oldSize > s.traderBaseLocked[traderIndex]! then
              { s with matchError := 1 }
            else if s.traderBaseFree[traderIndex]! > u64Max - oldSize then
              { s with matchError := 1 }
            else
              let traderFree := s.traderBaseFree[traderIndex]! + oldSize
              let traderLocked := s.traderBaseLocked[traderIndex]! - oldSize
              if size > traderFree then
                { s with matchError := 1 }
              else if traderLocked > u64Max - size then
                { s with matchError := 1 }
              else
                { aggregate with
                  traderBaseLocked := s.traderBaseLocked.set (traderIndex % 4)
                    (traderLocked + size)
                  traderBaseFree := s.traderBaseFree.set (traderIndex % 4)
                    (traderFree - size) }
          else if oldSize > s.traderBaseLocked[oldIndex]! then
            { s with matchError := 1 }
          else if s.traderBaseFree[oldIndex]! > u64Max - oldSize then
            { s with matchError := 1 }
          else if size > s.traderBaseFree[traderIndex]! then
            { s with matchError := 1 }
          else if s.traderBaseLocked[traderIndex]! > u64Max - size then
            { s with matchError := 1 }
          else
            { aggregate with
              traderBaseLocked :=
                (s.traderBaseLocked.set (oldIndex % 4)
                  (s.traderBaseLocked[oldIndex]! - oldSize)).set (traderIndex % 4)
                    (s.traderBaseLocked[traderIndex]! + size)
              traderBaseFree :=
                (s.traderBaseFree.set (oldIndex % 4)
                  (s.traderBaseFree[oldIndex]! + oldSize)).set (traderIndex % 4)
                    (s.traderBaseFree[traderIndex]! - size) }
        else
          { s with matchError := 1 }
      else
        aggregate

/-- Quote-ledger analogue of `postAskFunds`; values are precomputed bid collateral. -/
private def postBidFunds
    (s : State) (trader oldTrader oldLock newLock : UInt64) : State :=
  if oldLock > s.quoteLocked then
    { s with matchError := 1 }
  else if s.quoteFree > u64Max - oldLock then
    { s with matchError := 1 }
  else
    let aggregateFree := s.quoteFree + oldLock
    let aggregateLocked := s.quoteLocked - oldLock
    if newLock > aggregateFree then
      { s with matchError := 1 }
    else if aggregateLocked > u64Max - newLock then
      { s with matchError := 1 }
    else
      let aggregate := { s with
        quoteLocked := aggregateLocked + newLock
        quoteFree := aggregateFree - newLock }
      if registeredSeat s trader then
        let traderIndex := trader.toNat - 1
        if oldLock = 0 then
          if newLock > s.traderQuoteFree[traderIndex]! then
            { s with matchError := 1 }
          else if s.traderQuoteLocked[traderIndex]! > u64Max - newLock then
            { s with matchError := 1 }
          else
            { aggregate with
              traderQuoteLocked := s.traderQuoteLocked.set (traderIndex % 4)
                (s.traderQuoteLocked[traderIndex]! + newLock)
              traderQuoteFree := s.traderQuoteFree.set (traderIndex % 4)
                (s.traderQuoteFree[traderIndex]! - newLock) }
        else if registeredSeat s oldTrader then
          let oldIndex := oldTrader.toNat - 1
          if oldTrader = trader then
            if oldLock > s.traderQuoteLocked[traderIndex]! then
              { s with matchError := 1 }
            else if s.traderQuoteFree[traderIndex]! > u64Max - oldLock then
              { s with matchError := 1 }
            else
              let traderFree := s.traderQuoteFree[traderIndex]! + oldLock
              let traderLocked := s.traderQuoteLocked[traderIndex]! - oldLock
              if newLock > traderFree then
                { s with matchError := 1 }
              else if traderLocked > u64Max - newLock then
                { s with matchError := 1 }
              else
                { aggregate with
                  traderQuoteLocked := s.traderQuoteLocked.set (traderIndex % 4)
                    (traderLocked + newLock)
                  traderQuoteFree := s.traderQuoteFree.set (traderIndex % 4)
                    (traderFree - newLock) }
          else if oldLock > s.traderQuoteLocked[oldIndex]! then
            { s with matchError := 1 }
          else if s.traderQuoteFree[oldIndex]! > u64Max - oldLock then
            { s with matchError := 1 }
          else if newLock > s.traderQuoteFree[traderIndex]! then
            { s with matchError := 1 }
          else if s.traderQuoteLocked[traderIndex]! > u64Max - newLock then
            { s with matchError := 1 }
          else
            { aggregate with
              traderQuoteLocked :=
                (s.traderQuoteLocked.set (oldIndex % 4)
                  (s.traderQuoteLocked[oldIndex]! - oldLock)).set (traderIndex % 4)
                    (s.traderQuoteLocked[traderIndex]! + newLock)
              traderQuoteFree :=
                (s.traderQuoteFree.set (oldIndex % 4)
                  (s.traderQuoteFree[oldIndex]! + oldLock)).set (traderIndex % 4)
                    (s.traderQuoteFree[traderIndex]! - newLock) }
        else
          { s with matchError := 1 }
      else
        aggregate

attribute [pf_inline] registeredSeat makerKey0 makerKey1 makerKey2 makerKey3
  postAskFunds postBidFunds

private def askKeyBeforeAt
    (s : State) (price sequence address : UInt64) : Bool :=
  let i := (address.toNat - 1) % 4
  price < s.priceTicks[i]! ||
    (price = s.priceTicks[i]! && sequence < s.sequences[i]!)

private def bidKeyBeforeAt
    (s : State) (price encodedSequence address : UInt64) : Bool :=
  let i := (address.toNat - 1) % 4
  s.bidPriceTicks[i]! < price ||
    (price = s.bidPriceTicks[i]! && s.bidSequences[i]! < encodedSequence)

private def askInsertionParent (s : State) (price sequence : UInt64) : UInt64 :=
  let a0 := s.askBook.root
  let a1 := if a0 = 0 then 0 else if askKeyBeforeAt s price sequence a0 then
    s.askBook.left[(a0.toNat - 1) % 4]! else s.askBook.right[(a0.toNat - 1) % 4]!
  let a2 := if a1 = 0 then 0 else if askKeyBeforeAt s price sequence a1 then
    s.askBook.left[(a1.toNat - 1) % 4]! else s.askBook.right[(a1.toNat - 1) % 4]!
  let a3 := if a2 = 0 then 0 else if askKeyBeforeAt s price sequence a2 then
    s.askBook.left[(a2.toNat - 1) % 4]! else s.askBook.right[(a2.toNat - 1) % 4]!
  if a3 ≠ 0 then a3 else if a2 ≠ 0 then a2 else if a1 ≠ 0 then a1 else a0

private def bidInsertionParent (s : State) (price encodedSequence : UInt64) : UInt64 :=
  let a0 := s.bidBook.root
  let a1 := if a0 = 0 then 0 else if bidKeyBeforeAt s price encodedSequence a0 then
    s.bidBook.left[(a0.toNat - 1) % 4]! else s.bidBook.right[(a0.toNat - 1) % 4]!
  let a2 := if a1 = 0 then 0 else if bidKeyBeforeAt s price encodedSequence a1 then
    s.bidBook.left[(a1.toNat - 1) % 4]! else s.bidBook.right[(a1.toNat - 1) % 4]!
  let a3 := if a2 = 0 then 0 else if bidKeyBeforeAt s price encodedSequence a2 then
    s.bidBook.left[(a2.toNat - 1) % 4]! else s.bidBook.right[(a2.toNat - 1) % 4]!
  if a3 ≠ 0 then a3 else if a2 ≠ 0 then a2 else if a1 ≠ 0 then a1 else a0

private def insertAskOrder (s : State) (address price sequence : UInt64) : State :=
  let parent := askInsertionParent s price sequence
  let direction := if parent = 0 || askKeyBeforeAt s price sequence parent then 0 else 1
  { s with askBook := insertBookAddress s.askBook address parent direction }

private def insertBidOrder
    (s : State) (address price encodedSequence : UInt64) : State :=
  let parent := bidInsertionParent s price encodedSequence
  let direction := if parent = 0 || bidKeyBeforeAt s price encodedSequence parent then 0 else 1
  { s with bidBook := insertBookAddress s.bidBook address parent direction }

/-- Ask topology in-order is ascending `(price, sequence)` and contains every live payload once. -/
def orderedAsks (s : State) : Bool :=
  let a0 := minBookAddress s.askBook
  let a1 := nextBookInOrder s.askBook a0
  let a2 := nextBookInOrder s.askBook a1
  let a3 := nextBookInOrder s.askBook a2
  let live : UInt64 :=
    (if s.sizes[0]! = 0 then 0 else 1) + (if s.sizes[1]! = 0 then 0 else 1) +
      (if s.sizes[2]! = 0 then 0 else 1) + (if s.sizes[3]! = 0 then 0 else 1)
  let before (left right : UInt64) : Bool :=
    right = 0 || (left ≠ 0 &&
      let li := (left.toNat - 1) % 4
      let ri := (right.toNat - 1) % 4
      s.priceTicks[li]! < s.priceTicks[ri]! ||
        (s.priceTicks[li]! = s.priceTicks[ri]! && s.sequences[li]! < s.sequences[ri]!))
  s.askBook.count = live && (a0 = 0 || s.sizes[(a0.toNat - 1) % 4]! ≠ 0) &&
    (a1 = 0 || s.sizes[(a1.toNat - 1) % 4]! ≠ 0) &&
    (a2 = 0 || s.sizes[(a2.toNat - 1) % 4]! ≠ 0) &&
    (a3 = 0 || s.sizes[(a3.toNat - 1) % 4]! ≠ 0) &&
    before a0 a1 && before a1 a2 && before a2 a3

/-- Bid topology in-order is descending price then descending encoded sequence (FIFO). -/
def orderedBids (s : State) : Bool :=
  let a0 := minBookAddress s.bidBook
  let a1 := nextBookInOrder s.bidBook a0
  let a2 := nextBookInOrder s.bidBook a1
  let a3 := nextBookInOrder s.bidBook a2
  let live : UInt64 :=
    (if s.bidSizes[0]! = 0 then 0 else 1) + (if s.bidSizes[1]! = 0 then 0 else 1) +
      (if s.bidSizes[2]! = 0 then 0 else 1) + (if s.bidSizes[3]! = 0 then 0 else 1)
  let before (left right : UInt64) : Bool :=
    right = 0 || (left ≠ 0 &&
      let li := (left.toNat - 1) % 4
      let ri := (right.toNat - 1) % 4
      s.bidPriceTicks[ri]! < s.bidPriceTicks[li]! ||
        (s.bidPriceTicks[li]! = s.bidPriceTicks[ri]! &&
          s.bidSequences[ri]! < s.bidSequences[li]!))
  s.bidBook.count = live && (a0 = 0 || s.bidSizes[(a0.toNat - 1) % 4]! ≠ 0) &&
    (a1 = 0 || s.bidSizes[(a1.toNat - 1) % 4]! ≠ 0) &&
    (a2 = 0 || s.bidSizes[(a2.toNat - 1) % 4]! ≠ 0) &&
    (a3 = 0 || s.bidSizes[(a3.toNat - 1) % 4]! ≠ 0) &&
    before a0 a1 && before a1 a2 && before a2 a3

attribute [pf_inline] askKeyBeforeAt bidKeyBeforeAt askInsertionParent bidInsertionParent
  insertAskOrder insertBidOrder

private def ensureAskCapacity (s : State) (price : UInt64) : Except Error UInt64 :=
  if s.askBook.count = 4 then
    let evictedAddress := maxBookAddress s.askBook
    let evictedIndex := (evictedAddress.toNat - 1) % 4
    if price < s.priceTicks[evictedIndex]! then .ok 0 else .error .full
  else
    .ok 0

private def ensureBidCapacity (s : State) (price : UInt64) : Except Error UInt64 :=
  if s.bidBook.count = 4 then
    let evictedAddress := maxBookAddress s.bidBook
    let evictedIndex := (evictedAddress.toNat - 1) % 4
    if s.bidPriceTicks[evictedIndex]! < price then .ok 0 else .error .full
  else
    .ok 0

attribute [pf_inline] ensureAskCapacity ensureBidCapacity

/--
固定容量 ask tree 插入。payload address 在分配后保持稳定；树满时按 `get_max()`
驱逐最差订单，删除后的 LIFO free-list 会把同一 address 交给新订单。

这是 free-funds 挂单：`baseFree → baseLocked`。驱逐先把旧 maker 的 base 解锁。
传进来已经过期的 TIF 是成功 no-op，不占 sequence。
-/
private def postAskAccepted (s : State)
    (trader price size clientOrderIdLo clientOrderIdHi lastSlot lastTime : UInt64) :
    Except Error (State × UInt64) := Id.run do
    let full := s.askBook.count = 4
    let evictedAddress := if full then maxBookAddress s.askBook else 0
    let evictedIndex := (evictedAddress.toNat - 1) % 4
    let oldSize := if evictedAddress = 0 then 0 else s.sizes[evictedIndex]!
    let mut st := { s with
      matchStopped := 0, matchError := 0
      matchLevel := 0
      eventCount := 0, lastEvent := .uninitialized }
    for i in [0:17] do
      if i = 0 then
        let address := if full then evictedAddress else st.askBook.freeHead
        let detachedBook :=
          if full then removeBookAddress st.askBook evictedAddress else st.askBook
        let oldTrader : UInt64 :=
          if evictedAddress = 0 then 0 else st.traders[evictedIndex]!
        let funded := postAskFunds st trader oldTrader oldSize size
        let detached := { funded with askBook := detachedBook }
        let inserted := insertAskOrder detached address price st.sequence
        let j := (address.toNat - 1) % 4
        st := { inserted with
          priceTicks := inserted.priceTicks.set j price
          sequences := inserted.sequences.set j st.sequence
          traders := inserted.traders.set j trader
          sizes := inserted.sizes.set j size
          lastSlots := inserted.lastSlots.set j lastSlot
          lastTimes := inserted.lastTimes.set j lastTime
          sequence := st.sequence + 1
          matchStopped := address
          matchLevel := if full then 1 else 0 }
      else if i = 14 then
        if st.matchStopped ≠ (0 : UInt64) then
          if st.matchError = (0 : UInt64) then
            if st.matchLevel = (1 : UInt64) then
              let maker := s.traders[evictedIndex]!
              let _ := recordPhoenix!(st, 3, 1;
                .u8le 5, .u16le 0,
                .u64le (makerKey0 s maker), .u64le (makerKey1 s maker),
                .u64le (makerKey2 s maker), .u64le (makerKey3 s maker),
                .u64le s.sequences[evictedIndex]!, .u64le s.priceTicks[evictedIndex]!,
                .u64le s.sizes[evictedIndex]!)
              st := appendEvent st
                (.evict st.eventCount (makerKey0 s maker) (makerKey1 s maker)
                  (makerKey2 s maker) (makerKey3 s maker)
                  s.sequences[evictedIndex]! s.priceTicks[evictedIndex]!
                  s.sizes[evictedIndex]!)
      else if i = 15 then
        if st.matchStopped ≠ (0 : UInt64) then
          if st.matchError = (0 : UInt64) then
            let _ := recordPhoenix!(st, 3, 1;
              .u8le 3, .u16le 0, .u64le s.sequence,
              .u64le clientOrderIdLo, .u64le clientOrderIdHi,
              .u64le price, .u64le size)
            st := appendEvent st
              (.place st.eventCount s.sequence clientOrderIdLo clientOrderIdHi price size)
      else if i = 16 then
        if st.matchStopped ≠ (0 : UInt64) then
          if st.matchError = (0 : UInt64) then
            if lastSlot ≠ 0 || lastTime ≠ 0 then
              let _ := recordPhoenix!(st, 3, 1;
                .u8le 8, .u16le 0,
                .u64le s.sequence, .u64le lastSlot, .u64le lastTime)
              st := appendEvent st (.timeInForce st.eventCount s.sequence lastSlot lastTime)
    if st.matchError ≠ 0 then
      .error (errorOfMatch st.matchError)
    else if st.matchStopped = 0 then
      .error .overflow
    else
      .ok ({ st with matchStopped := 0, matchError := 0, matchLevel := 0 }, size)

attribute [pf_inline] postAskAccepted

def postAskWithClientAt (s : State)
    (trader price size clientOrderIdLo clientOrderIdHi lastSlot lastTime nowSlot nowTime : UInt64) :
    Except Error (State × UInt64) :=
  if price = 0 || size = 0 || maxOrderSequence ≤ s.sequence then
    .error .overflow
  else if expired lastSlot lastTime nowSlot nowTime then
    let _ := recordPhoenix!(s, 3, 0; )
    .ok (beginEvents s, 0)
  else do
    let _ ← ensureAskCapacity s price
    postAskAccepted s trader price size clientOrderIdLo clientOrderIdHi
      lastSlot lastTime

attribute [pf_inline] postAskWithClientAt

/-- 兼容宿主调用：client order id 为零。 -/
def postAskAt (s : State) (trader price size lastSlot lastTime nowSlot nowTime : UInt64) :
    Except Error (State × UInt64) :=
  postAskWithClientAt s trader price size 0 0 lastSlot lastTime nowSlot nowTime

attribute [pf_inline] postAskAt

/--
链上 free-funds ask 挂单；owner 由 account 1 signer 的完整 Pubkey 解析，slot/time
在入口各读取一次。调用者不能传入其他 trader 的内部 address。
-/
@[pf_entry]
def postAsk (s : State)
    (price size clientOrderIdLo clientOrderIdHi lastSlot lastTime : UInt64) :
    Except Error (State × UInt64) := do
  let trader ← requireTraderAddress s (signerKey 1) (accKeyWord 1 1)
    (accKeyWord 1 2) (accKeyWord 1 3)
  postAskWithClientAt s trader price size clientOrderIdLo clientOrderIdHi
    lastSlot lastTime clockSlot unixTime

/-- 兼容宿主调用：匿名 trader、无 TIF。 -/
def postAskFull (s : State) (price size : UInt64) : Except Error (State × UInt64) :=
  postAskAt s 0 price size 0 0 0 0

/-- `tickSize * price * baseLots`，在 UInt64 剖面内 fail closed。 -/
private def adjustedQuoteFor (s : State) (price size : UInt64) : Except Error UInt64 :=
  if size = 0 then .ok 0
  else if price = 0 then .error .overflow
  else if s.tickSize ≤ u64Max / price then
    let quotePerBase := s.tickSize * price
    if quotePerBase = 0 || size > u64Max / quotePerBase then .error .overflow
    else .ok (quotePerBase * size)
  else .error .overflow

/-- bid 的 quote collateral：`floor(tickSize * price * baseLots / baseLotsPerBaseUnit)`。 -/
private def bidCollateral (s : State) (price size : UInt64) : Except Error UInt64 := do
  if s.baseLotsPerBaseUnit = 0 then .error .overflow
  else .ok ((← adjustedQuoteFor s price size) / s.baseLotsPerBaseUnit)

attribute [pf_inline] adjustedQuoteFor bidCollateral

/--
固定容量 bid tree 插入。订单 ID 存官方编码 `~~~sequence`；in-order 是价格降序、
encoded sequence 降序，因此最小 topology address 仍是 best bid。满书时只有更高价能
驱逐 `get_max()` 的最差 bid。free-funds collateral 从 quoteFree 锁进 quoteLocked，
驱逐则按原价准确解锁旧订单。
-/
private def postBidAccepted (s : State)
    (trader price size clientOrderIdLo clientOrderIdHi lastSlot lastTime : UInt64) :
    Except Error (State × UInt64) := do
    let full := s.bidBook.count = 4
    let evictedAddress := if full then maxBookAddress s.bidBook else 0
    let evictedIndex := (evictedAddress.toNat - 1) % 4
    let oldSize := if evictedAddress = 0 then 0 else s.bidSizes[evictedIndex]!
    let oldPrice := if evictedAddress = 0 then 0 else s.bidPriceTicks[evictedIndex]!
    let newLock ← bidCollateral s price size
    let oldLock ← bidCollateral s oldPrice oldSize
    Id.run do
      let mut st := { s with
        matchStopped := 0, matchError := 0
        matchLevel := 0
        eventCount := 0, lastEvent := .uninitialized }
      for i in [0:17] do
        if i = 0 then
          let address := if full then evictedAddress else st.bidBook.freeHead
          let detachedBook :=
            if full then removeBookAddress st.bidBook evictedAddress else st.bidBook
          let oldTrader : UInt64 :=
            if evictedAddress = 0 then 0 else st.bidTraders[evictedIndex]!
          let funded := postBidFunds st trader oldTrader oldLock newLock
          let detached := { funded with bidBook := detachedBook }
          let encodedSequence := ~~~st.sequence
          let inserted := insertBidOrder detached address price encodedSequence
          let j := (address.toNat - 1) % 4
          st := { inserted with
            bidPriceTicks := inserted.bidPriceTicks.set j price
            bidSequences := inserted.bidSequences.set j encodedSequence
            bidTraders := inserted.bidTraders.set j trader
            bidSizes := inserted.bidSizes.set j size
            bidLastSlots := inserted.bidLastSlots.set j lastSlot
            bidLastTimes := inserted.bidLastTimes.set j lastTime
            sequence := st.sequence + 1
            matchStopped := address
            matchLevel := if full then 1 else 0 }
        else if i = 14 then
          if st.matchStopped ≠ (0 : UInt64) then
            if st.matchError = (0 : UInt64) then
              if st.matchLevel = (1 : UInt64) then
                let maker := s.bidTraders[evictedIndex]!
                let _ := recordPhoenix!(st, 3, 1;
                  .u8le 5, .u16le 0,
                  .u64le (makerKey0 s maker), .u64le (makerKey1 s maker),
                  .u64le (makerKey2 s maker), .u64le (makerKey3 s maker),
                  .u64le (~~~s.bidSequences[evictedIndex]!),
                  .u64le s.bidPriceTicks[evictedIndex]!, .u64le s.bidSizes[evictedIndex]!)
                st := appendEvent st
                  (.evict st.eventCount (makerKey0 s maker) (makerKey1 s maker)
                    (makerKey2 s maker) (makerKey3 s maker)
                    (~~~s.bidSequences[evictedIndex]!) s.bidPriceTicks[evictedIndex]!
                    s.bidSizes[evictedIndex]!)
        else if i = 15 then
          if st.matchStopped ≠ (0 : UInt64) then
            if st.matchError = (0 : UInt64) then
              let _ := recordPhoenix!(st, 3, 1;
                .u8le 3, .u16le 0, .u64le s.sequence,
                .u64le clientOrderIdLo, .u64le clientOrderIdHi,
                .u64le price, .u64le size)
              st := appendEvent st
                (.place st.eventCount s.sequence clientOrderIdLo clientOrderIdHi price size)
        else if i = 16 then
          if st.matchStopped ≠ (0 : UInt64) then
            if st.matchError = (0 : UInt64) then
              if lastSlot ≠ 0 || lastTime ≠ 0 then
                let _ := recordPhoenix!(st, 3, 1;
                  .u8le 8, .u16le 0,
                  .u64le s.sequence, .u64le lastSlot, .u64le lastTime)
                st := appendEvent st (.timeInForce st.eventCount s.sequence lastSlot lastTime)
      if st.matchError ≠ 0 then
        .error (errorOfMatch st.matchError)
      else if st.matchStopped = 0 then
        .error .overflow
        else
        .ok ({ st with matchStopped := 0, matchError := 0, matchLevel := 0 }, size)

attribute [pf_inline] postBidAccepted

def postBidWithClientAt (s : State)
    (trader price size clientOrderIdLo clientOrderIdHi lastSlot lastTime nowSlot nowTime : UInt64) :
    Except Error (State × UInt64) :=
  if price = 0 || size = 0 || maxOrderSequence ≤ s.sequence then
    .error .overflow
  else if expired lastSlot lastTime nowSlot nowTime then
    let _ := recordPhoenix!(s, 3, 0; )
    .ok (beginEvents s, 0)
  else do
    let _ ← ensureBidCapacity s price
    postBidAccepted s trader price size clientOrderIdLo clientOrderIdHi
      lastSlot lastTime

attribute [pf_inline] postBidWithClientAt

/-- 兼容宿主调用：client order id 为零。 -/
def postBidAt (s : State) (trader price size lastSlot lastTime nowSlot nowTime : UInt64) :
    Except Error (State × UInt64) :=
  postBidWithClientAt s trader price size 0 0 lastSlot lastTime nowSlot nowTime

attribute [pf_inline] postBidAt

/-- Bid-side signer adapter；不能以 instruction 参数伪造 resting-order owner。 -/
@[pf_entry]
def postBid (s : State)
    (price size clientOrderIdLo clientOrderIdHi lastSlot lastTime : UInt64) :
    Except Error (State × UInt64) := do
  let trader ← requireTraderAddress s (signerKey 1) (accKeyWord 1 1)
    (accKeyWord 1 2) (accKeyWord 1 3)
  postBidWithClientAt s trader price size clientOrderIdLo clientOrderIdHi
    lastSlot lastTime clockSlot unixTime

/-- Unlock canceled or expired ask inventory in its maker's authoritative TraderState. -/
private def unlockAskTrader (s : State) (maker amount : UInt64) : State :=
  if registeredSeat s maker then
    let i := maker.toNat - 1
    if amount > s.traderBaseLocked[i]! then
      { s with matchStopped := 1, matchError := 1 }
    else if s.traderBaseFree[i]! > u64Max - amount then
      { s with matchStopped := 1, matchError := 1 }
    else
      { s with
        traderBaseLocked := s.traderBaseLocked.set (i % 4)
          (s.traderBaseLocked[i]! - amount)
        traderBaseFree := s.traderBaseFree.set (i % 4)
          (s.traderBaseFree[i]! + amount) }
  else
    s

/-- Settle one ask fill to its maker: base leaves locked and quote becomes free. -/
private def fillAskTrader
    (s : State) (maker baseAmount quoteAmount : UInt64) : State :=
  if registeredSeat s maker then
    let i := maker.toNat - 1
    if baseAmount > s.traderBaseLocked[i]! then
      { s with matchStopped := 1, matchError := 1 }
    else if s.traderQuoteFree[i]! > u64Max - quoteAmount then
      { s with matchStopped := 1, matchError := 1 }
    else
      { s with
        traderBaseLocked := s.traderBaseLocked.set (i % 4)
          (s.traderBaseLocked[i]! - baseAmount)
        traderQuoteFree := s.traderQuoteFree.set (i % 4)
          (s.traderQuoteFree[i]! + quoteAmount) }
  else
    s

/-- Unlock canceled or expired bid collateral in its maker's TraderState. -/
private def unlockBidTrader (s : State) (maker quoteAmount : UInt64) : State :=
  if registeredSeat s maker then
    let i := maker.toNat - 1
    if quoteAmount > s.traderQuoteLocked[i]! then
      { s with matchStopped := 1, matchError := 1 }
    else if s.traderQuoteFree[i]! > u64Max - quoteAmount then
      { s with matchStopped := 1, matchError := 1 }
    else
      { s with
        traderQuoteLocked := s.traderQuoteLocked.set (i % 4)
          (s.traderQuoteLocked[i]! - quoteAmount)
        traderQuoteFree := s.traderQuoteFree.set (i % 4)
          (s.traderQuoteFree[i]! + quoteAmount) }
  else
    s

/-- Settle one bid fill to its maker: quote leaves locked and base becomes free. -/
private def fillBidTrader
    (s : State) (maker quoteAmount baseAmount : UInt64) : State :=
  if registeredSeat s maker then
    let i := maker.toNat - 1
    if quoteAmount > s.traderQuoteLocked[i]! then
      { s with matchStopped := 1, matchError := 1 }
    else if s.traderBaseFree[i]! > u64Max - baseAmount then
      { s with matchStopped := 1, matchError := 1 }
    else
      { s with
        traderQuoteLocked := s.traderQuoteLocked.set (i % 4)
          (s.traderQuoteLocked[i]! - quoteAmount)
        traderBaseFree := s.traderBaseFree.set (i % 4)
          (s.traderBaseFree[i]! + baseAmount) }
  else
    s

attribute [pf_inline] unlockAskTrader fillAskTrader unlockBidTrader fillBidTrader

/-- 扫书期间的瞬时 `MatchingEngineResponse`。不进入账户 schema。 -/
structure MatchAcc where
  sizes : Vector UInt64 4
  targetBase : UInt64
  filledBase : UInt64
  adjustedQuote : UInt64
  expiredBase : UInt64
  stopped : Bool
  events : Vector MarketEvent 5
  eventCount : UInt64
  lastEvent : MarketEvent
  deriving Repr, DecidableEq

private def MatchAcc.pushEvent (acc : MatchAcc) (event : MarketEvent) : Except Error MatchAcc :=
  if h : acc.eventCount.toNat < 5 then
    let indexed := event.withIndex acc.eventCount
    .ok { acc with
      events := acc.events.set acc.eventCount.toNat indexed
      eventCount := acc.eventCount + 1
      lastEvent := indexed }
  else
    .error .full

/--
沿 ask 树中序投影做至多四档的 IOC。过期单取消并继续；第一档超限即停止；
整档成交继续，部分成交终止。所有乘加都在 UInt64 剖面内 fail-closed。
-/
private def scanAsks (s : State) (taker limit nowSlot nowTime : UInt64)
    (behavior : SelfTradeBehavior)
    (fuel : Nat) (address : UInt64) (acc : MatchAcc) : Except Error MatchAcc :=
  match fuel with
  | 0 => .ok acc
  | fuel' + 1 => do
    if acc.stopped || acc.filledBase = acc.targetBase then
      .ok acc
    else if address ≠ 0 then
      let i := (address.toNat - 1) % 4
      let nextAddress := nextBookInOrder s.askBook address
      let size := acc.sizes[i]
      if size = 0 then
        scanAsks s taker limit nowSlot nowTime behavior fuel' nextAddress acc
      else if expired s.lastSlots[i] s.lastTimes[i] nowSlot nowTime then
        if acc.expiredBase ≤ u64Max - size then
          let maker := s.traders[i]
          let next ← acc.pushEvent
            (.expiredOrder 0 (makerKey0 s maker) (makerKey1 s maker)
              (makerKey2 s maker) (makerKey3 s maker)
              s.sequences[i] s.priceTicks[i] size)
          scanAsks s taker limit nowSlot nowTime behavior fuel' nextAddress
            { next with
              sizes := acc.sizes.set i 0
              expiredBase := acc.expiredBase + size }
        else
          .error .overflow
      else if limit < s.priceTicks[i] then
        .ok { acc with stopped := true }
      else if s.traders[i] = taker then
        match behavior with
        | .abort => .error .selfTrade
        | .cancelProvide =>
          if acc.expiredBase ≤ u64Max - size then
            let next ← acc.pushEvent (.reduce 0 s.sequences[i] s.priceTicks[i] size 0)
            scanAsks s taker limit nowSlot nowTime behavior fuel' nextAddress
              { next with
                sizes := acc.sizes.set i 0
                expiredBase := acc.expiredBase + size }
          else
            .error .overflow
        | .decrementTake =>
          let remaining := acc.targetBase - acc.filledBase
          let reduced := if remaining ≤ size then remaining else size
          if acc.expiredBase ≤ u64Max - reduced then
            let next ← acc.pushEvent
              (.reduce 0 s.sequences[i] s.priceTicks[i] reduced (size - reduced))
            scanAsks s taker limit nowSlot nowTime behavior fuel' nextAddress
              { next with
                sizes := acc.sizes.set i (size - reduced)
                targetBase := acc.targetBase - reduced
                expiredBase := acc.expiredBase + reduced
                stopped := reduced = remaining }
          else
            .error .overflow
      else
        let remaining := acc.targetBase - acc.filledBase
        let fill := if remaining ≤ size then remaining else size
        let price := s.priceTicks[i]
        if price = 0 || s.tickSize ≤ u64Max / price then
          let quotePerBase := price * s.tickSize
          if quotePerBase = 0 || fill ≤ u64Max / quotePerBase then
            let quote := quotePerBase * fill
            if acc.adjustedQuote ≤ u64Max - quote then
              let maker := s.traders[i]
              let next ← acc.pushEvent
                (.fill 0 (makerKey0 s maker) (makerKey1 s maker)
                  (makerKey2 s maker) (makerKey3 s maker)
                  s.sequences[i] price fill (size - fill))
              scanAsks s taker limit nowSlot nowTime behavior fuel' nextAddress
                { next with
                  sizes := acc.sizes.set i (size - fill)
                  targetBase := acc.targetBase
                  filledBase := acc.filledBase + fill
                  adjustedQuote := acc.adjustedQuote + quote
                  expiredBase := acc.expiredBase
                  stopped := fill = remaining }
            else
              .error .overflow
          else
            .error .overflow
        else
          .error .overflow
    else
      .ok acc

/-- Replay the bounded host event prefix into authoritative ask-maker seat balances. -/
private def applyAskEvents
    (s : State) (taker count : UInt64) (fuel i : Nat) : State :=
  match fuel with
  | 0 => s
  | fuel' + 1 =>
    if s.matchError ≠ 0 || count.toNat ≤ i then s
    else if h : i < 5 then
      let next :=
        match s.events[i] with
        | .expiredOrder _ maker0 maker1 maker2 maker3 _ _ removed =>
          let maker := traderAddressFor s maker0 maker1 maker2 maker3
          unlockAskTrader s maker removed
        | .reduce _ _ _ removed _ => unlockAskTrader s taker removed
        | .fill _ maker0 maker1 maker2 maker3 _ price filled _ =>
          let maker := traderAddressFor s maker0 maker1 maker2 maker3
          if s.baseLotsPerBaseUnit = 0 then
            { s with matchStopped := 1, matchError := 1 }
          else if price = 0 || s.tickSize = 0 then
            fillAskTrader s maker filled 0
          else
            match adjustedQuoteFor s price filled with
            | .error _ => { s with matchStopped := 1, matchError := 1 }
            | .ok adjusted =>
              let makerQuote := adjusted / s.baseLotsPerBaseUnit
              if s.matchMakerQuote > u64Max - makerQuote then
                { s with matchStopped := 1, matchError := 1 }
              else
                let ledger := fillAskTrader s maker filled makerQuote
                { ledger with matchMakerQuote := s.matchMakerQuote + makerQuote }
        | _ => s
      applyAskEvents next taker count fuel' (i + 1)
    else
      s

/-- Debit a registered free-funds buy taker's quote and credit received base, then project totals. -/
private def commitBuy
    (s : State) (taker filled expired quoteLots feeLots : UInt64) :
    Except Error (State × UInt64) :=
  if quoteLots > u64Max - feeLots then
    .error .overflow
  else
    let quoteDebit := quoteLots + feeLots
    if filled > u64Max - expired then
      .error .overflow
    else
      let baseDebit := filled + expired
      if baseDebit > s.baseLocked then
        .error .overflow
      else if s.unclaimedFees > u64Max - feeLots then
        .error .overflow
      else if registeredSeat s taker then
        if s.baseFree > u64Max - baseDebit then
          .error .overflow
        else
        let i := taker.toNat - 1
        if quoteDebit > s.traderQuoteFree[i]! then
          .error .overflow
        else if s.traderBaseFree[i]! > u64Max - filled then
          .error .overflow
        else if quoteDebit > s.quoteFree then
          .error .overflow
        else
          let remainingQuoteFree := s.quoteFree - quoteDebit
          if remainingQuoteFree > u64Max - s.matchMakerQuote then
            .error .overflow
          else
            .ok ({ s with
              traderQuoteFree := s.traderQuoteFree.set (i % 4)
                (s.traderQuoteFree[i]! - quoteDebit)
              traderBaseFree := s.traderBaseFree.set (i % 4)
                (s.traderBaseFree[i]! + filled)
              quoteFree := remainingQuoteFree + s.matchMakerQuote
              baseLocked := s.baseLocked - baseDebit
              baseFree := s.baseFree + baseDebit
              unclaimedFees := s.unclaimedFees + feeLots }, filled)
      else
        if s.quoteFree > u64Max - quoteLots then
          .error .overflow
        else if s.baseFree > u64Max - expired then
          .error .overflow
        else
          let _ := tokenTransferCheckedIx 7 2 4 6 0 quoteDebit 6
          let seeds : Array PdaSeed := #[.ascii "vault", .stateKey, .accKey 3]
          let _ := tokenTransferCheckedSignedIx 7 5 3 1 5 filled 6 seeds (findPdaSeeds seeds)
          .ok ({ s with
            quoteFree := s.quoteFree + quoteLots
            baseLocked := s.baseLocked - baseDebit
            baseFree := s.baseFree + expired
            unclaimedFees := s.unclaimedFees + feeLots }, filled)

attribute [pf_inline] commitBuy

/--
把聚合撮合结果结算到摊平 TraderState。注册 maker 的逐档余额先按 event replay
更新，注册 taker 的 quote-free / base-free 在 commit 中原子更新。

registered free-funds buy 从 taker 的 `quoteFree` 扣成交额和费用，并把成交 base
加进该 seat 的 `baseFree`。未注册 take-only 通过 classic SPL Token 双 vault 做实际
输入/输出，四个 aggregate 余额只同步投影 registered maker seat，不虚构 taker custody。
撮合只增加 `unclaimedFees`，`collectedFees` 留给独立收取动作。
-/
private def settleBuy (s : State) (taker clientOrderIdLo clientOrderIdHi : UInt64)
    (acc : MatchAcc) : Except Error (State × UInt64) :=
  if s.baseLotsPerBaseUnit = 0 then
    .error .overflow
  else if acc.adjustedQuote ≠ 0 && s.takerFeeBps > u64Max / acc.adjustedQuote then
    .error .overflow
  else
    let quoteLots := ceilDiv acc.adjustedQuote s.baseLotsPerBaseUnit
    let adjustedFee := ceilDiv (acc.adjustedQuote * s.takerFeeBps) 10000
    let feeLots := ceilDiv adjustedFee s.baseLotsPerBaseUnit
    let ledgerStart := { s with
      sizes := acc.sizes
      askBook := pruneBook s.askBook s.sizes acc.sizes
      events := acc.events
      eventCount := acc.eventCount
      lastEvent := acc.lastEvent
      matchMakerQuote := 0
      matchStopped := 0
      matchError := 0 }
    let ledger := applyAskEvents ledgerStart taker acc.eventCount 5 0
    if ledger.matchError ≠ 0 then
      .error (errorOfMatch ledger.matchError)
    else do
      let (settled, filled) ←
        commitBuy ledger taker acc.filledBase acc.expiredBase quoteLots feeLots
      finishWithEvent settled
        (.fillSummary settled.eventCount clientOrderIdLo clientOrderIdHi
          filled quoteLots feeLots) filled

/--
可测试的完整 N=4 IOC：红黑树中序跨档、严格 slot/time TIF、聚合费用和余额记账。
无流动性或首个有效价格超限是成功的零成交 IOC，不伪装成 overflow。
-/
def swapBuyForClientAt (s : State)
    (taker clientOrderIdLo clientOrderIdHi want limit nowSlot nowTime : UInt64)
    (behavior : SelfTradeBehavior) :
    Except Error (State × UInt64) := do
  let s := beginEvents s
  let acc ← scanAsks s taker limit nowSlot nowTime behavior 4 (minBookAddress s.askBook)
    { sizes := s.sizes, targetBase := want, filledBase := 0, adjustedQuote := 0,
      expiredBase := 0, stopped := false, events := s.events,
      eventCount := s.eventCount, lastEvent := s.lastEvent }
  settleBuy s taker clientOrderIdLo clientOrderIdHi acc

/-- 兼容宿主调用：client order id 为零。 -/
def swapBuyForAt (s : State) (taker want limit nowSlot nowTime : UInt64)
    (behavior : SelfTradeBehavior) : Except Error (State × UInt64) :=
  swapBuyForClientAt s taker 0 0 want limit nowSlot nowTime behavior

/-- 无自成交身份的兼容入口。 -/
def swapBuyAt (s : State) (want limit nowSlot nowTime : UInt64) :
    Except Error (State × UInt64) :=
  swapBuyForAt s u64Max want limit nowSlot nowTime .abort

/-- sell IOC 扫 bid 时的宿主 accumulator。 -/
structure SellAcc where
  sizes : Vector UInt64 4
  targetBase : UInt64
  filledBase : UInt64
  adjustedQuote : UInt64
  makerQuote : UInt64
  unlockedQuote : UInt64
  stopped : Bool
  events : Vector MarketEvent 5
  eventCount : UInt64
  lastEvent : MarketEvent
  deriving Repr, DecidableEq

private def SellAcc.pushEvent (acc : SellAcc) (event : MarketEvent) : Except Error SellAcc :=
  if h : acc.eventCount.toNat < 5 then
    let indexed := event.withIndex acc.eventCount
    .ok { acc with
      events := acc.events.set acc.eventCount.toNat indexed
      eventCount := acc.eventCount + 1
      lastEvent := indexed }
  else
    .error .full

private def scanBids (s : State) (taker limit nowSlot nowTime : UInt64)
    (behavior : SelfTradeBehavior)
    (fuel : Nat) (address : UInt64) (acc : SellAcc) : Except Error SellAcc :=
  match fuel with
  | 0 => .ok acc
  | fuel' + 1 => do
    if acc.stopped || acc.filledBase = acc.targetBase then
      .ok acc
    else if address ≠ 0 then
      let i := (address.toNat - 1) % 4
      let nextAddress := nextBookInOrder s.bidBook address
      let size := acc.sizes[i]
      if size = 0 then
        scanBids s taker limit nowSlot nowTime behavior fuel' nextAddress acc
      else if expired s.bidLastSlots[i] s.bidLastTimes[i] nowSlot nowTime then
        let unlocked ← bidCollateral s s.bidPriceTicks[i] size
        if acc.unlockedQuote ≤ u64Max - unlocked then
          let maker := s.bidTraders[i]
          let next ← acc.pushEvent
            (.expiredOrder 0 (makerKey0 s maker) (makerKey1 s maker)
              (makerKey2 s maker) (makerKey3 s maker)
              (~~~s.bidSequences[i]) s.bidPriceTicks[i] size)
          scanBids s taker limit nowSlot nowTime behavior fuel' nextAddress
            { next with
              sizes := acc.sizes.set i 0
              unlockedQuote := acc.unlockedQuote + unlocked }
        else
          .error .overflow
      else if s.bidPriceTicks[i] < limit then
        .ok { acc with stopped := true }
      else if s.bidTraders[i] = taker then
        match behavior with
        | .abort => .error .selfTrade
        | .cancelProvide =>
          let unlocked ← bidCollateral s s.bidPriceTicks[i] size
          if acc.unlockedQuote ≤ u64Max - unlocked then
            let next ← acc.pushEvent
              (.reduce 0 (~~~s.bidSequences[i]) s.bidPriceTicks[i] size 0)
            scanBids s taker limit nowSlot nowTime behavior fuel' nextAddress
              { next with
                sizes := acc.sizes.set i 0
                unlockedQuote := acc.unlockedQuote + unlocked }
          else
            .error .overflow
        | .decrementTake =>
          let remaining := acc.targetBase - acc.filledBase
          let reduced := if remaining ≤ size then remaining else size
          let unlocked ← bidCollateral s s.bidPriceTicks[i] reduced
          if acc.unlockedQuote ≤ u64Max - unlocked then
            let next ← acc.pushEvent
              (.reduce 0 (~~~s.bidSequences[i]) s.bidPriceTicks[i] reduced (size - reduced))
            scanBids s taker limit nowSlot nowTime behavior fuel' nextAddress
              { next with
                sizes := acc.sizes.set i (size - reduced)
                targetBase := acc.targetBase - reduced
                unlockedQuote := acc.unlockedQuote + unlocked
                stopped := reduced = remaining }
          else
            .error .overflow
      else
        let remaining := acc.targetBase - acc.filledBase
        let fill := if remaining ≤ size then remaining else size
        let adjusted ← adjustedQuoteFor s s.bidPriceTicks[i] fill
        let makerQuote ← bidCollateral s s.bidPriceTicks[i] fill
        if acc.adjustedQuote > u64Max - adjusted || acc.makerQuote > u64Max - makerQuote then
          .error .overflow
        else
          let maker := s.bidTraders[i]
          let next ← acc.pushEvent
            (.fill 0 (makerKey0 s maker) (makerKey1 s maker)
              (makerKey2 s maker) (makerKey3 s maker)
              (~~~s.bidSequences[i]) s.bidPriceTicks[i] fill (size - fill))
          scanBids s taker limit nowSlot nowTime behavior fuel' nextAddress
            { next with
              sizes := acc.sizes.set i (size - fill)
              targetBase := acc.targetBase
              filledBase := acc.filledBase + fill
              adjustedQuote := acc.adjustedQuote + adjusted
              makerQuote := acc.makerQuote + makerQuote
              unlockedQuote := acc.unlockedQuote
              stopped := fill = remaining }
    else
      .ok acc

/-- Replay the bounded host event prefix into authoritative bid-maker seat balances. -/
private def applySellEvents
    (s : State) (taker count : UInt64) (fuel i : Nat) : State :=
  match fuel with
  | 0 => s
  | fuel' + 1 =>
    if s.matchError ≠ 0 || count.toNat ≤ i then s
    else if h : i < 5 then
      let next :=
        match s.events[i] with
        | .expiredOrder _ maker0 maker1 maker2 maker3 _ price removed =>
          let maker := traderAddressFor s maker0 maker1 maker2 maker3
          match bidCollateral s price removed with
          | .ok quote => unlockBidTrader s maker quote
          | .error _ => { s with matchStopped := 1, matchError := 1 }
        | .reduce _ _ price removed _ =>
          match bidCollateral s price removed with
          | .ok quote => unlockBidTrader s taker quote
          | .error _ => { s with matchStopped := 1, matchError := 1 }
        | .fill _ maker0 maker1 maker2 maker3 _ price filled _ =>
          let maker := traderAddressFor s maker0 maker1 maker2 maker3
          match bidCollateral s price filled with
          | .ok quote => fillBidTrader s maker quote filled
          | .error _ => { s with matchStopped := 1, matchError := 1 }
        | _ => s
      applySellEvents next taker count fuel' (i + 1)
    else
      s

/-- Debit the registered sell taker's free base and credit net quote, then project totals. -/
private def commitSell
    (s : State) (taker filled unlocked makerQuote grossQuote feeLots : UInt64) :
    Except Error (State × UInt64) :=
  if grossQuote < feeLots then
    .error .overflow
  else if makerQuote > u64Max - unlocked then
    .error .overflow
  else
    let quoteDebit := makerQuote + unlocked
    let takerQuote := grossQuote - feeLots
    if quoteDebit > s.quoteLocked then
      .error .overflow
    else
      if s.unclaimedFees > u64Max - feeLots then
        .error .overflow
      else if registeredSeat s taker then
        if filled > s.baseFree then
          .error .overflow
        else if takerQuote > u64Max - unlocked then
          .error .overflow
        else
        let quoteCredit := takerQuote + unlocked
        if s.quoteFree > u64Max - quoteCredit then
          .error .overflow
        else
        let i := taker.toNat - 1
        if filled > s.traderBaseFree[i]! then
          .error .overflow
        else if s.traderQuoteFree[i]! > u64Max - takerQuote then
          .error .overflow
        else
          .ok ({ s with
            traderBaseFree := s.traderBaseFree.set (i % 4)
              (s.traderBaseFree[i]! - filled)
            traderQuoteFree := s.traderQuoteFree.set (i % 4)
              (s.traderQuoteFree[i]! + takerQuote)
            quoteLocked := s.quoteLocked - quoteDebit
            quoteFree := s.quoteFree + quoteCredit
            unclaimedFees := s.unclaimedFees + feeLots }, filled)
      else
        if s.quoteFree > u64Max - unlocked then
          .error .overflow
        else if s.baseFree > u64Max - filled then
          .error .overflow
        else
          let _ := tokenTransferCheckedIx 7 1 3 5 0 filled 6
          let seeds : Array PdaSeed := #[.ascii "vault", .stateKey, .accKey 4]
          let _ := tokenTransferCheckedSignedIx
            7 6 4 2 6 takerQuote 6 seeds (findPdaSeeds seeds)
          .ok ({ s with
            quoteLocked := s.quoteLocked - quoteDebit
            quoteFree := s.quoteFree + unlocked
            baseFree := s.baseFree + filled
            unclaimedFees := s.unclaimedFees + feeLots }, filled)

attribute [pf_inline] commitSell

private def settleSell (s : State) (taker clientOrderIdLo clientOrderIdHi : UInt64)
    (acc : SellAcc) : Except Error (State × UInt64) :=
  if s.baseLotsPerBaseUnit = 0 then
    .error .overflow
  else if acc.adjustedQuote ≠ 0 && s.takerFeeBps > u64Max / acc.adjustedQuote then
    .error .overflow
  else
    let grossQuote := acc.adjustedQuote / s.baseLotsPerBaseUnit
    let adjustedFee := ceilDiv (acc.adjustedQuote * s.takerFeeBps) 10000
    let feeLots := ceilDiv adjustedFee s.baseLotsPerBaseUnit
    let ledgerStart := { s with
      bidSizes := acc.sizes
      bidBook := pruneBook s.bidBook s.bidSizes acc.sizes
      events := acc.events
      eventCount := acc.eventCount
      lastEvent := acc.lastEvent
      matchStopped := 0
      matchError := 0 }
    let ledger := applySellEvents ledgerStart taker acc.eventCount 5 0
    if ledger.matchError ≠ 0 then
      .error (errorOfMatch ledger.matchError)
    else do
      let (settled, filled) ← commitSell ledger taker acc.filledBase acc.unlockedQuote
        acc.makerQuote grossQuote feeLots
      finishWithEvent settled
        (.fillSummary settled.eventCount clientOrderIdLo clientOrderIdHi
          filled grossQuote feeLots) filled

/-- 可测试的 N=4 sell IOC 宿主语义。 -/
def swapSellForClientAt (s : State)
    (taker clientOrderIdLo clientOrderIdHi want limit nowSlot nowTime : UInt64)
    (behavior : SelfTradeBehavior) : Except Error (State × UInt64) := do
  let s := beginEvents s
  let acc ← scanBids s taker limit nowSlot nowTime behavior 4 (minBookAddress s.bidBook)
    { sizes := s.bidSizes, targetBase := want, filledBase := 0, adjustedQuote := 0,
      makerQuote := 0, unlockedQuote := 0, stopped := false, events := s.events,
      eventCount := s.eventCount, lastEvent := s.lastEvent }
  settleSell s taker clientOrderIdLo clientOrderIdHi acc

/-- 兼容宿主调用：client order id 为零。 -/
def swapSellForAt (s : State) (taker want limit nowSlot nowTime : UInt64)
    (behavior : SelfTradeBehavior) : Except Error (State × UInt64) :=
  swapSellForClientAt s taker 0 0 want limit nowSlot nowTime behavior

def swapSellAt (s : State) (want limit nowSlot nowTime : UInt64) :
    Except Error (State × UInt64) :=
  swapSellForAt s u64Max want limit nowSlot nowTime .abort

/-- Ask-fold cancellation/expiry: update the book accumulator and its maker seat together. -/
private def unlockAskFold (s : State) (j : Nat) (amount : UInt64) : State :=
  let size := s.sizes[j]!
  if size < amount then
    { s with matchStopped := 1, matchError := 1 }
  else if s.matchExpired > u64Max - amount then
    { s with matchStopped := 1, matchError := 1 }
  else
    let ledger := unlockAskTrader s s.traders[j]! amount
    let nextSize := size - amount
    let askBook :=
      if nextSize = 0 then removeBookAddress s.askBook (UInt64.ofNat (j + 1)) else s.askBook
    { ledger with
      sizes := s.sizes.set (j % 4) nextSize
      askBook := askBook
      matchExpired := s.matchExpired + amount }

/-- Ask-fold fill: update its maker seat and all quote/base accumulators in one transition. -/
private def fillAskFold (s : State) (j : Nat) (fill : UInt64) : State :=
  let size := s.sizes[j]!
  let price := s.priceTicks[j]!
  if size < fill then
    { s with matchStopped := 1, matchError := 1 }
  else if s.baseLotsPerBaseUnit = 0 then
    { s with matchStopped := 1, matchError := 1 }
  else if price ≠ 0 && s.tickSize > u64Max / price then
    { s with matchStopped := 1, matchError := 1 }
  else
    let quotePerBase := price * s.tickSize
    if quotePerBase ≠ 0 && fill > u64Max / quotePerBase then
      { s with matchStopped := 1, matchError := 1 }
    else
      let adjusted := quotePerBase * fill
      let makerQuote := adjusted / s.baseLotsPerBaseUnit
      if s.matchQuote > u64Max - adjusted then
        { s with matchStopped := 1, matchError := 1 }
      else if s.matchMakerQuote > u64Max - makerQuote then
        { s with matchStopped := 1, matchError := 1 }
      else if s.matchFilled > u64Max - fill then
        { s with matchStopped := 1, matchError := 1 }
      else
        let ledger := fillAskTrader s s.traders[j]! fill makerQuote
        let nextSize := size - fill
        let askBook :=
          if nextSize = 0 then removeBookAddress s.askBook (UInt64.ofNat (j + 1)) else s.askBook
        { ledger with
          sizes := s.sizes.set (j % 4) nextSize
          askBook := askBook
          matchFilled := s.matchFilled + fill
          matchQuote := s.matchQuote + adjusted
          matchMakerQuote := s.matchMakerQuote + makerQuote }

private def finishFold (s : State) (taker quoteLots feeLots : UInt64) :
    Except Error (State × UInt64) :=
  commitBuy s taker s.matchFilled s.matchExpired quoteLots feeLots

private def settleFold (s : State) (taker : UInt64) : Except Error (State × UInt64) :=
  if s.matchError ≠ 0 then throwMatch s.matchError
  else finishFold s taker s.matchQuote s.matchLimit

attribute [pf_inline] unlockAskFold fillAskFold finishFold settleFold

/--
链上 N=4 IOC。`behavior`：0=Abort、1=CancelProvide、2=DecrementTake。
十九次 state-carrying bounded fold：第 0 次清瞬时响应，接着十六次按四档 ×
（slot TIF、time TIF、撮合、advance）推进，第 17 次计算结算数值，第 18 次追加
summary。把算术和动态 event write 分 phase，避免 checked-arithmetic continuation
复制动态 variant-vector write；循环 store 会继续下一次，不再静态复制后续档位。
-/
private def swapBuyFold (s : State)
    (taker behavior clientOrderIdLo clientOrderIdHi want limit : UInt64) :
    Except Error (State × UInt64) := Id.run do
  let mut st := beginEvents s
  for i in [0:19] do
    if i = 0 then
      st := { st with
        matchFilled := 0, matchQuote := 0, matchMakerQuote := 0, matchExpired := 0,
        matchStopped := 0, matchError := 0, matchLevel := 0,
        matchWant := want, matchLimit := limit }
    else if i = 17 then
      if st.matchError = 0 then
        if st.baseLotsPerBaseUnit = 0 then
          st := { st with matchError := 1 }
        else if st.matchQuote = 0 then
          st := { st with matchQuote := 0, matchLimit := 0 }
        else
          let quoteLots := (st.matchQuote - 1) / st.baseLotsPerBaseUnit + 1
          if st.takerFeeBps = 0 then
            st := { st with matchQuote := quoteLots, matchLimit := 0 }
          else if st.takerFeeBps ≤ u64Max / st.matchQuote then
            let feeProduct := st.matchQuote * st.takerFeeBps
            let adjustedFee := (feeProduct - 1) / 10000 + 1
            let feeLots := (adjustedFee - 1) / st.baseLotsPerBaseUnit + 1
            st := { st with matchQuote := quoteLots, matchLimit := feeLots }
          else
            st := { st with matchError := 1 }
    else if i = 18 then
      if st.matchError = 0 then
        let _ := recordPhoenix!(st, 0, 1;
          .u8le 6, .u16le 0, .u64le clientOrderIdLo, .u64le clientOrderIdHi,
          .u64le st.matchFilled, .u64le st.matchQuote, .u64le st.matchLimit)
        st := appendEvent st
          (.fillSummary st.eventCount clientOrderIdLo clientOrderIdHi
            st.matchFilled st.matchQuote st.matchLimit)
    else if st.matchStopped = 0 then
      let k := i - 1
      let phase := k % 4
      let address := if phase = 0 then minBookAddress st.askBook else st.matchLevel
      let j := (address.toNat - 1) % 4
      let size := if address = 0 then 0 else st.sizes[j]!
      if address = 0 then
        st := { st with matchStopped := 1 }
      else if st.matchFilled = st.matchWant then
        st := { st with matchStopped := 1 }
      else if phase = 3 then
        st := { st with matchLevel := 0 }
      else if size ≠ 0 then
        if phase = 0 then
          st := { st with matchLevel := address }
          if st.lastSlots[j]! ≠ 0 then
            if st.lastSlots[j]! < clockSlot then
              let unlocked := unlockAskFold st j size
              let maker := st.traders[j]!
              let _ := recordPhoenix!(unlocked, 0, 1;
                .u8le 9, .u16le 0,
                .u64le (makerKey0 st maker), .u64le (makerKey1 st maker),
                .u64le (makerKey2 st maker), .u64le (makerKey3 st maker),
                .u64le st.sequences[j]!, .u64le st.priceTicks[j]!, .u64le size)
              st := appendEvent unlocked
                (.expiredOrder st.eventCount (makerKey0 st maker) (makerKey1 st maker)
                  (makerKey2 st maker) (makerKey3 st maker)
                  st.sequences[j]! st.priceTicks[j]! size)
        else if phase = 1 then
          if st.lastTimes[j]! ≠ 0 then
            if st.lastTimes[j]! < unixTime then
              let unlocked := unlockAskFold st j size
              let maker := st.traders[j]!
              let _ := recordPhoenix!(unlocked, 0, 1;
                .u8le 9, .u16le 0,
                .u64le (makerKey0 st maker), .u64le (makerKey1 st maker),
                .u64le (makerKey2 st maker), .u64le (makerKey3 st maker),
                .u64le st.sequences[j]!, .u64le st.priceTicks[j]!, .u64le size)
              st := appendEvent unlocked
                (.expiredOrder st.eventCount (makerKey0 st maker) (makerKey1 st maker)
                  (makerKey2 st maker) (makerKey3 st maker)
                  st.sequences[j]! st.priceTicks[j]! size)
        else if phase = 2 then
          if st.matchLimit < st.priceTicks[j]! then
            st := { st with matchStopped := 1 }
          else if st.traders[j]! ≠ taker then
            let remaining := st.matchWant - st.matchFilled
            if remaining ≤ size then
              let filled := fillAskFold st j remaining
              let maker := st.traders[j]!
              let _ := recordPhoenix!(filled, 0, 1;
                .u8le 2, .u16le 0,
                .u64le (makerKey0 st maker), .u64le (makerKey1 st maker),
                .u64le (makerKey2 st maker), .u64le (makerKey3 st maker),
                .u64le st.sequences[j]!, .u64le st.priceTicks[j]!,
                .u64le remaining, .u64le (size - remaining))
              st := appendEvent { filled with matchStopped := 1 }
                (.fill st.eventCount (makerKey0 st maker) (makerKey1 st maker)
                  (makerKey2 st maker) (makerKey3 st maker)
                  st.sequences[j]! st.priceTicks[j]! remaining (size - remaining))
            else
              let filled := fillAskFold st j size
              let maker := st.traders[j]!
              let _ := recordPhoenix!(filled, 0, 1;
                .u8le 2, .u16le 0,
                .u64le (makerKey0 st maker), .u64le (makerKey1 st maker),
                .u64le (makerKey2 st maker), .u64le (makerKey3 st maker),
                .u64le st.sequences[j]!, .u64le st.priceTicks[j]!,
                .u64le size, .u64le 0)
              st := appendEvent filled
                (.fill st.eventCount (makerKey0 st maker) (makerKey1 st maker)
                  (makerKey2 st maker) (makerKey3 st maker)
                  st.sequences[j]! st.priceTicks[j]! size 0)
          else if behavior = 0 then
            st := { st with matchStopped := 1, matchError := matchSelfTrade }
          else if behavior = 1 then
            let unlocked := unlockAskFold st j size
            let _ := recordPhoenix!(unlocked, 0, 1;
              .u8le 4, .u16le 0,
              .u64le st.sequences[j]!, .u64le st.priceTicks[j]!,
              .u64le size, .u64le 0)
            st := appendEvent unlocked
              (.reduce st.eventCount st.sequences[j]! st.priceTicks[j]! size 0)
          else if behavior = 2 then
            let remaining := st.matchWant - st.matchFilled
            if remaining ≤ size then
              let unlocked := unlockAskFold st j remaining
              let _ := recordPhoenix!(unlocked, 0, 1;
                .u8le 4, .u16le 0,
                .u64le st.sequences[j]!, .u64le st.priceTicks[j]!,
                .u64le remaining, .u64le (size - remaining))
              st := appendEvent
                { unlocked with
                  matchWant := st.matchWant - remaining
                  matchStopped := 1 }
                (.reduce st.eventCount st.sequences[j]! st.priceTicks[j]!
                  remaining (size - remaining))
            else
              let unlocked := unlockAskFold st j size
              let _ := recordPhoenix!(unlocked, 0, 1;
                .u8le 4, .u16le 0,
                .u64le st.sequences[j]!, .u64le st.priceTicks[j]!,
                .u64le size, .u64le 0)
              st := appendEvent { unlocked with matchWant := st.matchWant - size }
                (.reduce st.eventCount st.sequences[j]! st.priceTicks[j]! size 0)
          else
            st := { st with matchStopped := 1, matchError := 1 }
  settleFold st taker

attribute [pf_inline] swapBuyFold

/-- SVM take-only/free-funds adapter; self-trade identity always comes from account 1 signer. -/
@[pf_entry]
def swapBuy (s : State)
    (behavior clientOrderIdLo clientOrderIdHi want limit : UInt64) :
    Except Error (State × UInt64) := do
  let taker ← optionalTraderAddress s (signerKey 1) (accKeyWord 1 1)
    (accKeyWord 1 2) (accKeyWord 1 3)
  swapBuyFold s taker behavior clientOrderIdLo clientOrderIdHi want limit

/-- sell fold 中减少 resting bid，并累计要解锁的 quote collateral。 -/
private def unlockBidFold (s : State) (j : Nat) (amount : UInt64) : State :=
  let size := s.bidSizes[j]!
  let price := s.bidPriceTicks[j]!
  if size < amount then
    { s with matchStopped := 1, matchError := 1 }
  else if s.baseLotsPerBaseUnit = 0 then
    { s with matchStopped := 1, matchError := 1 }
  else if price = 0 then
    { s with matchStopped := 1, matchError := 1 }
  else if s.tickSize ≤ u64Max / price then
    let quotePerBase := s.tickSize * price
    if quotePerBase = 0 then
      { s with matchStopped := 1, matchError := 1 }
    else if amount > u64Max / quotePerBase then
      { s with matchStopped := 1, matchError := 1 }
    else
      let unlocked := (quotePerBase * amount) / s.baseLotsPerBaseUnit
      if s.matchExpired ≤ u64Max - unlocked then
        let ledger := unlockBidTrader s s.bidTraders[j]! unlocked
        let nextSize := size - amount
        let bidBook :=
          if nextSize = 0 then removeBookAddress s.bidBook (UInt64.ofNat (j + 1)) else s.bidBook
        { ledger with
          bidSizes := s.bidSizes.set (j % 4) nextSize
          bidBook := bidBook
          matchExpired := s.matchExpired + unlocked }
      else
        { s with matchStopped := 1, matchError := 1 }
  else
    { s with matchStopped := 1, matchError := 1 }

/-- sell fold 中成交 resting bid，并累计 adjusted quote 和 maker quote debit。 -/
private def fillBidFold (s : State) (j : Nat) (fill : UInt64) : State :=
  let size := s.bidSizes[j]!
  let price := s.bidPriceTicks[j]!
  if size < fill then
    { s with matchStopped := 1, matchError := 1 }
  else if s.baseLotsPerBaseUnit = 0 then
    { s with matchStopped := 1, matchError := 1 }
  else if price = 0 then
    { s with matchStopped := 1, matchError := 1 }
  else if s.tickSize ≤ u64Max / price then
    let quotePerBase := s.tickSize * price
    if quotePerBase = 0 then
      { s with matchStopped := 1, matchError := 1 }
    else if fill > u64Max / quotePerBase then
      { s with matchStopped := 1, matchError := 1 }
    else
      let adjusted := quotePerBase * fill
      let makerQuote := adjusted / s.baseLotsPerBaseUnit
      if s.matchQuote > u64Max - adjusted then
        { s with matchStopped := 1, matchError := 1 }
      else if s.matchMakerQuote > u64Max - makerQuote then
        { s with matchStopped := 1, matchError := 1 }
      else if s.matchFilled > u64Max - fill then
        { s with matchStopped := 1, matchError := 1 }
      else
        let ledger := fillBidTrader s s.bidTraders[j]! makerQuote fill
        let nextSize := size - fill
        let bidBook :=
          if nextSize = 0 then removeBookAddress s.bidBook (UInt64.ofNat (j + 1)) else s.bidBook
        { ledger with
          bidSizes := s.bidSizes.set (j % 4) nextSize
          bidBook := bidBook
          matchFilled := s.matchFilled + fill
          matchQuote := s.matchQuote + adjusted
          matchMakerQuote := s.matchMakerQuote + makerQuote }
  else
    { s with matchStopped := 1, matchError := 1 }

attribute [pf_inline] unlockBidFold fillBidFold

private def commitSellFold (s : State) (taker grossQuote feeLots : UInt64) :
    Except Error (State × UInt64) :=
  commitSell s taker s.matchFilled s.matchExpired s.matchMakerQuote grossQuote feeLots

private def settleSellFold (s : State) (taker : UInt64) : Except Error (State × UInt64) :=
  if s.matchError ≠ 0 then throwMatch s.matchError
  else commitSellFold s taker s.matchLimit s.matchWant

attribute [pf_inline] commitSellFold settleSellFold

/--
链上 N=4 sell IOC。与 buy 一样使用十九次 state-carrying bounded fold：第 0 次
清瞬时响应，接着十六次按四档 ×（slot TIF、time TIF、撮合、advance）推进，
第 17 次计算结算数值，第 18 次追加 summary。内联 State helper 的结果可直接接
typed event 动态写，不再借 `lastEvent` 跨 phase 暂存完整 variant。
-/
private def swapSellFold (s : State)
    (taker behavior clientOrderIdLo clientOrderIdHi want limit : UInt64) :
    Except Error (State × UInt64) := Id.run do
  let mut st := beginEvents s
  for i in [0:19] do
    if i = 0 then
      st := { st with
        matchFilled := 0, matchQuote := 0, matchMakerQuote := 0, matchExpired := 0,
        matchStopped := 0, matchError := 0, matchLevel := 0,
        matchWant := want, matchLimit := limit }
    else if i = 17 then
      if st.matchError = 0 then
        if st.baseLotsPerBaseUnit = 0 then
          st := { st with matchError := 1 }
        else
          let grossQuote := st.matchQuote / st.baseLotsPerBaseUnit
          if st.matchQuote = 0 then
            st := { st with matchLimit := grossQuote, matchWant := 0 }
          else if st.takerFeeBps = 0 then
            st := { st with matchLimit := grossQuote, matchWant := 0 }
          else if st.takerFeeBps ≤ u64Max / st.matchQuote then
            let feeProduct := st.matchQuote * st.takerFeeBps
            let adjustedFee := (feeProduct - 1) / 10000 + 1
            let feeLots := (adjustedFee - 1) / st.baseLotsPerBaseUnit + 1
            st := { st with matchLimit := grossQuote, matchWant := feeLots }
          else
            st := { st with matchError := 1 }
    else if i = 18 then
      if st.matchError = 0 then
        let _ := recordPhoenix!(st, 0, 1;
          .u8le 6, .u16le 0, .u64le clientOrderIdLo, .u64le clientOrderIdHi,
          .u64le st.matchFilled, .u64le st.matchLimit, .u64le st.matchWant)
        st := appendEvent st
          (.fillSummary st.eventCount clientOrderIdLo clientOrderIdHi
            st.matchFilled st.matchLimit st.matchWant)
    else if st.matchStopped = 0 then
      let k := i - 1
      let phase := k % 4
      let address := if phase = 0 then minBookAddress st.bidBook else st.matchLevel
      let j := (address.toNat - 1) % 4
      let size := if address = 0 then 0 else st.bidSizes[j]!
      if address = 0 then
        st := { st with matchStopped := 1 }
      else if st.matchFilled = st.matchWant then
        st := { st with matchStopped := 1 }
      else if phase = 3 then
        st := { st with matchLevel := 0 }
      else if size ≠ 0 then
        if phase = 0 then
          st := { st with matchLevel := address }
          if st.bidLastSlots[j]! ≠ 0 then
            if st.bidLastSlots[j]! < clockSlot then
              let unlocked := unlockBidFold st j size
              let maker := st.bidTraders[j]!
              let _ := recordPhoenix!(unlocked, 0, 1;
                .u8le 9, .u16le 0,
                .u64le (makerKey0 st maker), .u64le (makerKey1 st maker),
                .u64le (makerKey2 st maker), .u64le (makerKey3 st maker),
                .u64le (~~~st.bidSequences[j]!),
                .u64le st.bidPriceTicks[j]!, .u64le size)
              st := appendEvent unlocked
                (.expiredOrder st.eventCount
                  (makerKey0 st maker) (makerKey1 st maker)
                  (makerKey2 st maker) (makerKey3 st maker)
                  (~~~st.bidSequences[j]!) st.bidPriceTicks[j]! size)
        else if phase = 1 then
          if st.bidLastTimes[j]! ≠ 0 then
            if st.bidLastTimes[j]! < unixTime then
              let unlocked := unlockBidFold st j size
              let maker := st.bidTraders[j]!
              let _ := recordPhoenix!(unlocked, 0, 1;
                .u8le 9, .u16le 0,
                .u64le (makerKey0 st maker), .u64le (makerKey1 st maker),
                .u64le (makerKey2 st maker), .u64le (makerKey3 st maker),
                .u64le (~~~st.bidSequences[j]!),
                .u64le st.bidPriceTicks[j]!, .u64le size)
              st := appendEvent unlocked
                (.expiredOrder st.eventCount
                  (makerKey0 st maker) (makerKey1 st maker)
                  (makerKey2 st maker) (makerKey3 st maker)
                  (~~~st.bidSequences[j]!) st.bidPriceTicks[j]! size)
        else if phase = 2 then
          if st.bidPriceTicks[j]! < st.matchLimit then
            st := { st with matchStopped := 1 }
          else if st.bidTraders[j]! ≠ taker then
            let remaining := st.matchWant - st.matchFilled
            if remaining ≤ size then
              let filled := fillBidFold st j remaining
              let maker := st.bidTraders[j]!
              let _ := recordPhoenix!(filled, 0, 1;
                .u8le 2, .u16le 0,
                .u64le (makerKey0 st maker), .u64le (makerKey1 st maker),
                .u64le (makerKey2 st maker), .u64le (makerKey3 st maker),
                .u64le (~~~st.bidSequences[j]!), .u64le st.bidPriceTicks[j]!,
                .u64le remaining, .u64le (size - remaining))
              st := appendEvent { filled with matchStopped := 1 }
                (.fill st.eventCount
                  (makerKey0 st maker) (makerKey1 st maker)
                  (makerKey2 st maker) (makerKey3 st maker)
                  (~~~st.bidSequences[j]!) st.bidPriceTicks[j]! remaining (size - remaining))
            else
              let filled := fillBidFold st j size
              let maker := st.bidTraders[j]!
              let _ := recordPhoenix!(filled, 0, 1;
                .u8le 2, .u16le 0,
                .u64le (makerKey0 st maker), .u64le (makerKey1 st maker),
                .u64le (makerKey2 st maker), .u64le (makerKey3 st maker),
                .u64le (~~~st.bidSequences[j]!), .u64le st.bidPriceTicks[j]!,
                .u64le size, .u64le 0)
              st := appendEvent filled
                (.fill st.eventCount
                  (makerKey0 st maker) (makerKey1 st maker)
                  (makerKey2 st maker) (makerKey3 st maker)
                  (~~~st.bidSequences[j]!) st.bidPriceTicks[j]! size 0)
          else if behavior = 0 then
            st := { st with matchStopped := 1, matchError := matchSelfTrade }
          else if behavior = 1 then
            let unlocked := unlockBidFold st j size
            let _ := recordPhoenix!(unlocked, 0, 1;
              .u8le 4, .u16le 0,
              .u64le (~~~st.bidSequences[j]!), .u64le st.bidPriceTicks[j]!,
              .u64le size, .u64le 0)
            st := appendEvent unlocked
              (.reduce st.eventCount
                (~~~st.bidSequences[j]!) st.bidPriceTicks[j]! size 0)
          else if behavior = 2 then
            let remaining := st.matchWant - st.matchFilled
            if remaining ≤ size then
              let unlocked := unlockBidFold st j remaining
              let _ := recordPhoenix!(unlocked, 0, 1;
                .u8le 4, .u16le 0,
                .u64le (~~~st.bidSequences[j]!), .u64le st.bidPriceTicks[j]!,
                .u64le remaining, .u64le (size - remaining))
              st := appendEvent
                { unlocked with
                  matchWant := st.matchWant - remaining
                  matchStopped := 1 }
                (.reduce st.eventCount (~~~st.bidSequences[j]!) st.bidPriceTicks[j]!
                  remaining (size - remaining))
            else
              let unlocked := unlockBidFold st j size
              let _ := recordPhoenix!(unlocked, 0, 1;
                .u8le 4, .u16le 0,
                .u64le (~~~st.bidSequences[j]!), .u64le st.bidPriceTicks[j]!,
                .u64le size, .u64le 0)
              st := appendEvent { unlocked with matchWant := st.matchWant - size }
                (.reduce st.eventCount
                  (~~~st.bidSequences[j]!) st.bidPriceTicks[j]! size 0)
          else
            st := { st with matchStopped := 1, matchError := 1 }
  settleSellFold st taker

attribute [pf_inline] swapSellFold

/-- Bid-side SVM adapter with signer-derived self-trade identity. -/
@[pf_entry]
def swapSell (s : State)
    (behavior clientOrderIdLo clientOrderIdHi want limit : UInt64) :
    Except Error (State × UInt64) := do
  let taker ← optionalTraderAddress s (signerKey 1) (accKeyWord 1 1)
    (accKeyWord 1 2) (accKeyWord 1 3)
  swapSellFold s taker behavior clientOrderIdLo clientOrderIdHi want limit

/--
官方 `reduce_order_inner` 的 ask-side bounded 版本：按 `(price, sequence)` 找订单，
校验内部 seat address，减少 `min(qty, restingSize)`，并把对应 trader 的 base
从 locked 解到 free。aggregate balance 暂时同步维护，供尚未迁移的 matching path
使用；它是 per-seat ledger 的兼容投影，不再是 owner 授权来源。
缺失订单成功返回 0；错误 owner、无效 seat 和账本不一致 fail closed。
-/
def reduceAskAt (s : State) (trader price sequence qty : UInt64) :
    Except Error (State × UInt64) :=
  if trader = 0 || 4 < trader then
    .error .overflow
  else
    let traderIndex := trader.toNat - 1
    if s.traderUsed[traderIndex]! = 0 then
      .error .overflow
    else Id.run do
      let s := beginEvents s
      if qty = 0 then
        let _ := recordPhoenix!(s, 5, 0; )
        .ok (s, 0)
      else
        let mut st := { s with matchFilled := 0, matchStopped := 0, matchError := 0 }
        for i in [0:4] do
          if st.matchStopped = (0 : UInt64) then
            let j : Nat := i
            let size : UInt64 := st.sizes[j]!
            if size ≠ (0 : UInt64) then
              if st.priceTicks[j]! = price then
                if st.sequences[j]! = sequence then
                  if st.traders[j]! = trader then
                    let removed := if qty ≤ size then qty else size
                    if removed ≤ st.traderBaseLocked[traderIndex]! then
                      if st.traderBaseFree[traderIndex]! ≤ u64Max - removed then
                        if removed ≤ st.baseLocked then
                          if st.baseFree ≤ u64Max - removed then
                            let nextSize := size - removed
                            let reduced := { st with
                              sizes := st.sizes.set (j % 4) nextSize
                              askBook := if nextSize = 0 then
                                removeBookAddress st.askBook (UInt64.ofNat (j + 1))
                              else st.askBook
                              traderBaseLocked := st.traderBaseLocked.set
                                (traderIndex % 4) (st.traderBaseLocked[traderIndex]! - removed)
                              traderBaseFree := st.traderBaseFree.set
                                (traderIndex % 4) (st.traderBaseFree[traderIndex]! + removed)
                              baseLocked := st.baseLocked - removed
                              baseFree := st.baseFree + removed
                              matchFilled := removed
                              matchStopped := 1 }
                            let _ := recordPhoenix!(reduced, 5, 1;
                              .u8le 4, .u16le 0,
                              .u64le sequence, .u64le price,
                              .u64le removed, .u64le (size - removed))
                            st := appendEvent reduced
                              (.reduce reduced.eventCount sequence price removed (size - removed))
                          else
                            st := { st with matchStopped := 1, matchError := 1 }
                        else
                          st := { st with matchStopped := 1, matchError := 1 }
                      else
                        st := { st with matchStopped := 1, matchError := 1 }
                    else
                      st := { st with matchStopped := 1, matchError := 1 }
                  else
                    st := { st with matchStopped := 1, matchError := 1 }
        if st.matchError ≠ 0 then
          .error (errorOfMatch st.matchError)
        else
          let reduced := st.matchFilled
          if st.eventCount = 0 then
            let _ := recordPhoenix!(st, 5, 0; )
            .ok ({ st with matchFilled := 0, matchStopped := 0, matchError := 0 }, reduced)
          else
            .ok ({ st with matchFilled := 0, matchStopped := 0, matchError := 0 }, reduced)

/-- bid reduce/cancel 按 encoded order id 查找，并按原价解锁 quote collateral。 -/
def reduceBidAt (s : State) (trader price sequence qty : UInt64) :
    Except Error (State × UInt64) :=
  if trader = 0 || 4 < trader then
    .error .overflow
  else
    let traderIndex := trader.toNat - 1
    if s.traderUsed[traderIndex]! = 0 then
      .error .overflow
    else Id.run do
      let s := beginEvents s
      if qty = 0 then
        let _ := recordPhoenix!(s, 5, 0; )
        .ok (s, 0)
      else
        let mut st := { s with
          matchFilled := 0, matchExpired := 0, matchStopped := 0, matchError := 0 }
        for i in [0:4] do
          if st.matchStopped = (0 : UInt64) then
            let j : Nat := i
            let size : UInt64 := st.bidSizes[j]!
            if size ≠ (0 : UInt64) then
              if st.bidPriceTicks[j]! = price then
                if st.bidSequences[j]! = sequence then
                  if st.bidTraders[j]! = trader then
                    let removed := if qty ≤ size then qty else size
                    st := unlockBidFold st j removed
                    let reduced := { st with matchFilled := removed, matchStopped := 1 }
                    let _ := recordPhoenix!(reduced, 5, 1;
                      .u8le 4, .u16le 0,
                      .u64le sequence, .u64le price,
                      .u64le removed, .u64le (size - removed))
                    st := appendEvent reduced
                      (.reduce reduced.eventCount sequence price removed (size - removed))
                  else
                    st := { st with matchStopped := 1, matchError := 1 }
        if st.matchError ≠ 0 then
          .error (errorOfMatch st.matchError)
        else if st.matchExpired > st.quoteLocked then
          .error .overflow
        else if st.quoteFree > u64Max - st.matchExpired then
          .error .overflow
        else
          let reduced := st.matchFilled
          if st.eventCount = 0 then
            let _ := recordPhoenix!(st, 5, 0; )
            .ok ({ st with
                    quoteLocked := st.quoteLocked - st.matchExpired
                    quoteFree := st.quoteFree + st.matchExpired
                    matchFilled := 0, matchExpired := 0,
                    matchStopped := 0, matchError := 0 }, reduced)
          else
            .ok ({ st with
                    quoteLocked := st.quoteLocked - st.matchExpired
                    quoteFree := st.quoteFree + st.matchExpired
                    matchFilled := 0, matchExpired := 0,
                    matchStopped := 0, matchError := 0 }, reduced)

attribute [pf_inline] reduceAskAt reduceBidAt

/-- SVM adapter：由 account 1 signer 的完整 Pubkey 解析 seat，不能伪造其他 owner。 -/
@[pf_entry]
def reduceAsk (s : State) (price sequence qty : UInt64) :
    Except Error (State × UInt64) := do
  let trader ← requireTraderAddress s (signerKey 1) (accKeyWord 1 1)
    (accKeyWord 1 2) (accKeyWord 1 3)
  reduceAskAt s trader price sequence qty

/-- Bid-side signer adapter；encoded sequence 仍原样传给 bounded order lookup。 -/
@[pf_entry]
def reduceBid (s : State) (price sequence qty : UInt64) :
    Except Error (State × UInt64) := do
  let trader ← requireTraderAddress s (signerKey 1) (accKeyWord 1 1)
    (accKeyWord 1 2) (accKeyWord 1 3)
  reduceBidAt s trader price sequence qty

/-- 官方部分成交兼容 helper：吃光当前 best ask。 -/
def sweepAsk (s : State) : Except Error (State × UInt64) :=
  let address := minBookAddress s.askBook
  let i := (address.toNat - 1) % 4
  if address = 0 || s.sizes[i]! = 0 then
    .error .overflow
  else if s.baseFree ≤ u64Max - s.sizes[i]! then
    if s.sizes[i]! ≤ s.baseLocked then
      let _ := tokenTransferChecked s.sizes[i]! 6
      .ok ({ s with
              sizes := s.sizes.set i 0
              askBook := removeBookAddress s.askBook address
              baseLocked := s.baseLocked - s.sizes[i]!
              baseFree := s.baseFree + s.sizes[i]! }, s.sizes[i]!)
    else
      .error .overflow
  else
    .error .overflow

/-- `CancelOrder` 是把指定订单 reduce 到 0。 -/
def cancelAsk (s : State) (trader price sequence : UInt64) :
    Except Error (State × UInt64) :=
  reduceAskAt s trader price sequence u64Max

def cancelBid (s : State) (trader price sequence : UInt64) :
    Except Error (State × UInt64) :=
  reduceBidAt s trader price sequence u64Max

/-- Authenticated Phoenix `CollectFees` adapter with one canonical fee event. -/
@[pf_entry]
def collectFees (s : State) : Except Error (State × UInt64) :=
  let fees := s.unclaimedFees
  let _ := recordPhoenix!(s, 108, 1; .u8le 7, .u16le 0, .u64le fees)
  if s.collectedFees ≤ u64Max - fees then
    let s := beginEvents s
    let settled := { s with
      collectedFees := s.collectedFees + fees
      unclaimedFees := 0 }
    .ok (appendEvent settled (.fee settled.eventCount fees), fees)
  else
    .error .overflow

def takeFee (qty : UInt64) : UInt64 :=
  if qty = 0 then 0 else feeOf qty

def checkLimit (s : State) (limit : UInt64) : Bool :=
  let address := minBookAddress s.askBook
  address = 0 || limit ≥ s.priceTicks[(address.toNat - 1) % 4]!

def checkTif (deadline : UInt64) : Bool :=
  deadline = 0 || unixTime < deadline

@[pf_entry]
def bestAsk (s : State) : UInt64 :=
  let address := minBookAddress s.askBook
  if address = 0 then 0 else s.priceTicks[(address.toNat - 1) % 4]!

@[pf_entry]
def bestBid (s : State) : UInt64 :=
  let address := minBookAddress s.bidBook
  if address = 0 then 0 else s.bidPriceTicks[(address.toNat - 1) % 4]!

@[pf_entry]
def askQty (s : State) : UInt64 :=
  s.sizes[0]! + s.sizes[1]! + s.sizes[2]! + s.sizes[3]!

@[pf_entry]
def bidQty (s : State) : UInt64 :=
  s.bidSizes[0]! + s.bidSizes[1]! + s.bidSizes[2]! + s.bidSizes[3]!

@[pf_entry]
def makerBase (s : State) : UInt64 :=
  s.baseLocked

@[pf_entry]
def takerBase (s : State) : UInt64 :=
  s.baseFree

@[pf_entry]
def nextSeq (s : State) : UInt64 :=
  s.sequence

@[pf_entry]
def feeBpsOf (s : State) : UInt64 :=
  s.takerFeeBps

@[pf_entry]
def level0 (s : State) : UInt64 :=
  s.sizes[0]!

@[pf_entry]
def eventCountOf (s : State) : UInt64 :=
  s.eventCount

@[pf_entry]
def lastEventKind (s : State) : UInt64 :=
  match s.lastEvent with
  | .uninitialized => 0
  | .header => 1
  | .fill _ _ _ _ _ _ _ _ _ => 2
  | .place _ _ _ _ _ _ => 3
  | .reduce _ _ _ _ _ => 4
  | .evict _ _ _ _ _ _ _ _ => 5
  | .fillSummary _ _ _ _ _ _ => 6
  | .fee _ _ => 7
  | .timeInForce _ _ _ _ => 8
  | .expiredOrder _ _ _ _ _ _ _ _ => 9

@[pf_entry]
def lastEventAmount (s : State) : UInt64 :=
  match s.lastEvent with
  | .uninitialized => 0
  | .header => 0
  | .fill _ _ _ _ _ _ _ filled _ => filled
  | .place _ _ _ _ _ placed => placed
  | .reduce _ _ _ removed _ => removed
  | .evict _ _ _ _ _ _ _ evicted => evicted
  | .fillSummary _ _ _ totalBase _ _ => totalBase
  | .fee _ fees => fees
  | .timeInForce _ _ lastValidSlot _ => lastValidSlot
  | .expiredOrder _ _ _ _ _ _ _ removed => removed

end Projects.Phoenix
