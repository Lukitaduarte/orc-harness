# orc-harness

Harness para rodar várias sessões de Claude Code em paralelo, em várias contas, cada uma com seu próprio conjunto de skills, MCPs e envs. Projetos viram cards que rodam em worktrees até virar PR.

Plano completo: https://claude.ai/artifact/69F6tkzkd1TZqcbXBABdaQ

## Arquitetura

- **Daemon em Rust** (headless): dono das sessões, dos processos, do estado e dos segredos.
- **App em Flutter** (`shadcn_flutter`): cliente no desktop e no celular.
- **Transporte via iroh** (QUIC P2P): só aceita chaves de devices pareados.

## Estrutura

```
app/        Flutter (desktop + mobile)
```

Os crates Rust (`protocol`, `client-core`, `daemon`) entram a partir da fase 1.

## Fase atual: 0, UI mockada

A experiência é validada com dados falsos antes do código pesado. O protocolo daemon ↔ app nasce das telas.

```sh
cd app
flutter run -d macos
```
