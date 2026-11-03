//! Git for the harness: worktrees per branch, conventional commits enforced
//! per worktree, diffs against the base, and code search. Everything runs
//! the `git` CLI, the same tool the agents use.

use std::path::{Path, PathBuf};
use std::process::Command;

use orc_protocol::{DiffFile, SearchHit};
use regex::Regex;

fn git(dir: &Path, args: &[&str]) -> std::io::Result<String> {
    let out = Command::new("git").arg("-C").arg(dir).args(args).output()?;
    if !out.status.success() {
        return Err(std::io::Error::other(format!(
            "git {}: {}",
            args.join(" "),
            String::from_utf8_lossy(&out.stderr).trim()
        )));
    }
    Ok(String::from_utf8_lossy(&out.stdout).into_owned())
}

/// Branch names the harness accepts: `type/slug` style, no tricks.
pub fn valid_branch(name: &str) -> bool {
    !name.is_empty()
        && !name.starts_with(['-', '/', '.'])
        && !name.ends_with(['/', '.'])
        && !name.contains("..")
        && !name.contains("//")
        && !name.ends_with(".lock")
        && name.chars().all(|c| c.is_ascii_alphanumeric() || "._/-".contains(c))
}

pub fn is_repo(dir: &Path) -> bool {
    git(dir, &["rev-parse", "--git-dir"]).is_ok()
}

/// Creates (or reuses) the worktree of `branch`. A new branch starts from
/// `base`.
pub fn worktree_add(repo: &Path, path: &Path, branch: &str, base: &str) -> std::io::Result<()> {
    if !valid_branch(branch) || !valid_branch(base) {
        return Err(std::io::Error::other(format!("nome de branch inválido: {branch}")));
    }
    if path.exists() {
        return Ok(());
    }
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let p = path.to_string_lossy();
    let exists = git(repo, &["rev-parse", "--verify", "--quiet", &format!("refs/heads/{branch}")]).is_ok();
    if exists {
        git(repo, &["worktree", "add", &p, branch])?;
    } else {
        git(repo, &["worktree", "add", "-b", branch, &p, base])?;
    }
    Ok(())
}

pub fn worktree_remove(repo: &Path, path: &Path) -> std::io::Result<()> {
    git(repo, &["worktree", "remove", "--force", &path.to_string_lossy()]).map(|_| ())
}

/// Points the worktree (only it) at the harness hooks, whose commit-msg
/// runs `orc-commit-check`. The main clone's hooks are untouched.
pub fn enable_commit_check(repo: &Path, worktree: &Path, hooks_dir: &Path, checker: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(hooks_dir)?;
    let hook = hooks_dir.join("commit-msg");
    std::fs::write(&hook, format!("#!/bin/sh\nexec \"{}\" \"$1\"\n", checker.display()))?;
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(&hook, std::fs::Permissions::from_mode(0o755))?;
    git(repo, &["config", "extensions.worktreeConfig", "true"])?;
    git(worktree, &["config", "--worktree", "core.hooksPath", &hooks_dir.to_string_lossy()])?;
    Ok(())
}

/// Conventional commit check for the first line of a message. Merge and
/// revert messages from git itself and fixup/squash commits pass.
pub fn check_commit_message(msg: &str) -> Result<(), String> {
    let first = msg
        .lines()
        .find(|l| !l.trim().is_empty() && !l.starts_with('#'))
        .unwrap_or("")
        .trim();
    if first.starts_with("Merge ") || first.starts_with("Revert \"") {
        return Ok(());
    }
    if first.starts_with("fixup! ") || first.starts_with("squash! ") || first.starts_with("amend! ") {
        return Ok(());
    }
    let re = Regex::new(
        r"^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9][a-z0-9._/-]*\))?!?: \S.*$",
    )
    .expect("valid regex");
    if !re.is_match(first) {
        return Err(format!(
            "commit fora do padrão conventional commits: \"{first}\"\n\
             use tipo(escopo opcional): descrição, por exemplo \"feat(api): paginação por cursor\".\n\
             tipos: feat fix docs style refactor perf test build ci chore revert"
        ));
    }
    if first.chars().count() > 100 {
        return Err("a primeira linha do commit passa de 100 caracteres".into());
    }
    Ok(())
}

