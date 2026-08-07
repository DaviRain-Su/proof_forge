#!/usr/bin/env python3
"""Independent PA98 declaration-record wire oracle (no Lean/ProofForge)."""
import sys, unicodedata
WIDTHS = (8, 16, 32, 64, 128, 256)
QID_ERR = "source qualified id must contain 2..256 components"
W_ERR = "integer width must be one of 8,16,32,64,128,256"
LEN_ERR = "{k} length must be 0..4096"
VER_ERR = "extension version must use canonical exact SemVer"
DIG_ERR = "extension digest must use canonical sha256 spelling"
def u16le(v): return bytes((v & 255, (v >> 8) & 255))
def u32le(v): return bytes((v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255))
def enc_str(s):
    if unicodedata.normalize("NFC", s) != s: raise ValueError("non-NFC")
    r = s.encode("utf-8"); return u32le(len(r)) + r
def enc_ident(s):
    if unicodedata.normalize("NFC", s) != s: raise ValueError("non-NFC")
    r = s.encode("utf-8")
    if not 1 <= len(r) <= 240: raise ValueError("raw length")
    if "»" in s: raise ValueError("closing guillemet")
    if any(ord(c) <= 0x1F or 0x7F <= ord(c) <= 0x9F for c in s): raise ValueError("Cc")
    return enc_str(s)
def enc_tag(tag, fs):
    if not tag or any(ord(c) > 127 for c in tag): raise ValueError("tag")
    tb = tag.encode("ascii")
    return u32le(len(tb)) + tb + u16le(len(fs)) + b"".join(fs)
def enc_arr(xs): return u32le(len(xs)) + b"".join(xs)
def null(t): return enc_tag(t, [])
def vis(v): return null(f"Visibility.{v}")
def t_uint(w):
    if w not in WIDTHS: raise ValueError(W_ERR)
    return enc_tag("Type.UInt", [u16le(w)])
def t_bytes(n):
    if not 0 <= n <= 4096: raise ValueError(LEN_ERR.format(k="bytes"))
    return enc_tag("Type.Bytes", [u32le(n)])
def t_array(el, n):
    if not 0 <= n <= 4096: raise ValueError(LEN_ERR.format(k="array"))
    return enc_tag("Type.Array", [el, u32le(n)])
def t_option(el): return enc_tag("Type.Option", [el])
def t_map(k, v): return enc_tag("Type.Map", [k, v])
def enc_param(v, n, t): return enc_tag("Param", [vis(v), enc_ident(n), t])
def enc_field(n, t): return enc_tag("FieldDecl", [enc_ident(n), t])
def enc_variant(n, tys): return enc_tag("EnumVariant", [enc_ident(n), enc_arr(tys)])
def enc_qid(ps):
    if not 2 <= len(ps) <= 256: raise ValueError(QID_ERR)
    return enc_arr([enc_ident(p) for p in ps])
def semver(s):
    core, _, rest = s.partition("-")
    nums = core.split(".")
    if len(nums) != 3 or any(not n.isdigit() or (len(n) > 1 and n[0] == "0") for n in nums):
        raise ValueError(VER_ERR)
    if rest:
        pre, _, build = rest.partition("+")
        if not pre: raise ValueError(VER_ERR)
        idents = pre.split(".") + (build.split(".") if build else [])
        for i in idents:
            if not i or not all(c.isalnum() or c == "-" for c in i): raise ValueError(VER_ERR)
        for i in pre.split("."):
            if i.isdigit() and len(i) > 1 and i[0] == "0": raise ValueError(VER_ERR)
def digest(s):
    if not (s.startswith("sha256:") and len(s) == 71
            and all(c in "0123456789abcdef" for c in s[7:])):
        raise ValueError(DIG_ERR)
def enc_state(v, n, t): return enc_tag("StateDecl", [vis(v), enc_ident(n), t])
def enc_struct(n, fs):
    if not fs: raise ValueError("struct fields must be nonempty")
    return enc_tag("StructDecl", [enc_ident(n), enc_arr(fs)])
def enc_enum(n, vs):
    if not vs: raise ValueError("enum variants must be nonempty")
    return enc_tag("EnumDecl", [enc_ident(n), enc_arr(vs)])
