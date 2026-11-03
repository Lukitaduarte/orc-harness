//! The harness's own memory provider: what agents of a workspace learn and
//! want to keep (decisions, preferences, facts about the projects), shared
//! by its sessions through `remember` / `recall` / `forget`.
//! `~/.orc/memory/<workspace>.jsonl`, one entry per line.

use std::io::Write;
use std::path::PathBuf;

use orc_protocol::MemoryEntry;

pub struct Memory {
    dir: PathBuf,
}

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
    pub fn new(dir: PathBuf) -> Self {
        Self { dir }
    }

    fn file(&self, workspace: &str) -> std::io::Result<PathBuf> {
        if !crate::workspaces::valid_id(workspace) {
            return Err(std::io::Error::other("workspace inválido"));
        }
        Ok(self.dir.join(format!("{workspace}.jsonl")))
    }

    pub fn list(&self, workspace: &str) -> Vec<MemoryEntry> {
        let Ok(file) = self.file(workspace) else { return Vec::new() };
        std::fs::read_to_string(file)
            .unwrap_or_default()
            .lines()
            .filter_map(|l| serde_json::from_str(l).ok())
            .collect()
    }

    pub fn remember(&self, workspace: &str, session: &str, text: &str, tags: Vec<String>) -> std::io::Result<MemoryEntry> {
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
        std::fs::create_dir_all(&self.dir)?;
        let mut f = std::fs::OpenOptions::new().create(true).append(true).open(self.file(workspace)?)?;
        writeln!(f, "{}", serde_json::to_string(&entry)?)?;
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
        let all = self.list(workspace);
        let kept: Vec<&MemoryEntry> = all.iter().filter(|e| e.id != id).collect();
        if kept.len() == all.len() {
            return Ok(false);
        }
        let mut out = String::new();
        for e in kept {
            out.push_str(&serde_json::to_string(e)?);
            out.push('\n');
        }
        std::fs::write(self.file(workspace)?, out)?;
        Ok(true)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn remembers_recalls_by_words_and_forgets() {
        let dir = tempfile::tempdir().unwrap();
        let m = Memory::new(dir.path().to_path_buf());
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
}