/// Changes since the branch left `base`: committed and not yet committed
/// (tracked files), plus untracked files by name.
pub fn diff(worktree: &Path, base: &str) -> std::io::Result<Vec<DiffFile>> {
    let merge_base = git(worktree, &["merge-base", base, "HEAD"])?.trim().to_string();
    let names = git(worktree, &["diff", "--name-status", "--no-renames", &merge_base])?;
    let patch = git(worktree, &["diff", "--no-color", "--no-ext-diff", "--no-renames", &merge_base])?;

    // Split the full patch per file at each "diff --git" header.
    let mut patches: Vec<(String, String)> = Vec::new();
    for chunk in patch.split("\ndiff --git ").enumerate().map(|(i, c)| {
        if i == 0 { c.trim_start_matches("diff --git ").to_string() } else { c.to_string() }
    }) {
        if chunk.trim().is_empty() {
            continue;
        }
        // "a/path b/path\n..."
        let header = chunk.lines().next().unwrap_or_default();
        let path = header.rsplit(" b/").next().unwrap_or_default().to_string();
        patches.push((path, format!("diff --git {chunk}")));
    }

    let mut files: Vec<DiffFile> = names
        .lines()
        .filter_map(|l| {
            let (status, path) = l.split_once('\t')?;
            let patch = patches.iter().find(|(p, _)| p == path).map(|(_, x)| x.clone()).unwrap_or_default();
            Some(DiffFile { path: path.into(), status: status.into(), patch })
        })
        .collect();
    for path in git(worktree, &["ls-files", "--others", "--exclude-standard"])?.lines() {
        files.push(DiffFile { path: path.into(), status: "?".into(), patch: String::new() });
    }
    Ok(files)
}

/// Text search under `root`, honoring .gitignore. Binary and very large
/// files are skipped. Returns the hits and whether it stopped at `max`.
pub fn search(root: &Path, query: &str, regex: bool, max: usize) -> Result<(Vec<SearchHit>, bool), String> {
    let pattern = if regex { query.to_string() } else { regex::escape(query) };
    let re = regex::RegexBuilder::new(&pattern)
        .case_insensitive(!query.chars().any(char::is_uppercase))
        .build()
        .map_err(|e| format!("regex inválida: {e}"))?;
    let mut hits = Vec::new();
    for entry in ignore::WalkBuilder::new(root).hidden(true).build().flatten() {
        let path = entry.path();
        if !entry.file_type().is_some_and(|t| t.is_file()) {
            continue;
        }
        if std::fs::metadata(path).map(|m| m.len() > 2_000_000).unwrap_or(true) {
            continue;
        }
        let Ok(bytes) = std::fs::read(path) else { continue };
        if bytes.iter().take(8000).any(|b| *b == 0) {
            continue;
        }
        let text = String::from_utf8_lossy(&bytes);
        for (i, line) in text.lines().enumerate() {
            if re.is_match(line) {
                if hits.len() == max {
                    return Ok((hits, true));
                }
                hits.push(SearchHit {
                    path: path.strip_prefix(root).unwrap_or(path).to_string_lossy().into_owned(),
                    line: i as u32 + 1,
                    text: line.chars().take(300).collect(),
                });
            }
        }
    }
    Ok((hits, false))
}

