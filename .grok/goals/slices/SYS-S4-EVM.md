# Goal slice — SYS-S4-EVM: CALLVALUE

## ID
`SYS-S4-EVM`

## Objective
Open EVM Plan/IR/Yul for `context.attachedValue` as `CALLVALUE` (UInt64),
with Anvil engineering gate. Non-payable / unexpected value fail closed.
View remains independent of value.

## Dependencies
`SYS-S4-SHARED`

## Allowed path prefixes
```
ProofForgeV2/Targets/Evm/
Tests/Materialization/
runtime-tests/evm/
Examples/
docs/engineering-backlog.md
.grok/next-wave-queue.md
supply-chain/
```
