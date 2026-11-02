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
          delivered: ['PageCursor no pacote de contratos (contracts 2.3.0)'],
          gates: {
            'analyze': '0 issues',
            'unit': '24 passed',
            'coverage': '96%',
          },
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
          delivered: ['keysetPaginate() no query builder'],
          problems: [
            'Índice (created_at, id) faltava em staging; criado na migration',
          ],
          gates: {
            'analyze': '0 issues',
            'unit': '31 passed',
            'coverage': '93%',
          },
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
          tasks: const [
            CardTask(
              'T1',
              'Handler com cursor',
              skill: 'backend-service',
              model: 'opus',
              group: 1,
            ),
            CardTask(
              'T2',
              'Header de depreciação do offset',
              skill: 'backend-service',
              model: 'haiku',
              group: 1,
            ),
            CardTask(
              'T3',
              'Testes de contrato',
              skill: 'unit-tests-handler',
              model: 'sonnet',
              group: 2,
              dependsOn: ['T1', 'T2'],
            ),
          ],
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
          tasks: const [
            CardTask(
              'T1',
              'Hook de paginação',
              skill: 'frontend-data',
              model: 'sonnet',
              group: 1,
            ),
            CardTask(
              'T2',
              'Tabela com scroll infinito',
              skill: 'frontend-ui',
              model: 'sonnet',
              group: 1,
            ),
            CardTask(
              'T3',
              'Testes de componente',
              skill: 'unit-tests-handler',
              model: 'sonnet',
              group: 2,
              dependsOn: ['T1', 'T2'],
            ),
          ],
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
      plan: pushPlan(now),
    ),
  ];
}

List<TaskCard> _pushLoops() => [
  TaskCard(
    number: 1,
    title: 'Evento order.status_changed',
    type: 'feat',
    model: 'opus',
    description:
        'Contrato versionado do evento e publicação no serviço de pedidos.',
    criteria: ['Evento versionado (v1)', 'Idempotente por order_id + status'],
    tasks: const [
      CardTask(
        'T1',
        'Contrato do evento',
        skill: 'clean-arch-layer-generator',
        model: 'opus',
        group: 1,
      ),
      CardTask(
        'T2',
        'Publicar no serviço de pedidos',
        skill: 'backend-service',
        model: 'sonnet',
        group: 2,
        dependsOn: ['T1'],
      ),
      CardTask(
        'T3',
        'Testes do publisher',
        skill: 'unit-tests-handler',
        model: 'sonnet',
        group: 3,
        dependsOn: ['T2'],
      ),
    ],
  ),
  TaskCard(
    number: 2,
    title: 'Notifier com fila, retry e DLQ',
    type: 'feat',
    model: 'opus',
    dependsOn: [1],
    description:
        'Consumidor da fila que aplica preferências e entrega via FCM e APNs.',
    criteria: [
      '3 tentativas com backoff',
      'Falhas vão para a DLQ',
      'Token inválido é removido',
    ],
    tasks: const [
      CardTask(
        'T4',
        'Consumer da fila',
        skill: 'backend-service',
        model: 'sonnet',
        group: 1,
      ),
      CardTask(
        'T5',
        'Preferências por canal',
        skill: 'backend-service',
        model: 'sonnet',
        group: 1,
      ),
      CardTask(
        'T6',
        'Providers FCM e APNs',
        skill: 'backend-service',
        model: 'opus',
        group: 2,
        dependsOn: ['T4'],
      ),
      CardTask(
        'T7',
        'Testes do notifier',
        skill: 'unit-tests-handler',
        model: 'sonnet',
        group: 3,
        dependsOn: ['T5', 'T6'],
      ),
    ],
  ),
  TaskCard(
    number: 3,
    title: 'App: permissão e recebimento',
    type: 'feat',
    model: 'sonnet',
    dependsOn: [2],
    description:
        'Serviço de push no app, prompt de permissão e abertura do pedido pela notificação.',
    criteria: [
      'Pede permissão só depois do primeiro pedido',
      'Não pede de novo se o usuário negar',
      'Toque abre o pedido',
    ],
    tasks: const [
      CardTask(
        'T8',
        'push_service + cubit',
        skill: 'cubit-state-creator',
        model: 'sonnet',
        group: 1,
      ),
      CardTask(
        'T9',
        'Prompt de permissão',
        skill: 'presentation-layer-scaffolder',
        model: 'sonnet',
        group: 1,
      ),
      CardTask(
        'T10',
        'Eventos de analytics',
        skill: 'event-bridge-implementer',
        model: 'haiku',
        group: 1,
      ),
      CardTask(
        'T11',
        'DI + rota',
        skill: 'di-route-wirer',
        model: 'haiku',
        group: 2,
        dependsOn: ['T8', 'T9'],
      ),
      CardTask(
        'T12',
        'Flow Maestro, Android → iOS',
        skill: 'maestro-e2e-scaffolder',
        model: 'sonnet',
        group: 3,
        dependsOn: ['T11'],
      ),
    ],
  ),
  TaskCard(
    number: 4,
    title: 'Auditoria e painel de entregas',
    type: 'feat',
    model: 'haiku',
    dependsOn: [2],
    description:
        'Tabela de entregas e dashboard com taxa de entrega e abertura.',
    criteria: ['Toda entrega registrada com status do provider'],
    tasks: const [
      CardTask(
        'T13',
        'Tabela notification_deliveries',
        skill: 'backend-service',
        model: 'sonnet',
        group: 1,
      ),
      CardTask(
        'T14',
        'Dashboard de entregas',
        skill: 'dashboard',
        model: 'haiku',
        group: 2,
        dependsOn: ['T13'],
      ),
    ],
  ),
];

