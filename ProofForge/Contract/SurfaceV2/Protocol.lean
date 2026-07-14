import ProofForge.Frontend.Surface

namespace ProofForge.Contract.SurfaceV2.Protocol

open ProofForge.Frontend.Surface

structure RemoteRef where
  peerId : String
  method : String

def invoke (remote : RemoteRef) (args : Array SurfaceExpr)
    (returnType : SurfaceType := .u64) : SurfaceExpr :=
  .crosscall .invoke (.peerRef remote.peerId) (.literal (.stringLit remote.method))
    args returnType

def externalToken (peerId method : String) : RemoteRef := { peerId, method }
def externalVault (peerId method : String) : RemoteRef := { peerId, method }

end ProofForge.Contract.SurfaceV2.Protocol
