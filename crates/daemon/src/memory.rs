//! The harness's own memory provider: what agents of a workspace learn and
//! want to keep (decisions, preferences, facts about the projects), shared
//! by its sessions through `remember` / `recall` / `forget`.
//! Kept in `orc.db` (table `memory`).

use std::path::PathBuf;

use orc_protocol::MemoryEntry;

use crate::db::{Db, Value, int, t, text};

pub struct Memory {
    db: Db,
}

const SCHEMA: &str = "CREATE TABLE IF NOT EXISTS memory (
    id TEXT PRIMARY KEY, workspace TEXT NOT NULL, at INTEGER NOT NULL,
    session TEXT NOT NULL, text TEXT NOT NULL, tags TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS memory_workspace ON memory (workspace);";

/// Lowercase words without accents, for matching.
fn words(s: &str) -> Vec<String> {
    let fold = |c: char| match c {
        'á' | 'à' | 'â' | 'ã' => 'a',
        'é' | 'ê' => 'e',
        'í' => 'i',
        'ó' | 'ô' | 'õ' => 'o',
        'ú' => 'u',
        'ç' => 'c',
        c => c,
    };
    s.to_lowercase()
        .chars()
        .map(fold)
        .collect::<String>()
        .split(|c: char| !c.is_alphanumeric())
        .filter(|w| w.len() > 2)
        .map(String::from)
        .collect()
}

impl Memory {
    /// The memory in `db`. Entries of an old `legacy` folder
    /// (`<workspace>.jsonl` files) move in once; the files become `.imported`.
    pub fn open(db: Db, legacy: Option<PathBuf>) -> Self {
        if let Err(e) = db.batch(SCHEMA) {
            eprintln!("orcd: tabela de memória: {e}");
        }
        let m = Self { db };
        for f in legacy.iter().flat_map(|d| std::fs::read_dir(d).into_iter().flatten().flatten()) {
            let path = f.path();
            let Some(ws) = path.file_name().and_then(|n| n.to_str()).and_then(|n| n.strip_suffix(".jsonl")).map(String::from) else { continue };
            let entries: Vec<MemoryEntry> = std::fs::read_to_string(&path).unwrap_or_default().lines().filter_map(|l| serde_json::from_str(l).ok()).collect();
            if entries.iter().all(|e| m.insert(&ws, e).is_ok()) {
                let _ = std::fs::rename(&path, path.with_extension("jsonl.imported"));
            }
        }
        m
    }

    fn insert(&self, workspace: &str, e: &MemoryEntry) -> std::io::Result<()> {
        self.db.exec(
            "INSERT OR REPLACE INTO memory (id, workspace, at, session, text, tags) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            vec![t(&e.id), t(workspace), Value::Integer(e.at), t(&e.session), t(&e.text), t(&serde_json::to_string(&e.tags)?)],
        )?;
        Ok(())
    }

    fn check(workspace: &str) -> std::io::Result<()> {
        if crate::workspaces::valid_id(workspace) { Ok(()) } else { Err(std::io::Error::other("workspace inválido")) }
    }

    pub fn list(&self, workspace: &str) -> Vec<MemoryEntry> {
        self.db
            .query("SELECT id, at, session, text, tags FROM memory WHERE workspace = ?1 ORDER BY at, id", vec![t(workspace)])
            .unwrap_or_default()
            .into_iter()
            .map(|r| MemoryEntry {
                id: text(&r[0]),
                at: int(&r[1]),
                session: text(&r[2]),
                text: text(&r[3]),
                tags: serde_json::from_str(&text(&r[4])).unwrap_or_default(),
            })
            .collect()
    }

    pub fn remember(&self, workspace: &str, session: &str, text: &str, tags: Vec<String>) -> std::io::Result<MemoryEntry> {
        Self::check(workspace)?;
        let text = text.trim();
        if text.is_empty() || text.len() > 4000 {
            return Err(std::io::Error::other("a memória precisa de texto (até 4000 caracteres)"));
        }
        let entry = MemoryEntry {
            id: uuid::Uuid::new_v4().simple().to_string()[..10].to_string(),
            at: std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0),
            session: session.into(),
            text: text.into(),
            tags,
        };
        self.insert(workspace, &entry)?;
        Ok(entry)
    }

    /// The entries that share the most words with `query` (tags count
    /// double), best first; newer wins ties.
    pub fn recall(&self, workspace: &str, query: &str, max: usize) -> Vec<MemoryEntry> {
        let q = words(query);
        let mut scored: Vec<(usize, MemoryEntry)> = self
            .list(workspace)
            .into_iter()
            .map(|e| {
                let text = words(&e.text);
                let tags: Vec<String> = e.tags.iter().flat_map(|t| words(t)).collect();
                let score = q.iter().map(|w| text.iter().filter(|t| *t == w).count() + 2 * tags.iter().filter(|t| *t == w).count()).sum();
                (score, e)
            })
            .filter(|(s, _)| *s > 0 || q.is_empty())
            .collect();
        scored.sort_by(|a, b| b.0.cmp(&a.0).then(b.1.at.cmp(&a.1.at)));
        scored.into_iter().take(max).map(|(_, e)| e).collect()
    }

    pub fn forget(&self, workspace: &str, id: &str) -> std::io::Result<bool> {
        Self::check(workspace)?;
        Ok(self.db.exec("DELETE FROM memory WHERE workspace = ?1 AND id = ?2", vec![t(workspace), t(id)])? > 0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn remembers_recalls_by_words_and_forgets() {
        let m = Memory::open(Db::memory(), None);
        m.remember("trabalho", "s1", "O app usa Riverpod, não Bloc, para estado.", vec!["arquitetura".into()]).unwrap();
        let deploy = m.remember("trabalho", "s2", "Deploy da API é no Railway, serviço api-prod.", vec!["deploy".into()]).unwrap();
        m.remember("pessoal", "s3", "Blog em Astro.", vec![]).unwrap();

        let hits = m.recall("trabalho", "como faço o deploy da api?", 5);
        assert_eq!(hits[0].id, deploy.id);
        assert_eq!(m.recall("trabalho", "gerência de estado riverpod", 5)[0].session, "s1");
        assert!(m.recall("trabalho", "astro", 5).is_empty(), "workspaces are apart");
        assert_eq!(m.recall("trabalho", "", 5).len(), 2);

        assert!(m.forget("trabalho", &deploy.id).unwrap());
        assert!(!m.forget("trabalho", &deploy.id).unwrap());
        assert_eq!(m.list("trabalho").len(), 1);
        assert!(m.remember("../x", "s", "x", vec![]).is_err());
        assert!(m.remember("trabalho", "s", "  ", vec![]).is_err());
    }

    #[test]
    fn old_memory_files_move_in_once() {
        let dir = tempfile::tempdir().unwrap();
        let e = MemoryEntry { id: "m1".into(), at: 5, session: "s".into(), text: "Deploy no Railway".into(), tags: vec!["deploy".into()] };
        std::fs::write(dir.path().join("trabalho.jsonl"), format!("{}\n", serde_json::to_string(&e).unwrap())).unwrap();
        let m = Memory::open(Db::memory(), Some(dir.path().to_path_buf()));
        assert_eq!(m.list("trabalho"), [e]);
        assert!(dir.path().join("trabalho.jsonl.imported").exists());
    }
}