def enc_event(n, ps): return enc_tag("EventDecl", [enc_ident(n), enc_arr(ps)])
def enc_error(n, ps): return enc_tag("ErrorDecl", [enc_ident(n), enc_arr(ps)])
def enc_ext(i, v, d):
    iB = enc_qid(i); semver(v); digest(d)
    return enc_tag("ExtensionReq", [iB, enc_str(v), enc_str(d)])
def enc_kind(k):
    if k not in ("Holds", "Preserving"): raise ValueError("proof kind must be Holds or Preserving")
    return null(f"ProofKind.{k}")
def enc_proof(inv, kind, th): return enc_tag("ProofDecl", [enc_ident(inv), enc_kind(kind), enc_qid(th)])
VP = {"Public": "110000005669736962696c6974792e5075626c69630000",
      "Private": "120000005669736962696c6974792e507269766174650000",
      "Commitment": "150000005669736962696c6974792e436f6d6d69746d656e740000"}
PK_H = "0f00000050726f6f664b696e642e486f6c64730000"
PK_P = "1400000050726f6f664b696e642e50726573657276696e670000"
TB, TU64, TU256 = ("09000000547970652e426f6f6c0000", "09000000547970652e55496e7401004000",
                   "09000000547970652e55496e7401000001")
TP = "0e000000547970652e5072696e636970616c0000"
TB0 = "0a000000547970652e4279746573010000000000"
TAOB = ("0a000000547970652e417272617902000b000000547970652e4f7074696f6e0100"
        "0a000000547970652e427974657301000000000000000000")
FD_C = "090000004669656c644465636c020005000000636f756e74" + TU256
FD_I = ("090000004669656c644465636c0200050000006974656d7308000000547970652e4d61700200"
        "09000000547970652e426f6f6c000009000000547970652e556e69740000")
V_N = "0b000000456e756d56617269616e740200040000004e6f6e6500000000"
V_S = "0b000000456e756d56617269616e74020004000000536f6d6502000000" + TB + TP
P_F = "05000000506172616d0300" + VP["Public"] + "0400000066726f6d" + TP
P_A = "05000000506172616d0300" + VP["Private"] + "06000000616d6f756e74" + TU64
P_N = "05000000506172616d0300" + VP["Commitment"] + "040000006e6f7465" + TB0
P_R = "05000000506172616d0300" + VP["Public"] + "06000000726561736f6e" + TB
Q_FE = "020000000400000044656d6f0700000046656174757265"
Q_AD = "020000000400000044656d6f08000000416476616e636564"
Q_PS = "020000000600000050726f6f66730400000073616665"
G = {
"state_enabled": ("0900000053746174654465636c0300" + VP["Public"] + "07000000656e61626c6564" + TB,
    lambda: enc_state("Public", "enabled", null("Type.Bool"))),
"state_count": ("0900000053746174654465636c0300" + VP["Private"] + "05000000636f756e74" + TU64,
    lambda: enc_state("Private", "count", t_uint(64))),
"state_secret": ("0900000053746174654465636c0300" + VP["Commitment"] + "06000000736563726574" + TAOB,
    lambda: enc_state("Commitment", "secret", t_array(t_option(t_bytes(0)), 0))),
"struct_store": ("0a0000005374727563744465636c02000500000053746f726502000000" + FD_C + FD_I,
    lambda: enc_struct("Store", [enc_field("count", t_uint(256)),
        enc_field("items", t_map(null("Type.Bool"), null("Type.Unit")))])),
"struct_store_single": ("0a0000005374727563744465636c02000500000053746f726501000000" + FD_C,
    lambda: enc_struct("Store", [enc_field("count", t_uint(256))])),
"struct_store_reversed": ("0a0000005374727563744465636c02000500000053746f726502000000" + FD_I + FD_C,
    lambda: enc_struct("Store", [enc_field("items", t_map(null("Type.Bool"), null("Type.Unit"))),
        enc_field("count", t_uint(256))])),
"enum_choice": ("08000000456e756d4465636c02000600000043686f69636502000000" + V_N + V_S,
    lambda: enc_enum("Choice", [enc_variant("None", []),
        enc_variant("Some", [null("Type.Bool"), null("Type.Principal")])])),
"event_ping": ("090000004576656e744465636c02000400000050696e6700000000",
    lambda: enc_event("Ping", [])),
"event_transfer": ("090000004576656e744465636c0200080000005472616e7366657203000000" + P_F + P_A + P_N,
    lambda: enc_event("Transfer", [enc_param("Public", "from", null("Type.Principal")),
        enc_param("Private", "amount", t_uint(64)), enc_param("Commitment", "note", t_bytes(0))])),
"error_empty": ("090000004572726f724465636c020005000000456d70747900000000",
    lambda: enc_error("Empty", [])),
"error_denied": ("090000004572726f724465636c02000600000044656e69656401000000" + P_R,
    lambda: enc_error("Denied", [enc_param("Public", "reason", null("Type.Bool"))])),
"ext_feature": ("0c000000457874656e73696f6e5265710300" + Q_FE + "05000000312e302e30"
    + "470000007368613235363a" + "30" * 64,
    lambda: enc_ext(["Demo", "Feature"], "1.0.0", "sha256:" + "0" * 64)),
"ext_advanced": ("0c000000457874656e73696f6e5265710300" + Q_AD + "15000000312e322e332d616c7068612e312b6275696c642e35"
    + "470000007368613235363a" + "6162" * 32,
    lambda: enc_ext(["Demo", "Advanced"], "1.2.3-alpha.1+build.5", "sha256:" + "ab" * 32)),
"proof_safe": ("0900000050726f6f664465636c03000400000073616665" + PK_H + Q_PS,
    lambda: enc_proof("safe", "Holds", ["Proofs", "safe"])),
"proof_safe_preserving": ("0900000050726f6f664465636c03000400000073616665" + PK_P + Q_PS,
    lambda: enc_proof("safe", "Preserving", ["Proofs", "safe"])),
}
def _fail(name, want, fn):
    try: fn(); raise SystemExit(f"{name}: unexpectedly ok")
    except ValueError as e:
        if want is not None and str(e) != want: raise SystemExit(f"{name}: {e}")
