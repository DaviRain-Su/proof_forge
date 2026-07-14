import ProofForge.Backend.Stylus.DirectWasm.Storage

namespace ProofForge.Backend.Stylus

structure AbiLayoutError where
  message : String
  deriving Repr, BEq

structure DynamicAbiSlice where
  offset : Nat
  dataOffset : Nat
  length : Nat
  paddedEnd : Nat
  deriving Repr, BEq

structure DynamicArrayAbiSlice where
  offset : Nat
  dataOffset : Nat
  length : Nat
  elementWords : Nat
  endOffset : Nat
  deriving Repr, BEq

structure DynamicArrayChildSlice where
  index : Nat
  relativeOffset : Nat
  dataOffset : Nat
  length : Nat
  paddedEnd : Nat
  deriving Repr, BEq, Inhabited

structure DynamicBytesArrayAbiSlice where
  offset : Nat
  dataOffset : Nat
  length : Nat
  endOffset : Nat
  children : Array DynamicArrayChildSlice
  deriving Repr, BEq

structure DynamicTupleFieldSlice where
  fieldIndex : Nat
  relativeOffset : Nat
  dataOffset : Nat
  length : Nat
  paddedEnd : Nat
  deriving Repr, BEq, Inhabited

structure DynamicTupleAbiSlice where
  offset : Nat
  headWords : Nat
  endOffset : Nat
  dynamicFields : Array DynamicTupleFieldSlice
  deriving Repr, BEq

structure RecursiveDynamicAbiSlice where
  offset : Nat
  endOffset : Nat
  deriving Repr, BEq, Inhabited

private def fail (message : String) : Except AbiLayoutError α :=
  .error { message }

def checkedAdd (context : String) (limit lhs rhs : Nat) : Except AbiLayoutError Nat := do
  if lhs > limit || rhs > limit || rhs > limit - lhs then
    fail s!"{context} exceeds layout limit {limit}: {lhs} + {rhs}"
  pure (lhs + rhs)

def checkedMul (context : String) (limit lhs rhs : Nat) : Except AbiLayoutError Nat := do
  if lhs > limit || rhs > limit || (lhs != 0 && rhs > limit / lhs) then
    fail s!"{context} exceeds layout limit {limit}: {lhs} * {rhs}"
  pure (lhs * rhs)

partial def staticAbiWords (limit : Nat) : StylusAbiType -> Except AbiLayoutError Nat
  | .bool | .uint _ | .address | .fixedBytes _ => pure 1
  | .fixedArray element size => do
      if size == 0 then fail "static ABI fixed array length must be positive"
      checkedMul "static ABI fixed array" limit size (← staticAbiWords limit element)
  | .tuple fields => do
      if fields.isEmpty then fail "static ABI tuple must contain at least one field"
      fields.foldlM (fun words field => do
        checkedAdd "static ABI tuple" limit words (← staticAbiWords limit field)) 0
  | .bytes | .string | .dynamicArray _ =>
      fail "dynamic ABI type has no fixed static-word layout"

def abiHeadWords (limit : Nat) (params : Array StylusAbiParamPlan) : Except AbiLayoutError Nat :=
  params.foldlM (fun words param => do
    let width ← if param.type.isDynamic then pure 1 else staticAbiWords limit param.type
    checkedAdd s!"ABI head for `{param.name}`" limit words width) 0

def roundUpWord (length : Nat) : Nat :=
  ((length + 31) / 32) * 32

private def wordAt (bytes : Array UInt8) (offset : Nat) : Except AbiLayoutError (Array UInt8) :=
  if offset + 32 <= bytes.size then pure (bytes.extract offset (offset + 32))
  else fail s!"ABI word at {offset} exceeds calldata length {bytes.size}"

private def allZero (bytes : Array UInt8) : Bool := bytes.all (· == 0)

