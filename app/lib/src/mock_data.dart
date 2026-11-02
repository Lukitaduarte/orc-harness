import 'model.dart';

// Fake data for phase 0. Replaced by the daemon in phase 1.

const catalog = [
  CatalogItem(
    'code-review',
    CatalogKind.skill,
    'code-review',
    'Revisa o diff atual',
    detail: '~/.orc/skills/code-review',
  ),
  CatalogItem(
    'conventional-commits',
    CatalogKind.skill,
    'conventional-commits',
    'Padrão de commits',
    detail: '~/.orc/skills/conventional-commits',
  ),
  CatalogItem(
    'flutter-architecture',
    CatalogKind.skill,
    'flutter-architecture',
    'Camadas UI, lógica e dados',
    detail: '~/.orc/skills/flutter-architecture',
  ),
  CatalogItem(
    'docs',
    CatalogKind.skill,
    'docs',
    'Escreve documentação',
    detail: '~/.orc/skills/docs',
  ),
  CatalogItem(
    'postgres',
    CatalogKind.mcp,
    'postgres',
    'Banco de staging',
    detail: 'npx @modelcontextprotocol/server-postgres \$STAGING_DB_URL',
  ),
  CatalogItem(
    'linear',
    CatalogKind.mcp,
    'linear',
    'Issues e projetos',
    detail: 'https://mcp.linear.app/sse',
  ),
  CatalogItem(
    'browser',
    CatalogKind.mcp,
    'browser',
    'Chromium do workspace',
    detail: 'agent-browser mcp --cdp-endpoint <perfil do workspace>',
  ),
  CatalogItem(
    'memory',
    CatalogKind.mcp,
    'memory',
    'Memória de longo prazo',
    detail: 'npx @modelcontextprotocol/server-memory',
  ),
  CatalogItem(
    'env-staging',
    CatalogKind.env,
    'STAGING',
    'API e banco de staging',
    detail: 'Keychain · orc-harness/work/STAGING',
  ),
  CatalogItem(
    'env-prod-ro',
    CatalogKind.env,
    'PROD_READONLY',
    'Produção, só leitura',
    detail: 'Keychain · orc-harness/work/PROD_READONLY',
  ),
  CatalogItem(
    'env-sentry',
    CatalogKind.env,
    'SENTRY_TOKEN',
    'Token do Sentry',
    detail: 'Keychain · orc-harness/work/SENTRY_TOKEN',
  ),
];

const workspaces = [
  Workspace('work', 'Trabalho', 'TR'),
  Workspace('personal', 'Pessoal', 'PE'),
];

List<Account> seedAccounts(DateTime now) => [
  Account(
    id: 'work-main',
    workspaceId: 'work',
    email: 'lucas@work.dev',
    plan: 'Max',
    fiveHour: QuotaWindow(
      usedPercent: 62,
      resetsAt: now.add(const Duration(hours: 1, minutes: 40)),
      burnPerHour: 31,
    ),
    sevenDay: QuotaWindow(
      usedPercent: 38,
      resetsAt: now.add(const Duration(days: 3, hours: 6)),
      burnPerHour: 0.6,
    ),
    readAt: now.subtract(const Duration(seconds: 20)),
  ),
  Account(
    id: 'work-alt',
    workspaceId: 'work',
    email: 'lucas.alt@work.dev',
    plan: 'Pro',
    fiveHour: QuotaWindow(
      usedPercent: 91,
      resetsAt: now.add(const Duration(minutes: 25)),
      burnPerHour: 12,
    ),
    sevenDay: QuotaWindow(
      usedPercent: 74,
      resetsAt: now.add(const Duration(days: 1, hours: 2)),
      burnPerHour: 1.1,
    ),
    readAt: now.subtract(const Duration(minutes: 12)),
  ),
  Account(
    id: 'personal-main',
    workspaceId: 'personal',
    email: 'talk@lukita.me',
    plan: 'Max',
    fiveHour: QuotaWindow(
      usedPercent: 8,
      resetsAt: now.add(const Duration(hours: 4, minutes: 10)),
      burnPerHour: 4,
    ),
    sevenDay: QuotaWindow(
      usedPercent: 22,
      resetsAt: now.add(const Duration(days: 5)),
      burnPerHour: 0.3,
    ),
    readAt: now.subtract(const Duration(hours: 2)),
  ),
];

