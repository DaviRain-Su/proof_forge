#!/usr/bin/python3
"""Independent, test-only primitives for future TASK-D0-10 RED fixtures.

This module is deliberately standalone and non-authoritative.  It uses only the
Python standard library and does not import any production ProofForge parser.
Running it directly performs deterministic known-answer and mutation checks.
"""

from __future__ import annotations

import hashlib
import base64
import json
import re
import unicodedata
import zlib
from dataclasses import dataclass
from typing import Any


class Rejected(ValueError):
    pass


def reject(message: str) -> None:
    raise Rejected(message)


SAFE_INTEGER = 2**53 - 1
MAX_JSON_DEPTH = 64
MAX_JSON_NODES = 100_000
MAX_PROTOCOL_JSON_BYTES = 4 * 1024 * 1024
MAX_ARCHIVE_BYTES = 64 * 1024 * 1024
MAX_ARCHIVE_PATHS = 100_000
SAFE_ID = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9._:+-]{0,254}[A-Za-z0-9])?")
SCHEMA = re.compile(r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*(?:\.[a-z][a-z0-9]*(?:-[a-z0-9]+)*)+")
PROFILE_ID = re.compile(r"[a-z][a-z0-9]*(?:[-.][a-z0-9]+)*")
SEMVER = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-(?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?")
HEX40 = re.compile(r"[0-9a-f]{40}")
HEX64 = re.compile(r"[0-9a-f]{64}")
REVIEW_PIN = "f0" * 20
RFC8032_VECTOR4_MESSAGE = zlib.decompress(base64.b85decode(
    b"c-jH~0|5L8xU#o1LPA4!59B7KwMhtLArPi)FJ+PHy)#AQ<m;IFZYE3cp8gW<Q26yupLen2RrbXNMB+cOLp|SfzJ%C$-h2Q?+)0+%=X3PDp8i)jf|}bV$Qw7wIvXboATph0hIRaIr8MAy3Pdu3YxRtj9{Xk0dNYf?E+%9TiT}JBg^v8VRSx5&;hBrkcj-EFW5Y!LYZ;#9&@O`2BE<f>6-6(AD2jp_SCJO%ZLKRiF%78$KpLhY0IOXZHdQ_bAUiXO49U1M_n!C#V9dFroabkje%2_)tyes;7TfRd*HoF>mc3}Gse6)&i@Xp!W+D9EE9{{o9UyDw&7Q}v_V&q7&2j|oG*!logY={wq^~P<?_5*y*sO59%YM;?&VjvzHJwByO_gGvm{qAtd>L5L_^qYTQ!d!0sz0*Pd#4VzB#v258X}jhyR)58FB*()w(-s)v)&pXK+GgnK^dqqsjAiooUMpLUFN;vsTh8{V3N;gzbg~{W%6){*Nc9LJcn7*#P!Bn+jUciiq&=b`q+5r3Jja3JIl-`GUk+pyUEE5`_?3Z*$A8L&w$V3-xi|JWxbN!S$hWu;E{Uti@SCH)DzM;^;KGWR-J&uK}wAXS=?o$VJNz?diZ*AF;6j!cq=38{(y^uu+Anx9WEm9O@q-TUBw#R)3;hH8sK<E1m9FT_?DaF>TrVpf60i96iuS9SVEr3U@_au)7sgu4a=&pCXBfJ|LWOKJba{;;8v-$dd;^{`*Y@I#>Q2x=qYlS(0b9jUPJM`qay)j6FK531k8*=^^7pUO0U}kjoJuD-I$Hdrt`niTuV$vB>+mGZtwWYVR$;M>{t6eACj>CFVU!9XCzU3W#$yEXb9H!?lj-`F%R5=uD{s?upS-7ODQJ_OD(pIZ;(4^KpNh^T7C%EkM!?dV`VyJ1PuAV)U2nNN_5k4MVM!R{0kPWMHWfkVTh;O-x(idwftTxw0l?g_a|)B8NqrysNuOeu1VyGth#HKRuHvF0SU;ldw}7$w@}~5S&dy#5&bR9Rsf?e^|dM<%z_Ruilahu8mtLJzh;KEOC@<XWdzK`li7Z1?LV;j&2gkX)R*ud7r^4nH<zj^FC}JH7LII5YW!chGDh~X5o4I6M)9UW^RPkbiT9CDkjyN9|224a<p#A4GfSs@B3r`;x>Ipd^YLL0POs&a_SxAD5&Ee!p<eMel}3h&e>z2}XK2(9+0Zl+z>&r=T=f0t%V=O}H#iNl>Z)*iOhJXiF5S)325??Y!T-o|?(RogWZ$fYtE3zT7??kYLB;QA)1d+Aqqxe(43JzE{E-Mixl90{xzH?c4$S"
))


def exact_keys(value: Any, fields: tuple[str, ...], where: str) -> dict[str, Any]:
    if type(value) is not dict or len(value) != len(fields) or set(value) != set(fields):
        reject(f"{where} closed fields mismatch")
    return value


def _validate_json(value: Any, active: set[int] | None = None, depth: int = 1,
                   budget: list[int] | None = None) -> None:
    if active is None:
        active = set()
    if budget is None:
        budget = [MAX_JSON_NODES]
    budget[0] -= 1
    if budget[0] < 0 or depth > MAX_JSON_DEPTH:
        reject("PF-JCS resource bound")
    if value is None or type(value) is bool:
        return
    if type(value) is int:
        if not -SAFE_INTEGER <= value <= SAFE_INTEGER:
            reject("integer outside PF-JCS safe range")
        return
    if type(value) is str:
        if ("\x00" in value or any(ord(c) < 32 or 0x7f <= ord(c) <= 0x9f for c in value)
                or any(0xD800 <= ord(c) <= 0xDFFF for c in value)
                or len(value.encode("utf-8")) > 4096):
            reject("string outside PF-JCS profile")
        return
    if type(value) not in (list, dict):
        reject("value outside integer-only JSON model")
    marker = id(value)
    if marker in active:
        reject("cyclic JSON value")
    active.add(marker)
    if type(value) is list:
        if len(value) > 4096:
            reject("array too large")
        for item in value:
            _validate_json(item, active, depth + 1, budget)
    else:
        for key, item in value.items():
            if type(key) is not str or not key or len(key.encode("ascii", "ignore")) != len(key) or len(key.encode("ascii", "ignore")) > 256 or not all(0x21 <= ord(c) <= 0x7e for c in key):
                reject("object key must be nonempty ASCII graphic")
            _validate_json(item, active, depth + 1, budget)
    active.remove(marker)


def canonical_pf_jcs(value: Any) -> bytes:
    try:
        _validate_json(value)
        encoded = json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":"), sort_keys=True).encode()
        if not 1 <= len(encoded) <= MAX_PROTOCOL_JSON_BYTES:
            reject("PF-JCS root byte bound")
        return encoded
    except RecursionError as error:
        raise Rejected("PF-JCS recursion") from error