private partial def validateStaticAt (bytes : Array UInt8) (offset : Nat) : StylusAbiType ->
    Except AbiLayoutError Nat
  | .bool => do
      let word ← wordAt bytes offset
      unless allZero (word.extract 0 31) && (word[31]? == some 0 || word[31]? == some 1) do
        fail s!"non-canonical bool at ABI offset {offset}"
      pure (offset + 32)
  | .uint bits => do
      if bits == 0 || bits > 256 || bits % 8 != 0 then fail s!"unsupported uint{bits} ABI width"
      let word ← wordAt bytes offset
      unless allZero (word.extract 0 (32 - bits / 8)) do
        fail s!"non-canonical uint{bits} at ABI offset {offset}"
      pure (offset + 32)
  | .address => do
      let word ← wordAt bytes offset
      unless allZero (word.extract 0 12) do fail s!"non-canonical address at ABI offset {offset}"
      pure (offset + 32)
  | .fixedBytes size => do
      if size == 0 || size > 32 then fail s!"unsupported bytes{size} ABI width"
      let word ← wordAt bytes offset
      unless allZero (word.extract size 32) do fail s!"non-canonical bytes{size} at ABI offset {offset}"
      pure (offset + 32)
  | .fixedArray element size => do
      if size == 0 then fail "dynamic-array element contains a zero-length fixed array"
      let mut next := offset
      for _ in [0:size] do next ← validateStaticAt bytes next element
      pure next
  | .tuple fields => do
      if fields.isEmpty then fail "dynamic-array element contains an empty tuple"
      let mut next := offset
      for field in fields do next ← validateStaticAt bytes next field
      pure next
  | .bytes | .string | .dynamicArray _ =>
      fail "nested dynamic-array elements require recursive tail planning"

private def policyMaximum (maximums : Array Nat) (index : Nat) : Except AbiLayoutError Nat := do
  let some maximum := maximums[index]?
    | fail s!"dynamic ABI policy {index} is missing"
  if maximum == 0 then fail s!"dynamic ABI policy {index} has a zero maximum"
  pure maximum

