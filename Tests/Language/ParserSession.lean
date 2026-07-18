import ProofForgeV2.Language.Loader

namespace Tests.Language.ParserSession

open ProofForgeV2

private initialize cache : IO.Ref (Option Language.Loader.ParserSession) ←
  IO.mkRef none

/-- Reuse the immutable parser environment across sequential language suites. -/
unsafe def shared : IO Language.Loader.ParserSession := do
  match ← cache.get with
  | some session => return session
  | none =>
      let session ← Language.Loader.ParserSession.create
      cache.set (some session)
      return session

end Tests.Language.ParserSession
