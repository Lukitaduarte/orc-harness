import 'model.dart';

// Plan mode templates and the example plan, as markdown. In phase 0 they
// ship with the app; the daemon will read them from ~/.orc/templates/*.md
// so each user keeps their own.

final seedTemplates = [
  PlanTemplate(
    'back',
    'Back end com deploy',
    'Serviço ou API: contrato, dados, observabilidade e deploy por provider.',
    _back,
  ),
  PlanTemplate(
    'app',
    'App mobile com release',
    'Feature de app: telas e estados, design system, testes em device e release nas lojas.',
    _app,
  ),
  PlanTemplate(
    'spike',
    'Spike / investigação',
    'Pergunta, hipóteses e experimentos curtos que terminam numa decisão.',
    _spike,
  ),
];

/// Skeleton for a new template.
const blankTemplate = '''# Nome do plano

Resumo em uma frase: o que entrega e para quem.

## Fontes
<!-- Uma linha por fonte: o que ela decidiu e os critérios que traz. -->
| Fonte | O que decidiu | Critérios |
|---|---|---|
| Jira | a preencher | a preencher |

## Arquitetura
<!-- Fluxo dos componentes e a interação principal, com o ramo de falha. -->
```mermaid Componentes
flowchart TB
  A[Origem] --> B[Destino]:::new
```

## Execução
<!-- Loops do tamanho de um PR; tarefas com skill, modelo e grupo paralelo. -->
```loops
- title: Primeiro loop
  model: sonnet
  tasks:
    - {id: T1, title: Primeira tarefa, skill: a-definir, model: sonnet, group: 1}
```
''';

const _back = '''# Serviço novo

Resumo do que o serviço entrega e para quem.

## Fontes
<!-- prompt: Leia cada link (Jira, Confluence, Figma). Uma linha por fonte, com o que decidiu e os critérios de aceite que traz. Aponte conflitos entre fontes. -->
| Fonte | O que decidiu | Critérios que traz |
|---|---|---|
| Jira | resumo lido | ver checklist |

## Checklist
<!-- prompt: Responda pelas fontes e pelo código, marcando a origem. O que ficar aberto vira pendência. -->
| Item | Resposta | Origem |
|---|---|---|
| Métrica de sucesso | a confirmar | pendente |
| Contrato da API | a definir | pendente |
| PII / LGPD | o que nunca logar | dev |

## Arquitetura
<!-- prompt: Flowchart dos componentes e uma sequência da interação principal com o ramo de falha. Marque com :::new o que é criado. -->
```mermaid Componentes
flowchart TB
  subgraph svc [Serviço]
    api[API<br/>handlers]:::new --> domain[Domínio<br/>regras]:::new
    domain --> repo[(Banco<br/>Postgres)]
  end
  client[Cliente] --> api
  domain -.->|erro| api
```

```mermaid Interação principal
sequenceDiagram
  participant C as Cliente
  participant A as API
  participant D as Banco
  C->>A: POST recurso
  A->>D: insert
  D-->>A: ok
  A-->>C: 201
  alt falha
    D-->>A: conflito
    A-->>C: 409
  end
```

## Contrato da API {#contrato}
<!-- prompt: Endpoints, request, response e códigos de erro. -->
```http
POST /v1/recurso
201 Created | 409 Conflict | 422 Unprocessable
```

## Dados e migrações {#dados}
<!-- prompt: Tabelas novas ou alteradas, índices e a estratégia de migração sem downtime. -->
| Tabela | Mudança | Migração |
|---|---|---|
| recurso | nova | expand → backfill → contract |

## Observabilidade
<!-- prompt: Logs, métricas e alertas; o que nunca logar. -->
- Métricas de latência e erro por endpoint
- Alerta de taxa de erro acima de 2%

## Testes
- Unit e integração com banco real em container
- Teste de contrato da API

## Deploy
<!-- prompt: Para cada provider, o que sobe e por qual MCP ou skill do catálogo, e se está configurado. Ambientes com gatilho, segredos (Keychain) e aprovação. Pipeline com rollback. Produção sempre espera o OK do dev. -->
| Provider | O que sobe | Via | No catálogo |
|---|---|---|---|
| Railway | serviço | use-railway + MCP railway | configurado |
| GCP | Cloud SQL ou Cloud Run | MCP gcloud | configurado |
| AWS | fila ou bucket | MCP aws | configurado |

| Ambiente | Gatilho | Segredos (Keychain) | Aprovação |
|---|---|---|---|
| staging | merge na main | STAGING | automática |
| produção | tag v* | a definir | seu OK |

```mermaid Pipeline, com o caminho de rollback
flowchart TB
  merge[Merge na main] --> ci[CI<br/>testes e build]
  subgraph stg [Staging]
    dstg[Deploy]:::new --> smoke[Smoke test]:::new
  end
  ci --> dstg
  smoke -->|verde| ok{Seu OK?}
  ok ==>|sim| dprd[Deploy produção]:::new
  smoke -.->|falhou| rb[Rollback]:::external
  dprd -.->|alarme| rb
```

## Execução
<!-- prompt: Um loop por PR; tarefas em grupos paralelos com skill e modelo. O deploy fecha e não gera PR. -->
```loops
- title: Contrato e domínio
  model: opus
  tasks:
    - {id: T1, title: Contrato da API, skill: backend-service, model: opus, group: 1}
    - {id: T2, title: Migração, skill: backend-service, model: sonnet, group: 2, after: [T1]}
    - {id: T3, title: Testes, skill: unit-tests-handler, model: sonnet, group: 3, after: [T2]}
- title: Handlers e observabilidade
  model: sonnet
  depends_on: [1]
  tasks:
    - {id: T4, title: Handlers, skill: backend-service, model: sonnet, group: 1}
    - {id: T5, title: Métricas e alertas, skill: log-instrumenter, model: haiku, group: 1}
- title: Deploy
  type: chore
  model: sonnet
  depends_on: [2]
  tasks:
    - {id: T6, title: Infra no provider, skill: MCP do provider, model: haiku, group: 1}
    - {id: T7, title: Deploy em staging, skill: use-railway, model: sonnet, group: 2, after: [T6]}
    - {id: T8, title: Smoke test, skill: run-test-learn, model: sonnet, group: 3, after: [T7]}
    - {id: T9, title: Deploy em produção, skill: use-railway, model: sonnet, group: 4, after: [T8], needs_ok: true}
```

## Pendências e riscos {#pendencias}
| Item | Impacto | Quem resolve |
|---|---|---|
| Escolher o provider de deploy | bloqueia | dev |
''';

