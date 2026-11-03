//! Workspaces (`~/.orc/workspaces.json`): a name and the accounts in it.
//! A workspace's sessions are its accounts' sessions; its repositories,
//! plans and browser profile are its own. No file: one workspace with every
//! account. An account no workspace lists shows in the first one.

use std::path::PathBuf;

use orc_protocol::WorkspaceInfo;

pub struct Workspaces {
    file: Option<PathBuf>,
    list: Vec<WorkspaceInfo>,
}

pub fn valid_id(id: &str) -> bool {
    !id.is_empty() && id.len() <= 48 && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

impl Workspaces {
    pub fn load(file: Option<PathBuf>) -> Self {
        let list = file
            .as_ref()
            .and_then(|f| std::fs::read(f).ok())
            .and_then(|raw| serde_json::from_slice(&raw).ok())
            .unwrap_or_default();
        Self { file, list }
    }

    /// What clients see, given the daemon's accounts.
    pub fn view(&self, accounts: &[String]) -> Vec<WorkspaceInfo> {
        let mut list: Vec<WorkspaceInfo> = self
            .list
            .iter()
            .map(|w| WorkspaceInfo {
                accounts: w.accounts.iter().filter(|a| accounts.contains(a)).cloned().collect(),
                ..w.clone()
            })
            .collect();
        if list.is_empty() {
            list.push(WorkspaceInfo { id: "default".into(), name: "Este Mac".into(), accounts: Vec::new(), memory: None, budget_usd: None });
        }
        let listed: Vec<String> = list.iter().flat_map(|w| w.accounts.clone()).collect();
        let loose = accounts.iter().filter(|a| !listed.contains(a)).cloned();
        list[0].accounts.extend(loose);
        list
    }

    /// Adds or renames a workspace and sets its accounts; an account moves
    /// out of any other workspace.
    pub fn upsert(&mut self, w: WorkspaceInfo, known: &[String]) -> std::io::Result<()> {
        if !valid_id(&w.id) || w.name.trim().is_empty() {
            return Err(std::io::Error::other("workspace precisa de id (letras, números, - _) e nome"));
        }
        if let Some(a) = w.accounts.iter().find(|a| !known.contains(a)) {
            return Err(std::io::Error::other(format!("conta desconhecida: {a}")));
        }
        // The implicit default becomes real once anything is saved.
        if self.list.is_empty() && w.id != "default" {
            self.list = self.view(known);
        }
        for other in self.list.iter_mut().filter(|o| o.id != w.id) {
            other.accounts.retain(|a| !w.accounts.contains(a));
        }
        match self.list.iter_mut().find(|o| o.id == w.id) {
            Some(o) => *o = w,
            None => self.list.push(w),
        }
        self.save()
    }

    pub fn remove(&mut self, id: &str, known: &[String]) -> std::io::Result<()> {
        let view = self.view(known);
        if view.len() <= 1 {
            return Err(std::io::Error::other("o último workspace fica"));
        }
        self.list = view;
        self.list.retain(|w| w.id != id);
        self.save()
    }

    /// Puts `account` in workspace `id` (a new account).
    pub fn assign(&mut self, account: &str, id: &str, known: &[String]) -> std::io::Result<()> {
        let mut w = self
            .view(known)
            .into_iter()
            .find(|w| w.id == id)
            .ok_or_else(|| std::io::Error::other(format!("workspace desconhecido: {id}")))?;
        if !w.accounts.iter().any(|a| a == account) {
            w.accounts.push(account.into());
        }
        self.upsert(w, known)
    }

    fn save(&self) -> std::io::Result<()> {
        match &self.file {
            Some(f) => std::fs::write(f, serde_json::to_vec_pretty(&self.list)?),
            None => Ok(()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ws(id: &str, accounts: &[&str]) -> WorkspaceInfo {
        WorkspaceInfo { id: id.into(), name: id.to_uppercase(), accounts: accounts.iter().map(|a| a.to_string()).collect(), memory: None, budget_usd: None }
    }

    #[test]
    fn workspaces_own_accounts_and_persist() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("workspaces.json");
        let known = vec!["a".to_string(), "b".to_string(), "c".to_string()];
        let mut w = Workspaces::load(Some(file.clone()));
        assert_eq!(w.view(&known), [WorkspaceInfo { id: "default".into(), name: "Este Mac".into(), accounts: known.clone(), memory: None, budget_usd: None }]);

        w.upsert(ws("trabalho", &["a", "b"]), &known).unwrap();
        let v = w.view(&known);
        assert_eq!(v.iter().map(|w| (w.id.as_str(), w.accounts.len())).collect::<Vec<_>>(), [("default", 1), ("trabalho", 2)]);
        // Moving an account takes it out of the other workspace.
        w.upsert(ws("pessoal", &["b"]), &known).unwrap();
        let v = Workspaces::load(Some(file.clone())).view(&known);
        assert_eq!(v[1].accounts, ["a"]);
        assert_eq!(v[2].accounts, ["b"]);

        assert!(w.upsert(ws("x", &["nope"]), &known).is_err());
        assert!(w.upsert(ws("../x", &[]), &known).is_err());
        w.remove("default", &known).unwrap();
        // c had nowhere to go: it shows in the first workspace.
        assert_eq!(w.view(&known)[0].accounts, ["a", "c"]);
        w.remove("pessoal", &known).unwrap();
        assert!(w.remove("trabalho", &known).is_err(), "the last one stays");
        w.assign("d", "trabalho", &[known.clone(), vec!["d".into()]].concat()).unwrap();
        assert!(w.view(&[known, vec!["d".into()]].concat())[0].accounts.contains(&"d".to_string()));
    }
}
