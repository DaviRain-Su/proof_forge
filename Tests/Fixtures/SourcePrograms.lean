import ProofForgeV2.Core.Source

namespace Tests.Fixtures.SourcePrograms

open ProofForgeV2.Source

private def u64 (n : Nat) : Expr := .literal (UInt64.ofNat n)
private def var (name : String) : Expr := .variable name
private def param (name : String) : Param := { name, type := .u64 }
private def privateParam (name : String) : Param := { name, type := .u64, visibility := .proverWitness }
private def state (name : String) : StateDecl := { name, type := .u64 }

private def initParam (name : String) : Param := param name

/-- Counter: legacy Source.Program fixture matching ProofForgeV2.Examples.Counter. -/
def counter : Program :=
  Program.build "Counter" #[
    .stateDecl (state "count"),
    .initializer {
      params := #[initParam "initial"],
      body := #[.assign "count" (var "initial")]
    },
    .entry {
      name := "increment"
      params := #[param "delta"]
      result := .u64
      mode := .mutate
      body := #[
        .assign "count" (.checkedAdd (var "count") (var "delta")),
        .returnValue (var "count")
      ]
    },
    .entry {
      name := "get"
      params := #[]
      result := .u64
      mode := .view
      body := #[.returnValue (var "count")]
    }
  ]

def counterQualified : Program :=
  { counter with qualifiedName := "ProofForgeV2.Examples.Counter" }

/-- Accumulator: legacy Source.Program fixture matching ProofForgeV2.Examples.Accumulator. -/
def accumulator : Program :=
  Program.build "Accumulator" #[
    .stateDecl (state "total"),
    .initializer {
      params := #[initParam "seed"],
      body := #[.assign "total" (var "seed")]
    },
    .entry {
      name := "add"
      params := #[param "amount"]
      result := .u64
      mode := .mutate
      body := #[
        .assign "total" (.checkedAdd (var "total") (var "amount")),
        .returnValue (var "total")
      ]
    },
    .entry {
      name := "current"
      params := #[]
      result := .u64
      mode := .view
      body := #[.returnValue (var "total")]
    }
  ]

def accumulatorQualified : Program :=
  { accumulator with qualifiedName := "ProofForgeV2.Examples.Accumulator" }

/-- PrivateSum4: legacy Source.Program fixture matching ProofForgeV2.Examples.PrivateSum4. -/
def privateSum4 : Program :=
  Program.build "PrivateSum4" #[
    .entry {
      name := "sum"
      params := #[privateParam "a", privateParam "b", privateParam "c", privateParam "d"]
      result := .u64
      mode := .mutate
      body := #[
        .returnValue (
          .checkedAdd
            (.checkedAdd
              (.checkedAdd (var "a") (var "b"))
              (var "c"))
            (var "d"))
      ]
    }
  ]

def privateSum4Qualified : Program :=
  { privateSum4 with qualifiedName := "ProofForgeV2.Examples.PrivateSum4" }

/-- Counter variant that performs a zero-argument synchronous external call. -/
def counterWithSynchronousCall : Program :=
  Program.build "CounterWithCall" #[
    .stateDecl (state "count"),
    .initializer { params := #[], body := #[] },
    .entry {
      name := "callPeer"
      params := #[]
      result := .u64
      mode := .mutate
      body := #[.synchronousCall "peer", .returnValue (u64 0)]
    }
  ]

/-- Counter variant with different business logic for target-backend independence tests. -/
def counterWithDifferentBusinessLogic : Program :=
  Program.build "CounterDifferentLogic" #[
    .stateDecl (state "count"),
    .initializer {
      params := #[initParam "initial"],
      body := #[.assign "count" (var "initial")]
    },
    .entry {
      name := "increment"
      params := #[param "delta"]
      result := .u64
      mode := .mutate
      body := #[.returnValue (u64 99)]
    },
    .entry {
      name := "get"
      params := #[]
      result := .u64
      mode := .view
      body := #[.returnValue (var "count")]
    }
  ]

def counterQualifiedWithSynchronousCall : Program :=
  { counterWithSynchronousCall with qualifiedName := "ProofForgeV2.Examples.CounterWithCall" }

def counterQualifiedWithDifferentBusinessLogic : Program :=
  { counterWithDifferentBusinessLogic with qualifiedName := "ProofForgeV2.Examples.CounterDifferentLogic" }

end Tests.Fixtures.SourcePrograms
