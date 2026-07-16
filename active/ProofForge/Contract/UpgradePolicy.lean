namespace ProofForge.Contract

/-- Logical key reference resolved by the signer at deployment time. -/
abbrev KeyRef := String

/-- Upgrade policy intent for a contract. -/
inductive UpgradePolicy where
  | immutable
  | authority (keyRef : KeyRef)
  | governance (ref : String)
  deriving BEq, Repr

def UpgradePolicy.kind : UpgradePolicy → String
  | .immutable => "immutable"
  | .authority _ => "authority"
  | .governance _ => "governance"

def UpgradePolicy.keyRef? : UpgradePolicy → Option KeyRef
  | .authority keyRef => some keyRef
  | _ => none

/-- EVM proxy layout declared by `contract_source` for honest upgrade-policy lowering. -/
inductive ProxyPattern where
  | uups
  | transparent
  deriving BEq, Repr

def ProxyPattern.kind : ProxyPattern → String
  | .uups => "uups"
  | .transparent => "transparent"

private def jsonString (value : String) : String :=
  let escapeChar : Char → String
    | '"' => "\\\""
    | '\\' => "\\\\"
    | '\n' => "\\n"
    | '\r' => "\\r"
    | '\t' => "\\t"
    | ch => ch.toString
  "\"" ++ String.intercalate "" (value.toList.map escapeChar) ++ "\""

private def jsonObject (fields : Array (String × String)) : String :=
  "{" ++
    String.intercalate "," (fields.toList.map fun field =>
      jsonString field.fst ++ ":" ++ field.snd) ++
  "}"

def UpgradePolicy.json (policy : UpgradePolicy) : String :=
  match policy with
  | .immutable =>
      jsonObject #[("kind", jsonString "immutable")]
  | .authority keyRef =>
      jsonObject #[
        ("kind", jsonString "authority"),
        ("keyRef", jsonString keyRef)
      ]
  | .governance ref =>
      jsonObject #[
        ("kind", jsonString "governance"),
        ("ref", jsonString ref)
      ]

def ProxyPattern.json (pattern : ProxyPattern) : String :=
  jsonObject #[("kind", jsonString pattern.kind)]

end ProofForge.Contract
