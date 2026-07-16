# RFC 0012: Versioning and Compatibility Policy

Status: **Accepted** (D-042; P1.3 closed 2026-07-10)
Date: 2026-07-03

## Problem

The IR has 99 constructors and three coverage manifests already gate its
evolution — but only structurally. The strings `portable-ir-v0` and artifact
`schemaVersion` fields exist with no stated rules:

- What is a breaking IR change vs. a compatible addition?
- Which artifact/deploy schema fields are stable for external consumers
  (explorers, the future cloud platform)?
- Can a capability id ever change meaning, or must new semantics get a new id?
- What does the SDK promise contract authors across releases?

Workstreams 26–28 all add external consumers of these formats. Without a
policy, every consumer bakes in accidental assumptions that become expensive
to fix.

## Summary

Define a small, explicit versioning and compatibility policy:

| Layer | Version rule | Stability promise |
|---|---|---|
| Portable IR | `portable-ir-v{major}.{minor}` | New constructor = minor; changed semantics = major + migration note |
| Coverage manifests | Same major.minor as IR | New constructor required by tests = manifest minor bump |
| Artifact JSON (`proof-forge-artifact.json`) | `schemaVersion` integer | Consumers must tolerate unknown fields; field removal/renaming = schema bump |
| Deploy JSON (`proof-forge-deploy.json`) | `schemaVersion` integer | Same as artifact JSON |
| Capability ids | Append-only registry | Meaning changes require a new id; old ids stay documented |
| SDK / CLI | Semver-ish `0.x` until 1.0 | Breaking CLI flags and SDK APIs require minor bump pre-1.0, major bump post-1.0 |

This RFC does not invent a new package manager. It records the rules that
existing version strings already imply.

## Portable IR Versioning

The IR version string follows `portable-ir-v{major}.{minor}`.

- **Minor bump:** a new constructor, new type, or new capability is added
  without changing existing semantics. Existing modules compile unchanged.
- **Major bump:** an existing constructor changes meaning, an existing
  capability is split/merged, or a previously valid module becomes invalid.
  Every major bump includes a migration note in `docs/rfcs/` or
  `docs/decisions.md`.
- **Patch:** not used for the IR itself; implementation fixes update the SDK
  version, not the IR version.

The IR version appears in:

- `ProofForge.Backend.*.irVersion` constants (today all `portable-ir-v0`).
- Artifact metadata (`irVersion` field).
- Testkit scenario artifacts.

## Coverage Manifest Versioning

Coverage manifests (the lists of IR constructors each backend promises to
support) are versioned together with the IR:

- New constructor that at least one backend must implement = manifest minor
  bump for that backend.
- Removed or redefined constructor = manifest major bump.
- A backend may lag the IR minor version, but it must never claim a higher
  minor version than the IR it targets.

## Artifact and Deploy JSON Schemas

Both schemas carry an integer `schemaVersion` field (currently `1`).

- **Field addition:** allowed without bump; consumers must ignore unknown
  fields (tolerant reader).
- **Field removal or semantic change:** requires `schemaVersion` bump and a
  migration note.
- **Field rename:** treat as removal + addition; requires bump.

External consumers (explorers, cloud platform) should validate the schema
version they understand and ignore fields they do not.

## Capability Id Stability

Capability ids in `docs/capability-registry.md` are append-only.

- A new capability gets a new id.
- If the meaning of an existing id drifts, the old id is deprecated and a new
  id is added. Backends continue to recognize the deprecated id for at least
  one SDK minor release.
- Renaming an id is a deprecation + new id.

## SDK and CLI Compatibility

Until `1.0.0`:

- Patch releases (`0.x.y`) fix bugs only; no breaking changes.
- Minor releases (`0.x.0`) may change CLI flags, SDK APIs, and default
  behaviors. RFC 0009's legacy-flag aliases are an example of a minor-release
  transition.

After `1.0.0`:

- Major releases break CLI/SDK.
- Minor releases add features.
- Patch releases fix bugs.

## Acceptance Criteria

- All `irVersion` constants and `schemaVersion` fields reference this policy.
- `capability-registry.md` states the append-only rule.
- A compatibility note is added to `README.md` and `docs/INDEX.md`.
- The next IR constructor added follows the minor-bump rule.

## Milestones

1. **M1:** Document the policy in this RFC and record D-042. ✅
2. **M2:** Align all emitters to the same `irVersion` string and
   `schemaVersion` integer. ✅ constants + `just versioning-policy` /
   `Tests/VersioningPolicy.lean` freeze current values (U6.1).
3. **M3:** Add a CI check that warns when a PR changes IR constructors
   without updating `irVersion` or coverage manifests. (open)
4. **M4:** Apply the policy to the first IR change after acceptance. (open)

## Non-goals

- This RFC does not define a package registry or dependency solver.
- It does not version Lean toolchain compatibility; that stays in
  `lean-toolchain`.
- It does not version individual backend toolchains (`solc`, `sbpf-linker`,
  `wat2wasm`); their versions remain in artifact metadata.

## Related

- [RFC 0002](0002-target-implementation-design.md): artifact metadata schema.
- [RFC 0009](0009-cli-product-surface.md): CLI surface whose flags are
  covered by the SDK compatibility rule.
- [RFC 0010](0010-resource-budgets-as-gates.md): budget baselines that become
  stable schema fields.
- [Workstream 30](../implementation-backlog.md#workstreams-2933-platform-hardening-planning-first): versioning and compatibility policy.