pub fn worktree_path(root: &Path, project_id: &str, branch: &str) -> PathBuf {
    root.join(project_id).join(branch.replace('/', "__"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn repo() -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path();
        for args in [
            vec!["init", "-q", "-b", "main"],
            vec!["config", "user.email", "t@t"],
            vec!["config", "user.name", "t"],
            vec!["config", "commit.gpgsign", "false"],
        ] {
            git(p, &args).unwrap();
        }
        std::fs::write(p.join("a.txt"), "one\ntwo\n").unwrap();
        std::fs::write(p.join(".gitignore"), "ignored/\n").unwrap();
        git(p, &["add", "."]).unwrap();
        git(p, &["commit", "-q", "-m", "chore: init"]).unwrap();
        dir
    }

    #[test]
    fn commit_messages() {
        for ok in [
            "feat: x",
            "fix(api): paginação por cursor",
            "feat(app/ui)!: quebra",
            "chore: x\n\ncorpo",
            "Merge branch 'main'",
            "fixup! feat: x",
            "# comentário\nfeat: x",
        ] {
            assert!(check_commit_message(ok).is_ok(), "{ok}");
        }
        for bad in ["wip", "Feat: x", "feat:x", "feat(Api): x", "", "feature: x"] {
            assert!(check_commit_message(bad).is_err(), "{bad}");
        }
        assert!(check_commit_message(&format!("feat: {}", "x".repeat(100))).is_err());
    }

    #[test]
    fn branches() {
        assert!(valid_branch("feat/3-get-users"));
        for bad in ["", "-x", "a..b", "a b", "x/", "a//b", "x.lock", "$(rm)"] {
            assert!(!valid_branch(bad), "{bad}");
        }
    }

    #[test]
    fn worktree_hook_diff_and_search() {
        let r = repo();
        let root = tempfile::tempdir().unwrap();
        let wt = worktree_path(root.path(), "proj", "feat/1-x");
        worktree_add(r.path(), &wt, "feat/1-x", "main").unwrap();
        worktree_add(r.path(), &wt, "feat/1-x", "main").unwrap(); // idempotent
        assert_eq!(git(&wt, &["branch", "--show-current"]).unwrap().trim(), "feat/1-x");

        // The hook only applies to this worktree.
        let checker = root.path().join("check.sh");
        std::fs::write(&checker, "#!/bin/sh\ngrep -qE '^(feat|fix|chore)(\\(.+\\))?: ' \"$1\"\n").unwrap();
        std::fs::set_permissions(&checker, std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
        enable_commit_check(r.path(), &wt, &root.path().join("hooks"), &checker).unwrap();
        std::fs::write(wt.join("a.txt"), "one\nTWO\n").unwrap();
        git(&wt, &["commit", "-qam", "wip"]).expect_err("hook must refuse");
        git(&wt, &["commit", "-qam", "feat: dois"]).unwrap();
        // The main clone commits freely.
        std::fs::write(r.path().join("b.txt"), "b").unwrap();
        git(r.path(), &["add", "b.txt"]).unwrap();
        git(r.path(), &["commit", "-qm", "anything"]).unwrap();

        // Diff: the commit, an uncommitted edit and an untracked file.
        std::fs::write(wt.join("a.txt"), "one\nTWO\nthree\n").unwrap();
        std::fs::write(wt.join("new.txt"), "n").unwrap();
        let files = diff(&wt, "main").unwrap();
        assert_eq!(files.len(), 2);
        assert_eq!((files[0].path.as_str(), files[0].status.as_str()), ("a.txt", "M"));
        assert!(files[0].patch.contains("+TWO") && files[0].patch.contains("+three"));
        assert_eq!((files[1].path.as_str(), files[1].status.as_str()), ("new.txt", "?"));

        // Search honors .gitignore and smart case.
        std::fs::create_dir_all(wt.join("ignored")).unwrap();
        std::fs::write(wt.join("ignored/x.txt"), "two").unwrap();
        let (hits, more) = search(&wt, "two", false, 10).unwrap();
        assert!(!more);
        assert_eq!(hits.len(), 1);
        assert_eq!((hits[0].path.as_str(), hits[0].line), ("a.txt", 2));
        assert!(search(&wt, "TWO", false, 10).unwrap().0.len() == 1);
        assert!(search(&wt, "(", true, 10).is_err());

        worktree_remove(r.path(), &wt).unwrap();
        assert!(!wt.exists());
    }
}
