import ProofForgeFormal.Evm.CounterRuntime

def main : IO UInt32 := do
  IO.println ProofForgeFormal.Evm.CounterRuntime.hex
  return 0