def decode_canonical_pf_jcs(data: bytes) -> Any:
    if (type(data) is not bytes or not 1 <= len(data) <= MAX_PROTOCOL_JSON_BYTES
            or data.startswith(b"\xef\xbb\xbf") or b"\x00" in data):
        reject("invalid PF-JCS bytes")
    def pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in items:
            if key in result:
                reject("duplicate JSON key")
            result[key] = value
        return result
    def integer(text: str) -> int:
        value = int(text)
        if not -SAFE_INTEGER <= value <= SAFE_INTEGER:
            reject("integer outside PF-JCS safe range")
        return value
    def number(_: str) -> Any:
        reject("non-integer number")
    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=pairs,
                           parse_int=integer, parse_float=number, parse_constant=number)
    except Rejected:
        raise
    except (UnicodeError, json.JSONDecodeError, ValueError, RecursionError) as error:
        raise Rejected("invalid PF-JCS JSON") from error
    _validate_json(value)
    if canonical_pf_jcs(value) != data:
        reject("noncanonical PF-JCS")
    return value


@dataclass(frozen=True)
class Digest:
    raw: bytes

    def __post_init__(self) -> None:
        if type(self.raw) is not bytes or len(self.raw) != 32:
            reject("Digest requires exactly 32 bytes")

    @classmethod
    def parse(cls, value: Any) -> "Digest":
        if type(value) is not str or not value.startswith("sha256:") or HEX64.fullmatch(value[7:]) is None:
            reject("invalid Digest wire")
        return cls(bytes.fromhex(value[7:]))

    def wire(self) -> str:
        return "sha256:" + self.raw.hex()


def domain_digest(domain: str, value: Any) -> Digest:
    try:
        prefix = domain.encode("ascii")
    except UnicodeError as error:
        raise Rejected("digest domain must be ASCII") from error
    if not domain or "\x00" in domain:
        reject("invalid digest domain")
    return Digest(hashlib.sha256(prefix + b"\x00" + canonical_pf_jcs(value)).digest())


def _ascii_domain(domain: str) -> bytes:
    try: raw = domain.encode("ascii")
    except (AttributeError, UnicodeError) as error: raise Rejected("domain must be ASCII") from error
    if not raw or b"\x00" in raw: reject("invalid domain")
    return raw


@dataclass(frozen=True)
class ContentRef:
    schema: str
    id: str
    version: str
    digest: Digest

    def __post_init__(self) -> None:
        if SCHEMA.fullmatch(self.schema) is None or len(self.schema) > 127:
            reject("invalid ContentRef schema")
        if PROFILE_ID.fullmatch(self.id) is None or len(self.id) > 127:
            reject("invalid ContentRef id")
        if (SEMVER.fullmatch(self.version) is None
                or any(int(part) > 2**64 - 1 for part in self.version.split("-", 1)[0].split("+", 1)[0].split("."))):
            reject("invalid ContentRef version")
        if type(self.digest) is not Digest:
            reject("invalid ContentRef digest")

    def wire(self) -> dict[str, Any]:
        return {"schema": self.schema, "id": self.id, "version": self.version, "digest": self.digest.wire()}

    @classmethod
    def parse(cls, value: Any) -> "ContentRef":
        obj = exact_keys(value, ("schema", "id", "version", "digest"), "ContentRef")
        if not all(type(obj[k]) is str for k in ("schema", "id", "version")):
            reject("ContentRef text field type")
        return cls(obj["schema"], obj["id"], obj["version"], Digest.parse(obj["digest"]))


def content_ref_for(value: dict[str, Any], domain: str) -> ContentRef:
    exact_keys(value, tuple(value), "content")
    return ContentRef(value["schema"], value["id"], value["version"], domain_digest(domain, value))


# RFC 8032 pure Ed25519.  Test signing is deterministic but not constant-time.
P = 2**255 - 19
L = 2**252 + 27742317777372353535851937790883648493
D = 37095705934669439343138083508754565189542113879843219016388785533085940283555
I = 19681161376707505956807079304988542015446066515923890162744021073123829784752
BX = 15112221349535400772501151409588531511454012693041857206046113283949847762202
BY = 46316835694926478169428394003475163141307993866256225615783033603165251855960
IDENTITY = (0, 1, 1, 0)
BASE = (BX, BY, 1, BX * BY % P)


def point_add(a: tuple[int, ...], b: tuple[int, ...]) -> tuple[int, ...]:
    x1, y1, z1, t1 = a; x2, y2, z2, t2 = b
    aa = (y1 - x1) * (y2 - x2) % P; bb = (y1 + x1) * (y2 + x2) % P
    cc = 2 * D * t1 * t2 % P; dd = 2 * z1 * z2 % P
    return ((bb-aa)*(dd-cc)%P, (dd+cc)*(bb+aa)%P, (dd-cc)*(dd+cc)%P, (bb-aa)*(bb+aa)%P)