List<Session> seedSessions() => [
  Session(
    id: 'api',
    workspaceId: 'work',
    accountId: 'work-main',
    name: 'api',
    branch: 'feat/3-get-users-com-cursor',
    model: 'opus',
    state: SessionState.running,
    tokens: 48200,
    costUsd: 1.20,
    fiveHourShare: 23,
    enabledItems: {
      'code-review',
      'conventional-commits',
      'postgres',
      'env-staging',
    },
    lines: _apiLines,
  ),
  Session(
    id: 'front',
    workspaceId: 'work',
    accountId: 'work-main',
    name: 'front',
    branch: 'feat/4-tabela-de-usuarios-com-paginacao',
    model: 'sonnet',
    state: SessionState.waitingInput,
    tokens: 21700,
    costUsd: 0.41,
    fiveHourShare: 9,
    enabledItems: {'code-review', 'conventional-commits', 'browser'},
    lines: _frontLines,
  ),
  Session(
    id: 'review',
    workspaceId: 'work',
    accountId: 'work-alt',
    name: 'review',
    branch: 'main',
    model: 'sonnet',
    state: SessionState.idle,
    tokens: 9100,
    costUsd: 0.12,
    fiveHourShare: 4,
    enabledItems: {'code-review', 'linear'},
    lines: _reviewLines,
  ),
  Session(
    id: 'fenda',
    workspaceId: 'personal',
    accountId: 'personal-main',
    name: 'fenda',
    branch: 'feat/fase-1-combate',
    model: 'opus',
    state: SessionState.running,
    tokens: 15300,
    costUsd: 0.38,
    fiveHourShare: 6,
    enabledItems: {'flutter-architecture', 'conventional-commits', 'memory'},
    lines: _fendaLines,
  ),
];

LayoutNode seedLayout(String workspaceId) => switch (workspaceId) {
  'work' => const LayoutSplit('root', true, [
    LayoutLeaf('p-api', 'api'),
    LayoutSplit('right', false, [
      LayoutLeaf('p-front', 'front'),
      LayoutLeaf('p-review', 'review'),
    ]),
  ]),
  _ => const LayoutLeaf('p-fenda', 'fenda'),
};

const _apiLines = [
  TerminalLine(
    LineKind.prompt,
    '> adiciona paginação por cursor no GET /users',
  ),
  TerminalLine(
    LineKind.assistant,
    '⏺ Vou ver como a rota está implementada hoje.',
  ),
  TerminalLine(LineKind.tool, '⏺ Read(src/routes/users.ts)'),
  TerminalLine(LineKind.result, '  ⎿  Read 84 lines'),
  TerminalLine(LineKind.tool, '⏺ Search(pattern: "paginate", path: "src")'),
  TerminalLine(LineKind.result, '  ⎿  Found 2 files'),
  TerminalLine(
    LineKind.assistant,
    '⏺ Já existe um helper em src/db/paginate.ts. Vou reaproveitar.',
  ),
  TerminalLine(LineKind.tool, '⏺ Update(src/routes/users.ts)'),
  TerminalLine(
    LineKind.result,
    '  ⎿  Updated with 18 additions and 6 removals',
  ),
  TerminalLine(LineKind.tool, '⏺ Bash(pnpm test users)'),
  TerminalLine(LineKind.result, '  ⎿  ✓ 14 passed (1.8s)'),
  TerminalLine(LineKind.dim, '✻ Commitando… (esc para interromper)'),
];

const _frontLines = [
  TerminalLine(
    LineKind.prompt,
    '> monta a tabela de usuários consumindo a paginação nova',
  ),
  TerminalLine(LineKind.tool, '⏺ Read(src/pages/users/UsersTable.tsx)'),
  TerminalLine(LineKind.result, '  ⎿  Read 132 lines'),
  TerminalLine(
    LineKind.assistant,
    '⏺ O contrato do cursor ainda não está no main.',
  ),
  TerminalLine(
    LineKind.assistant,
    '  Espero o PR do card #3 ou uso um mock do contrato?',
  ),
  TerminalLine(LineKind.dim, '  1. Esperar o PR do card #3'),
  TerminalLine(LineKind.dim, '  2. Usar mock do contrato e ajustar depois'),
];