const _app = '''# Feature de app

Resumo do que muda para o usuário do app.

## Fontes
<!-- prompt: Leia Jira, Confluence e Figma. Uma linha por fonte com decisões e critérios. -->
| Fonte | O que decidiu | Critérios que traz |
|---|---|---|
| Figma | telas lidas | ver telas e estados |

## Telas e estados {#telas}
<!-- prompt: Cada tela com seus estados: loading, vazio, erro, sucesso, offline. Aponte frames que faltam no Figma. -->
| Tela | Estados | Frame no Figma |
|---|---|---|
| Lista | loading, vazio, erro, sucesso | a mapear |

## Design System {#ds}
<!-- prompt: Nó do Figma → componente do design system → variante → tokens. -->
| Nó no Figma | Componente | Variante |
|---|---|---|
| a mapear | a mapear | a mapear |

## Arquitetura
<!-- prompt: Camadas da feature e a interação principal com o ramo de falha. -->
```mermaid Camadas da feature
flowchart TB
  subgraph feat [Feature]
    tela[Tela<br/>widgets]:::new --> cubit[Cubit<br/>estado]:::new
    cubit --> repo[Repositório<br/>contrato]:::new
    repo --> ds[Data source<br/>HTTP]:::new
  end
  ds --> api[API<br/>existente]:::external
  ds -.->|erro| cubit
```

```mermaid Interação principal
sequenceDiagram
  actor U as Usuário
  participant T as Tela
  participant C as Cubit
  participant A as API
  U->>T: abre
  T->>C: load()
  C->>A: GET
  A-->>C: 200
  C-->>T: sucesso
  alt falha
    A-->>C: 5xx
    C-->>T: erro + tentar de novo
  end
```

## Estrutura de pastas {#estrutura}
```text
lib/features/nome/
  data/
  domain/
  presentation/
```

## Testes
- Unit, widget e bloc por arquivo, 90% de cobertura
- Flow E2E: emulador Android, depois simulador iOS

## Release
<!-- prompt: Como chega no usuário: feature flag, TestFlight e Play interno, rollout gradual, versão mínima, kill switch. A publicação nas lojas espera o OK do dev. -->
| Etapa | Onde | Critério para avançar |
|---|---|---|
| Interno | TestFlight e Play interno | smoke test nos dois |
| Rollout 10% | lojas | crash-free acima de 99,5% |
| 100% | lojas | 48 h sem regressão |

```mermaid Release, com o kill switch
flowchart TB
  build[Build release] --> beta[TestFlight e Play interno]
  beta --> ok{Seu OK?}
  ok ==>|sim| r10[Rollout 10%]:::new
  r10 --> r100[Rollout 100%]
  r10 -.->|crash| kill[Desliga a flag]:::external
```

## Execução
```loops
- title: Camada de dados
  model: opus
  tasks:
    - {id: T1, title: Entidades e contratos, skill: clean-arch-layer-generator, model: opus, group: 1}
    - {id: T2, title: Data sources e repository, skill: clean-arch-layer-generator, model: sonnet, group: 2, after: [T1]}
    - {id: T3, title: Testes de dados, skill: unit-tests-handler, model: sonnet, group: 3, after: [T2]}
- title: Apresentação
  model: sonnet
  depends_on: [1]
  tasks:
    - {id: T4, title: Cubits, skill: cubit-state-creator, model: sonnet, group: 1}
    - {id: T5, title: Telas, skill: presentation-layer-scaffolder, model: sonnet, group: 1}
    - {id: T6, title: Eventos e logs, skill: event-bridge-implementer, model: haiku, group: 1}
- title: Wiring, E2E e release
  model: sonnet
  depends_on: [2]
  tasks:
    - {id: T7, title: DI e rota, skill: di-route-wirer, model: haiku, group: 1}
    - {id: T8, title: Flow Maestro Android → iOS, skill: maestro-e2e-scaffolder, model: sonnet, group: 2, after: [T7]}
    - {id: T9, title: Publicar nas lojas, skill: release, model: sonnet, group: 3, after: [T8], needs_ok: true}
```

## Pendências e riscos {#pendencias}
| Item | Impacto | Quem resolve |
|---|---|---|
| Frames de erro faltando no Figma | médio | design |
''';

