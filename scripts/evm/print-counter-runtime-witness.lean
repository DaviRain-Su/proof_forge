import EvmRefinement.CounterRuntime

def main : IO UInt32 := do
  IO.println EvmRefinement.CounterRuntime.hex
  return 0
