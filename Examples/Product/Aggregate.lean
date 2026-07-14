/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Product-level aggregate ABI probe for backends that advertise dynamic data.
The source stays renderer-neutral; target validation decides which aggregate
shapes are supported.
-/
import ProofForge.Contract.Source.Legacy

namespace Examples.Product.Aggregate

open ProofForge.Contract.Source.Legacy

contract_source Aggregate do
  query echo_bytes (value : .bytes) returns(.bytes) do
    return value;

  query echo_string (value : .string) returns(.string) do
    return value;

  query echo_fixed (value : .fixedArray .u64 2) returns(.fixedArray .u64 2) do
    return value;

end Examples.Product.Aggregate
