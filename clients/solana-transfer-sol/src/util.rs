//! Shared hex, domain-digest, URL redaction, and strict JSON helpers.

use std::collections::BTreeMap;
use std::fmt;

use serde::de::{self, Deserializer, MapAccess, SeqAccess, Visitor};
use serde::Deserialize;
use serde_json::Value;
use sha2::{Digest, Sha256};

use crate::error::ClientError;

/// SHA-256(domain_utf8 || 0x00 || payload) → lowercase 64-hex.
pub fn domain_separated_sha256_hex(domain: &str, payload: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(domain.as_bytes());
    h.update([0u8]);
    h.update(payload);
    hex::encode(h.finalize())
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(bytes);
    hex::encode(h.finalize())
}

/// Accept only exact lowercase 64 hex (no `sha256:` prefix, no uppercase).
pub fn require_bare_hex64(field: &str, s: &str) -> Result<(), ClientError> {
    if s.len() != 64 {
        return Err(ClientError::Artifact(format!(
            "{field}: expected lowercase 64-hex, len={}",
            s.len()
        )));
    }
    if !s.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f')) {
        return Err(ClientError::Artifact(format!(
            "{field}: expected lowercase 64-hex, got {s}"
        )));
    }
    Ok(())
}

/// Strip optional `sha256:` prefix and require the remainder is lowercase 64-hex.
pub fn require_sha256_wire(field: &str, s: &str) -> Result<String, ClientError> {
    let bare = s
        .strip_prefix("sha256:")
        .ok_or_else(|| ClientError::Artifact(format!("{field}: missing sha256: prefix")))?;
    require_bare_hex64(field, bare)?;
    Ok(bare.to_string())
}

/// Display-safe endpoint: `scheme://host[:port]` + `/<redacted>` if path/query/userinfo present.
/// Never returns secrets from path/query/userinfo.
pub fn display_endpoint(url: &str) -> String {
    match url::Url::parse(url) {
        Ok(u) => {
            let host = u.host_str().unwrap_or("invalid-host");
            let mut out = format!("{}://{}", u.scheme(), host);
            if let Some(port) = u.port() {
                out.push(':');
                out.push_str(&port.to_string());
            }
            let has_user = !u.username().is_empty() || u.password().is_some();
            let has_path = {
                let p = u.path();
                !p.is_empty() && p != "/"
            };
            let has_query = u.query().is_some();
            let has_frag = u.fragment().is_some();
            if has_user || has_path || has_query || has_frag {
                out.push_str("/<redacted>");
            }
            out
        }
        Err(_) => "<invalid-endpoint>".to_string(),
    }
}

// ---------------------------------------------------------------------------
// Strict JSON: reject duplicate object keys at every nesting level
// ---------------------------------------------------------------------------

#[derive(Clone, Debug)]
pub enum StrictValue {
    Null,
    Bool(bool),
    Number(serde_json::Number),
    String(String),
    Array(Vec<StrictValue>),
    Object(BTreeMap<String, StrictValue>),
}

impl StrictValue {
    pub fn into_json(self) -> Value {
        match self {
            Self::Null => Value::Null,
            Self::Bool(b) => Value::Bool(b),
            Self::Number(n) => Value::Number(n),
            Self::String(s) => Value::String(s),
            Self::Array(a) => Value::Array(a.into_iter().map(Self::into_json).collect()),
            Self::Object(m) => {
                Value::Object(m.into_iter().map(|(k, v)| (k, v.into_json())).collect())
            }
        }
    }
}

struct StrictVisitor;

impl<'de> Visitor<'de> for StrictVisitor {
    type Value = StrictValue;

    fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str("any JSON value without duplicate object keys")
    }

    fn visit_bool<E: de::Error>(self, v: bool) -> Result<Self::Value, E> {
        Ok(StrictValue::Bool(v))
    }
    fn visit_i64<E: de::Error>(self, v: i64) -> Result<Self::Value, E> {
        Ok(StrictValue::Number(v.into()))
    }
    fn visit_u64<E: de::Error>(self, v: u64) -> Result<Self::Value, E> {
        Ok(StrictValue::Number(v.into()))
    }
    fn visit_f64<E: de::Error>(self, v: f64) -> Result<Self::Value, E> {
        serde_json::Number::from_f64(v)
            .map(StrictValue::Number)
            .ok_or_else(|| de::Error::custom("invalid f64"))
    }
    fn visit_str<E: de::Error>(self, v: &str) -> Result<Self::Value, E> {
        Ok(StrictValue::String(v.to_string()))
    }
    fn visit_string<E: de::Error>(self, v: String) -> Result<Self::Value, E> {
        Ok(StrictValue::String(v))
    }
    fn visit_none<E: de::Error>(self) -> Result<Self::Value, E> {
        Ok(StrictValue::Null)
    }
    fn visit_unit<E: de::Error>(self) -> Result<Self::Value, E> {
        Ok(StrictValue::Null)
    }
    fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<Self::Value, A::Error> {
        let mut out = Vec::new();
        while let Some(v) = seq.next_element_seed(StrictSeed)? {
            out.push(v);
        }
        Ok(StrictValue::Array(out))
    }
    fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
        let mut out = BTreeMap::new();
        while let Some(key) = map.next_key::<String>()? {
            if out.contains_key(&key) {
                return Err(de::Error::custom(format!("duplicate JSON key: {key}")));
            }
            let val = map.next_value_seed(StrictSeed)?;
            out.insert(key, val);
        }
        Ok(StrictValue::Object(out))
    }
}

struct StrictSeed;

impl<'de> de::DeserializeSeed<'de> for StrictSeed {
    type Value = StrictValue;
    fn deserialize<D: Deserializer<'de>>(self, deserializer: D) -> Result<Self::Value, D::Error> {
        deserializer.deserialize_any(StrictVisitor)
    }
}

impl<'de> Deserialize<'de> for StrictValue {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        deserializer.deserialize_any(StrictVisitor)
    }
}

/// Parse JSON rejecting duplicate keys; full-consume.
pub fn parse_json_no_dups(bytes: &[u8]) -> Result<Value, ClientError> {
    let mut de = serde_json::Deserializer::from_slice(bytes);
    let v = StrictValue::deserialize(&mut de)
        .map_err(|e| ClientError::Artifact(format!("json parse/dup: {e}")))?;
    de.end()
        .map_err(|e| ClientError::Artifact(format!("json trailing: {e}")))?;
    Ok(v.into_json())
}

pub fn encode_string_framed(s: &str) -> Vec<u8> {
    let raw = s.as_bytes();
    let mut out = Vec::with_capacity(4 + raw.len());
    out.extend_from_slice(&(raw.len() as u32).to_le_bytes());
    out.extend_from_slice(raw);
    out
}

pub fn encode_u32le(n: u32) -> [u8; 4] {
    n.to_le_bytes()
}

pub fn encode_u64le(n: u64) -> [u8; 8] {
    n.to_le_bytes()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hex64_strict() {
        assert!(require_bare_hex64("x", &"a".repeat(64)).is_ok());
        assert!(require_bare_hex64("x", &"A".repeat(64)).is_err());
        assert!(require_bare_hex64("x", &"g".repeat(64)).is_err());
        assert!(require_bare_hex64("x", "aa").is_err());
    }

    #[test]
    fn domain_digest_plan_matches_product_formula() {
        // Smoke: domain separator is domain||0||payload
        let d = domain_separated_sha256_hex("pf.test", b"abc");
        let mut h = Sha256::new();
        h.update(b"pf.test");
        h.update([0u8]);
        h.update(b"abc");
        assert_eq!(d, hex::encode(h.finalize()));
    }

    #[test]
    fn reject_duplicate_keys() {
        let ok = br#"{"a":1,"b":2}"#;
        assert!(parse_json_no_dups(ok).is_ok());
        let bad = br#"{"a":1,"a":2}"#;
        assert!(parse_json_no_dups(bad).is_err());
        let nested = br#"{"o":{"x":1,"x":2}}"#;
        assert!(parse_json_no_dups(nested).is_err());
    }

    #[test]
    fn redact_url_path_and_token() {
        let d = display_endpoint("https://example.quiknode.pro/abc123/token?x=1");
        assert_eq!(d, "https://example.quiknode.pro/<redacted>");
        assert!(!d.contains("abc123"));
        let plain = display_endpoint("https://api.devnet.solana.com");
        assert_eq!(plain, "https://api.devnet.solana.com");
    }
}
