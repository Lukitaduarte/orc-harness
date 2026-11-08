//! The harness MCP server, started by Claude Code in every session the
//! daemon runs (stdio). Tools are answered by the daemon over the local
//! socket, tagged with the session's id (`ORC_SESSION`), so a session can
//! only act as itself.

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::time::Duration;

use orc_protocol::{ClientMessage, DaemonMessage};
use serde_json::{Value, json};

fn tools() -> Value {
    let s = |props: Value, req: &[&str]| json!({ "type": "object", "properties": props, "required": req });
    json!([
        { "name": "list_sessions",
          "description": "Lista as sessões do harness (id, estado, branch) para conversar ou delegar.",
          "inputSchema": s(json!({}), &[]) },
        { "name": "send_message",
          "description": "Envia uma mensagem para outra sessão do harness. Ela lê com read_inbox.",
          "inputSchema": s(json!({ "to": { "type": "string", "description": "id da sessão" },
                                   "body": { "type": "string" } }), &["to", "body"]) },
        { "name": "read_inbox",
          "description": "Lê (e esvazia) as mensagens recebidas de outras sessões.",
          "inputSchema": s(json!({}), &[]) },
        { "name": "delegate_task",
          "description": "Cria outra sessão do harness para uma tarefa, com prompt inicial. Opcional: model (opus, sonnet, haiku) e branch para trabalhar numa worktree nova do mesmo projeto. Peça para ela responder com send_message.",
          "inputSchema": s(json!({ "prompt": { "type": "string" },
                                   "model": { "type": "string" },
                                   "branch": { "type": "string" } }), &["prompt"]) },
        { "name": "search_code",
          "description": "Busca texto (ou regex) nos arquivos da sessão, respeitando o .gitignore.",
          "inputSchema": s(json!({ "query": { "type": "string" },
                                   "regex": { "type": "boolean" } }), &["query"]) },
        { "name": "save_plan",
          "description": "Só para a sessão de planejamento: salva o plano completo (markdown) para o usuário revisar no app. Em revisões, responda os comentários em replies e registre pedidos sobre seções aprovadas em amendments.",
          "inputSchema": s(json!({ "markdown": { "type": "string" },
                                   "replies": { "type": "array", "items": { "type": "object", "properties": {
                                       "thread": { "type": "string" }, "body": { "type": "string" }, "resolve": { "type": "boolean" } },
                                       "required": ["thread", "body"] } },
                                   "amendments": { "type": "array", "items": { "type": "string" } } }), &["markdown"]) },
        { "name": "propose_learning",
          "description": "Só para a sessão de Learn: propõe uma mudança numa skill (troca o trecho `old`, que aparece uma vez, por `new`; `old` vazio acrescenta ao fim). O usuário aprova no app.",
          "inputSchema": s(json!({ "skill": { "type": "string" }, "file": { "type": "string" },
                                   "summary": { "type": "string" }, "old": { "type": "string" },
                                   "new": { "type": "string" }, "source": { "type": "string" } }),
                           &["skill", "file", "summary", "new"]) },
        { "name": "remember",
          "description": "Guarda na memória do workspace algo que vale para as próximas sessões: decisões, preferências do usuário, fatos dos projetos (não segredos). Tags ajudam a achar.",
          "inputSchema": s(json!({ "text": { "type": "string" },
                                   "tags": { "type": "array", "items": { "type": "string" } } }), &["text"]) },
        { "name": "recall",
          "description": "Busca na memória do workspace o que outras sessões guardaram. Use no começo de uma tarefa sobre um projeto ou decisão.",
          "inputSchema": s(json!({ "query": { "type": "string" } }), &["query"]) },
        { "name": "forget",
          "description": "Apaga da memória do workspace uma entrada errada ou velha (pelo id que o recall mostra).",
          "inputSchema": s(json!({ "id": { "type": "string" } }), &["id"]) },
        { "name": "list_envs",
          "description": "Lista as envs do catálogo do harness (nunca os valores): se têm valor no Keychain e se estão ativas nesta sessão. Para gravar ou mudar uma, use request_env_change.",
          "inputSchema": s(json!({}), &[]) },
        { "name": "request_env_change",
          "description": "Pede ao usuário para gravar o valor de uma env no Keychain do harness. Só acontece se ele aprovar no app.",
          "inputSchema": s(json!({ "name": { "type": "string" },
                                   "value": { "type": "string" } }), &["name", "value"]) },
        { "name": "request_mcp_add",
          "description": "Pede ao usuário para adicionar um servidor MCP a esta sessão (claude mcp add não funciona aqui: as sessões do harness só usam os MCPs do perfil). Se ele aprovar no app, o MCP entra no catálogo e esta sessão reinicia com ele, continuando a conversa. `config` vai no formato do mcpServers do Claude Code: {\"command\", \"args\"} para stdio ou {\"type\": \"http\", \"url\", \"headers\"}. Nunca escreva segredos: valores de env e headers vão como \"${NOME}\", e o valor você pede com request_env_change.",
          "inputSchema": s(json!({ "name": { "type": "string", "description": "Nome curto, ex.: github" },
                                   "config": { "type": "object" },
                                   "reason": { "type": "string", "description": "Para que você precisa dele" } }), &["name", "config", "reason"]) },
    ])
}

