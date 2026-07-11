# Primary-Triad Runtime Handoff

> Status: checkpoint ready for a Draft PR; Wave T implementation is present,
> but `T-99` is intentionally still `pending`.

## 1. Objective And Source Of Truth

The product objective remains:

```text
portable business source
  -> typed product intent
  -> evidence-eligible target route
  -> EVM code | NEAR Wasm | Solana protocol bundle/program
  -> client + deployment/broadcast plan + receipt + evidence
```

The authoritative full roadmap is
`docs/superpowers/plans/2026-07-11-primary-triad-multichain-runtime.md`.
This document is the executable handoff for work after the current checkpoint.

Checkpoint branch and base:

- Branch: `feat/primary-triad-runtime-execution`
- Original base: `origin/main@ad8f2e86`
- Upstream integrated before PR: `origin/main@e8806d20`
- Last implementation checkpoint: `ca0d8e25`
- Worktree: `.worktrees/primary-triad-runtime`

Do not mark the long-running milestone complete after closing only `T-99`.
The final multi-chain runtime still requires Waves F, R, E, N, S, and P.

## 2. Completed In This Checkpoint

All Wave-T rows before `T-99` are implemented and recorded in the execution
ledger:

- `T-00`: requirement-level compliance manifests and evidence model.
- `E-P0-01`: canonical EVM selector/schema derivation.
- `E-P0-02`: atomic ERC-2612 permit and attack matrix.
- `E-P0-03`: immutable standard identity and access surfaces.
- `E-P0-04`: runtime custom-error type/range/payload safety.
- `N-P0-01`: authoritative per-entrypoint NEAR ABI plan and generated client.
- `N-P0-02`: NEAR FT initialization, authority, callback, concurrency, refund safety.
- `N-P0-03`: stable non-aliasing hash-valued map reads.
- `S-P0-01`: duplicate-aware Solana account decoding with live Surfpool proof.
- `S-P0-02`: per-entrypoint Solana account graphs and least privilege.
- `X-P0-01`: exact manifest/adapter/version/artifact evidence-bound feature support.
- `T99-01`: stale scalar-safety fixture now injects the authoritative
  `NearAbiPlan`, with a negative bare-context regression.
- `T99-02`: the platform-dependent worker-resource checks remain in ordinary
  `just check` but are outside the skip-free Wave-T evidence scope.

The checkpoint also adds the `T-99` infrastructure:

- `just wave-t-gate` executes a code-locked 25-command manifest.
- Production mode cannot be weakened by editing the manifest profile.
- Historical implementation commits must exist and be ancestors of `HEAD`.
- Dirty worktrees, failed/missing tools, skip markers, missing/stale/changed
  artifacts, wrong metadata, and wrong adapter versions fail closed.
- GitHub uploads JSON plus per-command logs; GitHub and Woodpecker use full
  history and install pinned native toolchains.
- NEAR sandbox is pinned to 2.13.0 with S3 version ID and SHA-256 validation.
- NEAR sandbox gates export the checked binary before compiling
  `near-workspaces`.
- Solana Surfpool cleanup has a bounded `TERM` then `KILL` fallback.

Focused regressions fixed while exercising the aggregate:

- EVM semantic-plan callbacks now satisfy the error-returning lowering API.
- Strict Solana gates build the optional ValueVault ELF instead of counting a
  skip as a pass.
- `token_plan_smoke` validates burn instructions according to the actual
  operation list rather than requiring burn for every token.

The PR branch also integrates upstream Batch B/C work through `e8806d20`,
including dynamic ERC-1155 batch IR, NEAR U128/gas/storage primitives, Solana
control-flow and arithmetic coverage, NEAR/Metaplex NFT stdlib primitives, and
cross-target refinement extensions. These are useful implementation inputs;
they do not by themselves close the router-backed `E-03`, `N-07`, `S-06`, or
cross-target product rows below.

Upstream `e8806d20` was an empty commit whose message claimed EVM upgrade-policy
honesty had been restored. During integration this branch reinstated the actual
fail-closed behavior: portable `UpgradePolicy.authority keyRef` remains rejected
until `keyRef` is bound to runtime authorization. The explicit UUPS fixture
`admin` constructor argument is documented separately from that portable
policy.

## 3. Current Evidence

The latest complete report was generated from clean source
`880417b69d5893ea86c84e772c0586e94166b72d`:

- Result: `20 / 25` gates passed.
- Tools: all `18 / 18` required tool-version probes passed.
- Artifacts: all five expected artifacts were present. The report is not
  promotable while any gate is red.
- `just evm-all` failed because the generated dynamic ERC-1155 batch calldata
  differs from the checked golden. The new emitter writes dynamic tails four
  bytes before the selector-relative ABI offsets; do not accept this by blindly
  regenerating the golden.
