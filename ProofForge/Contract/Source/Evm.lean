/- # EVM target-extension authoring facade

Import this module from EVM-specific SDK and stdlib modules. Portable product
sources continue to import `ProofForge.Contract.Source` only.
-/
import ProofForge.Contract.Source.Legacy
import ProofForge.Target.HostOps.Evm

namespace ProofForge.Contract.Source.Evm

open ProofForge.Contract.Source.Legacy

def origin : ProofForge.IR.Expr :=
  .hostCall ProofForge.Target.HostOps.Evm.originSig.id #[]
    .address #[.callerSender]

def prevRandao : ProofForge.IR.Expr :=
  .hostCall ProofForge.Target.HostOps.Evm.prevRandaoSig.id #[]
    .hash #[.envBlock]

def gasPrice : ProofForge.IR.Expr :=
  .hostCall ProofForge.Target.HostOps.Evm.gasPriceSig.id #[]
    .u64 #[.envBlock]

def baseFee : ProofForge.IR.Expr :=
  .hostCall ProofForge.Target.HostOps.Evm.baseFeeSig.id #[]
    .u64 #[.envBlock]

def coinbase : ProofForge.IR.Expr :=
  .hostCall ProofForge.Target.HostOps.Evm.coinbaseSig.id #[]
    .hash #[.envBlock]

def blockHash (blockNumber : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  .hostCall ProofForge.Target.HostOps.Evm.blockHashSig.id #[blockNumber]
    .hash #[.envBlock]

def ecrecover (digest v r s : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  .hostCall ProofForge.Target.HostOps.Evm.ecrecoverSig.id #[digest, v, r, s]
    .u64 #[.cryptoEcrecover]

def eip712PermitDigest
    (owner spender value nonce deadline domainSep : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  .hostCall ProofForge.Target.HostOps.Evm.eip712PermitDigestSig.id
    #[owner, spender, value, nonce, deadline, domainSep] .hash #[.cryptoEcrecover]

/-- EVM CREATE deployment with fixed init-code bytes. -/
def createDeploy (callValue : ProofForge.IR.Expr) (initCodeHex : String) :
    ProofForge.IR.Expr :=
  .hostCall ProofForge.Target.HostOps.Evm.createSig.id
    #[callValue, .literal (.string initCodeHex)] .address #[.crosscallInvoke]

/-- EVM CREATE2 deployment with fixed init-code bytes. -/
def create2Deploy (callValue salt : ProofForge.IR.Expr) (initCodeHex : String) :
    ProofForge.IR.Expr :=
  .hostCall ProofForge.Target.HostOps.Evm.create2Sig.id
    #[callValue, salt, .literal (.string initCodeHex)] .address #[.crosscallInvoke]

def checkErc721Received (operator fromAddr toAddr tokenId : ProofForge.IR.Expr) :
    EntryM Unit :=
  ProofForge.Contract.Builder.effect
    (.hostCall ProofForge.Target.HostOps.Evm.erc721ReceivedSig.id
      #[operator, fromAddr, toAddr, tokenId] #[.crosscallInvoke])

def checkErc1155Received
    (operator fromAddr toAddr id amount : ProofForge.IR.Expr) : EntryM Unit :=
  ProofForge.Contract.Builder.effect
    (.hostCall ProofForge.Target.HostOps.Evm.erc1155ReceivedSig.id
      #[operator, fromAddr, toAddr, id, amount] #[.crosscallInvoke])

def checkErc1155BatchReceived
    (operator fromAddr toAddr ids amounts : ProofForge.IR.Expr) : EntryM Unit :=
  ProofForge.Contract.Builder.effect
    (.hostCall ProofForge.Target.HostOps.Evm.erc1155BatchReceivedSig.id
      #[operator, fromAddr, toAddr, ids, amounts] #[.crosscallInvoke, .dataFixedArray])

end ProofForge.Contract.Source.Evm
