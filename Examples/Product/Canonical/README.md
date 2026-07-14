# Canonical EVM Product Sources

This directory contains the public EVM materialization source set during the
ordered Legacy replacement. The product roots are selected by the entries in
`../catalog.json` that advertise the `evm` target. Additional files may be
focused collection examples and are not silently added to the product gate.

Each source exports `contract : SurfaceContract`. The public EVM build and
check commands load that value directly and run:

`Surface v2 -> checked Canonical Core -> EVM ModulePlan -> Yul/bytecode`

These files do not export `ContractSpec` and do not convert through Legacy IR.
The older sibling sources remain temporarily because NEAR and Solana have not
yet completed their ordered source migration. Remove those old definitions in
the corresponding chain phase, not by routing EVM back through them.
