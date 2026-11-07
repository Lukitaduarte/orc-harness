// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get languageSystem => 'Idioma do sistema';

  @override
  String get language => 'Idioma';

  @override
  String get orcReady => 'Ready to work!';

  @override
  String get orcWorkWork => 'Work, work.';

  @override
  String get orcZugZug => 'Zug zug!';

  @override
  String get orcNeedDoing => 'Something need doing?';

  @override
  String get orcNotThatKind => 'Me not that kind of orc!';

  @override
  String get orcJobsDone => 'Job\'s done!';

  @override
  String coreHaltFailed(String note) {
    return 'Não começou: $note';
  }

  @override
  String coreHaltStopped(String note) {
    return 'Parou: $note';
  }

  @override
  String get coreUnknownError => 'erro';

  @override
  String get coreSessionEnded => 'sessão encerrada';

  @override
  String corePromptCard(String number, String plan, String title, String type) {
    return 'Card #$number do plano \"$plan\": $title ($type)';
  }

  @override
  String corePromptPlan(String summary) {
    return 'Plano: $summary';
  }

  @override
  String get corePromptCriteria => 'Critérios de aceite:';

  @override
  String get corePromptTasks =>
      'Tarefas, por grupo (subagentes, com skill e modelo):';

  @override
  String corePromptTask(
    String group,
    String title,
    String skill,
    String model,
  ) {
    return '- grupo $group: $title · $skill · $model';
  }

  @override
  String get corePromptNeedsOk => ' — peça o OK do usuário antes';

  @override
  String get corePromptNotes => 'Notas:';

  @override
  String corePromptDraft(String name) {
    return 'Escreva o plano \"$name\" preenchendo cada seção do template conforme a instrução dela.';
  }

  @override
  String corePromptBuild(String description) {
    return 'O que construir: $description';
  }

  @override
  String get corePromptSources => 'Fontes:';

  @override
  String get corePromptReview =>
      'Revise o plano a partir destes comentários e salve com save_plan, respondendo cada um em replies:';

  @override
  String get corePromptLocked =>
      ' (aprovada: não mude, registre em amendments)';

  @override
  String get coreAlertWaitingTitle => 'Esperando você';

  @override
  String coreAlertWaitingBody(String session) {
    return '$session precisa de uma resposta.';
  }

  @override
  String get coreAlertEnvTitle => 'Um agente pede uma env';

  @override
  String coreAlertEnvBody(String session, String name) {
    return '$session quer gravar $name. Aprove ou recuse no app.';
  }

  @override
  String get coreAlertApprovalTitle => 'Precisa do seu OK';

  @override
  String get coreAlertPrTitle => 'PR aberto';

  @override
  String coreAlertPrBody(String plan, String number) {
    return '$plan · card #$number está em review.';
  }

  @override
  String get coreAlertMergedTitle => 'Card mergeado';

  @override
  String coreAlertMergedBody(String plan, String number) {
    return '$plan · card #$number foi feito.';
  }

  @override
  String get coreAlertStoppedTitle => 'Card parou';

  @override
  String coreAlertStoppedBody(String plan, String number, String note) {
    return '$plan · card #$number: $note.';
  }

  @override
  String get coreBudgetOverTitle => 'Orçamento estourado';

  @override
  String get coreBudget80Title => 'Orçamento em 80%';

  @override
  String coreBudgetBody(String workspace, String spent, String budget) {
    return '$workspace: US\$$spent de US\$$budget este mês.';
  }

  @override
  String get coreEnvWithValue => 'Keychain do daemon · com valor';

  @override
  String get coreEnvNoValue => 'Keychain do daemon · sem valor ainda';

  @override
  String coreAmendment(String text) {
    return 'Emenda: $text';
  }

  @override
  String coreCommentOn(String section, String text) {
    return 'Comentário em $section: $text';
  }

  @override
  String get coreImportedPlan => 'Plano importado';

  @override
  String devRepoBase(String branch) {
    return 'base $branch';
  }

  @override
  String get devNewWorktreeSession => 'Nova sessão em worktree';

  @override
  String get devTrustWorktreesHint =>
      'O Claude Code pergunta se confia em cada pasta nova. Responda \"Yes\" uma vez nesta sessão e todas as worktrees do harness ficam confiáveis.';

  @override
  String get devTrustWorktrees => 'Confiar nas worktrees';

  @override
  String get devAddRepository => 'Adicionar repositório';

  @override
  String get devAddRepositoryHint =>
      'Um clone local. As sessões trabalham em worktrees dele, uma por branch.';

  @override
  String get devName => 'Nome';

  @override
  String get devClonePath => 'Caminho do clone';

  @override
  String get devClonePathPlaceholder => '~/Project/meu-repo';

  @override
  String get devChoose => 'Escolher…';

  @override
  String get devBaseBranch => 'Branch base';

  @override
  String get devCancel => 'Cancelar';

  @override
  String get devAdd => 'Adicionar';

  @override
  String devNewSessionIn(String project) {
    return 'Nova sessão em $project';
  }

  @override
  String get devNewWorktreeHint =>
      'Cria (ou reaproveita) a worktree da branch. Commits fora de conventional commits são recusados nela.';

  @override
  String get devBranch => 'Branch';

  @override
  String get devBranchRule =>
      'Use letras, números, . _ / -; ex.: feat/12-login';

  @override
  String get devCreateSession => 'Criar sessão';

  @override
  String get devLoading => 'Carregando…';

  @override
  String get devChooseFolder => 'Escolher pasta';

  @override
  String get devFolderUp => 'Subir';

  @override
  String get devFolderHome => 'Início';

  @override
  String get devHideHidden => 'Esconder ocultas';

  @override
  String get devShowHidden => 'Mostrar ocultas';

  @override
  String get devNoSubfolders => 'Nenhuma subpasta.';

  @override
  String get devUseThisFolder => 'Usar esta pasta';

  @override
  String get devCommitPlaceholder => 'feat(escopo): o que muda';

  @override
  String get devCommit => 'Commit';

  @override
  String get devPush => 'Push';

  @override
  String get devMergeSquash => 'Merge (squash)';

  @override
  String devGitResultOk(String op) {
    return '$op: ok';
  }

  @override
  String devGitResultFailed(String op) {
    return '$op: falhou';
  }

  @override
  String get devSessionChanges => 'Mudanças da sessão';

  @override
  String devDiffSummary(int count, String base) {
    return '$count arquivo(s) contra $base, incluindo o que ainda não foi commitado';
  }

  @override
  String get devNoPr => 'sem PR';

  @override
  String get devNoChangesYet => 'Nenhuma mudança ainda.';

  @override
  String get devPrDraft => 'rascunho';

  @override
  String devPrChip(String number, String state) {
    return 'PR #$number · $state';
  }

  @override
  String devPrChecksFailing(int count) {
    return '$count check(s) falhando';
  }

  @override
  String get devPrChecksOk => 'checks ok';

  @override
  String get devUntrackedFile => 'Arquivo novo, ainda não rastreado pelo git.';

  @override
  String get devDefinitionNotFound => 'Definição não encontrada.';

  @override
  String devDefinedOutside(String location) {
    return 'Definido fora do projeto: $location';
  }

  @override
  String get devNothingAboutSymbol => 'Nada sobre este símbolo.';

  @override
  String get devPickFile => 'Escolha um arquivo à esquerda.';

  @override
  String get devGoToDefinition => 'Ir para definição (F12)';

  @override
  String get devAboutSymbol => 'Sobre o símbolo (⌘I)';

  @override
  String get devFormat => 'Formatar (⇧⌥F)';

  @override
  String get devSeverityError => 'erro';

  @override
  String get devSeverityWarning => 'aviso';

  @override
  String devDiagnostic(String severity, int line, String message) {
    return '$severity · linha $line: $message';
  }

  @override
  String get devBack => 'Voltar';

  @override
  String get devForward => 'Avançar';

  @override
  String get devReload => 'Recarregar';

  @override
  String get devAddress => 'Endereço';

  @override
  String get devCloseBrowser => 'Fechar o navegador (cookies ficam no perfil)';

  @override
  String get devOpenWorkspaceBrowser => 'Abrir navegador do workspace';

  @override
  String get devConnectingTerminal => 'Conectando ao terminal…';

  @override
  String get devMessageClaude => 'Mensagem para o Claude';

  @override
  String get devNoQuotaReading => 'sem leitura de quota ainda';

  @override
  String get devSessions => 'Sessões';

  @override
  String get devPlans => 'Planos';

  @override
  String devDeleteSessionTitle(String name) {
    return 'Apagar a sessão $name?';
  }

  @override
  String get devDeleteSessionBody =>
      'Encerra o processo. A worktree, os commits e a conversa ficam.';

  @override
  String get devDelete => 'Apagar';

  @override
  String get devNoSessions => 'Nenhuma sessão neste workspace.';

  @override
  String get devNewSession => 'Nova sessão';

  @override
  String devPlanReviewProgress(int approved, int total, int comments) {
    return '$approved/$total seções aprovadas · $comments comentários';
  }

  @override
  String devCardsDone(int done, int total) {
    return '$done/$total cards feitos';
  }

  @override
  String devDeletePlanTitle(String name) {
    return 'Apagar o plano $name?';
  }

  @override
  String get devDeletePlanBody =>
      'Sessões dos cards em execução são encerradas. Branches, worktrees e PRs ficam.';

  @override
  String get devNoPlans => 'Nenhum plano neste workspace.';

  @override
  String get devRetry => 'Tentar de novo';

  @override
  String get devColumnBlocked => 'bloqueado';

  @override
  String get devColumnReady => 'pronto';

  @override
  String get devColumnRunning => 'rodando';

  @override
  String get devColumnReview => 'review';

  @override
  String get devColumnDone => 'feito';

  @override
  String plansVersion(int version) {
    return 'plano v$version';
  }

  @override
  String plansRunningSince(String time) {
    return 'em execução desde $time';
  }

  @override
  String plansApprovedCount(int approved, int total) {
    return '$approved/$total seções aprovadas';
  }

  @override
  String get plansPlanningSession => 'Sessão de planejamento';

  @override
  String get plansClaudeReviewing => 'Claude revisando…';

  @override
  String get plansAskClaudeReview => 'Pedir revisão ao Claude';

  @override
  String plansAskClaudeReviewCount(int count) {
    return 'Pedir revisão ao Claude ($count)';
  }

  @override
  String plansDrafting(int count) {
    return 'Claude está lendo $count fontes e escrevendo as seções…';
  }

  @override
  String plansStartLoops(int count) {
    return 'Iniciar execução · $count loops';
  }

  @override
  String plansChangedAfterApprovalCount(int count) {
    return '$count seção alterada após aprovação';
  }

  @override
  String plansStartApproved(int approved, int total) {
    return 'Iniciar execução · $approved/$total aprovadas';
  }

  @override
  String plansTemplateInstruction(String instruction) {
    return 'Instrução do template: $instruction';
  }

  @override
  String get plansChangedAfterApproval => 'alterada após aprovação';

  @override
  String plansOpenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count abertos',
      one: '1 aberto',
    );
    return '$_temp0';
  }

  @override
  String get plansComment => 'Comentar';

  @override
  String get plansApprove => 'Aprovar';

  @override
  String get plansApprovedSectionPlaceholder =>
      'Seção aprovada: o comentário vira emenda do primeiro loop…';

  @override
  String plansCommentOn(String section) {
    return 'Comentar em $section…';
  }

  @override
  String plansApprovedAt(String time, String digest) {
    return 'Aprovada $time · digest $digest';
  }

  @override
  String get plansApproved => 'aprovada';

  @override
  String get plansCanStartNow => 'pode começar já';

  @override
  String plansAfterLoops(String loops) {
    return 'depois do $loops';
  }

  @override
  String plansLoopRef(int number) {
    return 'loop $number';
  }

  @override
  String get plansListAnd => ' e ';

  @override
  String get plansTableTask => 'Tarefa';

  @override
  String get plansTableModel => 'Modelo';

  @override
  String get plansTableGroup => 'Grupo';

  @override
  String plansTaskAfter(String tasks) {
    return 'após $tasks';
  }

  @override
  String get plansYourOk => 'seu OK';

  @override
  String get plansComments => 'Comentários';

  @override
  String get plansHideResolved => 'Ocultar resolvidos';

  @override
  String get plansShowResolved => 'Ver resolvidos';

  @override
  String plansFiltering(String section) {
    return 'Filtrando: $section';
  }

  @override
  String get plansShowAll => 'Ver todos';

  @override
  String get plansNoCommentsHere =>
      'Nenhum comentário aqui.\nUse \"Comentar\" em qualquer seção.';

  @override
  String get plansAmendmentsHeader => 'EMENDAS PARA O PRIMEIRO LOOP';

  @override
  String get plansClaudeReviewingComments =>
      'Claude está revisando os comentários…';

  @override
  String get plansReviewHint =>
      'Em seção aberta, Claude ajusta a seção. Em seção aprovada, nada muda: o pedido vira emenda do primeiro loop.';

  @override
  String get plansResolved => 'resolvido';

  @override
  String get plansAwaitingClaude => 'aguardando Claude';

  @override
  String get plansReopen => 'Reabrir';

  @override
  String get plansResolve => 'Resolver';

  @override
  String get plansReply => 'Responder…';

  @override
  String plansBoardSummary(
    String repo,
    int done,
    int total,
    int running,
    int max,
  ) {
    return '$repo · $done/$total feitos · $running/$max em execução';
  }

  @override
  String plansRunReady(int count) {
    return 'Executar prontos ($count)';
  }

  @override
  String plansBoardHint(String email) {
    return 'Cada card roda na própria worktree e sessão, na conta com mais folga ($email).';
  }

  @override
  String get plansColumnBlocked => 'Bloqueados';

  @override
  String get plansColumnReady => 'Prontos';

  @override
  String get plansColumnRunning => 'Em execução';

  @override
  String get plansColumnReview => 'Em review';

  @override
  String get plansColumnDone => 'Feitos';

  @override
  String plansWaitingFor(String cards) {
    return 'aguardando $cards';
  }

  @override
  String get plansNoDependencies => 'sem dependências';

  @override
  String plansDependsOn(String cards) {
    return 'depende de $cards';
  }

  @override
  String get plansRun => 'Executar';

  @override
  String get plansOpenSession => 'Abrir sessão';

  @override
  String get plansSimulatePr => 'Simular PR';

  @override
  String get plansSimulateMerge => 'Simular merge';

  @override
  String plansPrMerged(int number) {
    return 'PR #$number mergeado';
  }

  @override
  String get plansRetry => 'Tentar de novo';

  @override
  String get plansQueued => 'Na fila: começa quando houver vaga';

  @override
  String get plansMerged => 'mergeado';

  @override
  String get plansPhaseZeroSimulation => 'Simulação da fase 0';

  @override
  String get plansAcceptanceCriteria => 'Critérios de aceite';

  @override
  String get plansNoCriteria => 'Nenhum critério definido.';

  @override
  String get plansTasksHeader => 'Tarefas · subagentes por grupo';

  @override
  String plansGroupParallel(int group) {
    return 'Grupo $group · em paralelo';
  }

  @override
  String plansGroup(int group) {
    return 'Grupo $group';
  }

  @override
  String get plansLoopResult => 'Resultado do loop';

  @override
  String get plansDependencies => 'Dependências';

  @override
  String get plansNoDependenciesLong =>
      'Nenhuma: pode rodar em paralelo com outros cards prontos.';

  @override
  String get plansSession => 'Sessão';

  @override
  String get plansCommentsAndNotes => 'Comentários e observações';

  @override
  String get plansNoCommentsYet => 'Nenhum comentário ainda.';

  @override
  String get plansAddNote => 'Adicionar observação…';

  @override
  String get plansStateDone => 'feito';

  @override
  String get plansStatePending => 'pendente';

  @override
  String get plansStateBlocked => 'bloqueado';

  @override
  String get plansStateReady => 'pronto';

  @override
  String get plansStateRunning => 'em execução';

  @override
  String get plansStateReview => 'em review';

  @override
  String get plansLearnIntro =>
      'Cada comentário nos cards vira uma mudança na skill que tem a lacuna. Você aprova antes de aplicar.';

  @override
  String get plansLearnEmptyLive =>
      'O Claude está lendo os comentários e as skills dos cards.\nAs propostas aparecem aqui; nada muda sem o seu OK.';

  @override
  String get plansLearnEmpty =>
      'Nenhum comentário novo nos cards.\nComente no dialog de um card e rode o Learn de novo.';

  @override
  String plansLearnNotApplied(String error) {
    return 'Não aplicou: $error';
  }

  @override
  String get plansDiscard => 'Descartar';

  @override
  String get plansApplyToSkill => 'Aplicar na skill';

  @override
  String get plansAppliedToSkill => 'Aplicado na skill';

  @override
  String get plansDiscarded => 'Descartado';

  @override
  String get plansImportedPlan => 'Plano importado';

  @override
  String get plansNewPlan => 'Novo plano';

  @override
  String get plansFromTemplate => 'A partir de um template';

  @override
  String get plansPasteMarkdown => 'Colar markdown';

  @override
  String get plansCancel => 'Cancelar';

  @override
  String get plansImportPlan => 'Importar plano';

  @override
  String get plansCreatePlan => 'Criar plano';

  @override
  String get plansRepository => 'Repositório';

  @override
  String get plansAddRepoFirst =>
      'Adicione um repositório na barra lateral (Este Mac) primeiro.';

  @override
  String get plansTemplate => 'Template';

  @override
  String get plansFeatureName => 'Nome da feature';

  @override
  String get plansSources => 'Fontes (Jira, Confluence, Figma), uma por linha';

  @override
  String get plansWhatToBuild => 'O que construir';

  @override
  String get plansImportHint =>
      'Qualquer markdown no formato de plano: cada ## vira uma seção aprovável, tabelas e listas viram widgets, ```mermaid vira diagrama e ```loops define a execução.';

  @override
  String get plansImportPlaceholder => '# Nome do plano\n\n## Fontes\n…';

  @override
  String plansAgo(String duration) {
    return 'há $duration';
  }

  @override
  String get plansYouInitial => 'V';

  @override
  String get plansWriteComment => 'Escreva um comentário…';

  @override
  String get shellNewWorkspace => 'Novo workspace';

  @override
  String get shellUsageAndCost => 'Uso e custo';

  @override
  String get shellCatalogTip => 'Catálogo de skills, MCPs e envs';

  @override
  String shellSidebarCounts(int accounts, int sessions) {
    return '$accounts contas · $sessions sessões';
  }

  @override
  String get shellAccounts => 'Contas';

  @override
  String get shellNewAccount => 'Nova conta';

  @override
  String get shellSessions => 'Sessões';

  @override
  String get shellNewSession => 'Nova sessão';

  @override
  String get shellDeleteSession => 'Apagar sessão';

  @override
  String shellDeleteSessionTitle(String name) {
    return 'Apagar a sessão $name?';
  }

  @override
  String get shellDeleteSessionBody =>
      'Encerra o processo e tira da lista. A worktree, os commits e a conversa (claude --resume) ficam.';

  @override
  String get shellDelete => 'Apagar';

  @override
  String get shellRepositories => 'Repositórios';

  @override
  String get shellAddRepository => 'Adicionar repositório';

  @override
  String get shellPlans => 'Planos';

  @override
  String get shellNewPlan => 'Novo plano';

  @override
  String get shellDeletePlan => 'Apagar plano';

  @override
  String shellDeletePlanTitle(String name) {
    return 'Apagar o plano $name?';
  }

  @override
  String get shellDeletePlanBodyRunning =>
      'Ele tem cards em execução: as sessões deles são encerradas. Branches, worktrees e PRs ficam.';

  @override
  String get shellDeletePlanBody => 'Branches, worktrees e PRs ficam.';

  @override
  String shellAccountTitle(String email) {
    return 'Conta $email';
  }

  @override
  String get shellLogoutButton => 'Sair da conta (/logout)';

  @override
  String get shellLogoutHint =>
      'Abre uma sessão nela e roda o /logout do Claude Code.';

  @override
  String get shellRemoveFromHarness => 'Remover do harness';

  @override
  String get shellRemoveHint =>
      'Encerra as sessões dela e a tira das contas. A pasta e as conversas ficam no disco.';

  @override
  String get shellCancel => 'Cancelar';

  @override
  String shellLogoutTitle(String email) {
    return 'Sair da conta $email?';
  }

  @override
  String get shellLogoutDefaultBody =>
      'É a conta padrão do Claude Code neste Mac: o login sai também fora do harness.';

  @override
  String get shellLogoutBody => 'O login dessa conta sai do Claude Code.';

  @override
  String get shellLogout => 'Sair';

  @override
  String shellRemoveTitle(String email) {
    return 'Remover $email do harness?';
  }

  @override
  String get shellRemoveBody => 'As sessões dela são encerradas.';

  @override
  String get shellRemove => 'Remover';

  @override
  String get shellNoReadingYet =>
      'sem leitura ainda: a quota chega com a primeira resposta do Claude';

  @override
  String shellUpdatedAgo(String duration) {
    return 'atualizado há $duration';
  }

  @override
  String shellResetIn(String duration) {
    return 'reset em $duration';
  }

  @override
  String shellExhaustsIn(String duration) {
    return 'nesse ritmo, esgota em ~$duration';
  }

  @override
  String get shellPlanBadge => 'plano';

  @override
  String get shellSearchOrRun => 'Buscar ou rodar um comando…';

  @override
  String get shellExecution => 'Execução';

  @override
  String get shellPlan => 'Plano';

  @override
  String get shellUsage => 'Uso';

  @override
  String get shellCatalog => 'Catálogo';

  @override
  String get shellWorkspaceBrowser => 'Navegador do workspace';

  @override
  String shellToolInUse(String tool, String session) {
    return '$tool · em uso por $session';
  }

  @override
  String shellInUseBy(String session) {
    return 'em uso por $session';
  }

  @override
  String shellCodePaneTitle(String session) {
    return 'Código · $session';
  }

  @override
  String get shellEmptyPane => 'Pane vazio';

  @override
  String get shellChangesAndPr => 'Mudanças e PR';

  @override
  String get shellCodeTip => 'Código (IDE na pasta da sessão)';

  @override
  String get shellSplitSideBySide => 'Dividir lado a lado';

  @override
  String get shellSplitTopBottom => 'Dividir em cima e embaixo';

  @override
  String get shellClosePane => 'Fechar pane';

  @override
  String shellTokensCost(String tokens, String cost) {
    return '$tokens tokens · $cost';
  }

  @override
  String shellFiveHourShare(int percent) {
    return '$percent% da janela de 5h';
  }

  @override
  String get shellRestartingResumeLine => '↻ reiniciando com --resume…';

  @override
  String get shellOpenInPane => 'Abrir neste pane';

  @override
  String get shellSessionMemory => 'Memória das sessões';

  @override
  String get shellSessionMemoryHint =>
      'O que os agentes guardam (decisões, preferências, fatos dos projetos) e as outras sessões do workspace encontram.';

  @override
  String get shellMemoryHarness => 'Do harness';

  @override
  String get shellMemoryOff => 'Desligada';

  @override
  String get shellWorkspace => 'Workspace';

  @override
  String get shellWorkspaceHint =>
      'Um workspace junta contas, sessões, repositórios, planos e um navegador com logins próprios (ex.: Trabalho, Pessoal).';

  @override
  String get shellName => 'Nome';

  @override
  String get shellWorkspaceAccounts => 'Contas neste workspace';

  @override
  String get shellWorkspaceAccountsHint =>
      'Uma conta fica em um workspace só; marcar aqui a tira do outro.';

  @override
  String shellAccountInWorkspace(String email, String workspace) {
    return '$email (em $workspace)';
  }

  @override
  String get shellMonthlyBudget => 'Orçamento mensal (US\$)';

  @override
  String get shellBudgetHint =>
      'Opcional. O app avisa ao chegar em 80% e ao passar do limite.';

  @override
  String get shellBudgetExample => 'ex.: 200';

  @override
  String get shellDeleteWorkspace => 'Excluir';

  @override
  String get shellCreate => 'Criar';

  @override
  String get shellSave => 'Salvar';

  @override
  String shellNewAccountBody(String workspace) {
    return 'Uma conta do Claude Code com pasta de configuração própria (~/.orc/accounts/<nome>) no workspace $workspace. Abre uma sessão nela: faça o login com /login.';
  }

  @override
  String get shellAccountName => 'Nome da conta';

  @override
  String get shellAccountNameExample => 'trabalho-2';

  @override
  String get shellAccountTaken => 'Já existe uma conta com esse nome.';

  @override
  String get shellAccountRule => 'Use letras, números, - e _.';

  @override
  String get shellCreateAndLogin => 'Criar e fazer login';

  @override
  String shellApprovalRequest(String session, String action) {
    return '$session quer: $action. Fica bloqueado até você decidir (10 min).';
  }

  @override
  String get shellDecline => 'Recusar';

  @override
  String get shellApprove => 'Aprovar';

  @override
  String shellEnvRequest(String session, String env) {
    return '$session pede para gravar $env no Keychain do daemon. O valor não aparece aqui.';
  }

  @override
  String get shellDismiss => 'Dispensar';

  @override
  String get shellSelectSession => 'Selecione uma sessão';

  @override
  String get shellSessionProfile => 'Perfil da sessão';

  @override
  String get shellRestartingWithResume => 'Reiniciando com --resume…';

  @override
  String get shellApplyHint =>
      'Aplicar reinicia a sessão com --resume. O contexto é mantido.';

  @override
  String get shellDiscard => 'Descartar';

  @override
  String get shellApply => 'Aplicar';

  @override
  String get shellPairAnother => 'Parear outro aparelho';

  @override
  String get shellShowPairingQr => 'Mostrar QR de pareamento';

  @override
  String get shellPairQrHint =>
      'No celular: Conectar daemon → Escanear o QR. Vale uma vez, por 10 minutos.';

  @override
  String get shellCopy => 'Copiar';

  @override
  String get shellPairedDevices => 'Aparelhos pareados';

  @override
  String shellThisDevice(String name) {
    return '$name (este)';
  }

  @override
  String get shellRevoke => 'Revogar';

  @override
  String get shellNoDaemon => 'Este app foi iniciado sem o daemon.';

  @override
  String get shellConnectDaemon => 'Conectar daemon';

  @override
  String shellConnectedCounts(int accounts, int sessions) {
    return 'Conectado: $accounts conta(s), $sessions sessão(ões).';
  }

  @override
  String get shellConnecting => 'Conectando…';

  @override
  String get shellPairedOffline => 'Pareado, sem conexão agora.';

  @override
  String get shellNotPaired => 'Ainda não pareado.';

  @override
  String get shellPairInstructions =>
      'No Mac onde o orcd roda: `orcd serve` e, em outro terminal, `orcd pair`. Cole aqui o ticket (vale 10 minutos, uma vez).';

  @override
  String get shellScanPairQr => 'Escanear o QR do `orcd pair`';

  @override
  String get shellClose => 'Fechar';

  @override
  String get shellPairAndConnect => 'Parear e conectar';

  @override
  String get shellPointAtQr => 'Aponte para o QR do orcd pair';

  @override
  String get toolsSessionRunning => 'rodando';

  @override
  String get toolsSessionWaiting => 'esperando você';

  @override
  String get toolsSessionStarting => 'reiniciando';

  @override
  String get toolsSessionIdle => 'ociosa';

  @override
  String get toolsCatalogTitle => 'Catálogo';

  @override
  String get toolsCatalogSubtitle =>
      'Configure uma vez; cada sessão liga o que precisa no painel de perfil.';

  @override
  String get toolsAdd => 'Adicionar';

  @override
  String get toolsPlanTemplatesHeader => 'TEMPLATES DE PLAN MODE';

  @override
  String get toolsNewTemplate => 'Novo template';

  @override
  String get toolsPlanTemplatesHelp =>
      'Markdown com as seções de cada tipo de trabalho e a instrução de cada uma. Escolhido no \"Novo plano\".';

  @override
  String toolsSectionCount(int count) {
    return '$count seções';
  }

  @override
  String get toolsEditMarkdown => 'Editar markdown';

  @override
  String get toolsKindSkills => 'Skills';

  @override
  String get toolsKindMcps => 'MCPs';

  @override
  String get toolsKindEnvs => 'Envs';

  @override
  String get toolsUnused => 'sem uso';

  @override
  String toolsUsedInSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'em $count sessões',
      one: 'em 1 sessão',
    );
    return '$_temp0';
  }

  @override
  String get toolsMcpTesting => 'testando…';

  @override
  String toolsMcpConnected(String count) {
    return 'conectado · $count tools';
  }

  @override
  String toolsMcpFailed(String reason) {
    return 'falhou: $reason';
  }

  @override
  String get toolsTestConnection => 'Testar conexão';

  @override
  String get toolsSkillFolder => 'Pasta da skill';

  @override
  String get toolsCommandOrUrl => 'Comando ou URL';

  @override
  String get toolsEnvValue => 'Valor (guardado no Keychain)';

  @override
  String get toolsAddToCatalog => 'Adicionar ao catálogo';

  @override
  String get toolsName => 'Nome';

  @override
  String get toolsDescription => 'Descrição';

  @override
  String get toolsCancel => 'Cancelar';

  @override
  String get toolsNewPlanTemplate => 'Novo template de plan mode';

  @override
  String get toolsEditTemplate => 'Editar template';

  @override
  String get toolsTemplateNameHint => 'Nome, ex.: Back end com deploy';

  @override
  String get toolsTemplateDescriptionHint => 'Quando usar este template';

  @override
  String get toolsDeleteTemplate => 'Excluir template';

  @override
  String get toolsSave => 'Salvar';

  @override
  String get toolsHarnessUnderstood => 'O QUE O HARNESS ENTENDEU';

  @override
  String toolsReadError(String error) {
    return 'Erro ao ler: $error';
  }

  @override
  String toolsSectionsAndLoops(int sections, int loops) {
    return '$sections seções · $loops loops';
  }

  @override
  String toolsInstruction(String text) {
    return 'instrução: $text';
  }

  @override
  String get toolsBlockText => 'texto';

  @override
  String get toolsBlockList => 'lista';

  @override
  String get toolsBlockTable => 'tabela';

  @override
  String get toolsBlockCode => 'código';

  @override
  String get toolsBlockFlowchart => 'flowchart';

  @override
  String get toolsBlockSequence => 'sequência';

  @override
  String get toolsBlockLoops => 'loops';

  @override
  String get toolsSectionEmpty => 'vazia';

  @override
  String toolsUsageTitle(String workspace) {
    return 'Uso · $workspace';
  }

  @override
  String get toolsUsageLiveSubtitle =>
      'Métricas do próprio Claude Code (OpenTelemetry), por sessão, conta e modelo.';

  @override
  String get toolsUsageDemoSubtitle =>
      'Dados de demonstração; o workspace Este Mac mostra os reais.';

  @override
  String toolsDays(int count) {
    return '$count dias';
  }

  @override
  String get toolsCost => 'Custo';

  @override
  String get toolsTokens => 'Tokens';

  @override
  String get toolsDailyAverage => 'Média por dia';

  @override
  String get toolsCacheRead => 'Lido do cache';

  @override
  String get toolsThisMonth => 'Este mês';

  @override
  String toolsBudgetShare(int percent, String workspace) {
    return '$percent% do orçamento mensal de $workspace';
  }

  @override
  String get toolsTokensByType => 'Tokens por tipo';

  @override
  String get toolsInput => 'Entrada';

  @override
  String get toolsOutput => 'Saída';

  @override
  String get toolsCacheWrite => 'Escrito no cache';

  @override
  String get toolsCostPerDay => 'Custo por dia (US\$)';

  @override
  String get toolsShowChart => 'Ver gráfico';

  @override
  String get toolsShowTable => 'Ver tabela';

  @override
  String get toolsByAccountModel => 'Por conta e modelo';

  @override
  String get toolsAccount => 'Conta';

  @override
  String get toolsModel => 'Modelo';

  @override
  String get toolsNoUsage => 'Nenhum uso registrado no período.';

  @override
  String get toolsByPlan => 'Por plano';

  @override
  String get toolsPlan => 'Plano';

  @override
  String get toolsCardsDone => 'Cards feitos';

  @override
  String get toolsNoPlans => 'Nenhum plano em execução no período.';

  @override
  String get toolsByProjectBranch => 'Por projeto e branch (cards)';

  @override
  String get toolsProject => 'Projeto';

  @override
  String get toolsBranch => 'Branch';

  @override
  String get toolsLooseSessions => 'sessões soltas';

  @override
  String get toolsNoTokens => 'Nenhum token no período.';

  @override
  String get toolsGroupSessions => 'Sessões';

  @override
  String get toolsGroupPanes => 'Panes';

  @override
  String get toolsGroupProjects => 'Projetos';

  @override
  String get toolsGroupCatalog => 'Catálogo';

  @override
  String get toolsGroupCode => 'Código';

  @override
  String get toolsGroupUsage => 'Uso';

  @override
  String get toolsGroupWorkspaces => 'Workspaces';

  @override
  String toolsGroupProfileOf(String name) {
    return 'Perfil de $name';
  }

  @override
  String toolsGoTo(String name) {
    return 'Ir para $name';
  }

  @override
  String get toolsNewSession => 'Nova sessão';

  @override
  String get toolsSplitSideBySide => 'Dividir lado a lado';

  @override
  String get toolsSplitTopBottom => 'Dividir em cima e embaixo';

  @override
  String get toolsClosePane => 'Fechar pane';

  @override
  String get toolsHideProfilePanel => 'Ocultar painel de perfil';

  @override
  String get toolsShowProfilePanel => 'Mostrar painel de perfil';

  @override
  String toolsOpenPlanOf(String name) {
    return 'Abrir plano de $name';
  }

  @override
  String toolsOpenNamed(String name) {
    return 'Abrir $name';
  }

  @override
  String toolsOpenComments(int count) {
    return '$count comentários abertos';
  }

  @override
  String toolsRunReadyCards(String name) {
    return 'Executar cards prontos de $name';
  }

  @override
  String toolsReadyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count prontos',
      one: '1 pronto',
    );
    return '$_temp0';
  }

  @override
  String get toolsRequestReview => 'Pedir revisão dos comentários ao Claude';

  @override
  String get toolsNewPlanFromTemplate => 'Novo plano a partir de um template';

  @override
  String get toolsImportPlan => 'Importar plano em markdown';

  @override
  String get toolsSearchCodeCmd => 'Buscar no código (⌘⇧F)';

  @override
  String get toolsOpenUsage => 'Abrir uso e custo do workspace';

  @override
  String get toolsOpenCatalog => 'Abrir catálogo de skills, MCPs e envs';

  @override
  String get toolsBackToSessions => 'Voltar para as sessões';

  @override
  String toolsTurnOff(String name) {
    return 'Desligar $name';
  }

  @override
  String toolsTurnOn(String name) {
    return 'Ligar $name';
  }

  @override
  String get toolsApplyChanges => 'Aplicar mudanças (reinicia com --resume)';

  @override
  String toolsSwitchTo(String name) {
    return 'Trocar para $name';
  }

  @override
  String get toolsNothingOpen => 'nada aberto';

  @override
  String get toolsSearchNeedsDaemon =>
      'Busca no código precisa do daemon conectado.';

  @override
  String toolsSearchIn(String label) {
    return 'Buscar em $label…';
  }

  @override
  String get toolsSymbols => 'Símbolos';

  @override
  String get toolsSearch => 'Buscar';

  @override
  String toolsResults(String count, String query) {
    return '$count resultado(s) para \"$query\"';
  }
}
