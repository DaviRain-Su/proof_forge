# ProofShip Cloud · C0 spike — gate-in-container feasibility
# Question: can the real product gate (check → build --target evm → inspect)
# run in a minimal Linux container, and what does it cost (image size, cold
# start, per-gate duration)? Data goes back to docs/plan/proofship-cloud.md §3.3.
#
# Build context: monorepo root.   docker build -f proofship/cloud-spike/Dockerfile .
# Run:    docker run --rm proofship-gate-c0 check …   (see README.md)

FROM debian:bookworm-slim AS toolchain
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl ca-certificates git xz-utils zstd \
      build-essential pkg-config \
 && rm -rf /var/lib/apt/lists/*

# Lean via elan, pinned by lean-toolchain (v4.31.0)
RUN curl -sSfL https://elan.lean-lang.org/elan-init.sh | sh -s -- -y --default-toolchain none
ENV PATH="/root/.elan/bin:${PATH}"

WORKDIR /src
COPY lean-toolchain lakefile.lean lake-manifest.json ./
# Tool lock manifests are compile-time inputs (include_str in Core/ToolLockV4.lean)
COPY toolchains.lock.json toolchains-linux-x86_64.lock.json host-profiles.lock.json ./
COPY ProofForgeV2.lean ./
COPY ProofForgeV2 ./ProofForgeV2

# Product library + CLI only (no Tests)
RUN lake build ProofForgeV2 proof_forge_next

# Locked EVM tools (solc) per toolchains lock — needed for `build --target evm`
COPY scripts ./scripts
RUN PROOF_FORGE_ROOT=/src ./.lake/build/bin/proof-forge-next install --targets evm --yes

# Spike fixture: the ProofShip golden contract
COPY proofship/rwa-share-v1/src/RwaShareRegistry.lean /spike/RwaShareRegistry.lean

WORKDIR /spike
ENV PROOF_FORGE_ROOT=/src
ENTRYPOINT ["/src/.lake/build/bin/proof-forge-next"]
CMD ["version"]