Plan pushPlan(DateTime now) {
  DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));
  final loops = _pushLoops();
  final plan = Plan(
    summary:
        'Notificações push para iOS e Android quando um pedido muda de status, '
        'com preferências por usuário e entrega auditável.',
    sources: [
      PlanSource.fromUrl('https://work.atlassian.net/browse/MOB-412'),
      PlanSource.fromUrl(
        'https://work.atlassian.net/wiki/spaces/MOB/pages/9911/PRD-Push',
      ),
      PlanSource.fromUrl(
        'https://www.figma.com/design/aB12/Push?node-id=12-345',
      ),
    ],
    proposedCards: loops,
    sections: [
      PlanSection('fontes', 'Fontes', const [
        TableBlock(
          ['Fonte', 'O que decidiu', 'Critérios que traz'],
          [
            [
              'Jira MOB-412',
              'Escopo: status de pedido',
              'Push em pago, enviado, entregue',
            ],
            [
              'PRD §2',
              'Opt-in por canal; padrão ligado',
              'Usuário desliga por tipo de evento',
            ],
            [
              'Figma 12:345',
              'Prompt de permissão depois do 1º pedido',
              'Não insistir se negar',
            ],
          ],
        ),
        TextBlock(
          'Conflito: o PRD pede e-mail como fallback; o Jira não. Ficou em Pendências.',
        ),
      ]),
      PlanSection('checklist', 'Checklist', const [
        TableBlock(
          ['Item', 'Resposta', 'Origem'],
          [
            ['Métrica de sucesso', 'Taxa de abertura ≥ 8%', 'PRD §1'],
            [
              'Estados da tela',
              'permissão pendente, negada, concedida',
              'Figma 12:345',
            ],
            ['Feature flag', 'push_order_status', 'código'],
            [
              'Contrato do back end',
              'evento novo, sem OpenAPI ainda',
              'pendente',
            ],
            ['PII / LGPD', 'não logar token do device', 'dev'],
          ],
        ),
      ]),
      PlanSection('escopo', 'Escopo', const [
        BulletsBlock([
          'Consome serviço: sim, evento novo no serviço de pedidos',
          'Plataformizado: sim, o notifier serve todos os apps',
          'Local: services/notifier + apps/mobile/lib/notifications',
        ]),
        TextBlock(
          'Motivo: o notifier é infraestrutura reusável; a UI de permissão é do app.',
        ),
      ]),
      PlanSection('arquitetura', 'Arquitetura', const [
        FlowBlock([
          PlanBox('Serviço de pedidos', 'publica order.status_changed'),
          PlanBox('Fila (SQS)', 'desacopla e reprocessa'),
          PlanBox('Notifier', 'preferências e mensagem'),
          PlanBox('FCM / APNs', 'entrega no device'),
        ]),
        TextBlock(
          'Falha: após 3 tentativas a mensagem vai para a DLQ e gera alerta.',
        ),
      ]),
      PlanSection('padroes', 'Padrões', const [
        TableBlock(
          ['Padrão', 'Por que aqui', 'Alternativa rejeitada'],
          [
            [
              'Strategy',
              'FCM e APNs atrás da mesma interface',
              'if por plataforma no consumer',
            ],
            [
              'Outbox',
              'evento só sai se o pedido for salvo',
              'publicar direto na fila',
            ],
            [
              'Cubit',
              'estado simples da permissão',
              'sealed state com 6 variantes',
            ],
          ],
        ),
      ]),
      PlanSection('ds', 'Design System', const [
        TableBlock(
          ['Nó no Figma', 'Componente', 'Variante'],
          [
            ['12:350 Card de permissão', 'Card', 'elevated'],
            ['12:352 Botão permitir', 'Button', 'primary'],
            ['12:353 Agora não', 'Button', 'ghost'],
          ],
        ),
      ]),
      PlanSection('estrutura', 'Estrutura de pastas', const [
        CodeBlock('', """services/notifier/
  src/consumer.ts          # new
  src/preferences.ts       # new
  src/providers/fcm.ts     # new
  src/providers/apns.ts    # new
apps/mobile/lib/notifications/
  push_service.dart        # new
  permission_prompt.dart   # new
  push_cubit.dart          # new"""),
      ]),
      PlanSection('codigo', 'Código', const [
        CodeBlock(
          'services/notifier/src/providers/provider.ts',
          """export interface PushProvider {
  send(token: string, message: PushMessage): Promise<Delivery>;
}""",
        ),
        CodeBlock(
          'apps/mobile/lib/notifications/push_cubit.dart',
          """class PushCubit extends Cubit<PushState> {
  Future<void> requestPermissionAfterFirstOrder();
}""",
        ),
      ]),
      PlanSection('observabilidade', 'Observabilidade', const [
        TableBlock(
          ['Evento', 'Quando', 'Propriedades'],
          [
            ['push_permission_prompted', 'prompt exibido', 'source'],
            ['push_opened', 'toque na notificação', 'order_status'],
          ],
        ),
        BulletsBlock([
          'Nunca logar o token do device',
          'Dashboard: entrega, abertura, falhas por provider',
        ]),
      ]),
      PlanSection('testes', 'Testes', const [
        BulletsBlock([
          'Unit e widget por arquivo, meta de 90% de cobertura',
          'Flow Maestro: primeiro pedido → prompt → permitir → push abre o pedido',
          'Ordem: emulador Android, depois simulador iOS',
        ]),
      ]),
      PlanSection('execucao', 'Execução', [
        const TextBlock(
          'Cada loop vira um PR. Tarefas do mesmo grupo rodam em paralelo como subagentes; o próximo grupo espera.',
        ),
        LoopsBlock(loops),
      ]),
      PlanSection('entregas', 'Entregas', const [
        TableBlock(
          ['PR', 'Branch', 'Pacotes', '≈ linhas'],
          [
            [
              '1',
              'feat/1-evento-order-status-changed',
              'services/orders',
              '180',
            ],
            [
              '2',
              'feat/2-notifier-com-fila-retry-e-dlq',
              'services/notifier',
              '420',
            ],
            ['3', 'feat/3-app-permissao-e-recebimento', 'apps/mobile', '380'],
            [
              '4',
              'feat/4-auditoria-e-painel-de-entregas',
              'services/notifier',
              '150',
            ],
          ],
        ),
        TextBlock('PRs 1 e 2 formam uma stack; 3 e 4 saem de 2 em paralelo.'),
      ]),
      PlanSection('pendencias', 'Pendências e riscos', const [
        TableBlock(
          ['Item', 'Impacto', 'Quem resolve'],
          [
            ['Contrato do evento sem OpenAPI', 'bloqueia', 'back end'],
            ['E-mail como fallback (PRD x Jira)', 'médio', 'produto'],
            ['Cota do APNs em staging', 'baixo', 'dev'],
          ],
        ),
      ]),
    ],
    threads: [
      CommentThread('t1', 'padroes', 'Padrões', [
        Comment(
          'Você',
          'Por que Outbox? O serviço de pedidos já usa Kafka.',
          ago(40),
        ),
      ]),
    ],
  );
  // Already approved before this session, to show the mixed state.
  for (final id in ['fontes', 'checklist', 'escopo', 'arquitetura']) {
    final sec = plan.section(id);
    sec
      ..approvedDigest = sec.digest
      ..approvedAt = ago(35);
  }
  return plan;
}

