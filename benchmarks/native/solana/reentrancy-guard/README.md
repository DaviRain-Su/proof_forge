# Native Solana ReentrancyGuard reference

This Pinocchio program is an independent CMP-3f oracle. It owns one writable
8-byte state account and implements `locked`, `acquire`, and `release` through
instruction tags 0, 1, and 2. It imports no ProofForge compiler or IR module.