def self_check():
    for k, (want, fn) in G.items():
        got = fn().hex()
        if got != want: raise SystemExit(f"{k}: got {got}")
    if G["struct_store"][0] == G["struct_store_reversed"][0]:
        raise SystemExit("struct normal==reversed")
    _fail("struct_empty", "struct fields must be nonempty", lambda: enc_struct("Store", []))
    _fail("enum_empty", "enum variants must be nonempty", lambda: enc_enum("Choice", []))
    _fail("state_w24", W_ERR, lambda: enc_state("Public", "count", t_uint(24)))
    _fail("struct_w24", W_ERR, lambda: enc_struct("Store", [enc_field("count", t_uint(24))]))
    _fail("ext_qid1", QID_ERR, lambda: enc_ext(["Only"], "1.0.0", "sha256:" + "0" * 64))
    _fail("qid_first", QID_ERR, lambda: enc_ext(["Only"], "not-a-semver", "bad"))
    _fail("version_first", VER_ERR, lambda: enc_ext(["Demo", "Feature"], "01.0.0", "bad"))
    _fail("bad_digest", DIG_ERR, lambda: enc_ext(["Demo", "Feature"], "1.0.0", "sha256:ZZ"))
    _fail("proof_qid1", QID_ERR, lambda: enc_proof("safe", "Holds", ["Only"]))
    _fail("proof_kind_bad", "proof kind must be Holds or Preserving",
          lambda: enc_proof("safe", "Bogus", ["Proofs", "safe"]))
    if G["proof_safe"][0] == G["proof_safe_preserving"][0]:
        raise SystemExit("proof kind Holds==Preserving")
    _fail("raw_close", "closing guillemet", lambda: enc_state("Public", "»", null("Type.Bool")))
    _fail("raw_cc", "Cc", lambda: enc_field("a\x00", null("Type.Bool")))
    print("reference_source_ast_decl_v1: ok", len(G))
if __name__ == "__main__":
    if "--self-check" in sys.argv: self_check()
    else: print("usage: reference_source_ast_decl_v1.py --self-check")
