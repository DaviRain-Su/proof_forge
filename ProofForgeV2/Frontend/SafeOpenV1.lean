/-
  ProofForgeV2.Frontend.SafeOpenV1 — B11a source safe-open foundation.

  A trusted absolute project root and validated ProjectRelativePath are opened
  component-by-component by the package-owned native implementation. Every
  component is no-follow/nonblocking/close-on-exec; the leaf must be a regular,
  single-link file. The native read uses the initial fstat size, probes one byte
  past EOF, and rechecks fd + pathname metadata before returning at most 16 MiB.

  This module intentionally does not claim a read deadline, process/session
  containment, a supervisor receipt, or CLI product cutover. B11b owns the
  killable execution unit and shared monotonic deadline needed for those claims.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Frontend.ProtocolV1

namespace ProofForgeV2.Frontend.SafeOpenV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Frontend.ProtocolV1
open System

inductive SafeOpenFaultV1 where
  | invalidRoot
  | notFound
  | permissionDenied
  | unsafePath
  | nonRegular
  | multipleLinks
  | tooLarge
  | shortRead
  | grewDuringRead
  | changedDuringRead
  | io
  | nativeProtocol
  deriving BEq, DecidableEq, Repr

namespace SafeOpenFaultV1

def wire : SafeOpenFaultV1 → String
  | .invalidRoot => "invalid-root"
  | .notFound => "not-found"
  | .permissionDenied => "permission-denied"
  | .unsafePath => "unsafe-path"
  | .nonRegular => "non-regular"
  | .multipleLinks => "multiple-links"
  | .tooLarge => "too-large"
  | .shortRead => "short-read"
  | .grewDuringRead => "grew-during-read"
  | .changedDuringRead => "changed-during-read"
  | .io => "io"
  | .nativeProtocol => "native-protocol"

def ofWire? : String → Option SafeOpenFaultV1
  | "invalid-root" => some .invalidRoot
  | "not-found" => some .notFound
  | "permission-denied" => some .permissionDenied
  | "unsafe-path" => some .unsafePath
  | "non-regular" => some .nonRegular
  | "multiple-links" => some .multipleLinks
  | "too-large" => some .tooLarge
  | "short-read" => some .shortRead
  | "grew-during-read" => some .grewDuringRead
  | "changed-during-read" => some .changedDuringRead
  | "io" => some .io
  | "native-protocol" => some .nativeProtocol
  | _ => none

end SafeOpenFaultV1

/-- Opaque bytes from one stable native file snapshot. -/
structure SafeSourceSnapshotV1 where
  private mk ::
  private bytes_ : ByteArray

namespace SafeSourceSnapshotV1

def bytes (snapshot : SafeSourceSnapshotV1) : ByteArray := snapshot.bytes_
def size (snapshot : SafeSourceSnapshotV1) : Nat := snapshot.bytes_.size

end SafeSourceSnapshotV1

@[extern "proof_forge_safe_open_source_v1"]
private opaque nativeSafeOpenSourceV1
    (root relative : @& String) (maxBytes : UInt64) :
    IO (Except String ByteArray)

private def containsNul (value : String) : Bool :=
  value.toList.any (· == '\x00')

/-- Open and read one project-relative source beneath a trusted absolute root.

    The 16 MiB maximum is the same B9/B10 `maxSourceBytes`; callers cannot raise
    it. Native errors are a closed, redacted class and never include errno prose
    or host paths. Unknown native labels fail closed as `.nativeProtocol`. -/
def safeOpenSourceV1
    (root : FilePath) (path : ProjectRelativePath) :
    IO (Except SafeOpenFaultV1 SafeSourceSnapshotV1) := do
  let rootString := root.toString
  if !root.isAbsolute || rootString.isEmpty || containsNul rootString then
    return .error .invalidRoot
  let relative ←
    match renderProjectRelativePath path with
    | .ok value => pure value
    | .error _ => return .error .unsafePath
  if containsNul relative then
    return .error .unsafePath
  match ← nativeSafeOpenSourceV1 rootString relative (UInt64.ofNat maxSourceBytes) with
  | .error wire =>
      let fault := match SafeOpenFaultV1.ofWire? wire with
        | some fault => fault
        | none => .nativeProtocol
      pure (.error fault)
  | .ok bytes =>
      if bytes.size > maxSourceBytes then
        pure (.error .nativeProtocol)
      else
        pure (.ok ⟨bytes⟩)

end ProofForgeV2.Frontend.SafeOpenV1
