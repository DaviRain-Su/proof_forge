import ProofForge.Frontend.Surface

open ProofForge.Frontend.Surface

namespace Examples.Product.Canonical.Ownable

private def zeroAddress : SurfaceExpr :=
  .literal (.addressLit "0x0000000000000000000000000000000000000000")

private def sender : SurfaceExpr :=
  .contextRead .sender

private def ownerCheck : SurfaceStmt :=
  .assert (.compare .eq (.stateRead "owner") sender) "caller is not owner"

def contract : SurfaceContract := {
  name := "Ownable"
  structs := #[]
  state := #[
    { name := "owner", kind := .scalar .address },
    { name := "initialized", kind := .scalar .bool }
  ]
  events := #[{
    name := "OwnershipTransferred"
    fields := #[
      { name := "previousOwner", type := .address, indexed := true },
      { name := "newOwner", type := .address, indexed := true }
    ]
  }]
  errors := #[]
  entrypoints := #[
    { name := "init", kind := .function, mutability := .call,
      selector? := some "e1c7392a", params := #[], retType := .unit,
      body := #[
        .assert (.compare .eq (.stateRead "initialized") (.literal (.boolLit false)))
          "already initialized",
        .stateWrite "initialized" (.literal (.boolLit true)),
        .emit "OwnershipTransferred" #[zeroAddress, sender],
        .stateWrite "owner" sender] },
    { name := "owner", kind := .function, mutability := .view,
      selector? := some "8da5cb5b", params := #[], retType := .address,
      body := #[.returnExpr (.stateRead "owner")] },
    { name := "transferOwnership", kind := .function, mutability := .call,
      selector? := some "f2fde38b",
      params := #[{ name := "newOwner", type := .address }], retType := .unit,
      body := #[
        ownerCheck,
        .assert (.compare .ne (.local "newOwner") zeroAddress) "zero address",
        .emit "OwnershipTransferred" #[.stateRead "owner", .local "newOwner"],
        .stateWrite "owner" (.local "newOwner")] },
    { name := "renounceOwnership", kind := .function, mutability := .call,
      selector? := some "715018a6", params := #[], retType := .unit,
      body := #[
        ownerCheck,
        .emit "OwnershipTransferred" #[.stateRead "owner", zeroAddress],
        .stateWrite "owner" zeroAddress] }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

end Examples.Product.Canonical.Ownable
