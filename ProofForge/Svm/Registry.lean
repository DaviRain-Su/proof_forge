namespace ProofForge.Svm.Registry

/-- Source program registered for SVM builds and its canonical target-IR digest. -/
structure Entry where
  name : String
  digest : String
  deriving BEq, Repr, Inhabited

def entries : Array Entry := #[
  { name := "Counter", digest := "3382e308fa0843e9" },
  { name := "Pair", digest := "67bb79356a73c78e" },
  { name := "Nested", digest := "7ce1913d3f9781b1" },
  { name := "Tree", digest := "5f7101960e6b8c15" },
  { name := "Flag", digest := "35d56ff1f3242582" },
  { name := "Maybe", digest := "2748805231c05ee2" },
  { name := "Window", digest := "2d13510bc7111128" },
  { name := "Phase", digest := "927b7fa633bd223" },
  { name := "Choice", digest := "77dcaa9d61a2a535" },
  { name := "Clock", digest := "9df09f9ee94b97f0" },
  { name := "Transfer", digest := "f2da40e6199ba343" },
  { name := "Ping", digest := "2d14206f60b0cbd6" },
  { name := "Call", digest := "d61ef848389e963a" },
  { name := "Info", digest := "a52527680ee65c03" },
  { name := "Peer", digest := "8c8ed8f343755cba" },
  { name := "Pda", digest := "1f1a994e206aa42b" },
  { name := "Signed", digest := "23102ccf4deeceda" },
  { name := "Create", digest := "ae81054e874be24f" },
  { name := "TokenXfer", digest := "c9edc88528b425dd" },
  { name := "Token2022", digest := "85f3957e1c6e3f3a" },
  { name := "Ata", digest := "574dc90c21ca9723" },
  { name := "Rent", digest := "831e5502b9b3cfe5" },
  { name := "TokenMint", digest := "f7535d90750f9692" },
  { name := "SysAlloc", digest := "dbb2269b9ac57a3" },
  { name := "TokenAcc", digest := "53013fc1bc2e0753" },
  { name := "Memo", digest := "26a3540da902ccb5" },
  { name := "CreatePda", digest := "403b2e609334f1ee" },
  { name := "TokenApprove", digest := "e99f2008d320e15c" },
  { name := "TokenFreeze", digest := "6d4fceb52be9cf0a" },
  { name := "TokenAuth", digest := "bf3d403346f51b82" },
  { name := "Epoch", digest := "27254aa6c545c80" },
  { name := "TokenSize", digest := "fa48e892121ea415" },
  { name := "SysSeed", digest := "490cec59af518f0c" },
  { name := "SysXfer", digest := "906efee37227cb35" },
  { name := "TokenMint2", digest := "89ae474933102cb4" },
  { name := "TokenNative", digest := "5bc920f79c3711f0" },
  { name := "Hash", digest := "b4b9944a712e0466" },
  { name := "Keys", digest := "c1ccffc6967872ba" },
  { name := "Keccak", digest := "d6b87324d0e8ebdf" },
  { name := "Trio", digest := "5238c1a71a4f49e2" },
  { name := "Gate", digest := "76215ebadb4e84d6" },
  { name := "Nonce", digest := "5746ebbdd382bd56" },
  { name := "TokenOwner", digest := "d29884f00e7311b7" },
  { name := "TokenMs", digest := "672b83a54f057f79" },
  { name := "SelfLog", digest := "7c000e2c7844d1af" },
  { name := "Phoenix", digest := "7d561c4f974a86d2" },
  { name := "Book", digest := "525c5967ae68d203" },
  { name := "Seat", digest := "831f313077f89947" },
  { name := "Lang", digest := "64264acebea0c34c" }
]

def names : Array String := entries.map (·.name)

def digestOf (name : String) : Option String :=
  (entries.find? (·.name == name)).map (·.digest)

end ProofForge.Svm.Registry
