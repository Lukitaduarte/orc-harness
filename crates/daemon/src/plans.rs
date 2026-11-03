//! Plans and their execution. A plan is `~/.orc/plans/<id>/plan.md` plus
//! the review state the app keeps (`state.json`). Once started, its loops
//! (cards) run as worktree sessions; GitHub moves them: an open PR means
//! review, a merged PR means done, and done cards free their dependents.

use std::path::PathBuf;

use orc_protocol::{CardRun, CardSpec, PlanDoc};
use serde::{Deserialize, Serialize};

/// Loops running at the same time per plan.
pub const MAX_RUNNING: usize = 3;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Run {
    pub plan_id: String,
    pub project_id: String,
    pub account_id: String,
    pub specs: Vec<CardSpec>,
    pub cards: Vec<CardRun>,
}

impl Run {
    pub fn new(plan_id: &str, project_id: &str, account_id: &str, specs: Vec<CardSpec>) -> Self {
        let cards = specs
            .iter()
            .map(|s| CardRun {
                number: s.number,
                state: "todo".into(),
                session_id: None,
                branch: s.branch.clone(),
                pr: None,
                pr_url: None,
                note: None,
                account_id: None,
            })
            .collect();
        Self { plan_id: plan_id.into(), project_id: project_id.into(), account_id: account_id.into(), specs, cards }
    }

    fn state_of(&self, n: u32) -> Option<&str> {
        self.cards.iter().find(|c| c.number == n).map(|c| c.state.as_str())
    }

    /// Cards to start now: every dependency done, within the limit.
    pub fn ready_to_start(&self) -> Vec<CardSpec> {
        let running = self.cards.iter().filter(|c| c.state == "running" || c.state == "review").count();
        let room = MAX_RUNNING.saturating_sub(running);
        self.specs
            .iter()
            .filter(|s| self.state_of(s.number) == Some("todo"))
            .filter(|s| s.depends_on.iter().all(|d| self.state_of(*d) == Some("done")))
            .take(room)
            .cloned()
            .collect()
    }

    pub fn card_mut(&mut self, n: u32) -> Option<&mut CardRun> {
        self.cards.iter_mut().find(|c| c.number == n)
    }

    /// Applies a PR status (`gh pr view` JSON) to the card on `branch`.
    /// Returns true when the card moved.
    pub fn apply_pr(&mut self, branch: &str, pr: &serde_json::Value) -> bool {
        let Some(card) = self.cards.iter_mut().find(|c| c.branch == branch) else { return false };
        let before = (card.state.clone(), card.pr);
        card.pr = pr["number"].as_u64();
        card.pr_url = pr["url"].as_str().map(String::from);
        match pr["state"].as_str() {
            Some("MERGED") => card.state = "done".into(),
            Some("OPEN") if card.state == "running" => card.state = "review".into(),
            _ => {}
        }
        before != (card.state.clone(), card.pr)
    }

    pub fn finished(&self) -> bool {
        self.cards.iter().all(|c| c.state == "done")
    }

    /// Some card has a session or a PR out.
    pub fn active(&self) -> bool {
        self.cards.iter().any(|c| c.state == "running" || c.state == "review")
    }

    /// Checks the cards before a run starts: unique numbers and branches,
    /// valid branch names, dependencies on cards of the plan, no cycles.
    pub fn validate(specs: &[CardSpec]) -> Result<(), String> {
        use std::collections::HashSet;
        let numbers: HashSet<u32> = specs.iter().map(|s| s.number).collect();
        let branches: HashSet<&str> = specs.iter().map(|s| s.branch.as_str()).collect();
        if specs.is_empty() {
            return Err("o plano não tem cards".into());
        }
        if numbers.len() != specs.len() || branches.len() != specs.len() {
            return Err("cards com número ou branch repetidos".into());
        }
        for s in specs {
            if !crate::git::valid_branch(&s.branch) {
                return Err(format!("branch inválida no card {}: {}", s.number, s.branch));
            }
            if let Some(d) = s.depends_on.iter().find(|d| !numbers.contains(d)) {
                return Err(format!("o card {} depende do {d}, que não existe", s.number));
            }
        }
        // Peel cards whose dependencies are all peeled; leftovers form a cycle.
        let mut done: HashSet<u32> = HashSet::new();
        while done.len() < specs.len() {
            let before = done.len();
            for s in specs {
                if s.depends_on.iter().all(|d| done.contains(d)) {
                    done.insert(s.number);
                }
            }
            if done.len() == before {
                return Err("dependências em ciclo entre os cards".into());
            }
        }
        Ok(())
    }
}

