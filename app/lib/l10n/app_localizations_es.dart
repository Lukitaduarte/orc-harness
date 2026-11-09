// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get languageSystem => 'Idioma del sistema';

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
    return 'No empezó: $note';
  }

  @override
  String coreHaltStopped(String note) {
    return 'Se detuvo: $note';
  }

  @override
  String get coreUnknownError => 'error';

  @override
  String get coreSessionEnded => 'sesión terminada';

  @override
  String corePromptCard(String number, String plan, String title, String type) {
    return 'Card #$number del plan \"$plan\": $title ($type)';
  }

  @override
  String corePromptPlan(String summary) {
    return 'Plan: $summary';
  }

  @override
  String get corePromptCriteria => 'Criterios de aceptación:';

  @override
  String get corePromptTasks =>
      'Tareas, por grupo (subagentes, con skill y modelo):';

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
  String get corePromptNeedsOk => ' — pide el OK del usuario antes';

  @override
  String get corePromptNotes => 'Notas:';

  @override
  String corePromptDraft(String name) {
    return 'Escribe el plan \"$name\" completando cada sección del template según su instrucción.';
  }

  @override
  String corePromptBuild(String description) {
    return 'Qué construir: $description';
  }

  @override
  String get corePromptSources => 'Fuentes:';

  @override
  String get corePromptReview =>
      'Revisa el plan a partir de estos comentarios y guárdalo con save_plan, respondiendo cada uno en replies:';

  @override
  String get corePromptLocked =>
      ' (aprobada: no la cambies, regístralo en amendments)';

  @override
  String get coreAlertWaitingTitle => 'Esperándote';

  @override
  String coreAlertWaitingBody(String session) {
    return '$session necesita una respuesta.';
  }

  @override
  String get coreAlertEnvTitle => 'Un agente pide una env';

  @override
  String coreAlertEnvBody(String session, String name) {
    return '$session quiere guardar $name. Apruébalo o recházalo en la app.';
  }

  @override
  String get coreAlertApprovalTitle => 'Necesita tu OK';

  @override
  String get coreAlertPrTitle => 'PR abierto';

  @override
  String coreAlertPrBody(String plan, String number) {
    return '$plan · card #$number está en review.';
  }

  @override
  String get coreAlertMergedTitle => 'Card mergeado';

  @override
  String coreAlertMergedBody(String plan, String number) {
    return '$plan · card #$number está hecho.';
  }

  @override
  String get coreAlertStoppedTitle => 'Card detenido';

  @override
  String coreAlertStoppedBody(String plan, String number, String note) {
    return '$plan · card #$number: $note.';
  }

  @override
  String get coreBudgetOverTitle => 'Presupuesto superado';

  @override
  String get coreBudget80Title => 'Presupuesto al 80%';

  @override
  String coreBudgetBody(String workspace, String spent, String budget) {
    return '$workspace: US\$$spent de US\$$budget este mes.';
  }

  @override
  String get coreEnvWithValue => 'Keychain del daemon · con valor';

  @override
  String get coreEnvNoValue => 'Keychain del daemon · sin valor aún';

  @override
  String coreAmendment(String text) {
    return 'Enmienda: $text';
  }

  @override
  String coreCommentOn(String section, String text) {
    return 'Comentario en $section: $text';
  }

  @override
  String get coreImportedPlan => 'Plan importado';

  @override
  String devRepoBase(String branch) {
    return 'base $branch';
  }

  @override
  String get devNewWorktreeSession => 'Nueva sesión en un worktree';

  @override
  String get devTrustWorktreesHint =>
      'Claude Code pregunta si confía en cada carpeta nueva. Responde \"Yes\" una vez en esta sesión y todos los worktrees del harness quedan como confiables.';

  @override
  String get devTrustWorktrees => 'Confiar en los worktrees';

  @override
  String get devAddRepository => 'Agregar repositorio';

  @override
  String get devAddRepositoryHint =>
      'Un clon local. Las sesiones trabajan en sus worktrees, uno por branch.';

  @override
  String get devName => 'Nombre';

  @override
  String get devClonePath => 'Ruta del clon';

  @override
  String get devClonePathPlaceholder => '~/Project/mi-repo';

  @override
  String get devChoose => 'Elegir…';

  @override
  String get devBaseBranch => 'Branch base';

  @override
  String get devCancel => 'Cancelar';

  @override
  String get devAdd => 'Agregar';

  @override
  String devNewSessionIn(String project) {
    return 'Nueva sesión en $project';
  }

  @override
  String get devNewWorktreeHint =>
      'Crea (o reutiliza) el worktree de la branch. Los commits que no siguen conventional commits se rechazan allí.';

  @override
  String get devBranch => 'Branch';

  @override
  String get devBranchRule =>
      'Usa letras, números, . _ / -; ej.: feat/12-login';

  @override
  String get devCreateSession => 'Crear sesión';

  @override
  String get devLoading => 'Cargando…';

  @override
  String get devChooseFolder => 'Elegir carpeta';

  @override
  String get devFolderUp => 'Subir';

  @override
  String get devFolderHome => 'Inicio';

  @override
  String get devHideHidden => 'Ocultar ocultas';

  @override
  String get devShowHidden => 'Mostrar ocultas';

  @override
  String get devNoSubfolders => 'No hay subcarpetas.';

  @override
  String get devUseThisFolder => 'Usar esta carpeta';

  @override
  String get devCommitPlaceholder => 'feat(alcance): qué cambia';

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
    return '$op: falló';
  }

  @override
  String get devSessionChanges => 'Cambios de la sesión';

  @override
  String devDiffSummary(int count, String base) {
    return '$count archivo(s) contra $base, incluyendo lo que aún no tiene commit';
  }

  @override
  String get devNoPr => 'sin PR';

  @override
  String get devNoChangesYet => 'Todavía no hay cambios.';

  @override
  String get devPrDraft => 'borrador';

  @override
  String devPrChip(String number, String state) {
    return 'PR #$number · $state';
  }

  @override
  String devPrChecksFailing(int count) {
    return '$count check(s) fallando';
  }

  @override
  String get devPrChecksOk => 'checks ok';

  @override
  String get devUntrackedFile =>
      'Archivo nuevo, todavía sin seguimiento en git.';

  @override
  String get devDefinitionNotFound => 'No se encontró la definición.';

  @override
  String devDefinedOutside(String location) {
    return 'Definido fuera del proyecto: $location';
  }

  @override
  String get devNothingAboutSymbol => 'Nada sobre este símbolo.';

  @override
  String get devPickFile => 'Elige un archivo a la izquierda.';

  @override
  String get devGoToDefinition => 'Ir a la definición (F12)';

  @override
  String get devAboutSymbol => 'Sobre el símbolo (⌘I)';

  @override
  String get devFormat => 'Formatear (⇧⌥F)';

  @override
  String get devSeverityError => 'error';

  @override
  String get devSeverityWarning => 'advertencia';

  @override
  String devDiagnostic(String severity, int line, String message) {
    return '$severity · línea $line: $message';
  }

  @override
  String get devBack => 'Atrás';

  @override
  String get devForward => 'Adelante';

  @override
  String get devReload => 'Recargar';

  @override
  String get devAddress => 'Dirección';

  @override
  String get devCloseBrowser =>
      'Cerrar el navegador (las cookies quedan en el perfil)';

  @override
  String get devOpenWorkspaceBrowser => 'Abrir el navegador del workspace';

  @override
  String get devConnectingTerminal => 'Conectando a la terminal…';

  @override
  String get devMessageClaude => 'Mensaje para Claude';

  @override
  String get devNoQuotaReading => 'todavía sin lectura de cuota';

  @override
  String get devSessions => 'Sesiones';

  @override
  String get devPlans => 'Planes';

  @override
  String devDeleteSessionTitle(String name) {
    return '¿Eliminar la sesión $name?';
  }

  @override
  String get devDeleteSessionBody =>
      'Termina el proceso. El worktree, los commits y la conversación se conservan.';

  @override
  String get devDelete => 'Eliminar';

  @override
  String get devNoSessions => 'No hay sesiones en este workspace.';

  @override
  String get devNewSession => 'Nueva sesión';

  @override
  String devPlanReviewProgress(int approved, int total, int comments) {
    return '$approved/$total secciones aprobadas · $comments comentarios';
  }

  @override
  String devCardsDone(int done, int total) {
    return '$done/$total tarjetas hechas';
  }

  @override
  String devDeletePlanTitle(String name) {
    return '¿Eliminar el plan $name?';
  }

  @override
  String get devDeletePlanBody =>
      'Las sesiones de las tarjetas en ejecución se terminan. Las branches, los worktrees y los PR se conservan.';

  @override
  String get devNoPlans => 'No hay planes en este workspace.';

  @override
  String get devRetry => 'Intentar de nuevo';

  @override
  String get devColumnBlocked => 'bloqueado';

  @override
  String get devColumnReady => 'listo';

  @override
  String get devColumnRunning => 'en ejecución';

  @override
  String get devColumnReview => 'revisión';

  @override
  String get devColumnDone => 'hecho';

  @override
  String plansVersion(int version) {
    return 'plan v$version';
  }

  @override
  String plansRunningSince(String time) {
    return 'en ejecución desde $time';
  }

  @override
  String plansApprovedCount(int approved, int total) {
    return '$approved/$total secciones aprobadas';
  }

  @override
  String get plansPlanningSession => 'Sesión de planificación';

  @override
  String get plansClaudeReviewing => 'Claude revisando…';

  @override
  String get plansAskClaudeReview => 'Pedir revisión a Claude';

  @override
  String plansAskClaudeReviewCount(int count) {
    return 'Pedir revisión a Claude ($count)';
  }

  @override
  String plansDrafting(int count) {
    return 'Claude está leyendo $count fuentes y escribiendo las secciones…';
  }

  @override
  String plansStartLoops(int count) {
    return 'Iniciar ejecución · $count loops';
  }

  @override
  String plansChangedAfterApprovalCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count secciones modificadas tras la aprobación',
      one: '1 sección modificada tras la aprobación',
    );
    return '$_temp0';
  }

  @override
  String plansStartApproved(int approved, int total) {
    return 'Iniciar ejecución · $approved/$total aprobadas';
  }

  @override
  String plansTemplateInstruction(String instruction) {
    return 'Instrucción de la plantilla: $instruction';
  }

  @override
  String get plansChangedAfterApproval => 'modificada tras la aprobación';

  @override
  String plansOpenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count abiertos',
      one: '1 abierto',
    );
    return '$_temp0';
  }

  @override
  String get plansComment => 'Comentar';

  @override
  String get plansApprove => 'Aprobar';

  @override
  String get plansApprovedSectionPlaceholder =>
      'Sección aprobada: el comentario se vuelve una enmienda del primer loop…';

  @override
  String plansCommentOn(String section) {
    return 'Comentar en $section…';
  }

  @override
  String plansApprovedAt(String time, String digest) {
    return 'Aprobada $time · digest $digest';
  }

  @override
  String get plansApproved => 'aprobada';

  @override
  String get plansCanStartNow => 'puede empezar ya';

  @override
  String plansAfterLoops(String loops) {
    return 'después del $loops';
  }

  @override
  String plansLoopRef(int number) {
    return 'loop $number';
  }

  @override
  String get plansListAnd => ' y ';

  @override
  String get plansTableTask => 'Tarea';

  @override
  String get plansTableModel => 'Modelo';

  @override
  String get plansTableGroup => 'Grupo';

  @override
  String plansTaskAfter(String tasks) {
    return 'después de $tasks';
  }

  @override
  String get plansYourOk => 'tu OK';

  @override
  String get plansComments => 'Comentarios';

  @override
  String get plansHideResolved => 'Ocultar resueltos';

  @override
  String get plansShowResolved => 'Ver resueltos';

  @override
  String plansFiltering(String section) {
    return 'Filtrando: $section';
  }

  @override
  String get plansShowAll => 'Ver todos';

  @override
  String get plansNoCommentsHere =>
      'No hay comentarios aquí.\nUsa \"Comentar\" en cualquier sección.';

  @override
  String get plansAmendmentsHeader => 'ENMIENDAS PARA EL PRIMER LOOP';

  @override
  String get plansClaudeReviewingComments =>
      'Claude está revisando los comentarios…';

  @override
  String get plansReviewHint =>
      'En una sección abierta, Claude ajusta la sección. En una sección aprobada, nada cambia: el pedido se vuelve una enmienda del primer loop.';

  @override
  String get plansResolved => 'resuelto';

  @override
  String get plansAwaitingClaude => 'esperando a Claude';

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
    return '$repo · $done/$total hechos · $running/$max en ejecución';
  }

  @override
  String plansRunReady(int count) {
    return 'Ejecutar listos ($count)';
  }

  @override
  String plansBoardHint(String email) {
    return 'Cada card corre en su propia worktree y sesión, en la cuenta con más margen ($email).';
  }

  @override
  String get plansColumnBlocked => 'Bloqueados';

  @override
  String get plansColumnReady => 'Listos';

  @override
  String get plansColumnRunning => 'En ejecución';

  @override
  String get plansColumnReview => 'En review';

  @override
  String get plansColumnDone => 'Hechos';

  @override
  String plansWaitingFor(String cards) {
    return 'esperando $cards';
  }

  @override
  String get plansNoDependencies => 'sin dependencias';

  @override
  String plansDependsOn(String cards) {
    return 'depende de $cards';
  }

  @override
  String get plansRun => 'Ejecutar';

  @override
  String get plansOpenSession => 'Abrir sesión';

  @override
  String get plansSimulatePr => 'Simular PR';

  @override
  String get plansSimulateMerge => 'Simular merge';

  @override
  String plansPrMerged(int number) {
    return 'PR #$number mergeado';
  }

  @override
  String get plansRetry => 'Intentar de nuevo';

  @override
  String get plansQueued => 'En cola: empieza cuando haya un lugar';

  @override
  String get plansMerged => 'mergeado';

  @override
  String get plansPhaseZeroSimulation => 'Simulación de la fase 0';

  @override
  String get plansAcceptanceCriteria => 'Criterios de aceptación';

  @override
  String get plansNoCriteria => 'Ningún criterio definido.';

  @override
  String get plansTasksHeader => 'Tareas · subagentes por grupo';

  @override
  String plansGroupParallel(int group) {
    return 'Grupo $group · en paralelo';
  }

  @override
  String plansGroup(int group) {
    return 'Grupo $group';
  }

  @override
  String get plansLoopResult => 'Resultado del loop';

  @override
  String get plansDependencies => 'Dependencias';

  @override
  String get plansNoDependenciesLong =>
      'Ninguna: puede correr en paralelo con otros cards listos.';

  @override
  String get plansSession => 'Sesión';

  @override
  String get plansCommentsAndNotes => 'Comentarios y observaciones';

  @override
  String get plansNoCommentsYet => 'Todavía no hay comentarios.';

  @override
  String get plansAddNote => 'Agregar observación…';

  @override
  String get plansStateDone => 'hecho';

  @override
  String get plansStatePending => 'pendiente';

  @override
  String get plansStateBlocked => 'bloqueado';

  @override
  String get plansStateReady => 'listo';

  @override
  String get plansStateRunning => 'en ejecución';

  @override
  String get plansStateReview => 'en review';

  @override
  String get plansLearnIntro =>
      'Cada comentario en los cards se vuelve un cambio en la skill que tiene la laguna. Tú apruebas antes de aplicar.';

  @override
  String get plansLearnEmptyLive =>
      'Claude está leyendo los comentarios y las skills de los cards.\nLas propuestas aparecen aquí; nada cambia sin tu OK.';

  @override
  String get plansLearnEmpty =>
      'No hay comentarios nuevos en los cards.\nComenta en el diálogo de un card y vuelve a correr Learn.';

  @override
  String plansLearnNotApplied(String error) {
    return 'No se aplicó: $error';
  }

  @override
  String get plansDiscard => 'Descartar';

  @override
  String get plansApplyToSkill => 'Aplicar en la skill';

  @override
  String get plansAppliedToSkill => 'Aplicado en la skill';

  @override
  String get plansDiscarded => 'Descartado';

  @override
  String get plansImportedPlan => 'Plan importado';

  @override
  String get plansNewPlan => 'Nuevo plan';

  @override
  String get plansFromTemplate => 'A partir de una plantilla';

  @override
  String get plansPasteMarkdown => 'Pegar markdown';

  @override
  String get plansCancel => 'Cancelar';

  @override
  String get plansImportPlan => 'Importar plan';

  @override
  String get plansCreatePlan => 'Crear plan';

  @override
  String get plansRepository => 'Repositorio';

  @override
  String get plansAddRepoFirst =>
      'Agrega un repositorio en la barra lateral (Esta Mac) primero.';

  @override
  String get plansTemplate => 'Plantilla';

  @override
  String get plansFeatureName => 'Nombre de la feature';

  @override
  String get plansSources => 'Fuentes (Jira, Confluence, Figma), una por línea';

  @override
  String get plansWhatToBuild => 'Qué construir';

  @override
  String get plansImportHint =>
      'Cualquier markdown en formato de plan: cada ## se vuelve una sección aprobable, las tablas y listas se vuelven widgets, ```mermaid se vuelve un diagrama y ```loops define la ejecución.';

  @override
  String get plansImportPlaceholder => '# Nombre del plan\n\n## Fuentes\n…';

  @override
  String plansAgo(String duration) {
    return 'hace $duration';
  }

  @override
  String get plansYouInitial => 'T';

  @override
  String get plansWriteComment => 'Escribe un comentario…';

  @override
  String get shellNewWorkspace => 'Nuevo workspace';

  @override
  String get shellUsageAndCost => 'Uso y costo';

  @override
  String get shellCatalogTip => 'Catálogo de skills, MCPs y envs';

  @override
  String shellSidebarCounts(int accounts, int sessions) {
    return '$accounts cuentas · $sessions sesiones';
  }

  @override
  String get shellAccounts => 'Cuentas';

  @override
  String get shellNewAccount => 'Nueva cuenta';

  @override
  String get shellSessions => 'Sesiones';

  @override
  String get shellNewSession => 'Nueva sesión';

  @override
  String get shellDeleteSession => 'Eliminar sesión';

  @override
  String shellDeleteSessionTitle(String name) {
    return '¿Eliminar la sesión $name?';
  }

  @override
  String get shellDeleteSessionBody =>
      'Termina el proceso y lo quita de la lista. La worktree, los commits y la conversación (claude --resume) se conservan.';

  @override
  String get shellDelete => 'Eliminar';

  @override
  String get shellRepositories => 'Repositorios';

  @override
  String get shellAddRepository => 'Agregar repositorio';

  @override
  String get shellPlans => 'Planes';

  @override
  String get shellNewPlan => 'Nuevo plan';

  @override
  String get shellDeletePlan => 'Eliminar plan';

  @override
  String shellDeletePlanTitle(String name) {
    return '¿Eliminar el plan $name?';
  }

  @override
  String get shellDeletePlanBodyRunning =>
      'Tiene cards en ejecución: sus sesiones se terminan. Las branches, worktrees y PRs se conservan.';

  @override
  String get shellDeletePlanBody =>
      'Las branches, worktrees y PRs se conservan.';

  @override
  String shellAccountTitle(String email) {
    return 'Cuenta $email';
  }

  @override
  String get shellLogoutButton => 'Cerrar sesión (/logout)';

  @override
  String get shellLogoutHint =>
      'Abre una sesión en ella y ejecuta el /logout de Claude Code.';

  @override
  String get shellRemoveFromHarness => 'Quitar del harness';

  @override
  String get shellRemoveHint =>
      'Termina sus sesiones y la quita de las cuentas. La carpeta y las conversaciones se quedan en el disco.';

  @override
  String get shellCancel => 'Cancelar';

  @override
  String shellLogoutTitle(String email) {
    return '¿Cerrar sesión de $email?';
  }

  @override
  String get shellLogoutDefaultBody =>
      'Es la cuenta predeterminada de Claude Code en esta Mac: la sesión se cierra también fuera del harness.';

  @override
  String get shellLogoutBody =>
      'La sesión de esta cuenta se cierra en Claude Code.';

  @override
  String get shellLogout => 'Cerrar sesión';

  @override
  String shellRemoveTitle(String email) {
    return '¿Quitar $email del harness?';
  }

  @override
  String get shellRemoveBody => 'Sus sesiones se terminan.';

  @override
  String get shellRemove => 'Quitar';

  @override
  String get shellNoReadingYet =>
      'sin lectura todavía: la cuota llega con la primera respuesta de Claude';

  @override
  String shellUpdatedAgo(String duration) {
    return 'actualizado hace $duration';
  }

  @override
  String shellResetIn(String duration) {
    return 'se reinicia en $duration';
  }

  @override
  String shellExhaustsIn(String duration) {
    return 'a este ritmo, se agota en ~$duration';
  }

  @override
  String get shellPlanBadge => 'plan';

  @override
  String get shellSearchOrRun => 'Buscar o ejecutar un comando…';

  @override
  String get shellExecution => 'Ejecución';

  @override
  String get shellPlan => 'Plan';

  @override
  String get shellUsage => 'Uso';

  @override
  String get shellCatalog => 'Catálogo';

  @override
  String get shellWorkspaceBrowser => 'Navegador del workspace';

  @override
  String shellToolInUse(String tool, String session) {
    return '$tool · en uso por $session';
  }

  @override
  String shellInUseBy(String session) {
    return 'en uso por $session';
  }

  @override
  String shellCodePaneTitle(String session) {
    return 'Código · $session';
  }

  @override
  String get shellEmptyPane => 'Pane vacío';

  @override
  String get shellChangesAndPr => 'Cambios y PR';

  @override
  String get shellCodeTip => 'Código (IDE en la carpeta de la sesión)';

  @override
  String get shellSplitSideBySide => 'Dividir lado a lado';

  @override
  String get shellSplitTopBottom => 'Dividir arriba y abajo';

  @override
  String get shellClosePane => 'Cerrar pane';

  @override
  String shellTokensCost(String tokens, String cost) {
    return '$tokens tokens · $cost';
  }

  @override
  String shellFiveHourShare(int percent) {
    return '$percent% de la ventana de 5h';
  }

  @override
  String get shellRestartingResumeLine => '↻ reiniciando con --resume…';

  @override
  String get shellOpenInPane => 'Abrir en este pane';

  @override
  String get shellSessionMemory => 'Memoria de las sesiones';

  @override
  String get shellSessionMemoryHint =>
      'Lo que los agentes guardan (decisiones, preferencias, datos de los proyectos) y las otras sesiones del workspace encuentran.';

  @override
  String get shellMemoryHarness => 'Del harness';

  @override
  String get shellMemoryOff => 'Desactivada';

  @override
  String get shellWorkspace => 'Workspace';

  @override
  String get shellWorkspaceHint =>
      'Un workspace reúne cuentas, sesiones, repositorios, planes y un navegador con sus propios inicios de sesión (p. ej.: Trabajo, Personal).';

  @override
  String get shellName => 'Nombre';

  @override
  String get shellWorkspaceAccounts => 'Cuentas en este workspace';

  @override
  String get shellWorkspaceAccountsHint =>
      'Una cuenta está en un solo workspace; marcarla aquí la quita del otro.';

  @override
  String shellAccountInWorkspace(String email, String workspace) {
    return '$email (en $workspace)';
  }

  @override
  String get shellMonthlyBudget => 'Presupuesto mensual (US\$)';

  @override
  String get shellBudgetHint =>
      'Opcional. La app avisa al llegar al 80% y al pasar el límite.';

  @override
  String get shellBudgetExample => 'p. ej.: 200';

  @override
  String get shellDeleteWorkspace => 'Eliminar';

  @override
  String get shellCreate => 'Crear';

  @override
  String get shellSave => 'Guardar';

  @override
  String shellNewAccountBody(String workspace) {
    return 'Una cuenta de Claude Code con su propia carpeta de configuración (~/.orc/accounts/<nombre>) en el workspace $workspace. Abre una sesión en ella: inicia sesión con /login.';
  }

  @override
  String get shellAccountName => 'Nombre de la cuenta';

  @override
  String get shellAccountNameExample => 'trabajo-2';

  @override
  String get shellAccountTaken => 'Ya existe una cuenta con ese nombre.';

  @override
  String get shellAccountRule => 'Usa letras, números, - y _.';

  @override
  String get shellCreateAndLogin => 'Crear e iniciar sesión';

  @override
  String shellApprovalRequest(String session, String action) {
    return '$session quiere: $action. Queda bloqueado hasta que decidas (10 min).';
  }

  @override
  String get shellDecline => 'Rechazar';

  @override
  String get shellApprove => 'Aprobar';

  @override
  String shellEnvRequest(String session, String env) {
    return '$session pide guardar $env en el Keychain del daemon. El valor no aparece aquí.';
  }

  @override
  String get shellDismiss => 'Descartar';

  @override
  String get shellSelectSession => 'Selecciona una sesión';

  @override
  String get shellSessionProfile => 'Perfil de la sesión';

  @override
  String get shellRestartingWithResume => 'Reiniciando con --resume…';

  @override
  String get shellApplyHint =>
      'Aplicar reinicia la sesión con --resume. El contexto se mantiene.';

  @override
  String get shellDiscard => 'Descartar';

  @override
  String get shellApply => 'Aplicar';

  @override
  String get shellPairAnother => 'Vincular otro dispositivo';

  @override
  String get shellShowPairingQr => 'Mostrar QR de vinculación';

  @override
  String get shellPairQrHint =>
      'En el celular: Conectar daemon → Escanear el QR. Vale una vez, por 10 minutos.';

  @override
  String get shellCopy => 'Copiar';

  @override
  String get shellPairedDevices => 'Dispositivos vinculados';

  @override
  String shellThisDevice(String name) {
    return '$name (este)';
  }

  @override
  String get shellRevoke => 'Revocar';

  @override
  String get shellNoDaemon => 'Esta app se inició sin el daemon.';

  @override
  String get shellConnectDaemon => 'Conectar daemon';

  @override
  String shellConnectedCounts(int accounts, int sessions) {
    return 'Conectado: $accounts cuenta(s), $sessions sesión(es).';
  }

  @override
  String get shellConnecting => 'Conectando…';

  @override
  String get shellPairedOffline => 'Vinculado, sin conexión ahora.';

  @override
  String get shellNotPaired => 'Aún no vinculado.';

  @override
  String get shellPairInstructions =>
      'En la Mac donde corre orcd: `orcd serve` y, en otra terminal, `orcd pair`. Pega aquí el ticket (vale 10 minutos, una vez).';

  @override
  String get shellScanPairQr => 'Escanear el QR de `orcd pair`';

  @override
  String get shellClose => 'Cerrar';

  @override
  String get shellPairAndConnect => 'Vincular y conectar';

  @override
  String get shellPointAtQr => 'Apunta al QR de orcd pair';

  @override
  String get toolsSessionRunning => 'en ejecución';

  @override
  String get toolsSessionWaiting => 'esperándote';

  @override
  String get toolsSessionStarting => 'reiniciando';

  @override
  String get toolsSessionIdle => 'inactiva';

  @override
  String get toolsCatalogTitle => 'Catálogo';

  @override
  String get toolsCatalogSubtitle =>
      'Configura una vez; cada sesión activa lo que necesita en el panel de perfil.';

  @override
  String get toolsAdd => 'Agregar';

  @override
  String get toolsPlanTemplatesHeader => 'TEMPLATES DE PLAN MODE';

  @override
  String get toolsNewTemplate => 'Nuevo template';

  @override
  String get toolsPlanTemplatesHelp =>
      'Markdown con las secciones de cada tipo de trabajo y la instrucción de cada una. Se elige en \"Nuevo plan\".';

  @override
  String toolsSectionCount(int count) {
    return '$count secciones';
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
  String get toolsUnused => 'sin uso';

  @override
  String toolsUsedInSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'en $count sesiones',
      one: 'en 1 sesión',
    );
    return '$_temp0';
  }

  @override
  String get toolsMcpTesting => 'probando…';

  @override
  String toolsMcpConnected(String count) {
    return 'conectado · $count tools';
  }

  @override
  String toolsMcpFailed(String reason) {
    return 'falló: $reason';
  }

  @override
  String get toolsTestConnection => 'Probar conexión';

  @override
  String get toolsSkillFolder => 'Carpeta de la skill';

  @override
  String get toolsCommandOrUrl => 'Comando o URL';

  @override
  String get toolsEnvValue => 'Valor (guardado en el Keychain)';

  @override
  String get toolsAddToCatalog => 'Agregar al catálogo';

  @override
  String get toolsName => 'Nombre';

  @override
  String get toolsDescription => 'Descripción';

  @override
  String get toolsCancel => 'Cancelar';

  @override
  String get toolsNewPlanTemplate => 'Nuevo template de plan mode';

  @override
  String get toolsEditTemplate => 'Editar template';

  @override
  String get toolsTemplateNameHint => 'Nombre, p. ej.: Back end con deploy';

  @override
  String get toolsTemplateDescriptionHint => 'Cuándo usar este template';

  @override
  String get toolsDeleteTemplate => 'Eliminar template';

  @override
  String get toolsSave => 'Guardar';

  @override
  String get toolsHarnessUnderstood => 'LO QUE EL HARNESS ENTENDIÓ';

  @override
  String toolsReadError(String error) {
    return 'Error al leer: $error';
  }

  @override
  String toolsSectionsAndLoops(int sections, int loops) {
    return '$sections secciones · $loops loops';
  }

  @override
  String toolsInstruction(String text) {
    return 'instrucción: $text';
  }

  @override
  String get toolsBlockText => 'texto';

  @override
  String get toolsBlockList => 'lista';

  @override
  String get toolsBlockTable => 'tabla';

  @override
  String get toolsBlockCode => 'código';

  @override
  String get toolsBlockFlowchart => 'flowchart';

  @override
  String get toolsBlockSequence => 'secuencia';

  @override
  String get toolsBlockLoops => 'loops';

  @override
  String get toolsSectionEmpty => 'vacía';

  @override
  String toolsUsageTitle(String workspace) {
    return 'Uso · $workspace';
  }

  @override
  String get toolsUsageLiveSubtitle =>
      'Métricas del propio Claude Code (OpenTelemetry), por sesión, cuenta y modelo.';

  @override
  String get toolsUsageDemoSubtitle =>
      'Datos de demostración; el workspace Esta Mac muestra los reales.';

  @override
  String toolsDays(int count) {
    return '$count días';
  }

  @override
  String get toolsCost => 'Costo';

  @override
  String get toolsTokens => 'Tokens';

  @override
  String get toolsDailyAverage => 'Promedio por día';

  @override
  String get toolsCacheRead => 'Leído de cache';

  @override
  String get toolsThisMonth => 'Este mes';

  @override
  String toolsBudgetShare(int percent, String workspace) {
    return '$percent% del presupuesto mensual de $workspace';
  }

  @override
  String get toolsTokensByType => 'Tokens por tipo';

  @override
  String get toolsInput => 'Entrada';

  @override
  String get toolsOutput => 'Salida';

  @override
  String get toolsCacheWrite => 'Escrito en cache';

  @override
  String get toolsCostPerDay => 'Costo por día (US\$)';

  @override
  String get toolsShowChart => 'Ver gráfico';

  @override
  String get toolsShowTable => 'Ver tabla';

  @override
  String get toolsByAccountModel => 'Por cuenta y modelo';

  @override
  String get toolsAccount => 'Cuenta';

  @override
  String get toolsModel => 'Modelo';

  @override
  String get toolsNoUsage => 'No hay uso registrado en el período.';

  @override
  String get toolsByPlan => 'Por plan';

  @override
  String get toolsPlan => 'Plan';

  @override
  String get toolsCardsDone => 'Cards hechas';

  @override
  String get toolsNoPlans => 'Ningún plan en ejecución en el período.';

  @override
  String get toolsByProjectBranch => 'Por proyecto y branch (cards)';

  @override
  String get toolsProject => 'Proyecto';

  @override
  String get toolsBranch => 'Branch';

  @override
  String get toolsLooseSessions => 'sesiones sueltas';

  @override
  String get toolsNoTokens => 'No hay tokens en el período.';

  @override
  String get toolsGroupSessions => 'Sesiones';

  @override
  String get toolsGroupPanes => 'Panes';

  @override
  String get toolsGroupProjects => 'Proyectos';

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
    return 'Ir a $name';
  }

  @override
  String get toolsNewSession => 'Nueva sesión';

  @override
  String get toolsSplitSideBySide => 'Dividir lado a lado';

  @override
  String get toolsSplitTopBottom => 'Dividir arriba y abajo';

  @override
  String get toolsClosePane => 'Cerrar pane';

  @override
  String get toolsHideProfilePanel => 'Ocultar panel de perfil';

  @override
  String get toolsShowProfilePanel => 'Mostrar panel de perfil';

  @override
  String toolsOpenPlanOf(String name) {
    return 'Abrir plan de $name';
  }

  @override
  String toolsOpenNamed(String name) {
    return 'Abrir $name';
  }

  @override
  String toolsOpenComments(int count) {
    return '$count comentarios abiertos';
  }

  @override
  String toolsRunReadyCards(String name) {
    return 'Ejecutar cards listas de $name';
  }

  @override
  String toolsReadyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count listas',
      one: '1 lista',
    );
    return '$_temp0';
  }

  @override
  String get toolsRequestReview => 'Pedir a Claude que revise los comentarios';

  @override
  String get toolsNewPlanFromTemplate => 'Nuevo plan a partir de un template';

  @override
  String get toolsImportPlan => 'Importar plan en markdown';

  @override
  String get toolsSearchCodeCmd => 'Buscar en el código (⌘⇧F)';

  @override
  String get toolsOpenUsage => 'Abrir uso y costo del workspace';

  @override
  String get toolsOpenCatalog => 'Abrir catálogo de skills, MCPs y envs';

  @override
  String get toolsBackToSessions => 'Volver a las sesiones';

  @override
  String toolsTurnOff(String name) {
    return 'Desactivar $name';
  }

  @override
  String toolsTurnOn(String name) {
    return 'Activar $name';
  }

  @override
  String get toolsApplyChanges => 'Aplicar cambios (reinicia con --resume)';

  @override
  String toolsSwitchTo(String name) {
    return 'Cambiar a $name';
  }

  @override
  String get toolsNothingOpen => 'nada abierto';

  @override
  String get toolsSearchNeedsDaemon =>
      'La búsqueda en el código necesita el daemon conectado.';

  @override
  String toolsSearchIn(String label) {
    return 'Buscar en $label…';
  }

  @override
  String get toolsSymbols => 'Símbolos';

  @override
  String get toolsSearch => 'Buscar';

  @override
  String toolsResults(String count, String query) {
    return '$count resultado(s) para \"$query\"';
  }

  @override
  String get devBrowserNoDaemon =>
      'El daemon no está conectado: el navegador corre en él. Conéctalo en ⚙.';

  @override
  String get devFoldersNoDaemon =>
      'El daemon no está conectado: las carpetas vienen de él. Conéctalo en ⚙.';

  @override
  String get toolsSessionEnded => 'terminada';

  @override
  String get sessionEndedBanner => 'La sesión terminó.';

  @override
  String get sessionReopen => 'Reabrir';

  @override
  String get sessionCloseEnded => 'Cerrar';

  @override
  String get onboardWelcomeTitle => 'Te damos la bienvenida a Orc Harness';

  @override
  String get onboardWelcomeWhy =>
      'Ejecuta muchas sesiones de Claude Code lado a lado. Antes, algunos permisos, uno a la vez: cada uno dice por qué hace falta, y puedes saltar cualquiera.';

  @override
  String get onboardNotificationsTitle => 'Notificaciones';

  @override
  String get onboardNotificationsWhy =>
      'Para que sepas cuándo una sesión te espera, un deploy necesita tu OK o una tarjeta termina. Solo aparecen con la app en segundo plano.';

  @override
  String get onboardServiceTitle => 'Servicio en segundo plano';

  @override
  String get onboardServiceWhy =>
      'Las sesiones corren en orcd, un servicio pequeño que arranca al iniciar sesión, así siguen con la app cerrada. macOS avisará que se agregó un ítem en segundo plano (puedes desactivarlo en Ajustes del Sistema → General → Ítems de inicio). Guarda su clave en el Llavero: si pregunta, elige Permitir siempre.';

  @override
  String get onboardNetworkTitle => 'Conectar al servicio';

  @override
  String get onboardNetworkWhy =>
      'La app habla con el servicio en esta misma Mac, cifrado y sin pasar por la red, así que no hay nada que permitir. Para usar el teléfono después, ejecuta orcd pair: entonces macOS puede pedir acceso a la red local para el servicio.';

  @override
  String get onboardNotNow => 'Ahora no';

  @override
  String get onboardStart => 'Vamos';

  @override
  String get onboardGrant => 'Conceder';

  @override
  String get onboardGrantFinish => 'Conceder y terminar';

  @override
  String get onboardRetry => 'Intentar de nuevo';

  @override
  String onboardStep(int n, int total) {
    return '$n de $total';
  }

  @override
  String onboardFailed(String error) {
    return 'No funcionó: $error';
  }

  @override
  String get coreAlertMcpTitle => 'Un agente quiere un MCP';

  @override
  String coreAlertMcpBody(String session, String name) {
    return '$session pide agregar $name';
  }

  @override
  String shellMcpRequest(String session, String name) {
    return '$session pide agregar el MCP $name';
  }

  @override
  String get shellMcpApprove => 'Aprobar y reiniciar';

  @override
  String get toolsImportMcps => 'Importar de esta Mac';

  @override
  String get toolsImportMcpsHint =>
      'MCPs y skills que ya están en esta Mac: todas las configuraciones de Claude Code (~/.claude*), otras herramientas (Claude Desktop, Cursor, Windsurf, VS Code, Gemini CLI, Codex…), tus proyectos y plugins. Los valores secretos van al Llavero; el catálogo guarda solo referencias.';

  @override
  String get toolsImportNone => 'No se encontraron MCPs ni skills en esta Mac.';

  @override
  String get toolsImportReplaces => '· reemplaza el del catálogo';

  @override
  String toolsImportSecrets(String names) {
    return 'Al Llavero: $names';
  }

  @override
  String toolsImportCount(int count) {
    return 'Importar $count';
  }

  @override
  String get shellConnectorsTitle => 'Conectores de claude.ai';

  @override
  String get shellConnectorsHint =>
      'Los que esta cuenta agregó en claude.ai (Gmail, Drive, Slack…). Solo los marcados entran en esta sesión.';

  @override
  String get shellConnectorsLoading =>
      'Preguntando a Claude Code (prueba cada uno)…';

  @override
  String get shellConnectorsNone =>
      'Ningún conector en esta cuenta (o inició sesión con una clave de API).';

  @override
  String get shellConnectorNeedsAuth => 'No conectado: conéctalo en claude.ai';

  @override
  String get shellConnectorFailed => 'No respondió en la última prueba';

  @override
  String get shellEmulators => 'Emuladores y simuladores';

  @override
  String get devEmulatorPick =>
      'Elige un dispositivo. Corre aquí, sin ventana propia.';

  @override
  String get devEmulatorNone =>
      'No se encontraron emuladores ni simuladores. Instala Xcode (iOS) o Android Studio con un AVD.';

  @override
  String get devEmulatorOn => 'encendido';

  @override
  String get devEmulatorOff => 'apagado';

  @override
  String get devEmulatorBooting => 'encendiendo…';

  @override
  String get devEmulatorBoot => 'Encender';

  @override
  String get devEmulatorShutdown => 'Apagar';

  @override
  String get devEmulatorHome => 'Inicio';

  @override
  String get devEmulatorSwitch => 'Otro dispositivo';

  @override
  String get toolsImportSearch => 'Buscar por nombre u origen';

  @override
  String get toolsImportInCatalog => '· ya está en el catálogo';

  @override
  String toolsEnvOnlyHere(String workspace) {
    return 'Solo en $workspace: valor propio, y las sesiones de otros workspaces no pueden usarla';
  }

  @override
  String get onboardUpdateTitle => 'Actualizando el servicio en segundo plano';

  @override
  String get onboardUpdateWhy =>
      'Esta versión trae un orcd nuevo. Aún no está firmado por Apple, así que macOS lo ve como un programa nuevo y puede preguntar otra vez: acceso al Llavero (la clave del daemon), elige Permitir siempre; y, con el firewall activo, conexiones entrantes. Para que no pregunte en cada versión, ejecuta una vez: orcd install --sign \"<tu identidad>\" (lístalas con security find-identity -v -p codesigning).';

  @override
  String get onboardUpdateGo => 'Actualizar';

  @override
  String get shellNoDaemonToSave =>
      'El daemon no está conectado, así que esto no se puede guardar. Revisa ⚙ → Conectar daemon.';

  @override
  String get shellProfileSearch => 'Buscar skills, MCPs, envs';

  @override
  String shellProfileOnOf(int on, int total) {
    return '$on de $total activas';
  }

  @override
  String shellProfileShowAvailable(int count) {
    return 'Mostrar las $count disponibles';
  }

  @override
  String get shellProfileHide => 'Mostrar solo las activas';

  @override
  String shellProfileRefine(int count) {
    return '$count más: afina la búsqueda';
  }

  @override
  String toolsShowAll(int count) {
    return 'Mostrar todas ($count)';
  }

  @override
  String get toolsCatalogSearch => 'Buscar en el catálogo';

  @override
  String get devEditRepo => 'Configuración del repositorio';

  @override
  String get devRemoveRepo => 'Quitar repositorio';

  @override
  String get devRemoveRepoSure => 'Quitar de verdad';

  @override
  String get devRemoveRepoConfirm =>
      'Sale del harness; la carpeta, los worktrees y las ramas siguen en git.';
}
