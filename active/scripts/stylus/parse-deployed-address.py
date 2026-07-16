#!/usr/bin/env python3
import re
import sys


text = open(sys.argv[1], encoding="utf-8").read() if len(sys.argv) > 1 else sys.stdin.read()
text = re.sub(r"\x1b\[[0-9;]*m", "", text)
matches = re.findall(
    r"deployed code at address:\s*(0x[0-9a-fA-F]{40})", text, re.IGNORECASE
)
print(matches[-1] if matches else "")
