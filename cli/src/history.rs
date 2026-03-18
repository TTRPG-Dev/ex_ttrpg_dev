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