- `just near-abi-client-sandbox` reached the generated client but failed because
  the RPC adapter returned a shape for which `response.result` was undefined.
- `just near-ft-security-sandbox` and `just near-map-hash-alias-sandbox` were
  rejected by NEAR with `PrepareError(Deserialization)`. Both emitted modules
  contain multi-value `(result i64 i64)` U128 helpers, and
  `wasm-validate --disable-multi-value` reproduces the incompatibility.
- `just wave-t-check` reached the Rust testkit and failed the Solana Counter
  compute budget: baseline `56`, allowed `58`, observed `70`.

Artifact SHA-256 values:

| Artifact | Adapter | SHA-256 |
|---|---|---|
| ERC-2612 contract metadata | `proof-forge.evm.erc2612@1` | `75bd5d6ab21134c927c7a87e2c7192936c8e13d47680a89d40be5e5e97395c3b` |
| ERC-2612 creation bytecode | `proof-forge.evm.erc2612@1` | `7ba8b02a77f9e6311c17c0355cf8009369d071eb57e331485fd5312235262fb5` |
| NEP-141 product plan | `proof-forge.near.nep141@1` | `d1a5a2aa07f7d476bb34ec522a6f0f8e4691336732a37916865aa4fe0c2efd50` |
| NEP-141 WAT | `proof-forge.near.nep141@1` | `9c20975b121977750c8cf09c0e4f39bf902f7b3e2f734559e0d246d1265119c4` |
| SPL Token plan | `proof-forge.solana.spl-token@1` | `06920170e33402ba89104ccf7722132025cdd1e32d3ab87fcdf275ef5ccc969d` |

The report is ignored build output at `build/evidence/wave-t.json`; CI uploads it
with `build/evidence/wave-t-logs/`.

## 4. Immediate Completion Queue

Execute these tasks in order. Do not start `R-03` before the barrier in Task 4.

### T99-03A: Restore ERC-1155 Dynamic Batch ABI Correctness

The merged dynamic batch emitter currently writes array tails at byte `160`
while its ABI head stores offset `160` relative to the argument block beginning
after the four-byte selector. The first tail therefore belongs at byte `164`.
Preserve the dynamic array design, repair every selector-relative tail offset,
and add an exact receiver calldata/runtime assertion. Do not update the golden
until the canonical ABI oracle passes.

Acceptance:

```sh
just evm-build-examples
just evm-semantic-plan
just evm-foundry
git diff --check
```

### T99-03B: Emit NEAR-Compatible U128 And Normalize RPC Results

1. Replace Wasm multi-value U128 helpers with an MVP-compatible convention,
   such as caller-provided result memory or inline locals. Do not narrow U128.
2. Add `wasm-validate --disable-multi-value` to the NEAR artifact gate so an
   unsupported proposal fails before deployment.
3. Capture the raw sandbox JSON-RPC response in the ABI-client regression and
   normalize the provider boundary exactly once. Accept both supported provider
   shapes only when the response is type-checked; do not silently treat missing
   result bytes as an empty value.

Acceptance:

```sh
just near-abi-client-sandbox
just near-ft-security-sandbox
just near-map-hash-alias-sandbox
just near-abi-plan
just near-plan-smoke
```

### T99-03C: Audit The Solana Counter Compute Regression

Compare the testkit instruction/trace delta that moved `initialize` from `56`
to `70` compute units after Batch B/C. Optimize or remove accidental work when
the extra instructions are not semantically required. Update the baseline only
after the emitted instruction delta is reviewed and the new cost is intentional.

Acceptance:

```sh
just testkit
just solana-light
just product
```

### CI-HYGIENE-01: Bound EVM Anvil Cleanup

Repeated `evm-all` runs leave orphaned random-port Anvil processes in this
worktree. Apply the same bounded shutdown policy as
`scripts/solana/stop-background-process.sh` to the affected EVM live scripts.
Add a real regression using a child that ignores `TERM`.

Acceptance:

```sh
before=$(pgrep -x anvil | wc -l | tr -d ' ')
just evm-all
after=$(pgrep -x anvil | wc -l | tr -d ' ')
test "$before" = "$after"
```

Do not kill Anvil instances whose cwd/parentage does not belong to the active
test run.

### T99-04: Close And Record Wave T

1. Commit T99-03A/B/C and ensure the worktree is clean.
2. Run `just wave-t-gate` once without interruption.
3. Require `25 / 25`, all tools passed, five artifacts present, no integrity
   failure, and `source.dirty == false`.
