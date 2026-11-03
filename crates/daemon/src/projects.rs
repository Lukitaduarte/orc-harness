//! Projects the daemon knows: local clones it makes worktrees from
//! (`~/.orc/projects.json`).

use std::path::PathBuf;

use orc_protocol::ProjectInfo;

use crate::git::{is_repo, valid_branch};

pub struct Projects {
    file: PathBuf,
    list: Vec<ProjectInfo>,
}

impl Projects {
    pub fn load(file: PathBuf) -> Self {
        let list = std::fs::read(&file)
            .ok()
            .and_then(|raw| serde_json::from_slice(&raw).ok())
            .unwrap_or_default();
        Self { file, list }
    }

    pub fn list(&self) -> Vec<ProjectInfo> {
        self.list.clone()
    }

    pub fn get(&self, id: &str) -> Option<&ProjectInfo> {
        self.list.iter().find(|p| p.id == id)
    }

    pub fn add(&mut self, name: &str, repo: &str, base_branch: &str, workspace_id: Option<String>) -> std::io::Result<ProjectInfo> {
        let path = crate::catalog::expand(repo);
        if !is_repo(&path) {
            return Err(std::io::Error::other(format!("{} não é um repositório git", path.display())));
        }
        if !valid_branch(base_branch) {
            return Err(std::io::Error::other(format!("branch base inválida: {base_branch}")));
        }
        let slug: String = name
            .to_lowercase()
            .chars()
            .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
            .collect::<String>()
            .split('-')
            .filter(|s| !s.is_empty())
            .collect::<Vec<_>>()
            .join("-");
        let mut id = if slug.is_empty() { "projeto".to_string() } else { slug };
        while self.get(&id).is_some() {
            id.push('2');
        }
        let p = ProjectInfo {
            id,
            name: name.into(),
            repo: path.display().to_string(),
            base_branch: base_branch.into(),
            workspace_id,
        };
        self.list.push(p.clone());
        self.save()?;
        Ok(p)
    }

    pub fn remove(&mut self, id: &str) -> std::io::Result<()> {
        self.list.retain(|p| p.id != id);
        self.save()
    }

    fn save(&self) -> std::io::Result<()> {
        std::fs::write(&self.file, serde_json::to_vec_pretty(&self.list)?)
    }
}