/// Drafts a plan from the links and description of "Novo plano". The daemon
/// will have the planning session read the sources and fill this in.
Plan draftPlan(String name, String description, List<String> links) {
  final sources = links.map(PlanSource.fromUrl).toList();
  return Plan(
    summary: description.isEmpty ? name : description,
    sources: sources,
    proposedCards: [],
    sections: [
      PlanSection('fontes', 'Fontes', [
        TableBlock(
          ['Fonte', 'O que decidiu', 'Critérios que traz'],
          [
            for (final s in sources)
              ['${s.kind} · ${s.url}', 'lendo…', 'lendo…'],
          ],
        ),
      ]),
      for (final (id, title) in const [
        ('checklist', 'Checklist'),
        ('escopo', 'Escopo'),
        ('arquitetura', 'Arquitetura'),
        ('padroes', 'Padrões'),
        ('ds', 'Design System'),
        ('estrutura', 'Estrutura de pastas'),
        ('codigo', 'Código'),
        ('observabilidade', 'Observabilidade'),
        ('testes', 'Testes'),
        ('execucao', 'Execução'),
        ('entregas', 'Entregas'),
        ('pendencias', 'Pendências e riscos'),
      ])
        PlanSection(id, title, const [
          TextBlock('Em elaboração a partir das fontes.'),
        ]),
    ],
  )..drafting = true;
}