4. Run `just docs-check` and `git diff --check`.
5. Request independent review of the report and aggregate implementation.
6. Update the roadmap row and Task 9 checkboxes to
   `done: verified@<tested SHA>; just wave-t-gate`.
7. Commit the evidence documentation separately.

## 5. Foundation And Router Queue

T99-01 and T99-02 are closed. Foundation and route-type tasks may proceed in
isolated worktrees while T99-03 is repaired, but keep shared IR migrations
separate and merge current `origin/main` before integration.

| Order | Task | Deliverable | Required acceptance |
|---|---|---|---|
| 1A | `F-01` | Real `NumericDomain` / `AmountPolicy`: EVM U256, NEAR U128, Solana u64; preserve or reject, never truncate | boundary arithmetic/codec tests, `just product`, `just check` |
| 1B | `F-02` | Opaque `Principal` / target `IdentityCodec`: 20-byte EVM, full NEAR AccountId, 32-byte Solana Pubkey | round-trip/compare/store/auth tests, no U64 hash projection |
| 1C | `R-01` | Versioned route draft, immutable route plan, build report, per-component payload/invocation/compliance types | deterministic JSON/repr; post-build evidence cannot mutate plan |
| 2 | `R-02` | One-pass `ProductIntent` loader for contract/token/NFT | elaborate once; preserve original errors; reject ambiguous/missing exports; remove exception fallback |
| 3 | Barrier | `T-99 + F-01 + F-02 + R-01 + R-02` all green | independent cross-backend review |
| 4 | `R-03` | Evidence-backed `ProductRouter` dispatching through `BackendRegistry` | exact eligible adapters only; stable target/feature/evidence rejection reason |
| 5 | `R-04..R-07` | Protocol intent, async completion, typed artifact/build report, `proof-forge plan --target` | EVM code, NEAR code, Solana bundles/hybrids truthfully distinct |

Parallel ownership rule:

- F lane owns shared numeric/principal IR and codecs.
- R lane owns `Target/ProductRoute`, `Contract/ProductIntent`, and router/CLI.
- Chain agents must not bypass these abstractions with target-specific source
  detection or ad hoc evidence strings.

## 6. Chain Delivery After The Router Barrier

Run chain lanes in parallel only after their listed dependencies:

- EVM: `E-01 -> E-02`, then ERC-721/1155/4626/lifecycle/protocol work
  (`E-03..E-09`).
- NEAR: `N-01 -> N-02 -> N-03 -> N-04`, with Promise and external FT work
  (`N-05/N-06`) before NFT/lifecycle closure (`N-07..N-09`).
- Solana: `S-01 -> S-02 -> S-03 -> S-04/S-05`, then Metaplex and loader
  lifecycle (`S-06..S-09`).
- Cross-target: implement semantic scenario schema `P-05` before FT/NFT/external
  protocol scenarios (`P-01..P-03`), then unified UX/formal/release evidence
  (`P-04/P-06/P-07`).

Every adapter task must include a standards manifest, target-native runtime
evidence, negative unsupported-feature tests, artifact/client parity, and docs.

## 7. Long-Running Agent Prompt

Use the following as the next long-running instruction:

```text
Continue ProofForge's primary-triad runtime plan from
docs/superpowers/plans/2026-07-11-primary-triad-runtime-handoff.md.

Work from feat/primary-triad-runtime-execution and merge current origin/main
before editing. Preserve all user changes and use isolated worktrees.

First close T99-03A, T99-03B, T99-03C, and CI-HYGIENE-01 with TDD. Do not
regenerate the ERC-1155 golden before canonical ABI runtime proof; do not emit
Wasm multi-value functions for NEAR; do not rebaseline Solana compute without a
reviewed instruction delta. Preserve mandatory NearAbiPlan checks, exact
evidence matching, clean-worktree enforcement, artifact freshness, and skip
detection. Commit each root-cause fix separately, then run one uninterrupted
`just wave-t-gate` on a clean commit. Require 25/25 gates, all tool probes, five
bound artifact digests, and independent review before marking T-99 done.

After T-99, execute F-01/F-02 and R-01/R-02 according to the dependency table.
Do not start R-03 until T-99, F-01, F-02, R-01, and R-02 are all verified.
Maintain the execution ledger after every task using
`done: verified@<tested SHA>; <fresh commands>`. Continue through verification,
commit, push, and PR updates; do not stop at a checkpoint unless a real blocker
is recorded with exact reproduction evidence.
```

## 8. PR Policy For This Checkpoint

Publish this checkpoint as a Draft PR. It is expected to show the five T-99
failures recorded above until T99-03A/B/C are completed. Do not mark ready or
merge while the required Wave-T CI step is red. Keep the worktree and branch for
follow-up.