/// Asks the daemon; any failure becomes an error the agent can read.
fn call(session_id: &str, tool: &str, args: Value) -> (String, bool) {
    let Ok(path) = std::env::var("ORC_SOCKET") else {
        return ("ORC_SOCKET ausente: esta sessão não foi iniciada pelo harness".into(), true);
    };
    let result = (|| -> std::io::Result<(String, bool)> {
        let mut stream = UnixStream::connect(path)?;
        stream.set_read_timeout(Some(Duration::from_secs(60)))?;
        let msg = ClientMessage::McpCall { session_id: session_id.into(), tool: tool.into(), args };
        writeln!(stream, "{}", serde_json::to_string(&msg)?)?;
        let mut line = String::new();
        BufReader::new(stream).read_line(&mut line)?;
        Ok(match serde_json::from_str::<DaemonMessage>(&line)? {
            DaemonMessage::McpResult { text, is_error } => (text, is_error),
            DaemonMessage::Error { message } => (message, true),
            other => (format!("resposta inesperada: {other:?}"), true),
        })
    })();
    result.unwrap_or_else(|e| (format!("o daemon não respondeu: {e}"), true))
}

fn main() {
    let session_id = std::env::var("ORC_SESSION").unwrap_or_default();
    let stdin = std::io::stdin();
    let mut out = std::io::stdout();
    for line in stdin.lock().lines().map_while(Result::ok) {
        let Ok(req) = serde_json::from_str::<Value>(&line) else { continue };
        let Some(id) = req.get("id").cloned() else { continue }; // notifications
        let result = match req["method"].as_str().unwrap_or_default() {
            "initialize" => json!({
                "protocolVersion": req["params"]["protocolVersion"].as_str().unwrap_or("2025-06-18"),
                "capabilities": { "tools": {} },
                "serverInfo": { "name": "orc-harness", "version": "0.1.0" },
            }),
            "tools/list" => json!({ "tools": tools() }),
            "tools/call" => {
                let name = req["params"]["name"].as_str().unwrap_or_default();
                let args = req["params"]["arguments"].clone();
                let (text, is_error) = call(&session_id, name, args);
                json!({ "content": [{ "type": "text", "text": text }], "isError": is_error })
            }
            "ping" => json!({}),
            other => {
                let err = json!({ "jsonrpc": "2.0", "id": id,
                                  "error": { "code": -32601, "message": format!("método desconhecido: {other}") } });
                let _ = writeln!(out, "{err}");
                let _ = out.flush();
                continue;
            }
        };
        let _ = writeln!(out, "{}", json!({ "jsonrpc": "2.0", "id": id, "result": result }));
        let _ = out.flush();
    }
}