private partial def decodeRecursiveValueAt (arguments : Array UInt8) (base : Nat)
    (type : StylusAbiType) (maximums : Array Nat) (policyIndex : Nat) :
    Except AbiLayoutError (RecursiveDynamicAbiSlice × Nat) := do
  match type with
  | .bytes | .string =>
      let maximum <- policyMaximum maximums policyIndex
      let length := ProofForge.Backend.Stylus.DirectWasm.wordToNat (← wordAt arguments base)
      if length > maximum then fail s!"dynamic ABI length {length} exceeds maximum {maximum}"
      let dataOffset <- checkedAdd "recursive dynamic data" arguments.size base 32
      let endOffset <- checkedAdd "recursive dynamic tail" arguments.size dataOffset (roundUpWord length)
      if endOffset > arguments.size then fail "recursive dynamic tail exceeds calldata"
      pure ({ offset := base, endOffset }, policyIndex + 1)
  | .dynamicArray element =>
      let maximum <- policyMaximum maximums policyIndex
      let length := ProofForge.Backend.Stylus.DirectWasm.wordToNat (← wordAt arguments base)
      if length > maximum then fail s!"dynamic-array length {length} exceeds maximum {maximum}"
      let dataOffset <- checkedAdd "recursive array data" arguments.size base 32
      if element.isDynamic then
        let headBytes <- checkedMul "recursive array head" arguments.size length 32
        let headEnd <- checkedAdd "recursive array head end" arguments.size dataOffset headBytes
        if headEnd > arguments.size then fail "recursive array head exceeds calldata"
        let childPolicyStart := policyIndex + 1
        let childPolicyEnd := childPolicyStart + element.dynamicPolicyArity
        if childPolicyEnd > maximums.size then fail "recursive array child policy is incomplete"
        let mut endOffset := headEnd
        for childIndex in [0:length] do
          let relativeOffset := ProofForge.Backend.Stylus.DirectWasm.wordToNat
            (← wordAt arguments (dataOffset + childIndex * 32))
          if relativeOffset % 32 != 0 then
            fail s!"recursive array child {childIndex} offset is not aligned"
          if relativeOffset < headBytes then
            fail s!"recursive array child {childIndex} points inside array head"
          let childBase <- checkedAdd s!"recursive array child {childIndex}" arguments.size
            dataOffset relativeOffset
          let (child, nextPolicy) <- decodeRecursiveValueAt arguments childBase element
            maximums childPolicyStart
          unless nextPolicy == childPolicyEnd do fail "recursive array child policy consumption changed"
          endOffset := max endOffset child.endOffset
        pure ({ offset := base, endOffset }, childPolicyEnd)
      else
        let elementWords <- staticAbiWords (arguments.size / 32 + 1) element
        let payloadWords <- checkedMul "recursive array payload words"
          (arguments.size / 32 + 1) length elementWords
        let payloadBytes <- checkedMul "recursive array payload bytes" arguments.size payloadWords 32
        let endOffset <- checkedAdd "recursive array tail" arguments.size dataOffset payloadBytes
        if endOffset > arguments.size then fail "recursive array tail exceeds calldata"
        let mut cursor := dataOffset
        for _ in [0:length] do cursor <- validateStaticAt arguments cursor element
        pure ({ offset := base, endOffset }, policyIndex + 1)
  | .tuple fields =>
      if fields.isEmpty then fail "recursive dynamic tuple must contain at least one field"
      let mut headWords := 0
      for field in fields do
        let width <- if field.isDynamic then pure 1
          else staticAbiWords (arguments.size / 32 + 1) field
        headWords <- checkedAdd "recursive tuple head" (arguments.size / 32 + 1) headWords width
      let headBytes <- checkedMul "recursive tuple head bytes" arguments.size headWords 32
      let headEnd <- checkedAdd "recursive tuple head end" arguments.size base headBytes
      if headEnd > arguments.size then fail "recursive tuple head exceeds calldata"
      let mut wordIndex := 0
      let mut nextPolicy := policyIndex
      let mut endOffset := headEnd
      for h : fieldIndex in [0:fields.size] do
        let field := fields[fieldIndex]
        if field.isDynamic then
          let relativeOffset := ProofForge.Backend.Stylus.DirectWasm.wordToNat
            (← wordAt arguments (base + wordIndex * 32))
          if relativeOffset % 32 != 0 then
            fail s!"recursive tuple field {fieldIndex} offset is not aligned"
          if relativeOffset < headBytes then
            fail s!"recursive tuple field {fieldIndex} points inside tuple head"
          let childBase <- checkedAdd s!"recursive tuple field {fieldIndex}" arguments.size
            base relativeOffset
          let (child, afterPolicy) <- decodeRecursiveValueAt arguments childBase field maximums nextPolicy
          nextPolicy := afterPolicy
          endOffset := max endOffset child.endOffset
          wordIndex := wordIndex + 1
        else
          wordIndex <- validateStaticAt arguments (base + wordIndex * 32) field |>.map fun next =>
            (next - base) / 32
      pure ({ offset := base, endOffset }, nextPolicy)
  | .fixedArray element size =>
      if size == 0 then fail "recursive dynamic fixed array length must be positive"
      if element.isDynamic then
        decodeRecursiveValueAt arguments base (.tuple (Array.replicate size element)) maximums policyIndex
      else
        let endOffset <- validateStaticAt arguments base type
        pure ({ offset := base, endOffset }, policyIndex)
  | _ =>
      let endOffset <- validateStaticAt arguments base type
      pure ({ offset := base, endOffset }, policyIndex)

