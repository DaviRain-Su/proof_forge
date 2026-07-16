/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Portable GuestBook (message board) for NEAR compare.

Classic NEAR guestbook stores free-form strings. Until EmitWat supports
dynamic string storage, this surface records **U64 message codes** with a
monotonic index and total count — same control flow as a guestbook
(append + length + read-by-index).

  lake env proof-forge build --target wasm-near --root . \
    -o build/guestbook Examples/Product/GuestBook.lean

NEAR compare: `just near-compare-guestbook` / `-live`
-/
import ProofForge.Contract.Source

namespace Examples.Product.GuestBook

open ProofForge.Contract.Source

contract_source GuestBook do
  state messageCount : .u64

  mapping messages from .u64 to .u64
  mapping authors from .u64 to .u64

  event MessagePosted

  entry init do
    messageCount := u64 0;

  entry add_message (code : .u64) do
    let idx : .u64 := messageCount;
    let who : .u64 := caller;
    do mapWrite messages idx code;
    do mapWrite authors idx who;
    messageCount := idx +! u64 1;
    emit MessagePosted indexed #[fieldAsName "index" idx, fieldAsName "author" who]
      data #[fieldAsName "code" code];

  query get_message (index : .u64) returns(.u64) do
    return mapRead messages index;

  query get_author (index : .u64) returns(.u64) do
    return mapRead authors index;

  query total_messages returns(.u64) do
    return messageCount;

end Examples.Product.GuestBook
