# Legacy Learn Parser Examples

These files are compatibility fixtures for the standalone `.learn` parser.
`ProofForge.Contract.Learn` parses the current portable subset into a source AST
and lowers it into the same `ContractSpec` and portable IR boundary used by the
Lean `contract_source` syntax. The current authoring surface remains Lean SDK
syntax; these files exist so the old file-based parser keeps exercising the
compiler pipeline.

The executable embedded equivalent lives in `ProofForge.Contract.Source`
through the `contract_source` syntax. The string-heavy `ContractSpec`, Builder,
and `ProofForge.Solana.Examples.*` fixtures are expected-IR/reference fixtures
for tests; they are not the surface application developers should author by
hand. The legacy parser may represent identifiers as strings internally after
parsing, but lowering checks Solana CPI/PDA/state/account references before
those names reach compiler artifacts. The portable ValueVault smoke deliberately
routes `Examples/Learn/ValueVault.learn` through the CLI so regressions in this
compatibility path are caught before backend package generation is considered
passing.
For CPI declarations, account operands must first be introduced with
`solana account ...`; writable and signer requirements are checked against that
declaration. Scalar instruction parameters and state values remain ordinary
Learn values.

- `Counter.learn` mirrors the portable Counter source.
- `ValueVault.learn` mirrors `ProofForge.Contract.Examples.ValueVault`.
- `SolanaVault.learn` mirrors `ProofForge.Solana.Examples.Vault` and exercises
  the first Solana target-extension syntax for accounts, PDA derivation, and
  SPL Token CPI.
- `SystemCpi.learn` mirrors `ProofForge.Solana.Examples.SystemCpi`.
- `SystemCreateAccountCpi.learn` mirrors
  `ProofForge.Solana.Examples.SystemCreateAccountCpi`.
- `SplTokenOpsCpi.learn` mirrors
  `ProofForge.Solana.Examples.SplTokenOpsCpi` and exercises selector-bearing
  SPL Token mint, burn, approve, and revoke CPI syntax.
- `LogEvent.learn` mirrors `ProofForge.Solana.Examples.LogEvent` and
  exercises Solana log helper syntax for pubkey and data logs.
- `ReturnDataCompute.learn` mirrors
  `ProofForge.Solana.Examples.ReturnDataCompute` and exercises Solana return
  data plus remaining-compute-unit helper syntax.
- `Memory.learn` mirrors `ProofForge.Solana.Examples.Memory` and exercises
  Solana memory helper syntax.
- `Crypto.learn` mirrors `ProofForge.Solana.Examples.Crypto` and exercises
  SHA-256, Keccak-256, and BLAKE3 hash helper syntax.
- `Clock.learn`, `Rent.learn`, `EpochSchedule.learn`, `EpochRewards.learn`,
  and `LastRestartSlot.learn` mirror the corresponding Solana examples and
  exercise Learn sysvar/context syntax.

`Tests/LearnSource.lean` checks that these files lower to the same IR modules as
the macro-generated examples, and checks that the Solana target-extension form
renders the same manifest as the embedded source example. The next
implementation step is keeping new SDK work in the Lean SDK layer while the
legacy parser reuses the same compiler-owned boundaries.

Token SDK compatibility examples use a separate Learn intent form that lowers
to the same Lean `TokenSpec` boundary as
[`Examples/Shared/FungibleToken.lean`](../Shared/FungibleToken.lean) and
[`Examples/Shared/FeeToken.lean`](../Shared/FeeToken.lean):

- `ProofToken.learn` describes one fungible token once and can be routed with
  `proof-forge --learn-token --target evm` to ERC-20 Yul, bytecode, and
  artifact metadata.
- `FeeToken.learn` mirrors the shared transfer-fee intent and remains an
  equivalence fixture for the Token-2022 plan selected by
  `Examples/Shared/FeeToken.lean`.

`TokenSpec` remains the internal compiler boundary used after parsing, target
routing, and validation. New product examples should start from the shared
Lean `TokenSpec`; these `.learn` files remain compatibility fixtures.