/-- Decode any recursively dynamic argument from an ABI method head. The root
maximum is the byte length for bytes/string or element count for a dynamic
array. Tuple roots consume only their preorder child maxima. -/
def decodeRecursiveDynamicArgument (arguments : Array UInt8) (headWords index rootMaximum : Nat)
    (type : StylusAbiType) (childMaximums : Array Nat) :
    Except AbiLayoutError RecursiveDynamicAbiSlice := do
  if index >= headWords then fail s!"recursive ABI index {index} exceeds head words {headWords}"
  let headBytes <- checkedMul "recursive ABI head" arguments.size headWords 32
  if headBytes > arguments.size then fail "recursive ABI head is truncated"
  let offset := ProofForge.Backend.Stylus.DirectWasm.wordToNat (← wordAt arguments (index * 32))
  if offset % 32 != 0 then fail s!"recursive ABI offset {offset} is not word aligned"
  if offset < headBytes then fail s!"recursive ABI offset {offset} points inside the static head"
  let rootMaximums := match type with
    | .bytes | .string | .dynamicArray _ => #[rootMaximum] ++ childMaximums
    | _ => childMaximums
  unless rootMaximums.size == type.dynamicPolicyArity do
    fail (s!"recursive ABI type needs {type.dynamicPolicyArity} maxima but " ++
      s!"{rootMaximums.size} were provided")
  let (slice, nextPolicy) <- decodeRecursiveValueAt arguments offset type rootMaximums 0
  unless nextPolicy == rootMaximums.size do fail "recursive ABI policy consumption is incomplete"
  pure slice

def decodeDynamicArgument (arguments : Array UInt8) (headWords index maximumLength : Nat) :
    Except AbiLayoutError DynamicAbiSlice := do
  if index >= headWords then fail s!"dynamic ABI argument index {index} exceeds head arity {headWords}"
  let headBytes := headWords * 32
  if headBytes > arguments.size then fail "dynamic ABI head is truncated"
  let offset := ProofForge.Backend.Stylus.DirectWasm.wordToNat (← wordAt arguments (index * 32))
  if offset % 32 != 0 then fail s!"dynamic ABI offset {offset} is not word aligned"
  if offset < headBytes then fail s!"dynamic ABI offset {offset} points inside the static head"
  let length := ProofForge.Backend.Stylus.DirectWasm.wordToNat (← wordAt arguments offset)
  if length > maximumLength then fail s!"dynamic ABI length {length} exceeds maximum {maximumLength}"
  let dataOffset := offset + 32
  let paddedEnd := dataOffset + roundUpWord length
  if paddedEnd > arguments.size then
    fail s!"dynamic ABI tail end {paddedEnd} exceeds calldata length {arguments.size}"
  pure { offset, dataOffset, length, paddedEnd }

/-- Decode a Solidity `T[]` argument when `T` has a fully static ABI layout.
Every element is canonical-validated before the slice is returned. -/
def decodeDynamicArrayArgument (arguments : Array UInt8) (headWords index maximumElements : Nat)
    (element : StylusAbiType) : Except AbiLayoutError DynamicArrayAbiSlice := do
  if index >= headWords then fail s!"dynamic-array ABI index {index} exceeds head words {headWords}"
  let headBytes ← checkedMul "dynamic-array ABI head" arguments.size headWords 32
  if headBytes > arguments.size then fail "dynamic-array ABI head is truncated"
  let offset := ProofForge.Backend.Stylus.DirectWasm.wordToNat (← wordAt arguments (index * 32))
  if offset % 32 != 0 then fail s!"dynamic-array ABI offset {offset} is not word aligned"
  if offset < headBytes then fail s!"dynamic-array ABI offset {offset} points inside the static head"
  let length := ProofForge.Backend.Stylus.DirectWasm.wordToNat (← wordAt arguments offset)
  if length > maximumElements then
    fail s!"dynamic-array length {length} exceeds maximum {maximumElements}"
  let elementWords ← staticAbiWords (arguments.size / 32 + 1) element
  let dataOffset ← checkedAdd "dynamic-array data offset" arguments.size offset 32
  let payloadWords ← checkedMul "dynamic-array payload words" (arguments.size / 32 + 1) length elementWords
  let payloadBytes ← checkedMul "dynamic-array payload bytes" arguments.size payloadWords 32
  let endOffset ← checkedAdd "dynamic-array tail end" arguments.size dataOffset payloadBytes
  if endOffset > arguments.size then
    fail s!"dynamic-array tail end {endOffset} exceeds calldata length {arguments.size}"
  let mut cursor := dataOffset
  for _ in [0:length] do cursor ← validateStaticAt arguments cursor element
  pure { offset, dataOffset, length, elementWords, endOffset }

