# orc-harness

Harness para rodar várias sessões de Claude Code em paralelo, em várias contas, cada uma com seu próprio conjunto de skills, MCPs e envs. Projetos viram cards que rodam em worktrees até virar PR.

Plano completo: https://claude.ai/artifact/69F6tkzkd1TZqcbXBABdaQ

## Arquitetura

- **Daemon em Rust** (headless): dono das sessões, dos processos, do estado e dos segredos.
- **App em Flutter** (`shadcn_flutter`): cliente no desktop e no celular.
- **Transporte via iroh** (QUIC P2P): só aceita chaves de devices pareados.

## Estrutura

```
app/              Flutter (desktop + mobile), shadcn_flutter
crates/protocol/  tipos compartilhados: statusLine, quota, grid do terminal, mensagens
crates/daemon/    orcd (sessões em PTY, terminal emulado, quota) e orc-statusline
```

## Fase atual: 1, núcleo

A UI mockada da fase 0 está no app. O daemon já roda sessões em PTY com o terminal emulado
(`alacritty_terminal`) e recebe a quota de 5h e 7d pelo statusLine. Próximo passo: transporte iroh
e o app trocando o mock pelo daemon.

```sh
cd app && flutter run -d macos             # app (dados mockados)
cargo test --workspace                     # daemon e protocolo
cargo run -p orc-daemon --bin orcd -- run -- claude   # tela do Claude Code emulada
```