/// Fills a drafted plan once the sources are "read". Loops follow the
/// create-feature order: data, then presentation, then wiring and E2E.
void fillDraft(Plan plan, String name) {
  final fill = <String, List<PlanBlock>>{
    'fontes': [
      TableBlock(
        ['Fonte', 'O que decidiu', 'Critérios que traz'],
        [
          for (final s in plan.sources)
            ['${s.kind} · ${s.url}', 'resumo lido', 'ver checklist'],
        ],
      ),
    ],
    'checklist': const [
      TableBlock(
        ['Item', 'Resposta', 'Origem'],
        [
          ['Métrica de sucesso', 'a confirmar', 'pendente'],
          ['Estados da tela', 'loading, vazio, erro, sucesso', 'fonte'],
          ['Feature flag', 'a definir', 'pendente'],
        ],
      ),
    ],
    'escopo': const [
      BulletsBlock([
        'Consome serviço: a confirmar',
        'Plataformizado: não',
        'Local: app',
      ]),
    ],
    'arquitetura': const [
      FlowBlock([
        PlanBox('Tela', 'widgets + cubit'),
        PlanBox('Repositório', 'contrato do domínio'),
        PlanBox('Data source', 'chamada HTTP'),
        PlanBox('API', 'back end existente'),
      ]),
    ],
    'padroes': const [
      TableBlock(
        ['Padrão', 'Por que aqui', 'Alternativa rejeitada'],
        [
          ['Repository', 'isola a fonte de dados', 'chamar a API do cubit'],
        ],
      ),
    ],
    'ds': const [
      TextBlock('Mapeamento Figma → componentes depois da leitura das telas.'),
    ],
    'estrutura': [
      CodeBlock(
        '',
        'lib/features/${_slugOf(name)}/\n  data/\n  domain/\n  presentation/',
      ),
    ],
    'codigo': const [
      CodeBlock(
        'domain/repository.dart',
        'abstract interface class Repository {\n  Future<Entity> load();\n}',
      ),
    ],
    'observabilidade': const [
      BulletsBlock(['Evento de abertura da tela', 'Falhas do data source']),
    ],
    'testes': const [
      BulletsBlock([
        'Unit e widget por arquivo, 90%',
        'Flow E2E: Android, depois iOS',
      ]),
    ],
    'entregas': const [TextBlock('Um PR por loop, em stack.')],
    'pendencias': const [
      TableBlock(
        ['Item', 'Impacto', 'Quem resolve'],
        [
          ['Métrica de sucesso', 'médio', 'produto'],
        ],
      ),
    ],
  };
  final loops = [
    TaskCard(
      number: 1,
      title: 'Camada de dados',
      type: 'feat',
      model: 'opus',
      tasks: const [
        CardTask(
          'T1',
          'Entidades + contratos',
          skill: 'clean-arch-layer-generator',
          model: 'opus',
          group: 1,
        ),
        CardTask(
          'T2',
          'Data sources + models',
          skill: 'clean-arch-layer-generator',
          model: 'sonnet',
          group: 2,
          dependsOn: ['T1'],
        ),
        CardTask(
          'T3',
          'Repository impl',
          skill: 'clean-arch-layer-generator',
          model: 'sonnet',
          group: 2,
          dependsOn: ['T1'],
        ),
        CardTask(
          'T4',
          'Testes de dados',
          skill: 'unit-tests-handler',
          model: 'sonnet',
          group: 3,
          dependsOn: ['T2', 'T3'],
        ),
      ],
    ),
    TaskCard(
      number: 2,
      title: 'Apresentação',
      type: 'feat',
      model: 'sonnet',
      dependsOn: [1],
      tasks: const [
        CardTask(
          'T5',
          'Cubits',
          skill: 'cubit-state-creator',
          model: 'sonnet',
          group: 1,
        ),
        CardTask(
          'T6',
          'Widgets e telas',
          skill: 'presentation-layer-scaffolder',
          model: 'sonnet',
          group: 1,
        ),
        CardTask(
          'T7',
          'Eventos, logs e falhas',
          skill: 'event-bridge-implementer',
          model: 'haiku',
          group: 1,
        ),
        CardTask(
          'T8',
          'Testes de cubit e widget',
          skill: 'unit-tests-handler',
          model: 'sonnet',
          group: 2,
          dependsOn: ['T5', 'T6'],
        ),
      ],
    ),
    TaskCard(
      number: 3,
      title: 'Wiring e E2E',
      type: 'feat',
      model: 'sonnet',
      dependsOn: [2],
      tasks: const [
        CardTask(
          'T9',
          'DI + rota',
          skill: 'di-route-wirer',
          model: 'haiku',
          group: 1,
        ),
        CardTask(
          'T10',
          'Flow Maestro',
          skill: 'maestro-e2e-scaffolder',
          model: 'sonnet',
          group: 2,
          dependsOn: ['T9'],
        ),
        CardTask(
          'T11',
          'Android, depois iOS',
          skill: 'run-test-learn',
          model: 'sonnet',
          group: 3,
          dependsOn: ['T10'],
        ),
      ],
    ),
  ];
  plan.proposedCards.addAll(loops);
  fill['execucao'] = [
    const TextBlock(
      'Cada loop vira um PR. Tarefas do mesmo grupo rodam em paralelo; o próximo grupo espera.',
    ),
    LoopsBlock(plan.proposedCards),
  ];
  for (final sec in plan.sections) {
    sec.blocks = fill[sec.id] ?? sec.blocks;
  }
  plan.drafting = false;
}

String _slugOf(String name) =>
    foldAccents(name).replaceAll(RegExp(r'[^a-z0-9]+'), '_');