/-- Decode a Solidity `bytes[]` or `string[]` argument. Element offsets are
relative to the array element-head base (the word immediately after length). -/
def decodeDynamicBytesArrayArgument (arguments : Array UInt8)
    (headWords index maximumElements maximumChildLength : Nat) :
    Except AbiLayoutError DynamicBytesArrayAbiSlice := do
  if index >= headWords then fail s!"dynamic-array ABI index {index} exceeds head words {headWords}"
  let headBytes <- checkedMul "dynamic-array ABI head" arguments.size headWords 32
  if headBytes > arguments.size then fail "dynamic-array ABI head is truncated"
  let offset := ProofForge.Backend.Stylus.DirectWasm.wordToNat (← wordAt arguments (index * 32))
  if offset % 32 != 0 then fail s!"dynamic-array ABI offset {offset} is not word aligned"
  if offset < headBytes then fail s!"dynamic-array ABI offset {offset} points inside the static head"
  let length := ProofForge.Backend.Stylus.DirectWasm.wordToNat (← wordAt arguments offset)
  if length > maximumElements then fail s!"dynamic-array length {length} exceeds maximum {maximumElements}"
  let dataOffset <- checkedAdd "dynamic-array data offset" arguments.size offset 32
  let childHeadBytes <- checkedMul "dynamic-array child head" arguments.size length 32
  let headEnd <- checkedAdd "dynamic-array child head end" arguments.size dataOffset childHeadBytes
  if headEnd > arguments.size then fail "dynamic-array child head exceeds calldata"
  let mut endOffset := headEnd
  let mut children := #[]
  for childIndex in [0:length] do
    let relativeOffset := ProofForge.Backend.Stylus.DirectWasm.wordToNat
      (← wordAt arguments (dataOffset + childIndex * 32))
    if relativeOffset % 32 != 0 then fail s!"dynamic-array child {childIndex} offset is not aligned"
    if relativeOffset < childHeadBytes then fail s!"dynamic-array child {childIndex} points inside array head"
    let lengthOffset <- checkedAdd s!"dynamic-array child {childIndex} length" arguments.size
      dataOffset relativeOffset
    let childLength := ProofForge.Backend.Stylus.DirectWasm.wordToNat (← wordAt arguments lengthOffset)
    if childLength > maximumChildLength then
      fail s!"dynamic-array child {childIndex} length {childLength} exceeds maximum {maximumChildLength}"
    let childDataOffset <- checkedAdd s!"dynamic-array child {childIndex} data" arguments.size lengthOffset 32
    let paddedEnd <- checkedAdd s!"dynamic-array child {childIndex} tail" arguments.size
      childDataOffset (roundUpWord childLength)
    if paddedEnd > arguments.size then fail s!"dynamic-array child {childIndex} tail exceeds calldata"
    endOffset := max endOffset paddedEnd
    children := children.push {
      index := childIndex, relativeOffset, dataOffset := childDataOffset,
      length := childLength, paddedEnd }
  pure { offset, dataOffset, length, endOffset, children }

