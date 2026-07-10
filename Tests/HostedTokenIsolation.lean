import ProofForge.Cli.TokenLoader

unsafe def main : IO UInt32 := do
  try
    discard <| ProofForge.Cli.TokenLoader.loadToken
      (System.FilePath.mk "Examples/Product/FungibleToken.lean")
      (some (System.FilePath.mk ".")) none
    throw <| IO.userError "TokenLoader bypassed hosted isolation"
  catch err =>
    let message := toString err
    if message.contains "hosted isolation is not ready" && message.contains "PF-P3-03" then
      IO.println "hosted-token-isolation: ok"
      pure 0
    else
      throw <| IO.userError s!"unexpected TokenLoader error: {message}"
