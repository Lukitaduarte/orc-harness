import 'model.dart';

// Fake data for phase 0. Replaced by the daemon in phase 1.

const catalog = [
  CatalogItem(
    'code-review',
    CatalogKind.skill,
    'code-review',
    'Revisa o diff atual',
  ),
  CatalogItem(
    'conventional-commits',
    CatalogKind.skill,
    'conventional-commits',
    'Padrão de commits',
  ),
  CatalogItem(
    'flutter-architecture',
    CatalogKind.skill,
    'flutter-architecture',
    'Camadas UI, lógica e dados',
  ),
  CatalogItem('docs', CatalogKind.skill, 'docs', 'Escreve documentação'),
  CatalogItem('postgres', CatalogKind.mcp, 'postgres', 'Banco de staging'),
  CatalogItem('linear', CatalogKind.mcp, 'linear', 'Issues e projetos'),
  CatalogItem('browser', CatalogKind.mcp, 'browser', 'Chromium do workspace'),
  CatalogItem('memory', CatalogKind.mcp, 'memory', 'Memória de longo prazo'),
  CatalogItem(
    'env-staging',
    CatalogKind.env,
    'STAGING',
    'API e banco de staging',
  ),
  CatalogItem(
    'env-prod-ro',
    CatalogKind.env,
    'PROD_READONLY',
    'Produção, só leitura',
  ),
  CatalogItem('env-sentry', CatalogKind.env, 'SENTRY_TOKEN', 'Token do Sentry'),
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
    branch: 'feat/12-users-pagination',
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
    branch: 'feat/13-users-table',
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
    '  Espero o PR da sessão api ou uso um mock do contrato?',
  ),
  TerminalLine(LineKind.dim, '  1. Esperar o PR #12'),
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
