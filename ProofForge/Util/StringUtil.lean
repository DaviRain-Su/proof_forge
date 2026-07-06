/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Low-level string utilities shared across the CLI, Contract, and Backend layers.
This module has no dependencies on higher ProofForge layers so any module may
import it without introducing a layering cycle. It exists to eliminate the
`trimAsciiString` and `stripHexPrefix` duplicates that were previously copied
into `Cli.lean`, `Cli/Check.lean`, `Cli/Deploy.lean`, `Contract/SdkSchema.lean`,
and several `Backend/Evm/*` modules.
-/

namespace ProofForge.Util.StringUtil

def trimAscii (s : String) : String :=
  s.trimAscii.toString

def stripHexPrefix (s : String) : String :=
  if s.startsWith "0x" || s.startsWith "0X" then (s.drop 2).toString else s

end ProofForge.Util.StringUtil