# Native Solana StatusMessage reference

This Pinocchio program is an independent CMP-3h oracle. Instructions zero
through two implement `init`, `set_status`, and `get_status`. Account zero is
the caller authority and account one owns the fixed-capacity state map. The
caller handle is the little-endian first word of SHA-256 over the full authority
public key, matching the documented portable Solana identity projection.
