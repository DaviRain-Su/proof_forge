#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Event {
    StorageLoad { value: u64 },
    StorageCache { value: u64 },
    StorageFlush { writes: usize },
    Result { value: Option<u64> },
    Revert { message: &'static str },
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Host {
    pub storage: Option<u64>,
    cache: Option<u64>,
    pub trace: Vec<Event>,
}

pub fn masked_word_update(
    mut word: [u8; 32],
    byte_offset: usize,
    field: &[u8],
) -> Result<[u8; 32], &'static str> {
    let end = byte_offset.checked_add(field.len()).ok_or("packed field overflow")?;
    if field.is_empty() || end > word.len() {
        return Err("packed field exceeds storage word");
    }
    word[byte_offset..end].copy_from_slice(field);
    Ok(word)
}

impl Host {
    pub fn initialize(&mut self) {
        self.trace.clear();
        self.cache(0);
        self.flush();
        self.trace.push(Event::Result { value: None });
    }

    pub fn increment(&mut self) -> Result<(), &'static str> {
        self.trace.clear();
        let value = self.load();
        let Some(next) = value.checked_add(1) else {
            self.cache = None;
            self.trace.push(Event::Revert {
                message: "checked arithmetic overflow",
            });
            return Err("checked arithmetic overflow");
        };
        self.cache(next);
        self.flush();
        self.trace.push(Event::Result { value: None });
        Ok(())
    }

    pub fn get(&mut self) -> u64 {
        self.trace.clear();
        let value = self.load();
        self.trace.push(Event::Result { value: Some(value) });
        value
    }

    fn load(&mut self) -> u64 {
        let value = self.cache.or(self.storage).unwrap_or(0);
        self.trace.push(Event::StorageLoad { value });
        value
    }

    fn cache(&mut self, value: u64) {
        self.cache = Some(value);
        self.trace.push(Event::StorageCache { value });
    }

    fn flush(&mut self) {
        let writes = usize::from(self.cache.is_some());
        if let Some(value) = self.cache.take() {
            self.storage = Some(value);
        }
        self.trace.push(Event::StorageFlush { writes });
    }

    pub fn normalized_json(&self) -> String {
        let events = self
            .trace
            .iter()
            .map(|event| match event {
                Event::StorageLoad { value } => format!(r#"{{"event":"storage_load","value":{value}}}"#),
                Event::StorageCache { value } => format!(r#"{{"event":"storage_cache","value":{value}}}"#),
                Event::StorageFlush { writes } => format!(r#"{{"event":"storage_flush","writes":{writes}}}"#),
                Event::Result { value: Some(value) } => format!(r#"{{"event":"result","value":{value}}}"#),
                Event::Result { value: None } => r#"{"event":"result","value":null}"#.to_owned(),
                Event::Revert { message } => format!(r#"{{"event":"revert","message":"{message}"}}"#),
            })
            .collect::<Vec<_>>()
            .join(",");
        format!(r#"{{"storage":{},"events":[{events}]}}"#, self.storage.map_or("null".to_owned(), |v| v.to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lifecycle_and_overflow_are_transactional() {
        let mut host = Host::default();
        host.initialize();
        assert_eq!(host.storage, Some(0));
        assert_eq!(host.trace.iter().filter(|e| matches!(e, Event::StorageFlush { .. })).count(), 1);
        host.increment().unwrap();
        assert_eq!(host.get(), 1);
        host.storage = Some((1_u64 << 40) + 7);
        assert_eq!(host.get(), (1_u64 << 40) + 7);
        host.storage = Some(u64::MAX);
        assert_eq!(host.increment(), Err("checked arithmetic overflow"));
        assert_eq!(host.storage, Some(u64::MAX));
        assert!(!host.trace.iter().any(|e| matches!(e, Event::StorageFlush { .. })));
        assert_eq!(
            host.normalized_json(),
            r#"{"storage":18446744073709551615,"events":[{"event":"storage_load","value":18446744073709551615},{"event":"revert","message":"checked arithmetic overflow"}]}"#
        );
    }


    #[test]
    fn packed_storage_update_preserves_unrelated_bytes() {
        let mut original = [0_u8; 32];
        for (index, byte) in original.iter_mut().enumerate() {
            *byte = index as u8;
        }
        let updated = masked_word_update(original, 8, &[0xff; 8]).unwrap();
        assert_eq!(&updated[..8], &original[..8]);
        assert_eq!(&updated[8..16], &[0xff; 8]);
        assert_eq!(&updated[16..], &original[16..]);
        assert!(masked_word_update(original, 31, &[1, 2]).is_err());
    }
}
