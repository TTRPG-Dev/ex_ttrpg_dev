//! History wrapper that skips saving consecutive duplicate entries.

use reedline::{
    FileBackedHistory, History, HistoryItem, HistoryItemId, HistorySessionId, SearchFilter,
    SearchQuery,
};

pub(crate) struct DeduplicatingHistory(pub(crate) Box<dyn History>);

impl DeduplicatingHistory {
    pub(crate) fn with_file(capacity: usize, path: std::path::PathBuf) -> Self {
        match FileBackedHistory::with_file(capacity, path) {
            Ok(h) => Self(Box::new(h)),
            Err(_) => Self(Box::new(
                FileBackedHistory::new(capacity).expect("in-memory history"),
            )),
        }
    }
}

impl History for DeduplicatingHistory {
    fn save(&mut self, h: HistoryItem) -> reedline::Result<HistoryItem> {
        let last = self
            .0
            .search(SearchQuery::last_with_search(SearchFilter::anything(None)));
        let duplicate = last
            .ok()
            .and_then(|v| v.into_iter().next())
            .filter(|e| e.command_line == h.command_line);
        if let Some(dup) = duplicate {
            return Ok(dup);
        }
        self.0.save(h)
    }

    fn load(&self, id: HistoryItemId) -> reedline::Result<HistoryItem> {
        self.0.load(id)
    }

    fn count(&self, query: SearchQuery) -> reedline::Result<i64> {
        self.0.count(query)
    }

    fn search(&self, query: SearchQuery) -> reedline::Result<Vec<HistoryItem>> {
        self.0.search(query)
    }

    fn update(
        &mut self,
        id: HistoryItemId,
        updater: &dyn Fn(HistoryItem) -> HistoryItem,
    ) -> reedline::Result<()> {
        self.0.update(id, updater)
    }

    fn clear(&mut self) -> reedline::Result<()> {
        self.0.clear()
    }

    fn delete(&mut self, id: HistoryItemId) -> reedline::Result<()> {
        self.0.delete(id)
    }

    fn sync(&mut self) -> std::io::Result<()> {
        self.0.sync()
    }

    fn session(&self) -> Option<HistorySessionId> {
        self.0.session()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use reedline::{HistoryItem, SearchDirection, SearchQuery};

    fn make_history() -> DeduplicatingHistory {
        DeduplicatingHistory(Box::new(
            FileBackedHistory::new(100).expect("in-memory history"),
        ))
    }

    fn count_all(h: &DeduplicatingHistory) -> i64 {
        h.count(SearchQuery::everything(SearchDirection::Forward, None))
            .unwrap_or(0)
    }

    #[test]
    fn saves_first_entry() {
        let mut h = make_history();
        let saved = h.save(HistoryItem::from_command_line("roll 1d6")).unwrap();
        assert_eq!(saved.command_line, "roll 1d6");
    }

    #[test]
    fn skips_consecutive_duplicate() {
        let mut h = make_history();
        h.save(HistoryItem::from_command_line("roll 1d6")).unwrap();
        h.save(HistoryItem::from_command_line("roll 1d6")).unwrap();
        assert_eq!(count_all(&h), 1);
    }

    #[test]
    fn duplicate_save_returns_original_item() {
        let mut h = make_history();
        let first = h.save(HistoryItem::from_command_line("roll 1d6")).unwrap();
        let second = h.save(HistoryItem::from_command_line("roll 1d6")).unwrap();
        assert_eq!(first.id, second.id);
    }

    #[test]
    fn saves_different_consecutive_commands() {
        let mut h = make_history();
        h.save(HistoryItem::from_command_line("roll 1d6")).unwrap();
        h.save(HistoryItem::from_command_line("roll 1d20")).unwrap();
        assert_eq!(count_all(&h), 2);
    }

    #[test]
    fn saves_repeated_command_after_different_one() {
        let mut h = make_history();
        h.save(HistoryItem::from_command_line("roll 1d6")).unwrap();
        h.save(HistoryItem::from_command_line("roll 1d20")).unwrap();
        h.save(HistoryItem::from_command_line("roll 1d6")).unwrap();
        assert_eq!(count_all(&h), 3);
    }
}
