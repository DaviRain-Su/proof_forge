import ProofForgeV2

open ProofForgeV2.Language

-- This must remain invalid: execution shape comes from --target, never source kind.
program Invalid : contract where
  state value : UInt64