/-- Decode a dynamic tuple whose dynamic children are bytes/string or dynamic
arrays with static element layouts. Static children may themselves be fixed
arrays or static tuples. Child offsets are relative to the tuple base. -/
def decodeDynamicTupleArgument (arguments : Array UInt8) (outerHeadWords index : Nat)
    (fields : Array StylusAbiType) (maximumLengths : Array Nat) :
    Except AbiLayoutError DynamicTupleAbiSlice := do
  if index >= outerHeadWords then fail s!"dynamic-tuple ABI index {index} exceeds head words {outerHeadWords}"
  let outerHeadBytes ← checkedMul "dynamic-tuple outer head" arguments.size outerHeadWords 32
  if outerHeadBytes > arguments.size then fail "dynamic-tuple outer head is truncated"
  let offset := ProofForge.Backend.Stylus.DirectWasm.wordToNat (← wordAt arguments (index * 32))
  if offset % 32 != 0 then fail s!"dynamic-tuple offset {offset} is not word aligned"
  if offset < outerHeadBytes then fail s!"dynamic-tuple offset {offset} points inside the outer head"
  let mut tupleHeadWords := 0
  let mut dynamicCount := 0
  for field in fields do
    if field.isDynamic then
      match field with
      | .bytes | .string => pure ()
      | .dynamicArray element =>
          let _ <- staticAbiWords (arguments.size / 32 + 1) element
          pure ()
      | _ => fail "dynamic-tuple nested dynamic type requires recursive child planning"
      tupleHeadWords ← checkedAdd "dynamic-tuple head" (arguments.size / 32 + 1) tupleHeadWords 1
      dynamicCount := dynamicCount + 1
    else
      tupleHeadWords ← checkedAdd "dynamic-tuple head" (arguments.size / 32 + 1)
        tupleHeadWords (← staticAbiWords (arguments.size / 32 + 1) field)
  unless dynamicCount == maximumLengths.size do
    fail s!"dynamic-tuple has {dynamicCount} dynamic fields but {maximumLengths.size} maximum lengths"
  let tupleHeadBytes ← checkedMul "dynamic-tuple head bytes" arguments.size tupleHeadWords 32
  let headEnd ← checkedAdd "dynamic-tuple head end" arguments.size offset tupleHeadBytes
  if headEnd > arguments.size then fail "dynamic-tuple head exceeds calldata"
  let mut wordIndex := 0
  let mut maximumIndex := 0
  let mut endOffset := headEnd
  let mut slices := #[]
  for h : fieldIndex in [0:fields.size] do
    let field := fields[fieldIndex]
    if field.isDynamic then
      let relativeOffset := ProofForge.Backend.Stylus.DirectWasm.wordToNat
        (← wordAt arguments (offset + wordIndex * 32))
      if relativeOffset % 32 != 0 then fail s!"dynamic tuple field {fieldIndex} offset is not aligned"
      if relativeOffset < tupleHeadBytes then fail s!"dynamic tuple field {fieldIndex} points inside tuple head"
      let lengthOffset ← checkedAdd s!"dynamic tuple field {fieldIndex} length" arguments.size offset relativeOffset
      let length := ProofForge.Backend.Stylus.DirectWasm.wordToNat (← wordAt arguments lengthOffset)
      let maximum := maximumLengths[maximumIndex]!
      if length > maximum then fail s!"dynamic tuple field {fieldIndex} length {length} exceeds maximum {maximum}"
      let dataOffset ← checkedAdd s!"dynamic tuple field {fieldIndex} data" arguments.size lengthOffset 32
      let paddedEnd ← match field with
        | .bytes | .string => do
            let tail <- checkedAdd s!"dynamic tuple field {fieldIndex} tail"
              arguments.size dataOffset (roundUpWord length)
            pure tail
        | .dynamicArray element => do
            let elementWords <- staticAbiWords (arguments.size / 32 + 1) element
            let payloadWords <- checkedMul s!"dynamic tuple field {fieldIndex} array words"
              (arguments.size / 32 + 1) length elementWords
            let payloadBytes <- checkedMul s!"dynamic tuple field {fieldIndex} array bytes"
              arguments.size payloadWords 32
            let tail <- checkedAdd s!"dynamic tuple field {fieldIndex} array tail"
              arguments.size dataOffset payloadBytes
            let mut cursor := dataOffset
            for _ in [0:length] do cursor <- validateStaticAt arguments cursor element
            pure tail
        | _ => fail s!"dynamic tuple field {fieldIndex} has unsupported recursive type"
      if paddedEnd > arguments.size then fail s!"dynamic tuple field {fieldIndex} tail exceeds calldata"
      endOffset := max endOffset paddedEnd
      slices := slices.push { fieldIndex, relativeOffset, dataOffset, length, paddedEnd }
      maximumIndex := maximumIndex + 1
      wordIndex := wordIndex + 1
    else
      wordIndex ← validateStaticAt arguments (offset + wordIndex * 32) field |>.map fun next =>
        (next - offset) / 32
  pure { offset, headWords := tupleHeadWords, endOffset, dynamicFields := slices }

end ProofForge.Backend.Stylus
