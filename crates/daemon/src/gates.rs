//! Actions that reach outside and need your OK even with the plan approved:
//! deploys, releases, infrastructure changes, pushes to the main branch and
//! merges. The session's PreToolUse hook (`orc-hook`) checks each tool call
//! here; a match waits for your decision in the app.

use std::sync::LazyLock;

use regex::Regex;
use serde_json::Value;

static COMMANDS: LazyLock<Vec<(Regex, &'static str)>> = LazyLock::new(|| {
    [
        (r"\brailway\s+(up|deploy|redeploy)\b", "deploy no Railway"),
        (r"\bgcloud\b.*\b(deploy|app\s+deploy)\b", "deploy no Google Cloud"),
        (r"\baws\b.*\b(deploy|update-function-code|update-service|create-deployment)\b", "deploy na AWS"),
        (r"\b(cdk|sam|serverless|sls)\s+deploy\b", "deploy na AWS"),
        (r"\bfirebase\s+deploy\b", "deploy no Firebase"),
        (r"\bvercel\b.*(--prod\b|\bdeploy\b.*--prod)", "deploy em produção na Vercel"),
        (r"\bnetlify\s+deploy\b.*--prod\b", "deploy em produção na Netlify"),
        (r"\b(fly|flyctl)\s+deploy\b", "deploy no Fly.io"),
        (r"\bfastlane\b.*\b(release|deliver|supply|beta|upload_to_\w+|pilot)\b", "release nas lojas (fastlane)"),
        (r"\bxcrun\s+altool\b.*--upload", "upload para a App Store"),
        (r"\bkubectl\s+(apply|rollout|delete|scale|set)\b", "mudança no Kubernetes"),
        (r"\bhelm\s+(install|upgrade|uninstall|rollback)\b", "mudança no Kubernetes (helm)"),
        (r"\b(terraform|tofu|pulumi)\s+(apply|destroy|up)\b", "mudança de infraestrutura"),
        (r"\bgit\s+push\b.*\b(main|master|production|prod|release)\b", "push na branch principal"),
        (r"\bgit\s+push\b.*(--force\b|\s-f\b)", "push forçado"),
        (r"\bgh\s+pr\s+merge\b", "merge de PR"),
        (r"\bgh\s+release\s+create\b", "release no GitHub"),
        (r"\b(npm|pnpm|yarn)\s+publish\b|\bcargo\s+publish\b|\bflutter\s+pub\s+publish\b", "publicação de pacote"),
    ]
    .into_iter()
    .map(|(r, why)| (Regex::new(r).expect("valid gate pattern"), why))
    .collect()
});

/// Why `tool` with `input` needs your OK, if it does.
pub fn needs_ok(tool: &str, input: &Value) -> Option<String> {
    if tool == "Bash" {
        let cmd = input["command"].as_str().unwrap_or_default();
        return COMMANDS
            .iter()
            .find(|(re, _)| re.is_match(cmd))
            .map(|(_, why)| format!("{why}: {}", cmd.chars().take(300).collect::<String>()));
    }
    // MCP tools named like a deploy or release (mcp__railway__deploy…).
    if let Some(rest) = tool.strip_prefix("mcp__") {
        let name = rest.to_lowercase();
        let outward = ["deploy", "release", "publish", "promote", "rollback", "destroy"];
        if outward.iter().any(|w| name.contains(w)) {
            return Some(format!("{tool} {}", input.to_string().chars().take(300).collect::<String>()));
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn bash(cmd: &str) -> Option<String> {
        needs_ok("Bash", &json!({ "command": cmd }))
    }

    #[test]
    fn deploys_and_releases_need_ok_everyday_work_does_not() {
        for cmd in [
            "railway up --service api",
            "gcloud run deploy api --region us-central1",
            "aws lambda update-function-code --function-name f",
            "firebase deploy --only hosting",
            "vercel --prod",
            "fly deploy",
            "cd ios && bundle exec fastlane release",
            "kubectl apply -f k8s/",
            "terraform apply -auto-approve",
            "git push origin main",
            "git push --force origin feat/x",
            "gh pr merge 12 --squash",
            "npm publish",
        ] {
            assert!(bash(cmd).is_some(), "{cmd}");
        }
        for cmd in [
            "git push -u origin feat/3-login",
            "gh pr create --draft --fill",
            "flutter test",
            "cargo build --release",
            "railway logs",
            "gcloud config list",
            "vercel dev",
            "kubectl get pods",
            "terraform plan",
            "echo deployment notes > README.md",
        ] {
            assert!(bash(cmd).is_none(), "{cmd}");
        }
        assert!(needs_ok("mcp__railway__deploy", &json!({ "service": "api" })).unwrap().contains("railway"));
        assert!(needs_ok("mcp__railway__list_services", &json!({})).is_none());
        assert!(needs_ok("Edit", &json!({ "file_path": "deploy.sh" })).is_none());
    }
}