def scalar_mul(n: int, point: tuple[int, ...]) -> tuple[int, ...]:
    result, addend = IDENTITY, point
    while n:
        if n & 1: result = point_add(result, addend)
        addend = point_add(addend, addend); n >>= 1
    return result


def point_equal(a: tuple[int, ...], b: tuple[int, ...]) -> bool:
    return (a[0]*b[2]-b[0]*a[2]) % P == 0 and (a[1]*b[2]-b[1]*a[2]) % P == 0


def encode_point(p: tuple[int, ...]) -> bytes:
    inv = pow(p[2], P-2, P); x, y = p[0]*inv % P, p[1]*inv % P
    result = bytearray(y.to_bytes(32, "little")); result[31] |= (x & 1) << 7
    return bytes(result)


def decode_point(data: bytes) -> tuple[int, ...] | None:
    if type(data) is not bytes or len(data) != 32: return None
    n = int.from_bytes(data, "little"); sign, y = n >> 255, n & (2**255-1)
    if y >= P: return None
    y2 = y*y % P; x2 = (y2-1) * pow(D*y2+1, P-2, P) % P
    x = pow(x2, (P+3)//8, P)
    if x*x % P != x2: x = x * I % P
    if x*x % P != x2 or (x == 0 and sign): return None
    if x & 1 != sign: x = P-x
    point = (x, y, 1, x*y % P)
    if encode_point(point) != data or point_equal(point, IDENTITY): return None
    if point_equal(scalar_mul(8, point), IDENTITY) or not point_equal(scalar_mul(L, point), IDENTITY): return None
    return point


def ed25519_public(seed: bytes) -> bytes:
    if type(seed) is not bytes or len(seed) != 32: reject("Ed25519 seed length")
    h = bytearray(hashlib.sha512(seed).digest()); h[0] &= 248; h[31] &= 63; h[31] |= 64
    return encode_point(scalar_mul(int.from_bytes(h[:32], "little"), BASE))


def ed25519_sign(seed: bytes, message: bytes) -> bytes:
    if type(seed) is not bytes or len(seed) != 32: reject("Ed25519 seed length")
    if type(message) is not bytes: reject("Ed25519 message type")
    h = bytearray(hashlib.sha512(seed).digest()); h[0] &= 248; h[31] &= 63; h[31] |= 64
    a = int.from_bytes(h[:32], "little"); public = encode_point(scalar_mul(a, BASE))
    r = int.from_bytes(hashlib.sha512(bytes(h[32:]) + message).digest(), "little") % L
    encoded_r = encode_point(scalar_mul(r, BASE))
    k = int.from_bytes(hashlib.sha512(encoded_r + public + message).digest(), "little") % L
    return encoded_r + ((r + k*a) % L).to_bytes(32, "little")


def ed25519_verify(public: bytes, message: bytes, signature: bytes) -> bool:
    if not (type(public) is type(message) is type(signature) is bytes and len(public) == 32 and len(signature) == 64): return False
    a, r = decode_point(public), decode_point(signature[:32]); s = int.from_bytes(signature[32:], "little")
    if a is None or r is None or s >= L: return False
    k = int.from_bytes(hashlib.sha512(signature[:32] + public + message).digest(), "little") % L
    return point_equal(scalar_mul(s, BASE), point_add(r, scalar_mul(k, a)))


def build_signed_object(statement: dict[str, Any], seeds: dict[str, bytes], statement_domain: str,
                        signature_domain: str, full_domain: str) -> tuple[bytes, Digest, ContentRef]:
    if "signatures" in statement: reject("statement already signed")
    statement_digest = domain_digest(statement_domain, statement)
    message = _ascii_domain(signature_domain) + b"\x00" + statement_digest.raw
    signatures = [{"keyId": key, "algorithm": "ed25519", "signature": ed25519_sign(seed, message).hex()}
                  for key, seed in sorted(seeds.items())]
    signed = dict(statement); signed["signatures"] = signatures
    schema, identifier, version = signed["schema"], signed["id"], signed["version"]
    wire = canonical_pf_jcs(signed)
    return wire, statement_digest, ContentRef(schema, identifier, version, domain_digest(full_domain, signed))


def validate_signed_object(data: bytes, public_keys: dict[str, bytes], fields: tuple[str, ...],
                           statement_domain: str, signature_domain: str,
                           full_domain: str) -> tuple[dict[str, Any], Digest, ContentRef]:
    obj = exact_keys(decode_canonical_pf_jcs(data), fields + ("signatures",), "signed object")
    signatures = obj["signatures"]
    if type(signatures) is not list or not signatures: reject("missing signatures")
    statement = {field: obj[field] for field in fields}
    statement_digest = domain_digest(statement_domain, statement)
    message = _ascii_domain(signature_domain) + b"\x00" + statement_digest.raw
    previous = None
    for item in signatures:
        sig = exact_keys(item, ("keyId", "algorithm", "signature"), "signature")
        key = sig["keyId"]
        if type(key) is not str or previous is not None and key <= previous or key not in public_keys: reject("signature key/order")
        if sig["algorithm"] != "ed25519" or type(sig["signature"]) is not str or re.fullmatch(r"[0-9a-f]{128}", sig["signature"]) is None: reject("signature wire")
        if not ed25519_verify(public_keys[key], message, bytes.fromhex(sig["signature"])): reject("bad signature")
        previous = key
    return obj, statement_digest, ContentRef(
        obj["schema"], obj["id"], obj["version"], domain_digest(full_domain, obj))


def _octal(value: int, width: int) -> bytes:
    text = format(value, "o")
    if len(text) > width - 1: reject("ustar number overflow")
    return text.rjust(width - 1, "0").encode() + b"\x00"


def _parse_octal(field: bytes, width: int) -> int:
    if len(field) != width or re.fullmatch(rb"[0-7]{%d}\x00" % (width - 1), field) is None:
        reject("bad tar octal")
    return int(field[:-1], 8)


def _ustar_name(path: bytes) -> tuple[bytes, bytes]:
    if len(path) <= 100: return path, b""
    choices = [(path[:i], path[i+1:]) for i, byte in enumerate(path) if byte == 47 and i <= 155 and len(path)-i-1 <= 100]
    if not choices: reject("ustar path not representable")
    prefix, name = choices[-1]
    if not name: reject("ustar empty name")
    return name, prefix


def build_ustar(task_id: str, paths: dict[str, tuple[int, bytes]]) -> bytes:
    root = task_id.lower() + "/"; output = bytearray()
    for path in sorted(paths, key=lambda p: p.encode("utf-8")):
        mode, payload = paths[path]; _validate_path(path)
        if mode not in (0o644, 0o755) or type(payload) is not bytes: reject("archive entry")
        name, prefix = _ustar_name((root + path).encode())
        header = bytearray(512); header[:len(name)] = name
        header[100:108] = _octal(mode, 8); header[108:116] = _octal(0, 8); header[116:124] = _octal(0, 8)
        header[124:136] = _octal(len(payload), 12); header[136:148] = _octal(0, 12)
        header[148:156] = b"        "; header[156:157] = b"0"; header[257:263] = b"ustar\x00"; header[263:265] = b"00"
        header[345:345+len(prefix)] = prefix
        header[148:156] = format(sum(header), "06o").encode() + b"\x00 "
        output += header + payload + b"\x00" * (-len(payload) % 512)
    return bytes(output + b"\x00" * 1024)


def _validate_path(path: str) -> None:
    if (type(path) is not str or not path or path.startswith("/") or "\\" in path
            or unicodedata.normalize("NFC", path) != path or len(path.encode()) > 4096
            or any(ord(c) < 32 or 0x7f <= ord(c) <= 0x9f for c in path)
            or any(part in ("", ".", "..") for part in path.split("/"))): reject("invalid archive path")


def parse_ustar(data: bytes, task_id: str) -> dict[str, tuple[int, bytes]]:
    if (type(data) is not bytes or not 1024 <= len(data) <= MAX_ARCHIVE_BYTES
            or len(data) % 512 or not data.endswith(b"\x00" * 1024)):
        reject("ustar framing")
    root = task_id.lower() + "/"; result: dict[str, tuple[int, bytes]] = {}; folded: set[str] = set(); offset = 0
    while data[offset:offset+512] != b"\x00" * 512:
        h = data[offset:offset+512]; offset += 512
        if h[257:265] != b"ustar\x0000" or h[156:157] not in (b"0", b"\x00"): reject("unsupported tar type")
        saved = h[148:156]
        if re.fullmatch(rb"[0-7]{6}\x00 ", saved) is None: reject("bad tar checksum grammar")
        checksum = int(saved[:6], 8); mode = _parse_octal(h[100:108], 8); size = _parse_octal(h[124:136], 12)
        temp = bytearray(h); temp[148:156] = b"        "
        if checksum != sum(temp) or mode not in (0o644, 0o755): reject("tar checksum/mode")
        if any(_parse_octal(h[start:start+width], width) != 0 for start, width in ((108,8),(116,8),(136,12))): reject("tar metadata")
        if any(h[a:b].strip(b"\x00") for a, b in ((157,257),(265,297),(297,329),(329,337),(337,345),(500,512))): reject("tar unused metadata")
        def padded(field: bytes) -> bytes:
            value, nul, padding = field.partition(b"\x00")
            if nul and padding.strip(b"\x00"): reject("tar field padding")
            return value
        name_part, prefix = padded(h[:100]), padded(h[345:500])
        if not name_part: reject("tar empty name")
        name = ((prefix + b"/") if prefix else b"") + name_part
        try: name = name.decode("utf-8")
        except UnicodeError as error: raise Rejected("tar name UTF-8") from error
        if not name.startswith(root): reject("tar root")
        path = name[len(root):]; _validate_path(path)
        key = path.casefold()
        if path in result or key in folded: reject("duplicate/casefold archive path")
        if len(result) >= MAX_ARCHIVE_PATHS: reject("too many archive paths")
        payload = data[offset:offset+size]
        if len(payload) != size: reject("truncated tar")
        padding = data[offset+size:offset+(size+511)//512*512]
        if any(padding): reject("nonzero tar payload padding")
        result[path] = (mode, payload); folded.add(key); offset += (size + 511) // 512 * 512
    if data[offset:] != b"\x00" * (len(data)-offset) or len(data)-offset < 1024: reject("tar trailer")
    if list(result) != sorted(result, key=lambda p: p.encode()): reject("tar path order")
    return result


def git_object(kind: str, payload: bytes) -> tuple[bytes, str]:
    if kind not in ("blob", "tree", "commit") or type(payload) is not bytes: reject("Git object input")
    raw = kind.encode() + b" " + str(len(payload)).encode() + b"\x00" + payload
    return raw, hashlib.sha1(raw).hexdigest()


def parse_git_object(raw: bytes, expected: str | None = None) -> tuple[str, bytes, str]:
    if type(raw) is not bytes: reject("Git object bytes")
    head, sep, payload = raw.partition(b"\x00")
    match = re.fullmatch(rb"(blob|tree|commit) (0|[1-9][0-9]*)", head)
    if not sep or match is None or int(match.group(2)) != len(payload): reject("Git object framing")
    oid = hashlib.sha1(raw).hexdigest()
    if expected is not None and oid != expected: reject("Git object ID mismatch")
    return match.group(1).decode(), payload, oid


def tree_from_map(paths: dict[str, tuple[int, bytes]]) -> tuple[bytes, str]:
    root: dict[str, Any] = {}
    for path, (mode, content) in paths.items():
        _validate_path(path); node = root
        if mode not in (0o644, 0o755) or type(content) is not bytes:
            reject("invalid Git path-map entry")
        parts = path.split("/")
        for part in parts[:-1]:
            existing = node.get(part)
            if existing is not None and type(existing) is not dict: reject("file/directory tree collision")
            node = node.setdefault(part, {})
        if type(node) is not dict: reject("file/directory tree collision")
        if parts[-1] in node: reject("tree collision")
        node[parts[-1]] = (mode, content)
    def emit(node: dict[str, Any]) -> tuple[bytes, str]:
        entries = []
        for name in sorted(node, key=lambda n: n.encode() + (b"/" if type(node[n]) is dict else b"\x00")):
            value = node[name]
            if type(value) is dict: raw, oid = emit(value); mode_text = b"40000"
            else:
                mode, content = value; raw, oid = git_object("blob", content); mode_text = b"100755" if mode == 0o755 else b"100644"
            entries.append(mode_text + b" " + name.encode() + b"\x00" + bytes.fromhex(oid))
        return git_object("tree", b"".join(entries))
    return emit(root)


def parse_tree(raw: bytes) -> list[tuple[str, str, str]]:
    kind, payload, _ = parse_git_object(raw)
    if kind != "tree": reject("not tree")
    result = []; offset = 0; previous = None
    while offset < len(payload):
        space = payload.find(b" ", offset); nul = payload.find(b"\x00", space+1)
        if space < 0 or nul < 0 or nul+21 > len(payload): reject("tree framing")
        mode, name = payload[offset:space], payload[space+1:nul]
        key = name + (b"/" if mode == b"40000" else b"\x00")
        if mode not in (b"100644", b"100755", b"40000") or not name or b"/" in name or previous is not None and key <= previous: reject("tree entry")
        result.append((mode.decode(), name.decode("utf-8"), payload[nul+1:nul+21].hex())); previous = key; offset = nul+21
    return result


def parse_commit(payload: bytes, expected: str | None = None) -> dict[str, Any]:
    if type(payload) is not bytes or b"\n\n" not in payload: reject("commit framing")
    oid = git_object("commit", payload)[1]
    if expected is not None and oid != expected: reject("commit object ID mismatch")
    headers, message = payload.split(b"\n\n", 1); lines = headers.split(b"\n")
    if not lines or not lines[0].startswith(b"tree "):
        reject("commit tree position")
    try: tree = lines[0][5:].decode("ascii")
    except UnicodeError as error: raise Rejected("commit tree encoding") from error
    if HEX40.fullmatch(tree) is None: reject("commit tree")
    parents = []; index = 1
    while index < len(lines) and lines[index].startswith(b"parent "):
        try: parent = lines[index][7:].decode("ascii")
        except UnicodeError as error: raise Rejected("commit parent encoding") from error
        if HEX40.fullmatch(parent) is None: reject("commit parent")
        parents.append(parent); index += 1
    remaining = lines[index:]
    if any(line.startswith((b"tree ", b"parent ")) for line in remaining):
        reject("late commit tree/parent")
    have_extension = False
    for line in remaining:
        if not line: reject("empty commit extension header")
        if line.startswith(b" "):
            if not have_extension: reject("orphan commit continuation")
        elif b" " not in line:
            reject("commit extension header")
        else:
            have_extension = True
    return {"id": oid, "tree": tree, "parents": parents, "message": message}


def validate_ancestry_closure(descendant: str, targets: set[str], commits: dict[str, bytes]) -> None:
    if not targets or descendant not in commits: reject("ancestry roots")
    parsed = {oid: parse_commit(payload, oid) for oid, payload in commits.items()}
    needed: set[str] = set(); reached: set[str] = set(); pending = [descendant]
    while pending:
        oid = pending.pop()
        if oid in needed: continue
        if oid not in parsed: reject("missing ancestry parent")
        needed.add(oid)
        if oid in targets:
            reached.add(oid)
            continue
        for parent in parsed[oid]["parents"]:
            if parent not in parsed: reject("missing ancestry parent")
            pending.append(parent)
    if reached != targets or needed != set(commits): reject("unreachable target or extra ancestry node")


def mine_fixture_candidate() -> tuple[dict[str, tuple[int, bytes]], bytes, str, bytes, str, bytes, str]:
    # Mine real hashes by changing real object bytes; never overwrite a digest.
    for nonce in range(10000):
        paths = {"fixture.txt": (0o644, f"fixture {nonce}\n".encode())}
        tree_raw, tree_id = tree_from_map(paths)
        if tree_id.startswith("f2"): break
    else: reject("tree mining exhausted")
    parent_payload = b"tree " + tree_id.encode() + b"\nauthor Fixture <f@example.test> 0 +0000\ncommitter Fixture <f@example.test> 0 +0000\n\nparent\n"
    parent_id = git_object("commit", parent_payload)[1]
    for nonce in range(10000):
        payload = (b"tree " + tree_id.encode() + b"\nparent " + parent_id.encode()
                   + b"\nauthor Fixture <f@example.test> 1 +0000\ncommitter Fixture <f@example.test> "
                   + str(nonce + 1).encode() + b" +0000\n\nfixture candidate\n")
        commit_id = git_object("commit", payload)[1]
        if commit_id.startswith("f1"): break
    else: reject("commit mining exhausted")
    return paths, tree_raw, tree_id, parent_payload, parent_id, payload, commit_id


FM_FIELDS = ("id", "title", "status", "owner", "updated", "normative", "approvers", "approvedAt", "reviewCommit", "reviewLink", "openFindings")
FIXTURE_IDS = {"GOV-TASKQUAL-FIXTURE-001", "GOV-D0CLOSE-FIXTURE-001"}


def build_fixture_markdown(identifier: str, title: str, owner: str, approvers: list[str], body: str) -> bytes:
    values = {"id": identifier, "title": title, "status": "accepted", "owner": owner, "updated": "2026-07-20",
              "normative": "true", "approvers": ", ".join(approvers), "approvedAt": "2026-07-20",
              "reviewCommit": REVIEW_PIN, "reviewLink": "https://example.test/fixture", "openFindings": "none"}
    raw = "---\n" + "".join(f"{key}: {values[key]}\n" for key in FM_FIELDS) + "---\n\n" + body
    if not raw.endswith("\n"): raw += "\n"
    parse_fixture_markdown(raw.encode())
    return raw.encode()


def parse_fixture_markdown(data: bytes) -> dict[str, str]:
    if type(data) is not bytes or data.startswith(b"\xef\xbb\xbf") or b"\x00" in data or b"\r" in data or not data.endswith(b"\n") or data.endswith(b"\n\n"):
        reject("fixture Markdown bytes")
    try: lines = data.decode("utf-8").split("\n")[:-1]
    except UnicodeError as error: raise Rejected("fixture Markdown UTF-8") from error
    if len(lines) < 16 or lines[0] != "---" or lines[12] != "---" or lines[13] != "": reject("fixture frontmatter framing")
    result: dict[str, str] = {}
    for index, key in enumerate(FM_FIELDS, 1):
        prefix = key + ": "
        if not lines[index].startswith(prefix): reject("fixture frontmatter field/order")
        result[key] = lines[index][len(prefix):]
        if any(ord(c) < 32 or 0x7f <= ord(c) <= 0x9f for c in result[key]): reject("fixture frontmatter control")
    if result["id"] not in FIXTURE_IDS or not result["title"] or result["status"] != "accepted" or result["normative"] != "true" or result["openFindings"] != "none": reject("fixture frontmatter value")
    if SAFE_ID.fullmatch(result["owner"]) is None or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", result["updated"]) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", result["approvedAt"]): reject("fixture metadata grammar")
    approvers = result["approvers"].split(", ")
    if not approvers or any(SAFE_ID.fullmatch(x) is None for x in approvers) or approvers != sorted(set(approvers)): reject("fixture approvers")
    if result["reviewCommit"] != REVIEW_PIN or not result["reviewLink"].startswith("https://") or result["reviewLink"] == "https://": reject("fixture review pin/link")
    if any(any(ord(c) < 32 or 0x7f <= ord(c) <= 0x9f for c in line) for line in lines[14:]): reject("fixture body control")
    h1 = next((line for line in lines[14:] if line.startswith("# ")), None); expected = "# " + result["id"]
    if h1 is None or not (h1 == expected or h1.startswith(expected + ":") or h1.startswith(expected + "：")): reject("fixture H1")
    return result


POLICY_FIELDS = ("schema", "id", "version", "namespace", "principals", "rule", "verifierKey")
VECTOR_PUBLIC = (
    "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
    "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
    "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025",
)


def build_fixture_policy(suffix: str = "core") -> tuple[bytes, ContentRef]:
    if PROFILE_ID.fullmatch(suffix) is None: reject("fixture policy suffix")
    roles = ("architecture", "quality", "security")
    principals = [{"principalId": f"fixture-principal-{role}", "keyId": f"fixture-key-{role}", "publicKey": public, "roles": [role]}
                  for role, public in zip(roles, VECTOR_PUBLIC)]
    obj = {"schema": "proof-forge.task-qualification-fixture-policy.v1", "id": "task-qualification-fixture-policy-" + suffix,
           "version": "1.0.0", "namespace": "task-qualification-fixture-v1", "principals": principals,
           "rule": {"requiredRoles": list(roles), "minimumDistinctSigners": 3},
           "verifierKey": {"keyId": "fixture-verifier-key", "algorithm": "ed25519", "publicKey": "278117fc144c72340f67d0f2316e8386ceffbf2b2428c9c51fef7c597f1d426e"}}
    wire = canonical_pf_jcs(obj); return wire, validate_fixture_policy(wire)[1]


def validate_fixture_policy(data: bytes) -> tuple[dict[str, Any], ContentRef]:
    obj = exact_keys(decode_canonical_pf_jcs(data), POLICY_FIELDS, "FixturePolicyV1")
    prefix = "task-qualification-fixture-policy-"
    if (obj["schema"] != "proof-forge.task-qualification-fixture-policy.v1" or obj["version"] != "1.0.0"
            or obj["namespace"] != "task-qualification-fixture-v1" or type(obj["id"]) is not str
            or not obj["id"].startswith(prefix) or PROFILE_ID.fullmatch(obj["id"][len(prefix):]) is None): reject("fixture policy identity")
    expected_roles = ("architecture", "quality", "security")
    principals = obj["principals"]
    if type(principals) is not list or len(principals) != 3: reject("fixture principals")
    for item, role, public in zip(principals, expected_roles, VECTOR_PUBLIC):
        exact_keys(item, ("principalId", "keyId", "publicKey", "roles"), "fixture principal")
        if item != {"principalId": f"fixture-principal-{role}", "keyId": f"fixture-key-{role}", "publicKey": public, "roles": [role]}: reject("fixture principal formula")
    exact_keys(obj["rule"], ("requiredRoles", "minimumDistinctSigners"), "fixture rule")
    if obj["rule"] != {"requiredRoles": list(expected_roles), "minimumDistinctSigners": 3}: reject("fixture rule value")
    exact_keys(obj["verifierKey"], ("keyId", "algorithm", "publicKey"), "fixture verifier")
    if obj["verifierKey"] != {"keyId": "fixture-verifier-key", "algorithm": "ed25519", "publicKey": "278117fc144c72340f67d0f2316e8386ceffbf2b2428c9c51fef7c597f1d426e"}: reject("fixture verifier value")
    return obj, ContentRef(obj["schema"], obj["id"], obj["version"], domain_digest("pf.taskqual.fixture-policy.v1", obj))


ROLE_PREFIXES = {"resolved-tool", "resolved-tool-closure", "resolved-probe", "sandbox-policy", "verifier-executable", "verifier-closure", "verifier-build-policy", "private-scan-policy", "private-scan-scanner", "authority-store-service", "host-observation", "host-profile"}
TOP_ROLES = {f"{prefix}-{part}" for prefix in ("bootstrap-verifier", "protected-consumer") for part in ("executable", "closure", "build-policy")}


def build_fixture_resolved_blob(role: str) -> tuple[bytes, ContentRef, bytes]:
    if role in TOP_ROLES: identifier = "fixture-resolved-" + role
    else:
        prefix, sep, gate = role.partition("/")
        if not sep or prefix not in ROLE_PREFIXES or PROFILE_ID.fullmatch(gate) is None: reject("fixture resolved role")
        identifier = f"fixture-resolved-{gate}-{prefix}"
    payload = b"pf.taskqual.fixture-resolved-payload.v1\x00" + role.encode()
    obj = {"schema": "proof-forge.task-qualification-fixture-resolved-blob.v1", "id": identifier, "version": "1.0.0", "role": role, "payloadSha256": Digest(hashlib.sha256(payload).digest()).wire()}
    wire = canonical_pf_jcs(obj); return wire, validate_fixture_resolved_blob(wire)[1], payload


def validate_fixture_resolved_blob(data: bytes) -> tuple[dict[str, Any], ContentRef]:
    obj = exact_keys(decode_canonical_pf_jcs(data), ("schema", "id", "version", "role", "payloadSha256"), "FixtureResolvedBlobV1")
    role = obj["role"]
    if type(role) is not str: reject("fixture resolved role type")
    if role in TOP_ROLES: expected_id = "fixture-resolved-" + role
    else:
        prefix, sep, gate = role.partition("/")
        if not sep or prefix not in ROLE_PREFIXES or PROFILE_ID.fullmatch(gate) is None or "/" in gate: reject("fixture resolved role")
        expected_id = f"fixture-resolved-{gate}-{prefix}"
    payload = b"pf.taskqual.fixture-resolved-payload.v1\x00" + role.encode()
    expected_digest = Digest(hashlib.sha256(payload).digest()).wire()
    if obj["schema"] != "proof-forge.task-qualification-fixture-resolved-blob.v1" or obj["id"] != expected_id or obj["version"] != "1.0.0" or obj["payloadSha256"] != expected_digest: reject("fixture resolved formula")
    return obj, ContentRef(obj["schema"], obj["id"], obj["version"], domain_digest("pf.taskqual.fixture-resolved-blob.v1", obj))


def must_reject(function: Any, *args: Any) -> None:
    try: function(*args)
    except (Rejected, ValueError, UnicodeError): return
    raise AssertionError("mutation was accepted")


def main() -> None:
    vectors = [
        ("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60", "", VECTOR_PUBLIC[0], "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"),
        ("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb", "72", VECTOR_PUBLIC[1], "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"),
        ("c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7", "af82", VECTOR_PUBLIC[2], "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a"),
        ("f5e5767cf153319517630f226876b86c8160cc583bc013744c6bf255f5cc0ee5", "08b8b2b733424243760fe426a4b54908632110a66c2f6591eabd3345e3e4eb98fa6e264bf09efe12ee50f8f54e9f77b1e355f6c50544e23fb1433ddf73be84d879de7c0046dc4996d9e773f4bc9efe5738829adb26c81b37c93a1b270b20329d658675fc6ea534e0810a4432826bf58c941efb65d57a338bbd2e26640f89ffbc1a858efcb8550ee3a5e1998bd177e93a7363c344fe6b199ee5d02e82d522c4fe574f2f74", "278117fc144c72340f67d0f2316e8386ceffbf2b2428c9c51fef7c597f1d426e", "0aab4c900501b3e24d7cdf4663326a3a87df5e4843b2cbdb67cbf6e460fec350aa5371b1508f9f4528ecea23c436d94b5e8fcd4f681e30a6ac00a9704a188a03"),
    ]
    for seed_hex, message_hex, public_hex, signature_hex in vectors:
        seed, message = bytes.fromhex(seed_hex), bytes.fromhex(message_hex)
        if public_hex == "278117fc144c72340f67d0f2316e8386ceffbf2b2428c9c51fef7c597f1d426e":
            message = RFC8032_VECTOR4_MESSAGE
        assert ed25519_public(seed).hex() == public_hex
        assert ed25519_sign(seed, message).hex() == signature_hex
        assert ed25519_verify(bytes.fromhex(public_hex), message, bytes.fromhex(signature_hex))
        assert not ed25519_verify(bytes.fromhex(public_hex), message+b"!", bytes.fromhex(signature_hex))
    good_sig = bytes.fromhex(vectors[0][3]); good_public = bytes.fromhex(vectors[0][2])
    must_reject(ed25519_public, b"short")
    assert not ed25519_verify(good_public, b"", good_sig[:32] + (int.from_bytes(good_sig[32:], "little") + L).to_bytes(32, "little"))
    assert not ed25519_verify(good_public, b"", P.to_bytes(32, "little") + good_sig[32:])
    assert not ed25519_verify(b"\x01" + b"\x00" * 31, b"", good_sig)

    value = {"z": [True, None, -1], "a": "é"}; encoded = canonical_pf_jcs(value)
    assert decode_canonical_pf_jcs(encoded) == value
    for bad in (b'{"a":1,"a":2}', b'{ "a":1}', b'{"a":1.0}', b'{"a":9007199254740992}', b'\xef\xbb\xbf{}'):
        must_reject(decode_canonical_pf_jcs, bad)
    must_reject(canonical_pf_jcs, {"x" * 257: 1})
    deep: Any = None
    for _ in range(64): deep = [deep]
    must_reject(canonical_pf_jcs, deep)
    must_reject(ContentRef, "proof-forge.fixture.v1", "fixture-core", "1.0.0-01", Digest(b"\x00" * 32))
    must_reject(ContentRef, "proof-forge.fixture.v1", "fixture-core", "18446744073709551616.0.0", Digest(b"\x00" * 32))

    digest = domain_digest("fixture.domain", value); assert Digest.parse(digest.wire()) == digest
    ref = ContentRef("proof-forge.fixture.v1", "fixture-core", "1.0.0", digest); assert ContentRef.parse(ref.wire()) == ref
    must_reject(ContentRef.parse, {**ref.wire(), "extra": 1})

    seeds = {"fixture-key-architecture": bytes.fromhex(vectors[0][0])}
    statement = {"schema": "proof-forge.fixture-signed.v1", "id": "fixture-signed", "version": "1.0.0", "value": 7}
    wire, statement_digest, signed_ref = build_signed_object(statement, seeds, "fixture.statement", "fixture.signature", "fixture.full")
    fields = ("schema", "id", "version", "value")
    parsed, checked_statement_digest, checked_ref = validate_signed_object(wire, {next(iter(seeds)): ed25519_public(next(iter(seeds.values())))}, fields, "fixture.statement", "fixture.signature", "fixture.full")
    assert checked_ref == signed_ref and checked_statement_digest == statement_digest and parsed["value"] == 7
    mutated_obj = decode_canonical_pf_jcs(wire)
    signature = mutated_obj["signatures"][0]["signature"]
    mutated_obj["signatures"][0]["signature"] = signature[:-1] + ("0" if signature[-1] != "0" else "1")
    mutated_wire = canonical_pf_jcs(mutated_obj)
    must_reject(validate_signed_object, mutated_wire, {next(iter(seeds)): ed25519_public(next(iter(seeds.values())))}, fields, "fixture.statement", "fixture.signature", "fixture.full")
    must_reject(build_signed_object, statement, seeds, "fixture.statement", "é", "fixture.full")

    paths, tree_raw, tree_id, parent_raw, parent_id, commit_raw, commit_id = mine_fixture_candidate()
    archive = build_ustar("TASK-D1-FIXTURE", paths); parsed_paths = parse_ustar(archive, "TASK-D1-FIXTURE")
    assert parsed_paths == paths and hashlib.sha256(archive).digest()
    recomputed_tree, recomputed_tree_id = tree_from_map(parsed_paths)
    assert recomputed_tree == tree_raw and recomputed_tree_id == tree_id and tree_id.startswith("f2")
    assert parse_tree(tree_raw) and parse_commit(commit_raw)["tree"] == tree_id and commit_id.startswith("f1")
    assert tree_from_map({"a/x": (0o644, b"x"), "a.c": (0o644, b"c")})[1] == "07047a9161e543b41d18b9d3d999579f13a81560"
    must_reject(tree_from_map, {"a": (0o644, b"x"), "a/x": (0o644, b"x")})
    commits = {parent_id: parent_raw, commit_id: commit_raw}
    validate_ancestry_closure(commit_id, {parent_id}, commits)
    must_reject(validate_ancestry_closure, commit_id, {parent_id}, {commit_id: commit_raw})
    extra_payload = parent_raw.replace(b"\n\nparent\n", b"\n\nextra\n")
    extra_id = git_object("commit", extra_payload)[1]
    must_reject(validate_ancestry_closure, commit_id, {parent_id}, {**commits, extra_id: extra_payload})
    second_parent = parent_raw.replace(b"\n\nparent\n", b"\n\nsecond root\n")
    second_parent_id = git_object("commit", second_parent)[1]
    merge = commit_raw.replace(b"parent " + parent_id.encode() + b"\n", b"parent " + parent_id.encode() + b"\nparent " + second_parent_id.encode() + b"\n")
    merge_id = git_object("commit", merge)[1]
    must_reject(validate_ancestry_closure, merge_id, {parent_id}, {parent_id: parent_raw, merge_id: merge})
    validate_ancestry_closure(merge_id, {parent_id, second_parent_id}, {parent_id: parent_raw, second_parent_id: second_parent, merge_id: merge})
    assert len({REVIEW_PIN[:2], commit_id[:2], tree_id[:2]}) == 3
    bad_archive = bytearray(archive); bad_archive[0] ^= 1; must_reject(parse_ustar, bytes(bad_archive), "TASK-D1-FIXTURE")
    bad_commit = bytearray(commit_raw); bad_commit[-1] ^= 1; must_reject(parse_commit, bytes(bad_commit), commit_id)
    long_path = "directory/" + "p" * 95
    assert parse_ustar(build_ustar("TASK-D1-FIXTURE", {long_path: (0o644, b"x")}), "TASK-D1-FIXTURE")[long_path][1] == b"x"
    malformed = bytearray(archive); malformed[100] = ord("_"); must_reject(parse_ustar, bytes(malformed), "TASK-D1-FIXTURE")

    markdown = build_fixture_markdown("GOV-TASKQUAL-FIXTURE-001", "Fixture", "quality-owner", ["architecture-owner", "quality-owner"], "Preface.\n\n# GOV-TASKQUAL-FIXTURE-001: title\n\nFixture body.\n")
    assert parse_fixture_markdown(markdown)["reviewCommit"] == REVIEW_PIN
    must_reject(parse_fixture_markdown, markdown.replace(REVIEW_PIN.encode(), commit_id.encode()))
    must_reject(parse_fixture_markdown, markdown.replace(b"Fixture body.", b"Fixture\x01body."))

    policy_wire, policy_ref = build_fixture_policy(); policy, recomputed_policy_ref = validate_fixture_policy(policy_wire)
    assert policy_ref == recomputed_policy_ref and policy["principals"][0]["publicKey"] == VECTOR_PUBLIC[0]
    policy_mutation = decode_canonical_pf_jcs(policy_wire); policy_mutation["rule"]["minimumDistinctSigners"] = 2
    must_reject(validate_fixture_policy, canonical_pf_jcs(policy_mutation))
    for role in ("resolved-tool/gate-doc-001", "bootstrap-verifier-build-policy"):
        blob_wire, blob_ref, payload = build_fixture_resolved_blob(role)
        blob, recomputed_blob_ref = validate_fixture_resolved_blob(blob_wire)
        assert blob_ref == recomputed_blob_ref and Digest.parse(blob["payloadSha256"]).raw == hashlib.sha256(payload).digest()
        mutation = decode_canonical_pf_jcs(blob_wire); mutation["id"] += "-wrong"
        must_reject(validate_fixture_resolved_blob, canonical_pf_jcs(mutation))
    print("task qualification fixture core self-check: passed")


if __name__ == "__main__":
    main()