const _reviewLines = [
  TerminalLine(LineKind.prompt, '> revisa o PR #11'),
  TerminalLine(LineKind.tool, '⏺ Bash(gh pr diff 11)'),
  TerminalLine(LineKind.result, '  ⎿  +212 −48 em 7 arquivos'),
  TerminalLine(
    LineKind.assistant,
    '⏺ Revisão concluída: 1 bug (off-by-one no limite) e 2 sugestões.',
  ),
  TerminalLine(LineKind.dim, '  Comentários publicados no PR.'),
];

const _fendaLines = [
  TerminalLine(LineKind.prompt, '> implementa o cálculo de dano da fase 1'),
  TerminalLine(LineKind.tool, '⏺ Read(docs/LORE.md)'),
  TerminalLine(LineKind.result, '  ⎿  Read 210 lines'),
  TerminalLine(LineKind.tool, '⏺ Write(lib/combate/dano.dart)'),
  TerminalLine(LineKind.result, '  ⎿  Wrote 64 lines'),
  TerminalLine(LineKind.dim, '✻ Rodando testes…'),
];

List<Project> seedProjects(DateTime now) {
  DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));
  return [
    Project(
      id: 'users-pagination',
      workspaceId: 'work',
      name: 'Paginação de usuários',
      repo: 'work/platform',
      cards: [
        TaskCard(
          number: 1,
          title: 'Contrato de paginação por cursor',
          type: 'feat',
          model: 'opus',
          state: CardState.done,
          pr: 10,
          description:
              'Define o formato do cursor e da resposta paginada, compartilhado por API e front.',
          criteria: [
            'Tipo PageCursor exportado no pacote de contratos',
            'Cursor opaco em base64',
            'Documentado no OpenAPI',
          ],
        ),
        TaskCard(
          number: 2,
          title: 'Helper de cursor no banco',
          type: 'feat',
          model: 'sonnet',
          dependsOn: [1],
          state: CardState.done,
          pr: 11,
          description:
              'Helper genérico de keyset pagination sobre o query builder.',
          criteria: [
            'Ordenação estável por (created_at, id)',
            'Testes com 10k linhas',
          ],
        ),
        TaskCard(
          number: 3,
          title: 'GET /users com cursor',
          type: 'feat',
          model: 'opus',
          dependsOn: [1, 2],
          state: CardState.running,
          sessionId: 'api',
          description:
              'Troca a paginação por offset do GET /users pela de cursor, mantendo compatibilidade por uma versão.',
          criteria: [
            'Aceita ?cursor= e ?limit= (máx. 100)',
            'Retorna next_cursor nulo na última página',
            'Offset continua funcionando com header de depreciação',
          ],
          notes: [
            Comment(
              'Você',
              'Mantém o offset até o app mobile migrar, combinado com o time.',
              ago(95),
            ),
            Comment(
              'Claude',
              'Ok. Coloquei o header Deprecation e um teste garantindo que offset ainda responde.',
              ago(80),
            ),
          ],
        ),
        TaskCard(
          number: 4,
          title: 'Tabela de usuários com paginação',
          type: 'feat',
          model: 'sonnet',
          dependsOn: [1],
          state: CardState.running,
          sessionId: 'front',
          description:
              'Tabela com scroll infinito consumindo o contrato do card #1.',
          criteria: [
            'Carrega a próxima página ao chegar a 80% do scroll',
            'Estado vazio e de erro',
            'Sem requisições duplicadas',
          ],
        ),
        TaskCard(
          number: 5,
          title: 'Testes e2e da listagem',
          type: 'test',
          model: 'sonnet',
          dependsOn: [3, 4],
          description: 'Fluxo completo: login, listagem, scroll até o fim.',
          criteria: [
            'Roda no CI em menos de 2 min',
            'Cobre última página e lista vazia',
          ],
        ),
        TaskCard(
          number: 6,
          title: 'Documentar o contrato na API pública',
          type: 'docs',
          model: 'haiku',
          dependsOn: [1],
          description:
              'Página de referência com exemplos de request e response.',
          criteria: [
            'Exemplo de iteração completa',
            'Nota de migração do offset',
          ],
        ),
        TaskCard(
          number: 7,
          title: 'Remover paginação por offset',
          type: 'chore',
          model: 'sonnet',
          dependsOn: [3, 4, 5],
          description:
              'Remove o caminho antigo depois que o app mobile migrar.',
          criteria: ['Nenhum cliente usando offset nos logs de 7 dias'],
        ),
      ],
    ),
    Project(
      id: 'onboarding-v2',
      workspaceId: 'work',
      name: 'Onboarding v2',
      repo: 'work/web',
      cards: [
        TaskCard(
          number: 1,
          title: 'Mapear etapas atuais',
          type: 'docs',
          model: 'sonnet',
          description:
              'Levantamento do funil atual com os números de conversão.',
        ),
        TaskCard(
          number: 2,
          title: 'Novo fluxo de convite',
          type: 'feat',
          model: 'opus',
          dependsOn: [1],
        ),
        TaskCard(
          number: 3,
          title: 'Tela de boas-vindas',
          type: 'feat',
          model: 'sonnet',
          dependsOn: [1],
        ),
        TaskCard(
          number: 4,
          title: 'E-mails transacionais',
          type: 'feat',
          model: 'sonnet',
          dependsOn: [2],
        ),
        TaskCard(
          number: 5,
          title: 'Métricas de ativação',
          type: 'feat',
          model: 'haiku',
          dependsOn: [2, 3],
        ),
      ],
    ),
    Project(
      id: 'push-notifications',
      workspaceId: 'work',
      name: 'Notificações push',
      repo: 'work/mobile',
      cards: [],
      plan: Plan(
        summary:
            'Enviar notificações push para iOS e Android quando um pedido muda de status, '
            'com preferências por usuário e entrega auditável.',
        architecture: const [
          PlanBox('Serviço de pedidos', 'publica order.status_changed'),
          PlanBox('Fila (SQS)', 'desacopla e reprocessa'),
          PlanBox('Notifier', 'aplica preferências e monta a mensagem'),
          PlanBox('FCM / APNs', 'entrega no device'),
        ],
        folders: '''services/notifier/
  src/
    consumer.ts        # lê a fila
    preferences.ts     # opt-in por canal
    providers/
      fcm.ts
      apns.ts
  test/
apps/mobile/lib/notifications/
  push_service.dart
  permission_prompt.dart''',
        stack: const [
          ('Fila', 'SQS com DLQ'),
          ('Notifier', 'Node 22 + TypeScript'),
          ('Push', 'Firebase Cloud Messaging (Android) e APNs (iOS)'),
          ('App', 'Flutter + firebase_messaging'),
          ('Auditoria', 'tabela notification_deliveries'),
        ],
        proposedCards: [
          TaskCard(
            number: 1,
            title: 'Evento order.status_changed',
            type: 'feat',
            model: 'sonnet',
            description: 'Publica o evento na fila a cada mudança de status.',
            criteria: [
              'Evento versionado',
              'Idempotente por order_id + status',
            ],
          ),
          TaskCard(
            number: 2,
            title: 'Notifier consumindo a fila',
            type: 'feat',
            model: 'opus',
            dependsOn: [1],
            description: 'Consumidor com retry e DLQ.',
            criteria: [
              '3 tentativas com backoff',
              'Mensagens com erro vão para a DLQ',
            ],
          ),
          TaskCard(
            number: 3,
            title: 'Preferências de notificação',
            type: 'feat',
            model: 'sonnet',
            description: 'Opt-in por canal e por tipo de evento.',
            criteria: ['Padrão: ligado para status de pedido'],
          ),
          TaskCard(
            number: 4,
            title: 'Integração FCM e APNs',
            type: 'feat',
            model: 'opus',
            dependsOn: [2, 3],
            criteria: ['Token inválido é removido automaticamente'],
          ),
          TaskCard(
            number: 5,
            title: 'Permissão e recebimento no app',
            type: 'feat',
            model: 'sonnet',
            dependsOn: [4],
            criteria: ['Pede permissão só depois do primeiro pedido'],
          ),
          TaskCard(
            number: 6,
            title: 'Painel de entregas',
            type: 'feat',
            model: 'haiku',
            dependsOn: [4],
          ),
        ],
        threads: [
          CommentThread('t1', 'stack', 'Stack', [
            Comment(
              'Você',
              'SQS mesmo? Já temos Kafka rodando para eventos de pedido.',
              ago(40),
            ),
          ]),
          CommentThread('t2', 'card-5', 'Card #5', [
            Comment(
              'Você',
              'Pedir permissão depois do primeiro pedido é ótimo, mantém.',
              ago(30),
            ),
            Comment(
              'Claude',
              'Mantido. Também adicionei um critério para não pedir de novo se o usuário negar.',
              ago(28),
            ),
          ])..resolved = true,
        ],
      ),
    ),
  ];
}
