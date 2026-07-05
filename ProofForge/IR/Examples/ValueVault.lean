import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.ValueVault

open ProofForge.IR

def balanceDecl : StateDecl := { id := "balance", kind := .scalar, type := .u64 }
def releasedDecl : StateDecl := { id := "released", kind := .scalar, type := .u64 }
def feesDecl : StateDecl := { id := "fees", kind := .scalar, type := .u64 }
def lastValueDecl : StateDecl := { id := "last_value", kind := .scalar, type := .u64 }
def lastCheckpointDecl : StateDecl := { id := "last_checkpoint", kind := .scalar, type := .u64 }
def operationsDecl : StateDecl := { id := "operations", kind := .scalar, type := .u64 }

def initializeEntrypoint : Entrypoint := {
  name := "initialize",
  selector? := some "8129fc1c",
  returns := .unit,
  params := #[("initial", .u64)],
  body := #[
    .letBind "checkpoint" .u64 (.effect (.contextRead .checkpointId)),
    .effect (.storageScalarWrite "balance" (.local "initial")),
    .effect (.storageScalarWrite "released" (.literal (.u64 0))),
    .effect (.storageScalarWrite "fees" (.literal (.u64 0))),
    .effect (.storageScalarWrite "last_value" (.local "initial")),
    .effect (.storageScalarWrite "last_checkpoint" (.local "checkpoint")),
    .effect (.storageScalarWrite "operations" (.literal (.u64 1))),
    .effect (.eventEmit "VaultInitialized" #[
      ("initial", .local "initial"),
      ("checkpoint", .local "checkpoint")
    ])
  ]
}

def depositEntrypoint : Entrypoint := {
  name := "deposit",
  selector? := some "d09de08a",
  returns := .unit,
  params := #[("amount", .u64)],
  body := #[
    .letBind "current" .u64 (.effect (.storageScalarRead "balance")),
    .letBind "next" .u64 (.add (.local "current") (.local "amount")),
    .letBind "ops" .u64 (.effect (.storageScalarRead "operations")),
    .letBind "next_ops" .u64 (.add (.local "ops") (.literal (.u64 1))),
    .effect (.storageScalarWrite "balance" (.local "next")),
    .effect (.storageScalarWrite "last_value" (.local "amount")),
    .effect (.storageScalarWrite "operations" (.local "next_ops")),
    .effect (.eventEmit "ValueDeposited" #[
      ("amount", .local "amount"),
      ("balance", .local "next"),
      ("operations", .local "next_ops")
    ])
  ]
}

def chargeFeeEntrypoint : Entrypoint := {
  name := "charge_fee",
  selector? := some "4ef4885b",
  returns := .unit,
  params := #[("gross", .u64), ("fee_bps", .u64)],
  body := #[
    .letBind "fee" .u64 (.div (.mul (.local "gross") (.local "fee_bps")) (.literal (.u64 10000))),
    .letBind "net" .u64 (.sub (.local "gross") (.local "fee")),
    .letBind "current" .u64 (.effect (.storageScalarRead "balance")),
    .letBind "next" .u64 (.add (.local "current") (.local "net")),
    .letBind "current_fees" .u64 (.effect (.storageScalarRead "fees")),
    .letBind "next_fees" .u64 (.add (.local "current_fees") (.local "fee")),
    .letBind "ops" .u64 (.effect (.storageScalarRead "operations")),
    .letBind "next_ops" .u64 (.add (.local "ops") (.literal (.u64 1))),
    .effect (.storageScalarWrite "balance" (.local "next")),
    .effect (.storageScalarWrite "fees" (.local "next_fees")),
    .effect (.storageScalarWrite "last_value" (.local "net")),
    .effect (.storageScalarWrite "operations" (.local "next_ops")),
    .effect (.eventEmit "ValueCharged" #[
      ("gross", .local "gross"),
      ("fee", .local "fee"),
      ("net", .local "net"),
      ("balance", .local "next")
    ])
  ]
}

def releaseEntrypoint : Entrypoint := {
  name := "release",
  selector? := some "b214faa5",
  returns := .unit,
  params := #[("amount", .u64)],
  body := #[
    .letBind "current" .u64 (.effect (.storageScalarRead "balance")),
    .letBind "next" .u64 (.sub (.local "current") (.local "amount")),
    .letBind "released_before" .u64 (.effect (.storageScalarRead "released")),
    .letBind "released_next" .u64 (.add (.local "released_before") (.local "amount")),
    .letBind "ops" .u64 (.effect (.storageScalarRead "operations")),
    .letBind "next_ops" .u64 (.add (.local "ops") (.literal (.u64 1))),
    .effect (.storageScalarWrite "balance" (.local "next")),
    .effect (.storageScalarWrite "released" (.local "released_next")),
    .effect (.storageScalarWrite "last_value" (.local "amount")),
    .effect (.storageScalarWrite "operations" (.local "next_ops")),
    .effect (.eventEmit "ValueReleased" #[
      ("amount", .local "amount"),
      ("balance", .local "next"),
      ("released", .local "released_next")
    ])
  ]
}

def snapshotEntrypoint : Entrypoint := {
  name := "snapshot",
  selector? := some "0c2d8b55",
  returns := .u64,
  params := #[],
  body := #[
    .letBind "checkpoint" .u64 (.effect (.contextRead .checkpointId)),
    .letBind "balance_now" .u64 (.effect (.storageScalarRead "balance")),
    .letBind "released_now" .u64 (.effect (.storageScalarRead "released")),
    .letBind "fees_now" .u64 (.effect (.storageScalarRead "fees")),
    .effect (.storageScalarWrite "last_checkpoint" (.local "checkpoint")),
    .effect (.eventEmit "ValueSnapshot" #[
      ("balance", .local "balance_now"),
      ("released", .local "released_now"),
      ("fees", .local "fees_now"),
      ("checkpoint", .local "checkpoint")
    ]),
    .return (.local "balance_now")
  ]
}

def getBalanceEntrypoint : Entrypoint := {
  name := "get_balance",
  selector? := some "f8a8fd6d",
  returns := .u64,
  body := #[
    .return (.effect (.storageScalarRead "balance"))
  ]
}

def getNetValueEntrypoint : Entrypoint := {
  name := "get_net_value",
  selector? := some "1a381be1",
  returns := .u64,
  body := #[
    .letBind "balance_now" .u64 (.effect (.storageScalarRead "balance")),
    .letBind "fees_now" .u64 (.effect (.storageScalarRead "fees")),
    .return (.sub (.local "balance_now") (.local "fees_now"))
  ]
}

def module : Module := {
  name := "ValueVault",
  state := #[balanceDecl, releasedDecl, feesDecl, lastValueDecl, lastCheckpointDecl, operationsDecl],
  entrypoints := #[
    initializeEntrypoint,
    depositEntrypoint,
    chargeFeeEntrypoint,
    releaseEntrypoint,
    snapshotEntrypoint,
    getBalanceEntrypoint,
    getNetValueEntrypoint
  ]
}

end ProofForge.IR.Examples.ValueVault
