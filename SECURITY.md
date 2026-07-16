# Security Policy

## Supported versions

ProofForge V2 is **pre-release alpha**. There is no stable supported release line yet.
Security fixes land on `main` when practical.

## Reporting a vulnerability

Please **do not** open a public issue for security-sensitive reports.

- Preferred: email the repository maintainer via the address on their
  [GitHub profile](https://github.com/DaviRain-Su), with subject
  `ProofForge security`.
- If GitHub private vulnerability reporting is enabled for this repository,
  use **Security → Report a vulnerability**.

Include:

1. Description and impact
2. Reproduction steps or PoC (non-destructive preferred)
3. Affected commit SHA or release tag
4. Whether the issue is in the compiler, docs, CI, or archived `active/` tree

We will acknowledge receipt when possible and coordinate disclosure after a fix
or mitigation is available.

## Scope notes

- The compiler intentionally treats external packagers, chain RPCs, provers, and
  network endpoints as **untrusted**. Build must not perform implicit network or
  key-material side effects.
- Archived code under `active/` is not a supported product surface.
- Do not submit exploit payloads against third-party systems; local defensive
  reproduction against fixtures is preferred.
