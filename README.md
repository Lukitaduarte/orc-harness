# orc-harness

Harness para rodar várias sessões de Claude Code em paralelo, em várias contas, cada uma com seu próprio conjunto de skills, MCPs e envs. Projetos viram cards que rodam em worktrees até virar PR.

Plano completo: https://claude.ai/artifact/69F6tkzkd1TZqcbXBABdaQ

## Arquitetura

- **Daemon em Rust** (headless): dono das sessões, dos processos, do estado e dos segredos.
- **App em Flutter** (`shadcn_flutter`): cliente no desktop e no celular.
- **Transporte via iroh** (QUIC P2P): só aceita chaves de devices pareados.

## Estrutura

```
app/                Flutter (desktop + mobile), shadcn_flutter
app/rust/           ponte Flutter ↔ Rust (flutter_rust_bridge), workspace próprio
crates/protocol/    tipos compartilhados: statusLine, quota, sessões, grid, mensagens
crates/link/        iroh: ticket de pareamento, chaves, endpoint sem relay público
crates/daemon/      orcd (sessões, terminal emulado, quota, pareamento) + orc-statusline e orc-hook
crates/client-core/ lado do app: parear e conectar
```

## Rodando de verdade

```sh
cargo build -p orc-daemon                    # orcd, orc-statusline, orc-hook
./target/debug/orcd serve                    # deixa rodando
./target/debug/orcd pair                     # em outro terminal: imprime o ticket orc1…
cd app && flutter run -d macos               # ⚙ → Conectar daemon → cole o ticket
```

Tudo do daemon fica em `~/.orc` (ou `ORC_HOME`): `config.json`, `catalog.json`, `templates/*.md`,
`devices.json` e as pastas das sessões. Segredos (valores das envs e a chave do daemon) ficam no
Keychain, serviço `orc-harness`.

Contas em `~/.orc/config.json` (sem o arquivo: uma conta `default` com a config padrão do Claude Code):

```json
{ "accounts": [ { "id": "trabalho", "config_dir": "~/.claude-trabalho" }, { "id": "pessoal" } ] }
```

## Testes

```sh
cargo test --workspace                       # daemon, protocolo, iroh ponta a ponta
cd app && flutter test                       # app
cargo test -p orc-daemon --test real_claude -- --ignored --nocapture   # claude real, sem prompt
```
