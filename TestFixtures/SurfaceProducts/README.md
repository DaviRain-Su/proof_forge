# Internal Surface Migration Fixtures

This directory temporarily preserves direct `SurfaceContract` values used to
test the EVM canonical route while the single `contract_source` frontend is
being completed. They are compiler fixtures, not product sources or a public
authoring API.

Each fixture exports `contract : SurfaceContract` and exercises:

`internal Surface -> checked Canonical Core -> EVM ModulePlan -> Yul/bytecode`

The only authored products remain in `Examples/Product`, using
`contract_source` and no target-specific AST. Delete these fixtures once that
frontend reaches the same canonical route for the full catalog.
