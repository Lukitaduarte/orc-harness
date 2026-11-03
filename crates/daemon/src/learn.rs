//! Learn: comments on a plan's cards become proposed edits to the skills
//! that had the gap. A Claude session reads the comments and the skills and
//! proposes each edit through `propose_learning` (replace one passage of a
//! skill file); nothing is written until you accept it in the app.

use std::path::{Path, PathBuf};

use orc_protocol::LearningItem;

/// A skill file shown to the learner is cut at this size.
const MAX_SKILL_TEXT: usize = 40 * 1024;

/// Learnings of a plan: `plans/<id>/learnings.json`.
pub fn load(plan_dir: &Path) -> Vec<LearningItem> {
    std::fs::read(plan_dir.join("learnings.json"))
        .ok()
        .and_then(|raw| serde_json::from_slice(&raw).ok())
        .unwrap_or_default()
}

pub fn save(plan_dir: &Path, items: &[LearningItem]) -> std::io::Result<()> {
    std::fs::create_dir_all(plan_dir)?;
    std::fs::write(plan_dir.join("learnings.json"), serde_json::to_vec_pretty(items)?)
}

/// What the learning session is told: the comments and each skill's
/// SKILL.md (inline, so it never reads outside its folder).
pub fn learner_prompt(plan_name: &str, notes: &[String], skills: &[(String, PathBuf)]) -> String {
    let mut out = format!(
        "Você é a sessão de aprendizado do harness para o plano \"{plan_name}\".\n\
         Os comentários abaixo foram feitos por pessoas nos cards. Para cada lacuna que eles \
         revelam, proponha uma mudança na skill responsável com a tool propose_learning \
         (MCP orc): skill (nome), file (relativo à pasta da skill, ex. SKILL.md), summary \
         (uma frase), old (trecho atual, que aparece exatamente uma vez; vazio para acrescentar \
         ao fim) e new (o trecho novo), source (qual comentário).\n\
         Não edite arquivos você mesmo: só proponha. Mudanças pequenas e precisas. \
         Se um comentário não pede mudança em skill, ignore.\n\nComentários:\n"
    );
    for n in notes {
        out.push_str(&format!("- {n}\n"));
    }
    for (name, dir) in skills {
        let text = std::fs::read_to_string(dir.join("SKILL.md")).unwrap_or_default();
        let cut: String = text.chars().take(MAX_SKILL_TEXT).collect();
        out.push_str(&format!("\n--- skill {name} ({}/SKILL.md) ---\n{cut}\n", dir.display()));
    }
    out
}

/// Applies an accepted learning to the skill folder `dir`: `old` must
/// appear exactly once in the file (an empty `old` appends `new`). The
/// file never leaves the folder.
pub fn apply(dir: &Path, item: &LearningItem) -> std::io::Result<()> {
    let path = crate::ide::resolve(dir, &item.file)?;
    let text = std::fs::read_to_string(&path).unwrap_or_default();
    let next = if item.old.is_empty() {
        let sep = if text.is_empty() || text.ends_with('\n') { "" } else { "\n" };
        format!("{text}{sep}{}\n", item.new.trim_end())
    } else {
        match text.matches(&item.old).count() {
            1 => text.replacen(&item.old, &item.new, 1),
            0 => return Err(std::io::Error::other("o trecho atual não está mais no arquivo")),
            _ => return Err(std::io::Error::other("o trecho atual aparece mais de uma vez")),
        }
    };
    std::fs::write(path, next)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(file: &str, old: &str, new: &str) -> LearningItem {
        LearningItem {
            id: "l1".into(),
            skill: "s".into(),
            file: file.into(),
            summary: "x".into(),
            old: old.into(),
            new: new.into(),
            source: "card 1".into(),
            status: "pending".into(),
            error: None,
        }
    }

    #[test]
    fn edits_land_once_inside_the_skill() {
        let dir = tempfile::tempdir().unwrap();
        let skill = dir.path().join("skill");
        std::fs::create_dir_all(&skill).unwrap();
        std::fs::write(skill.join("SKILL.md"), "# Skill\n\nUse testes.\n").unwrap();

        apply(&skill, &item("SKILL.md", "Use testes.", "Use testes de widget e golden.")).unwrap();
        apply(&skill, &item("SKILL.md", "", "## Release\nSempre peça OK.")).unwrap();
        assert_eq!(
            std::fs::read_to_string(skill.join("SKILL.md")).unwrap(),
            "# Skill\n\nUse testes de widget e golden.\n## Release\nSempre peça OK.\n"
        );
        assert!(apply(&skill, &item("SKILL.md", "não existe", "x")).is_err());
        std::fs::write(skill.join("dup.md"), "a a").unwrap();
        assert!(apply(&skill, &item("dup.md", "a", "b")).is_err());
        assert!(apply(&skill, &item("../fora.md", "", "x")).is_err());
        assert!(!dir.path().join("fora.md").exists());

        let prompt = learner_prompt("Push", &["card 2: faltou o golden".into()], &[("s".into(), skill)]);
        assert!(prompt.contains("faltou o golden") && prompt.contains("Use testes de widget"));
    }
}
