import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- Stateless System transfer through the ordinary product profile
-- solana-sbpf-cpi-elf-v1. The generated outer ABI has one dense handler
-- (handlerId = 0), exact data handlerId u64 LE + lamports u64 LE (16 bytes),
-- and ordered roles payer (writable signer), recipient (writable), then the
-- native System program (readonly). This builds through proof-forge.output.v1.
program TransferSol where
  requires extension solana.cpi.accounts version "1.0.0"
    digest "sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020"

  entry transfer(
      payer : Principal,
      recipient : Principal,
      lamports : UInt64
  ) : UInt64 do
    call solana.system.transfer(payer, recipient, lamports)
    return lamports

end Examples