pub struct Plans {
    dir: PathBuf,
    pub docs: Vec<PlanDoc>,
    pub runs: Vec<Run>,
}

fn valid_id(id: &str) -> bool {
    !id.is_empty() && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

impl Plans {
    pub fn load(dir: PathBuf) -> Self {
        let mut docs = Vec::new();
        let mut runs = Vec::new();
        for entry in std::fs::read_dir(&dir).into_iter().flatten().flatten() {
            let p = entry.path();
            let read = |name: &str| std::fs::read(p.join(name)).ok();
            if let Some(meta) = read("meta.json").and_then(|b| serde_json::from_slice::<PlanDoc>(&b).ok()) {
                let markdown = read("plan.md").map(|b| String::from_utf8_lossy(&b).into_owned()).unwrap_or_default();
                // Sessions do not outlive the daemon.
                docs.push(PlanDoc { markdown, planner: None, busy: false, ..meta });
            }
            if let Some(run) = read("run.json").and_then(|b| serde_json::from_slice::<Run>(&b).ok()) {
                runs.push(run);
            }
        }
        docs.sort_by(|a, b| a.id.cmp(&b.id));
        Self { dir, docs, runs }
    }

    fn folder(&self, id: &str) -> std::io::Result<PathBuf> {
        if !valid_id(id) {
            return Err(std::io::Error::other(format!("id de plano inválido: {id}")));
        }
        Ok(self.dir.join(id))
    }

    /// A save from the app: a new plan, or new name and review state for a
    /// known one (its markdown and planner fields are the daemon's).
    pub fn save_from_app(&mut self, doc: PlanDoc) -> std::io::Result<()> {
        let doc = match self.docs.iter().find(|d| d.id == doc.id) {
            Some(known) => PlanDoc { name: doc.name, state: doc.state, ..known.clone() },
            None => PlanDoc { planner: None, revision: 0, busy: false, ..doc },
        };
        self.save(doc)
    }

    pub fn doc_mut(&mut self, id: &str) -> Option<&mut PlanDoc> {
        self.docs.iter_mut().find(|d| d.id == id)
    }

    pub fn save(&mut self, doc: PlanDoc) -> std::io::Result<()> {
        let folder = self.folder(&doc.id)?;
        std::fs::create_dir_all(&folder)?;
        std::fs::write(folder.join("plan.md"), &doc.markdown)?;
        // meta.json keeps everything but the markdown.
        let meta = PlanDoc { markdown: String::new(), ..doc.clone() };
        std::fs::write(folder.join("meta.json"), serde_json::to_vec_pretty(&meta)?)?;
        match self.docs.iter_mut().find(|d| d.id == doc.id) {
            Some(d) => *d = doc,
            None => self.docs.push(doc),
        }
        Ok(())
    }

    pub fn remove(&mut self, id: &str) -> std::io::Result<()> {
        let folder = self.folder(id)?;
        let _ = std::fs::remove_dir_all(folder);
        self.docs.retain(|d| d.id != id);
        self.runs.retain(|r| r.plan_id != id);
        Ok(())
    }

    pub fn save_run(&self, run: &Run) -> std::io::Result<()> {
        let folder = self.folder(&run.plan_id)?;
        std::fs::create_dir_all(&folder)?;
        std::fs::write(folder.join("run.json"), serde_json::to_vec_pretty(run)?)
    }

    pub fn run_mut(&mut self, plan_id: &str) -> Option<&mut Run> {
        self.runs.iter_mut().find(|r| r.plan_id == plan_id)
    }
}

/// What the planning session is told when it starts.
pub fn planner_prompt(doc: &PlanDoc, repo: &str, request: &str) -> String {
    format!(
        "Você é a sessão de planejamento do harness para o plano \"{name}\" do repositório {repo}.\n\
         Não altere código nem faça commits: leia o código e as fontes e escreva o plano.\n\
         Formato: mantenha as seções `##` e a instrução de cada uma (comentário <!-- -->), \
         diagramas em ```mermaid (flowchart ou sequenceDiagram) e o bloco ```loops em YAML \
         (cada loop é um PR: title, type, model, depends_on, description, criteria, tasks).\n\
         Sempre que terminar um pedido, chame a tool save_plan (MCP orc) com o markdown completo. \
         Em revisões, responda cada comentário em `replies` ({{thread, body, resolve}}). \
         Seções aprovadas não mudam: pedidos sobre elas vão em `amendments`.\n\n\
         Plano atual:\n\n{markdown}\n\nPedido:\n{request}",
        name = doc.name,
        markdown = doc.markdown,
    )
}

/// Applies a `save_plan` call to `doc`: new markdown, and in the review
/// state the agent's replies (`state.threads[].messages`, by thread id)
/// and amendments (`state.amendments`). Returns what was not applied.
pub fn apply_save(doc: &mut PlanDoc, markdown: &str, replies: &[serde_json::Value], amendments: &[String], now_ms: u64) -> Vec<String> {
    use serde_json::{Value, json};
    let mut skipped = Vec::new();
    doc.markdown = markdown.into();
    doc.revision += 1;
    doc.busy = false;
    if !doc.state.is_object() {
        doc.state = json!({});
    }
    let state = doc.state.as_object_mut().expect("object");
    let threads = state.entry("threads").or_insert_with(|| json!([]));
    for r in replies {
        let (Some(id), Some(body)) = (r["thread"].as_str(), r["body"].as_str()) else {
            skipped.push(format!("resposta sem thread/body: {r}"));
            continue;
        };
        let thread = threads.as_array_mut().and_then(|ts| ts.iter_mut().find(|t| t["id"] == id));
        let Some(thread) = thread else {
            skipped.push(format!("comentário {id} não existe"));
            continue;
        };
        if !thread["messages"].is_array() {
            thread["messages"] = json!([]);
        }
        thread["messages"].as_array_mut().expect("array").push(json!({ "author": "Claude", "body": body, "at": now_ms }));
        if r["resolve"].as_bool().unwrap_or(false) {
            thread["resolved"] = Value::Bool(true);
        }
    }
    if !amendments.is_empty() {
        let list = state.entry("amendments").or_insert_with(|| json!([]));
        if let Some(list) = list.as_array_mut() {
            list.extend(amendments.iter().map(|a| json!(a)));
        }
    }
    skipped
}

/// What a card's session is told when it starts.
pub fn card_prompt(spec_prompt: &str, branch: &str) -> String {
    format!(
        "{spec_prompt}\n\n\
         Você está na worktree da branch {branch}, criada pelo harness para este card.\n\
         - Siga os grupos de tarefas em ordem; tarefas do mesmo grupo podem ir para subagentes em paralelo, com o modelo indicado.\n\
         - Commits em conventional commits (o hook recusa outros).\n\
         - Ao terminar e com os testes passando, faça push e abra um PR em rascunho com `gh pr create --draft --fill`.\n\
         - Se algo do plano não couber ou faltar decisão, pare e pergunte."
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn spec(n: u32, deps: &[u32]) -> CardSpec {
        CardSpec {
            number: n,
            title: format!("card {n}"),
            branch: format!("feat/{n}"),
            model: None,
            depends_on: deps.to_vec(),
            prompt: String::new(),
        }
    }

    #[test]
    fn dependencies_limit_and_github_move_cards() {
        let mut run = Run::new("p", "proj", "work", vec![spec(1, &[]), spec(2, &[1]), spec(3, &[]), spec(4, &[]), spec(5, &[])]);
        let first: Vec<u32> = run.ready_to_start().iter().map(|s| s.number).collect();
        assert_eq!(first, [1, 3, 4], "no deps first, at most {MAX_RUNNING}");
        for n in first {
            run.card_mut(n).unwrap().state = "running".into();
        }
        assert!(run.ready_to_start().is_empty(), "limit reached");

        assert!(run.apply_pr("feat/1", &json!({ "number": 7, "state": "OPEN", "url": "https://github.com/x/y/pull/7" })));
        assert_eq!(run.cards[0].state, "review");
        assert!(!run.apply_pr("feat/1", &json!({ "number": 7, "state": "OPEN", "url": "https://github.com/x/y/pull/7" })));
        assert!(run.apply_pr("feat/1", &json!({ "number": 7, "state": "MERGED" })));
        // #1 done frees #2; one slot is free again.
        let next: Vec<u32> = run.ready_to_start().iter().map(|s| s.number).collect();
        assert_eq!(next, [2]);
        assert!(!run.finished());
    }

    #[test]
    fn app_saves_keep_the_planners_markdown_and_replies_land_in_threads() {
        let dir = tempfile::tempdir().unwrap();
        let mut plans = Plans::load(dir.path().to_path_buf());
        let doc = PlanDoc { id: "p".into(), name: "P".into(), markdown: "# v1".into(), ..PlanDoc::default() };
        plans.save_from_app(doc.clone()).unwrap();
        let state = json!({ "threads": [{ "id": "t1", "anchor": "fontes", "resolved": false,
                                          "messages": [{ "author": "Você", "body": "e o iOS?", "at": 1 }] }] });
        let d = plans.doc_mut("p").unwrap();
        d.state = state;
        d.planner = Some("s1".into());
        d.busy = true;
        let skipped = apply_save(d, "# v2", &[json!({ "thread": "t1", "body": "incluí", "resolve": true }),
                                              json!({ "thread": "nope", "body": "x" })], &["Fontes: iOS".into()], 5);
        assert_eq!(skipped.len(), 1);
        // The app saves its review state, with a stale markdown: ignored.
        let mut from_app = plans.docs[0].clone();
        from_app.markdown = "# v1".into();
        from_app.planner = None;
        from_app.name = "Push".into();
        plans.save_from_app(from_app).unwrap();
        let d = &plans.docs[0];
        assert_eq!((d.markdown.as_str(), d.name.as_str(), d.planner.as_deref(), d.revision, d.busy), ("# v2", "Push", Some("s1"), 1, false));
        assert_eq!(d.state["threads"][0]["messages"][1]["body"], "incluí");
        assert_eq!(d.state["threads"][0]["resolved"], true);
        assert_eq!(d.state["amendments"], json!(["Fontes: iOS"]));
        // After a restart the planner is gone.
        plans.save(d.clone()).unwrap();
        assert_eq!(Plans::load(dir.path().to_path_buf()).docs[0].planner, None);
    }

    #[test]
    fn cards_are_validated() {
        assert!(Run::validate(&[spec(1, &[]), spec(2, &[1])]).is_ok());
        assert!(Run::validate(&[]).is_err());
        assert!(Run::validate(&[spec(1, &[2])]).unwrap_err().contains("não existe"));
        assert!(Run::validate(&[spec(1, &[2]), spec(2, &[1])]).unwrap_err().contains("ciclo"));
        let mut bad = spec(1, &[]);
        bad.branch = "feat/../x".into();
        assert!(Run::validate(&[bad]).is_err());
        assert!(Run::validate(&[spec(1, &[]), spec(1, &[])]).is_err());
    }

    #[test]
    fn plans_persist_and_ids_are_checked() {
        let dir = tempfile::tempdir().unwrap();
        let mut plans = Plans::load(dir.path().to_path_buf());
        let doc = PlanDoc {
            id: "push".into(),
            project_id: "web".into(),
            name: "Push".into(),
            markdown: "# Push\n\n## Fontes\n".into(),
            state: json!({ "approvals": { "fontes": { "digest": "ab" } } }),
            revision: 2,
            ..PlanDoc::default()
        };
        plans.save(doc.clone()).unwrap();
        let run = Run::new("push", "web", "work", vec![spec(1, &[])]);
        plans.runs.push(run.clone());
        plans.save_run(&run).unwrap();

        let again = Plans::load(dir.path().to_path_buf());
        assert_eq!(again.docs, [doc]);
        assert_eq!(again.runs, [run]);
        let bad = PlanDoc { id: "../x".into(), ..again.docs[0].clone() };
        assert!(Plans::load(dir.path().to_path_buf()).save(bad).is_err());
    }
}
