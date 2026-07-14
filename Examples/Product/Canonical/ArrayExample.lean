import ProofForge.Frontend.Surface

open ProofForge.Frontend.Surface

namespace Examples.Product.Canonical.ArrayExample

private def u64 (value : Nat) : SurfaceExpr := .literal (.u64Lit value)

private def values : SurfaceExpr :=
  .memoryArray .u64 #[u64 10, u64 20, u64 30]

private def elementAt (index : Nat) : SurfaceExpr :=
  .index (.local "xs") (u64 index)

def contract : SurfaceContract := {
  name := "ArrayExample"
  structs := #[]
  state := #[]
  events := #[]
  errors := #[]
  entrypoints := #[
    { name := "sizeOf3", kind := .function, mutability := .view,
      selector? := some "8c471d33", params := #[], retType := .u64,
      body := #[.returnExpr (u64 3)] },
    { name := "getElem", kind := .function, mutability := .view,
      selector? := some "ff170768", params := #[], retType := .u64,
      body := #[.bind "xs" (.memoryRef .u64) values, .returnExpr (elementAt 1)] },
    { name := "sumOf3", kind := .function, mutability := .view,
      selector? := some "6d666075", params := #[], retType := .u64,
      body := #[
        .bind "xs" (.memoryRef .u64) values,
        .returnExpr (.arith .add true
          (.arith .add true (elementAt 0) (elementAt 1)) (elementAt 2))] }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

end Examples.Product.Canonical.ArrayExample