const _spike = '''# Spike

A pergunta que este spike responde, em uma frase.

## Pergunta e critério de decisão {#pergunta}
<!-- prompt: A pergunta, o que decide e quanto tempo vale gastar. -->
- Pergunta: a definir
- Decide quando: a definir
- Limite de tempo: 2 dias

## Hipóteses
<!-- prompt: Hipóteses testáveis, cada uma com o sinal que a confirma ou derruba. -->
| Hipótese | Sinal | Resultado |
|---|---|---|
| a definir | a definir | pendente |

## Execução
```loops
- title: Experimentos
  model: sonnet
  tasks:
    - {id: T1, title: Protótipo A, skill: a-definir, model: sonnet, group: 1}
    - {id: T2, title: Protótipo B, skill: a-definir, model: sonnet, group: 1}
    - {id: T3, title: Comparar e recomendar, skill: a-definir, model: opus, group: 2, after: [T1, T2]}
```

## Decisão
<!-- prompt: A recomendação, o que foi descartado e por quê. Vira ADR se for aceita. -->
A preencher depois dos experimentos.
''';

/// The example plan of the "Notificações push" project, written as markdown
/// like any user plan.
const pushPlanMarkdown = '''---
repo: work/mobile
sources:
  - https://work.atlassian.net/browse/MOB-412
  - https://work.atlassian.net/wiki/spaces/MOB/pages/9911/PRD-Push
  - https://www.figma.com/design/aB12/Push?node-id=12-345
---
# Notificações push

Notificações push para iOS e Android quando um pedido muda de status, com preferências por usuário e entrega auditável.

## Fontes
| Fonte | O que decidiu | Critérios que traz |
|---|---|---|
| Jira MOB-412 | Escopo: status de pedido | Push em pago, enviado, entregue |
| PRD §2 | Opt-in por canal; padrão ligado | Usuário desliga por tipo de evento |
| Figma 12:345 | Prompt de permissão depois do 1º pedido | Não insistir se negar |

Conflito: o PRD pede e-mail como fallback; o Jira não. Ficou em Pendências.

## Checklist
| Item | Resposta | Origem |
|---|---|---|
| Métrica de sucesso | Taxa de abertura ≥ 8% | PRD §1 |
| Estados da tela | permissão pendente, negada, concedida | Figma 12:345 |
| Feature flag | push_order_status | código |
| Contrato do back end | evento novo, sem OpenAPI ainda | pendente |
| PII / LGPD | não logar token do device | dev |

## Escopo
- Consome serviço: sim, evento novo no serviço de pedidos
- Plataformizado: sim, o notifier serve todos os apps
- Local: services/notifier + apps/mobile/lib/notifications

```mermaid Decisão de escopo, com o caminho tomado
flowchart TB
  q1{Chama back end?} -->|não| ui[Só UI no app]
  q1 ==>|sim| q2{Usado por 2+ apps?}
  q2 ==>|sim| plat[Serviço plataforma<br/>services/notifier]:::new
  q2 -->|não| local[Feature no app]
```

Motivo: o notifier é infraestrutura reusável; a UI de permissão é do app.

## Arquitetura
```mermaid Componentes e fluxo do evento
flowchart TB
  subgraph pedidos [Serviço de pedidos]
    order[Pedido salvo<br/>muda de status] -->|mesma transação| outbox[(Outbox<br/>tabela transacional)]:::new
    outbox --> publisher[Publisher<br/>publica o evento v1]:::new
  end
  subgraph infra [Infra]
    queue[(Fila SQS<br/>order.status_changed)]
  end
  subgraph notifier [Notifier]
    consumer[Consumer<br/>retry com backoff]:::new
    prefs[(Preferências<br/>opt-in por canal)]:::new
    provider[PushProvider<br/>Strategy: FCM e APNs]:::new
  end
  subgraph app [App mobile]
    push[push_service<br/>abre o pedido]:::new
  end
  publisher -->|publica| queue
  queue -->|consome| consumer
  consumer -->|consulta| prefs
  consumer -->|envia| provider
  consumer -.->|falha 3x| dlq[(DLQ<br/>alerta no Slack)]
  provider --> fcm[FCM / APNs<br/>entrega no device]:::external
  fcm -->|push| push
```

```mermaid Interação principal, com o ramo de falha
sequenceDiagram
  participant P as Pedidos
  participant F as Fila
  participant N as Notifier
  participant X as FCM/APNs
  participant A as App
  P->>F: order.status_changed
  F->>N: entrega evento
  N->>N: aplica preferências
  N->>X: send(token, msg)
  X->>A: push
  X-->>N: entregue
  alt falha de entrega
    N->>X: send(token, msg)
    X-->>N: token inválido
    N->>N: remove o token
  end
```

## Padrões {#padroes}
| Padrão | Por que aqui | Alternativa rejeitada |
|---|---|---|
| Strategy | FCM e APNs atrás da mesma interface | if por plataforma no consumer |
| Outbox | evento só sai se o pedido for salvo | publicar direto na fila |
| Cubit | estado simples da permissão | sealed state com 6 variantes |

## Design System {#ds}
| Nó no Figma | Componente | Variante |
|---|---|---|
| 12:350 Card de permissão | Card | elevated |
| 12:352 Botão permitir | Button | primary |
| 12:353 Agora não | Button | ghost |

## Estrutura de pastas {#estrutura}
```text
services/notifier/
  src/consumer.ts          # new
  src/preferences.ts       # new
  src/providers/fcm.ts     # new
  src/providers/apns.ts    # new
apps/mobile/lib/notifications/
  push_service.dart        # new
  permission_prompt.dart   # new
  push_cubit.dart          # new
```

## Código {#codigo}
```ts services/notifier/src/providers/provider.ts
export interface PushProvider {
  send(token: string, message: PushMessage): Promise<Delivery>;
}
```

```dart apps/mobile/lib/notifications/push_cubit.dart
class PushCubit extends Cubit<PushState> {
  Future<void> requestPermissionAfterFirstOrder();
}
```

## Observabilidade
| Evento | Quando | Propriedades |
|---|---|---|
| push_permission_prompted | prompt exibido | source |
| push_opened | toque na notificação | order_status |

- Nunca logar o token do device
- Dashboard: entrega, abertura, falhas por provider

## Testes
- Unit e widget por arquivo, meta de 90% de cobertura
- Flow Maestro: primeiro pedido → prompt → permitir → push abre o pedido
- Ordem: emulador Android, depois simulador iOS

## Deploy
Notifier no Railway, fila na AWS, push pelo Firebase (GCP). Cada provider entra pelo MCP do catálogo, ligado só na sessão do loop de deploy.

| Provider | O que sobe | Via | No catálogo |
|---|---|---|---|
| Railway | serviço notifier, staging e produção | use-railway + MCP railway | configurado |
| AWS | fila SQS, DLQ e alarme no CloudWatch | MCP aws | configurado |
| GCP | projeto Firebase e chave do FCM | MCP gcloud | configurado |
| Apple | chave APNs (.p8) | manual, no portal | pendente |

| Ambiente | Gatilho | Segredos (Keychain) | Aprovação |
|---|---|---|---|
| staging | merge na main | STAGING, FCM_KEY_STAGING | automática |
| produção | tag v* | PROD_READONLY, FCM_KEY, APNS_KEY | seu OK |

```mermaid Pipeline, com o caminho de rollback
flowchart TB
  merge[Merge na main] --> ci[CI<br/>analyze, testes, build]
  subgraph stg [Staging]
    dstg[Deploy<br/>Railway · SQS staging]:::new --> smoke[Smoke test<br/>push de teste no device]:::new
  end
  ci --> dstg
  smoke -->|verde| ok{Seu OK?}
  ok ==>|sim| dprd
  subgraph prd [Produção]
    dprd[Deploy<br/>Railway · SQS produção]:::new --> watch[Monitorar 30 min<br/>alarmes da DLQ]
  end
  smoke -.->|falhou| rb[Rollback<br/>imagem anterior no Railway]:::external
  watch -.->|alarme| rb
```

- Produção sempre espera o seu OK, mesmo com o plano aprovado e a execução iniciada
- Segredos vão do Keychain para o provider pelo MCP; nunca no repositório nem no plano
- Rollback: redeploy da imagem anterior; fila e DLQ nunca são apagadas

## Execução {#execucao}
Cada loop vira um PR. Tarefas do mesmo grupo rodam em paralelo como subagentes; o próximo grupo espera.

```mermaid Ordem dos loops: 3 e 4 rodam em paralelo depois do 2; o deploy fecha
flowchart LR
  l1[Loop 1<br/>Evento] --> l2[Loop 2<br/>Notifier]
  l2 --> l3[Loop 3<br/>App]
  l2 --> l4[Loop 4<br/>Auditoria]
  l4 --> l5[Loop 5<br/>Deploy]
```

```loops
- title: Evento order.status_changed
  model: opus
  description: Contrato versionado do evento e publicação no serviço de pedidos.
  criteria: [Evento versionado (v1), Idempotente por order_id + status]
  tasks:
    - {id: T1, title: Contrato do evento, skill: clean-arch-layer-generator, model: opus, group: 1}
    - {id: T2, title: Publicar no serviço de pedidos, skill: backend-service, model: sonnet, group: 2, after: [T1]}
    - {id: T3, title: Testes do publisher, skill: unit-tests-handler, model: sonnet, group: 3, after: [T2]}
- title: Notifier com fila, retry e DLQ
  model: opus
  depends_on: [1]
  description: Consumidor da fila que aplica preferências e entrega via FCM e APNs.
  criteria: [3 tentativas com backoff, Falhas vão para a DLQ, Token inválido é removido]
  tasks:
    - {id: T4, title: Consumer da fila, skill: backend-service, model: sonnet, group: 1}
    - {id: T5, title: Preferências por canal, skill: backend-service, model: sonnet, group: 1}
    - {id: T6, title: Providers FCM e APNs, skill: backend-service, model: opus, group: 2, after: [T4]}
    - {id: T7, title: Testes do notifier, skill: unit-tests-handler, model: sonnet, group: 3, after: [T5, T6]}
- title: "App: permissão e recebimento"
  model: sonnet
  depends_on: [2]
  description: Serviço de push no app, prompt de permissão e abertura do pedido pela notificação.
  criteria: [Pede permissão só depois do primeiro pedido, Não pede de novo se o usuário negar, Toque abre o pedido]
  tasks:
    - {id: T8, title: push_service + cubit, skill: cubit-state-creator, model: sonnet, group: 1}
    - {id: T9, title: Prompt de permissão, skill: presentation-layer-scaffolder, model: sonnet, group: 1}
    - {id: T10, title: Eventos de analytics, skill: event-bridge-implementer, model: haiku, group: 1}
    - {id: T11, title: DI + rota, skill: di-route-wirer, model: haiku, group: 2, after: [T8, T9]}
    - {id: T12, title: "Flow Maestro, Android → iOS", skill: maestro-e2e-scaffolder, model: sonnet, group: 3, after: [T11]}
- title: Auditoria e painel de entregas
  model: haiku
  depends_on: [2]
  description: Tabela de entregas e dashboard com taxa de entrega e abertura.
  criteria: [Toda entrega registrada com status do provider]
  tasks:
    - {id: T13, title: Tabela notification_deliveries, skill: backend-service, model: sonnet, group: 1}
    - {id: T14, title: Dashboard de entregas, skill: dashboard, model: haiku, group: 2, after: [T13]}
- title: Deploy em staging e produção
  type: chore
  model: sonnet
  depends_on: [2, 4]
  description: Provisiona a fila, as credenciais de push e o serviço notifier pelos MCPs do catálogo. Não gera PR de código.
  criteria: [Smoke test em staging entrega um push de teste, Produção só sobe com o seu OK, Rollback testado em staging]
  tasks:
    - {id: T15, title: Fila SQS e DLQ, skill: aws (MCP), model: sonnet, group: 1}
    - {id: T16, title: Projeto Firebase e chave do FCM, skill: gcloud (MCP), model: haiku, group: 1}
    - {id: T17, title: Serviço notifier em staging, skill: use-railway + railway (MCP), model: sonnet, group: 2, after: [T15, T16]}
    - {id: T18, title: Smoke test em staging, skill: run-test-learn, model: sonnet, group: 3, after: [T17]}
    - {id: T19, title: Deploy em produção, skill: use-railway + railway (MCP), model: sonnet, group: 4, after: [T18], needs_ok: true}
```

## Entregas
| PR | Branch | Pacotes | ≈ linhas |
|---|---|---|---|
| 1 | feat/1-evento-order-status-changed | services/orders | 180 |
| 2 | feat/2-notifier-com-fila-retry-e-dlq | services/notifier | 420 |
| 3 | feat/3-app-permissao-e-recebimento | apps/mobile | 380 |
| 4 | feat/4-auditoria-e-painel-de-entregas | services/notifier | 150 |

PRs 1 e 2 formam uma stack; 3 e 4 saem de 2 em paralelo. O loop 5 não gera PR: provisiona e faz deploy pelos MCPs.

```mermaid Stacks de PR
flowchart TB
  subgraph back [Stack back end]
    p1[PR 1<br/>evento] --> p2[PR 2<br/>notifier]
    p2 --> p4[PR 4<br/>auditoria]
  end
  subgraph appstack [App]
    p3[PR 3<br/>app mobile]
  end
  p2 -->|após publicar| p3
```

## Pendências e riscos {#pendencias}
| Item | Impacto | Quem resolve |
|---|---|---|
| Contrato do evento sem OpenAPI | bloqueia | back end |
| E-mail como fallback (PRD x Jira) | médio | produto |
| Cota do APNs em staging | baixo | dev |
| Chave APNs de produção (manual) | bloqueia | dev |
| Release do app nas lojas fora deste plano | médio | mobile |
''';
