import Examples.Tree
import ProofForge

namespace Tests.TreeSpec

open Examples.Tree
open Lean Elab Command

private def nodeAt (s : Examples.Tree.State) (address : UInt64) : Node :=
  s.nodes[(address.toNat - 1) % 4]!

private def insertMany (s : Examples.Tree.State) :
    List (UInt64 × UInt64) → Except Error Examples.Tree.State
  | [] => .ok s
  | (k, v) :: rest =>
      match insertNode s k v with
      | .ok (s', _) => insertMany s' rest
      | .error e => .error e

private def checkSubtree (s : Examples.Tree.State) (address parent : UInt64)
    (lower upper : Option UInt64) : Nat → Option (Nat × Nat)
  | 0 => if address = 0 then some (1, 0) else none
  | fuel + 1 =>
      if address = 0 then
        some (1, 0)
      else if address > 4 then
        none
      else
        let node := nodeAt s address
        if node.parent ≠ parent || node.color > 1 then
          none
        else if lower.any (fun bound => decide (node.key ≤ bound)) then
          none
        else if upper.any (fun bound => decide (node.key ≥ bound)) then
          none
        else if node.color == 1 &&
            ((node.left != 0 && (nodeAt s node.left).color == 1) ||
              (node.right != 0 && (nodeAt s node.right).color == 1)) then
          none
        else
          match checkSubtree s node.left address lower (some node.key) fuel,
              checkSubtree s node.right address (some node.key) upper fuel with
          | some (leftBlackHeight, leftCount), some (rightBlackHeight, rightCount) =>
              if leftBlackHeight = rightBlackHeight then
                some (leftBlackHeight + (if node.color = 0 then 1 else 0),
                  leftCount + rightCount + 1)
              else
                none
          | _, _ => none

private def validRedBlackTree (s : Examples.Tree.State) : Bool :=
  if s.root = 0 then
    s.size == 0
  else
    (nodeAt s s.root).color == 0 &&
      match checkSubtree s s.root 0 none none 5 with
      | some (_, count) => s.size == UInt64.ofNat count
      | none => false

private def linkedContainsKey (s : Examples.Tree.State) (address key : UInt64) : Nat → Bool
  | 0 => false
  | fuel + 1 =>
      if address = 0 then false
      else
        let node := nodeAt s address
        node.key == key || linkedContainsKey s node.left key fuel ||
          linkedContainsKey s node.right key fuel

private def fourKeyOrders : List (List UInt64) :=
  [ [10, 20, 30, 40], [10, 20, 40, 30], [10, 30, 20, 40], [10, 30, 40, 20]
  , [10, 40, 20, 30], [10, 40, 30, 20], [20, 10, 30, 40], [20, 10, 40, 30]
  , [20, 30, 10, 40], [20, 30, 40, 10], [20, 40, 10, 30], [20, 40, 30, 10]
  , [30, 10, 20, 40], [30, 10, 40, 20], [30, 20, 10, 40], [30, 20, 40, 10]
  , [30, 40, 10, 20], [30, 40, 20, 10], [40, 10, 20, 30], [40, 10, 30, 20]
  , [40, 20, 10, 30], [40, 20, 30, 10], [40, 30, 10, 20], [40, 30, 20, 10] ]

private def validDeletion (order : List UInt64) (key : UInt64) : Bool :=
  match insertMany (init 0) (order.map fun value => (value, value)) with
  | .error _ => false
  | .ok full =>
      match removeNode full key with
      | .error _ => false
      | .ok (removed, address) =>
          validRedBlackTree removed && removed.size == 3 && removed.freeHead == address &&
            !linkedContainsKey removed removed.root key 5 &&
            [10, 20, 30, 40].all fun remaining =>
              remaining == key || linkedContainsKey removed removed.root remaining 5

private partial def maxIndexWrites (ops : Array ProofForge.Ops.Op) : Nat :=
  ops.foldl (init := 0) fun count op =>
    count +
      match op with
      | .indexSet .. => 1
      | .ite _ _ _ thn els => max (maxIndexWrites thn) (maxIndexWrites els)
      | .forBody bound body => bound * maxIndexWrites body
      | _ => 0

private partial def storeNames (ops : Array ProofForge.Ops.Op) : Array String :=
  ops.flatMap fun op =>
    match op with
    | .storeField name _ => #[name]
    | .ite _ _ _ thn els => storeNames thn ++ storeNames els
    | .forBody _ body => storeNames body
    | _ => #[]

private partial def storeValues (want : String)
    (ops : Array ProofForge.Ops.Op) : Array ProofForge.Ops.Val :=
  ops.flatMap fun op =>
    match op with
    | .storeField name value => if name == want then #[value] else #[]
    | .ite _ _ _ thn els => storeValues want thn ++ storeValues want els
    | .forBody _ body => storeValues want body
    | _ => #[]

private partial def localValues (want : Nat)
    (ops : Array ProofForge.Ops.Op) : Array ProofForge.Ops.Val :=
  ops.flatMap fun op =>
    match op with
    | .letLocal i value => if i == want then #[value] else #[]
    | .ite _ _ _ thn els => localValues want thn ++ localValues want els
    | .forBody _ body => localValues want body
    | _ => #[]

elab "#pf_guard_tree_allocator" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractModule env `Examples.Tree none with
    | .ok program => pure program
    | .error reason => throwError reason
  let asm ←
    match ProofForge.Svm.Emit.emitCounterAsm program with
    | .ok asm => pure asm
    | .error reason => throwError reason
  let evm ←
    match ProofForge.Evm.IR.fromProgram program with
    | .ok evm => pure evm
    | .error reason => throwError reason
  let yul ←
    match ProofForge.Evm.Emit.emitYul evm with
    | .ok yul => pure yul
    | .error reason => throwError reason
  let some evmRemove := evm.entries.find? (·.ixName == "removeNode")
    | throwError "missing EVM removeNode"
  let removeCfg ←
    match evmRemove.toCFG with
    | .ok cfg => pure cfg
    | .error reason => throwError reason
  unless ProofForge.Svm.ABI.dataLen program == 232 do
    throwError s!"Tree source account layout changed: {ProofForge.Svm.ABI.dataLen program} bytes"
  let some alloc := program.methods.find? (·.ixName == "allocNode")
    | throwError "missing allocNode"
  let some release := program.methods.find? (·.ixName == "releaseNode")
    | throwError "missing releaseNode"
  let some rotateLeft := program.methods.find? (·.ixName == "rotateLeft")
    | throwError "missing rotateLeft"
  let some rotateRight := program.methods.find? (·.ixName == "rotateRight")
    | throwError "missing rotateRight"
  let some insert := program.methods.find? (·.ixName == "insertNode")
    | throwError "missing insertNode"
  let some remove := program.methods.find? (·.ixName == "removeNode")
    | throwError "missing removeNode"
  unless alloc.paramCount == 2 && release.paramCount == 1 &&
      rotateLeft.paramCount == 1 && rotateRight.paramCount == 1 && insert.paramCount == 2 &&
      remove.paramCount == 1 do
    throwError "Tree storage ABI changed"
  let allocStores := storeNames alloc.ops
  let releaseStores := storeNames release.ops
  unless #["size", "bumpIndex", "freeHead"].all allocStores.contains &&
      #["size", "freeHead"].all releaseStores.contains do
    throwError s!"Tree allocator metadata writeback changed: {allocStores}, {releaseStores}"
  unless alloc.evaluation.dynamicWrites.size == 12 &&
      release.evaluation.dynamicWrites.size == 4 do
    throwError "Tree allocator dynamic writeback changed"
  unless maxIndexWrites rotateLeft.ops == 6 && maxIndexWrites rotateRight.ops == 6 &&
      rotateLeft.evaluation.dynamicWrites.size == 31 &&
      rotateRight.evaluation.dynamicWrites.size == 31 &&
      ((storeNames rotateLeft.ops).filter (· == "root")).size == 2 &&
      ((storeNames rotateRight.ops).filter (· == "root")).size == 2 do
    throwError "Tree rotation writeback is incomplete or duplicated"
  unless maxIndexWrites insert.ops == 17 && insert.evaluation.dynamicWrites.size == 54 do
    throwError s!"Tree insertion writeback changed or expanded: " ++
      s!"{maxIndexWrites insert.ops} path writes, " ++
      s!"{insert.evaluation.dynamicWrites.size} evaluated writes"
  unless maxIndexWrites remove.ops == 42 && remove.evaluation.dynamicWrites.size == 94 do
    throwError s!"Tree deletion writeback changed or expanded: " ++
      s!"{maxIndexWrites remove.ops} path writes, " ++
      s!"{remove.evaluation.dynamicWrites.size} evaluated writes"
  let xi := ProofForge.Ops.Val.select .ge (.arg 0) (.lit 1)
    (.subU64 (.arg 0) (.lit 1)) (.lit 0)
  let leftY := ProofForge.Ops.Val.indexGet (.arg 1) "nodes" xi 0 8
  let rightY := ProofForge.Ops.Val.indexGet (.arg 1) "nodes" xi 0 0
  unless (storeValues "root" rotateLeft.ops).all (· == .local 0) &&
      (storeValues "root" rotateRight.ops).all (· == .local 0) &&
      (localValues 0 rotateLeft.ops).contains leftY &&
      (localValues 0 rotateRight.ops).contains rightY do
    throwError "Tree rotation helper arguments escaped into source IR"
  let labels := (asm.splitOn "\n").filterMap fun line =>
    let line := line.trimAscii.toString
    if line.endsWith ":" then some line else none
  unless labels.length == labels.eraseDups.length do
    throwError "Tree allocator assembly contains duplicate labels"
  unless asm.toUTF8.size < 650000 do
    throwError s!"Tree assembly expanded unexpectedly: {asm.toUTF8.size} bytes"
  unless !removeCfg.blocks.isEmpty && yul.toUTF8.size < 400000 do
    throwError s!"Tree EVM deletion lowering changed: {removeCfg.blocks.size} blocks, " ++
      s!"{yul.toUTF8.size} Yul bytes"

#pf_guard_tree_allocator

#guard (init 0).root == 0
#guard (init 0).size == 0
#guard (init 0).bumpIndex == 1
#guard (init 0).freeHead == 1
#guard getRoot (init 0) == 0
#guard getSize (init 0) == 0
#guard getBumpIndex (init 0) == 1
#guard getFreeHead (init 0) == 1
#guard getHead (init 0) == 0
#guard getAt (init 0) 0 == 0
#guard getAt (init 0) 9 == 0
#guard sentinel == 0
#guard emptyNode.left == 0
#guard emptyNode.color == 0

#guard
  match setHead (init 0) 7 with
  | .ok (st, ret) => st.nodes[0]!.value == 7 && ret == 7 && st.nodes[0]!.left == 0
  | .error _ => false

#guard
  match setAt (init 0) 1 9 with
  | .ok (st, ret) => st.nodes[1]!.value == 9 && ret == 9 && st.nodes[0]!.value == 0
  | .error _ => false

#guard
  match setAt (init 0) 9 1 with
  | .error .overflow => true
  | _ => false

#guard getRight (init 0) 0 == 0

#guard
  match setRight (init 0) 0 2 with
  | .ok (st, ret) => st.nodes[0]!.right == 2 && ret == 2 && st.nodes[0]!.value == 0
  | .error _ => false

#guard
  match setParent (init 0) 1 1 with
  | .ok (st, ret) => st.nodes[1]!.parent == 1 && ret == 1 && st.nodes[0]!.parent == 0
  | .error _ => false

#guard
  match allocNode (init 0) 10 100 with
  | .ok (st, address) =>
      address == 1 && st.size == 1 && st.bumpIndex == 2 && st.freeHead == 2 &&
        st.nodes[0]!.key == 10 && st.nodes[0]!.value == 100 && st.nodes[0]!.left == 0
  | .error _ => false

#guard
  match allocNode (init 0) 10 100 with
  | .ok (st, _) =>
    match releaseNode st 1 with
    | .ok (freed, address) =>
      match allocNode freed 20 200 with
      | .ok (reused, reusedAddress) =>
          address == 1 && reusedAddress == 1 && reused.size == 1 &&
            reused.bumpIndex == 2 && reused.freeHead == 2 &&
            reused.nodes[0]!.left == 0 && reused.nodes[0]!.key == 20 &&
            reused.nodes[0]!.value == 200
      | .error _ => false
    | .error _ => false
  | .error _ => false

#guard
  match allocNode (init 0) 10 100 with
  | .ok (s1, _) =>
    match allocNode s1 20 200 with
    | .ok (s2, _) =>
      match releaseNode s2 1 with
      | .ok (f1, _) =>
        match releaseNode f1 2 with
        | .ok (f2, _) =>
          match allocNode f2 30 300 with
          | .ok (r2, a2) =>
            match allocNode r2 40 400 with
            | .ok (r1, a1) =>
                a2 == 2 && a1 == 1 && r1.size == 2 && r1.bumpIndex == 3 &&
                  r1.freeHead == 3 && r1.nodes[1]!.left == 0 &&
                  r1.nodes[0]!.left == 0 && r1.nodes[1]!.value == 300 &&
                  r1.nodes[0]!.value == 400
            | .error _ => false
          | .error _ => false
        | .error _ => false
      | .error _ => false
    | .error _ => false
  | .error _ => false

#guard
  match
    let s0 := { (init 0) with size := 4, bumpIndex := 5, freeHead := 5 }
    allocNode s0 1 1 with
  | .error .overflow => true
  | _ => false

#guard
  match bumpInsert (init 0) 3 7 with
  | .ok (st, ret) =>
      st.root == 1 && st.size == 1 && ret == 3 &&
        st.bumpIndex == 2 && st.freeHead == 2 &&
        st.nodes[0]!.key == 3 && st.nodes[0]!.value == 7 &&
        st.nodes[0]!.color == 1 && st.nodes[0]!.parent == 0
  | .error _ => false

#guard
  match bumpInsert (init 0) 3 7 with
  | .ok (st, _) =>
    match bumpInsert st 2 9 with
    | .ok (st2, ret) =>
        st2.size == 2 && ret == 2 &&
          st2.bumpIndex == 3 && st2.freeHead == 3 &&
          st2.nodes[1]!.key == 2 && st2.nodes[1]!.value == 9 &&
          st2.nodes[1]!.parent == 1 && st2.nodes[0]!.value == 7 &&
          st2.nodes[0]!.right == 2
    | .error _ => false
  | .error _ => false

#guard
  match bumpInsert { (init 0) with
      root := 1, size := 2
      nodes := (init 0).nodes.set 0 { left := 0, right := 2, parent := 0, color := 1, key := 3, value := 7 }
    } 4 1 with
  | .error .overflow => true
  | _ => false

#guard
  match
    let s0 :=
      { (init 0) with
        root := 1, size := 2
        nodes :=
          ((init 0).nodes.set 0 { left := 0, right := 2, parent := 0, color := 1, key := 3, value := 7 }).set 1
            { left := 0, right := 0, parent := 1, color := 1, key := 2, value := 9 } }
    rotateLeft s0 1 with
  | .ok (st, y) =>
      y == 2 && st.root == 2 &&
        st.nodes[0]!.right == 0 && st.nodes[0]!.parent == 2 &&
        st.nodes[1]!.left == 1 && st.nodes[1]!.parent == 0
  | .error _ => false

#guard
  match
    let s0 :=
      { (init 0) with
        root := 1, size := 2
        nodes :=
          ((init 0).nodes.set 0 { left := 2, right := 0, parent := 0, color := 1, key := 3, value := 7 }).set 1
            { left := 0, right := 0, parent := 1, color := 1, key := 2, value := 9 } }
    rotateRight s0 1 with
  | .ok (st, y) =>
      y == 2 && st.root == 2 &&
        st.nodes[0]!.left == 0 && st.nodes[0]!.parent == 2 &&
        st.nodes[1]!.right == 1 && st.nodes[1]!.parent == 0
  | .error _ => false

#guard
  match
    let s0 :=
      { (init 0) with
        root := 1, size := 3
        nodes :=
          (((init 0).nodes.set 0
              { left := 0, right := 3, parent := 0, color := 1, key := 10, value := 1 }).set 1
              { left := 0, right := 0, parent := 3, color := 0, key := 15, value := 2 }).set 2
              { left := 2, right := 0, parent := 1, color := 1, key := 20, value := 3 } }
    rotateLeft s0 1 with
  | .ok (st, y) =>
      y == 3 && st.root == 3 &&
        st.nodes[0]!.right == 2 && st.nodes[0]!.parent == 3 &&
        st.nodes[1]!.parent == 1 &&
        st.nodes[2]!.left == 1 && st.nodes[2]!.parent == 0
  | .error _ => false

#guard
  match
    let s0 :=
      { (init 0) with
        root := 1, size := 4
        nodes :=
          ((((init 0).nodes.set 0
              { left := 2, right := 0, parent := 0, color := 0, key := 40, value := 1 }).set 1
              { left := 0, right := 3, parent := 1, color := 1, key := 20, value := 2 }).set 2
              { left := 4, right := 0, parent := 2, color := 0, key := 30, value := 3 }).set 3
              { left := 0, right := 0, parent := 3, color := 1, key := 25, value := 4 } }
    rotateLeft s0 2 with
  | .ok (st, y) =>
      y == 3 && st.root == 1 && st.nodes[0]!.left == 3 &&
        st.nodes[2]!.parent == 1 && st.nodes[2]!.left == 2 &&
        st.nodes[1]!.parent == 3 && st.nodes[1]!.right == 4 &&
        st.nodes[3]!.parent == 2
  | .error _ => false

#guard
  match
    let s0 :=
      { (init 0) with
        root := 1, size := 4
        nodes :=
          ((((init 0).nodes.set 0
              { left := 0, right := 2, parent := 0, color := 0, key := 10, value := 1 }).set 1
              { left := 3, right := 0, parent := 1, color := 1, key := 30, value := 2 }).set 2
              { left := 0, right := 4, parent := 2, color := 0, key := 20, value := 3 }).set 3
              { left := 0, right := 0, parent := 3, color := 1, key := 25, value := 4 } }
    rotateRight s0 2 with
  | .ok (st, y) =>
      y == 3 && st.root == 1 && st.nodes[0]!.right == 3 &&
        st.nodes[2]!.parent == 1 && st.nodes[2]!.right == 2 &&
        st.nodes[1]!.parent == 3 && st.nodes[1]!.left == 4 &&
        st.nodes[3]!.parent == 2
  | .error _ => false

-- Bounded Sokoban insertion, including all four rotation shapes and red-uncle recoloring.
#guard
  match insertNode (init 0) 30 300 with
  | .ok (s, address) =>
      address == 1 && s.root == 1 && s.size == 1 && (nodeAt s 1).color == 0 &&
        (nodeAt s 1).key == 30 && (nodeAt s 1).value == 300 && validRedBlackTree s
  | .error _ => false

#guard
  match insertMany (init 0) [(30, 300), (20, 200), (10, 100)] with
  | .ok s =>
      s.root == 2 && (nodeAt s 2).key == 20 && (nodeAt s 2).left == 3 &&
        (nodeAt s 2).right == 1 && validRedBlackTree s
  | .error _ => false

#guard
  match insertMany (init 0) [(10, 100), (20, 200), (30, 300)] with
  | .ok s =>
      s.root == 2 && (nodeAt s 2).key == 20 && (nodeAt s 2).left == 1 &&
        (nodeAt s 2).right == 3 && validRedBlackTree s
  | .error _ => false

#guard
  match insertMany (init 0) [(30, 300), (10, 100), (20, 200)] with
  | .ok s =>
      s.root == 3 && (nodeAt s 3).key == 20 && (nodeAt s 3).left == 2 &&
        (nodeAt s 3).right == 1 && validRedBlackTree s
  | .error _ => false

#guard
  match insertMany (init 0) [(10, 100), (30, 300), (20, 200)] with
  | .ok s =>
      s.root == 3 && (nodeAt s 3).key == 20 && (nodeAt s 3).left == 1 &&
        (nodeAt s 3).right == 2 && validRedBlackTree s
  | .error _ => false

#guard
  match insertMany (init 0) [(20, 200), (10, 100), (30, 300), (5, 50)] with
  | .ok s =>
      s.root == 1 && s.size == 4 && s.bumpIndex == 5 && s.freeHead == 5 &&
        (nodeAt s 1).color == 0 && (nodeAt s 2).color == 0 &&
        (nodeAt s 3).color == 0 && (nodeAt s 4).color == 1 && validRedBlackTree s
  | .error _ => false

#guard
  match insertMany (init 0) [(20, 200), (10, 100), (30, 300), (5, 50)] with
  | .ok full =>
      match insertNode full 10 999, insertNode full 40 400 with
      | .ok (updated, address), .error .overflow =>
          address == 2 && updated.size == 4 && updated.bumpIndex == 5 &&
            (nodeAt updated 2).value == 999 && validRedBlackTree updated
      | _, _ => false
  | .error _ => false

#guard
  match insertNode (init 0) 10 100 with
  | .ok (one, _) =>
      match releaseNode one 1 with
      | .ok (freed, _) =>
          match insertNode { freed with root := 0 } 50 500 with
          | .ok (reused, address) =>
              address == 1 && reused.root == 1 && reused.size == 1 &&
                reused.bumpIndex == 2 && reused.freeHead == 2 &&
                (nodeAt reused 1).key == 50 && validRedBlackTree reused
          | .error _ => false
      | .error _ => false
  | .error _ => false

-- Red leaf deletion returns the detached address to the allocator.
#guard
  match insertMany (init 0) [(20, 200), (10, 100), (30, 300), (5, 50)] with
  | .ok full =>
      match removeNode full 5 with
      | .ok (removed, address) =>
          address == 4 && removed.size == 3 && removed.freeHead == 4 &&
            removed.nodes[3]!.left == 5 && validRedBlackTree removed
      | .error _ => false
  | .error _ => false

-- Removing a black node with one red child promotes and blackens that child.
#guard
  match insertMany (init 0) [(20, 200), (10, 100), (30, 300), (5, 50)] with
  | .ok full =>
      match removeNode full 10 with
      | .ok (removed, address) =>
          address == 2 && removed.size == 3 && removed.freeHead == 2 &&
            (nodeAt removed 4).parent == 1 && (nodeAt removed 4).color == 0 &&
            validRedBlackTree removed
      | .error _ => false
  | .error _ => false

-- Black-leaf deletion exercises the far-red sibling rotation.
#guard
  match insertMany (init 0) [(20, 200), (10, 100), (30, 300), (5, 50)] with
  | .ok full =>
      match removeNode full 30 with
      | .ok (removed, address) =>
          address == 3 && removed.root == 2 && (nodeAt removed 2).key == 10 &&
            removed.size == 3 && validRedBlackTree removed
      | .error _ => false
  | .error _ => false

-- A direct successor replaces a two-child root and still runs black-leaf fixup.
#guard
  match insertMany (init 0) [(20, 200), (10, 100), (30, 300), (5, 50)] with
  | .ok full =>
      match removeNode full 20 with
      | .ok (removed, address) =>
          address == 1 && removed.size == 3 && removed.freeHead == 1 &&
            validRedBlackTree removed
      | .error _ => false
  | .error _ => false

-- A deeper red successor is transplanted without a fixup pass.
#guard
  match insertMany (init 0) [(20, 200), (10, 100), (30, 300), (25, 250)] with
  | .ok full =>
      match removeNode full 20 with
      | .ok (removed, address) =>
          address == 1 && removed.root == 4 && (nodeAt removed 4).key == 25 &&
            (nodeAt removed 4).left == 2 && (nodeAt removed 4).right == 3 &&
            validRedBlackTree removed
      | .error _ => false
  | .error _ => false

#guard
  match insertMany (init 0) [(10, 100), (20, 200)] with
  | .ok two =>
      match removeNode two 10 with
      | .ok (one, address) =>
          address == 1 && one.root == 2 && (nodeAt one 2).color == 0 &&
            one.size == 1 && validRedBlackTree one
      | .error _ => false
  | .error _ => false

#guard
  match insertNode (init 0) 10 100 with
  | .ok (one, _) =>
      match removeNode one 10 with
      | .ok (empty, address) =>
          address == 1 && empty.root == 0 && empty.size == 0 &&
            empty.freeHead == 1 && validRedBlackTree empty
      | .error _ => false
  | .error _ => false

#guard
  match removeNode (init 0) 99 with
  | .error .overflow => true
  | _ => false

-- The next insertion reuses the exact removed address and restores a valid full tree.
#guard
  match insertMany (init 0) [(20, 200), (10, 100), (30, 300), (5, 50)] with
  | .ok full =>
      match removeNode full 30 with
      | .ok (removed, removedAddress) =>
          match insertNode removed 25 250 with
          | .ok (reused, insertedAddress) =>
              removedAddress == 3 && insertedAddress == 3 && reused.size == 4 &&
                reused.bumpIndex == 5 && reused.freeHead == 5 && validRedBlackTree reused
          | .error _ => false
      | .error _ => false
  | .error _ => false

-- All 24 insertion orders × all four deletion keys cover every reachable full N=4 shape.
#guard fourKeyOrders.all fun order =>
  [10, 20, 30, 40].all fun key => validDeletion order key

#guard
  (ProofForge.Golden.extractedTree.fields.find? (· == "nodes_0_value")).isSome
#guard ProofForge.Svm.ABI.dataLen ProofForge.Golden.extractedTree == 216

end Tests.TreeSpec
