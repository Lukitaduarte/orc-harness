// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get languageSystem => 'System language';

  @override
  String get language => 'Language';

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
    return 'Didn\'t start: $note';
  }

  @override
  String coreHaltStopped(String note) {
    return 'Stopped: $note';
  }

  @override
  String get coreUnknownError => 'error';

  @override
  String get coreSessionEnded => 'session ended';

  @override
  String corePromptCard(String number, String plan, String title, String type) {
    return 'Card #$number of plan \"$plan\": $title ($type)';
  }

  @override
  String corePromptPlan(String summary) {
    return 'Plan: $summary';
  }

  @override
  String get corePromptCriteria => 'Acceptance criteria:';

  @override
  String get corePromptTasks =>
      'Tasks, by group (subagents, with skill and model):';

  @override
  String corePromptTask(
    String group,
    String title,
    String skill,
    String model,
  ) {
    return '- group $group: $title · $skill · $model';
  }

  @override
  String get corePromptNeedsOk => ' — ask the user for OK first';

  @override
  String get corePromptNotes => 'Notes:';

  @override
  String corePromptDraft(String name) {
    return 'Write the plan \"$name\" filling in each section of the template as its instruction says.';
  }

  @override
  String corePromptBuild(String description) {
    return 'What to build: $description';
  }

  @override
  String get corePromptSources => 'Sources:';

  @override
  String get corePromptReview =>
      'Revise the plan from these comments and save it with save_plan, answering each one in replies:';

  @override
  String get corePromptLocked =>
      ' (approved: do not change it, record it in amendments)';

  @override
  String get coreAlertWaitingTitle => 'Waiting for you';

  @override
  String coreAlertWaitingBody(String session) {
    return '$session needs an answer.';
  }

  @override
  String get coreAlertEnvTitle => 'An agent asks for an env';

  @override
  String coreAlertEnvBody(String session, String name) {
    return '$session wants to store $name. Approve or refuse it in the app.';
  }

  @override
  String get coreAlertApprovalTitle => 'Needs your OK';

  @override
  String get coreAlertPrTitle => 'PR opened';

  @override
  String coreAlertPrBody(String plan, String number) {
    return '$plan · card #$number is in review.';
  }

  @override
  String get coreAlertMergedTitle => 'Card merged';

  @override
  String coreAlertMergedBody(String plan, String number) {
    return '$plan · card #$number is done.';
  }

  @override
  String get coreAlertStoppedTitle => 'Card stopped';

  @override
  String coreAlertStoppedBody(String plan, String number, String note) {
    return '$plan · card #$number: $note.';
  }

  @override
  String get coreBudgetOverTitle => 'Budget exceeded';

  @override
  String get coreBudget80Title => 'Budget at 80%';

  @override
  String coreBudgetBody(String workspace, String spent, String budget) {
    return '$workspace: US\$$spent of US\$$budget this month.';
  }

  @override
  String get coreEnvWithValue => 'daemon Keychain · has a value';

  @override
  String get coreEnvNoValue => 'daemon Keychain · no value yet';

  @override
  String coreAmendment(String text) {
    return 'Amendment: $text';
  }

  @override
  String coreCommentOn(String section, String text) {
    return 'Comment on $section: $text';
  }

  @override
  String get coreImportedPlan => 'Imported plan';

  @override
  String devRepoBase(String branch) {
    return 'base $branch';
  }

  @override
  String get devNewWorktreeSession => 'New session in a worktree';

  @override
  String get devTrustWorktreesHint =>
      'Claude Code asks whether it trusts each new folder. Answer \"Yes\" once in this session and all of the harness\'s worktrees become trusted.';

  @override
  String get devTrustWorktrees => 'Trust the worktrees';

  @override
  String get devAddRepository => 'Add repository';

  @override
  String get devAddRepositoryHint =>
      'A local clone. Sessions work in its worktrees, one per branch.';

  @override
  String get devName => 'Name';

  @override
  String get devClonePath => 'Clone path';

  @override
  String get devClonePathPlaceholder => '~/Project/my-repo';

  @override
  String get devChoose => 'Choose…';

  @override
  String get devBaseBranch => 'Base branch';

  @override
  String get devCancel => 'Cancel';

  @override
  String get devAdd => 'Add';

  @override
  String devNewSessionIn(String project) {
    return 'New session in $project';
  }

  @override
  String get devNewWorktreeHint =>
      'Creates (or reuses) the branch\'s worktree. Commits that don\'t follow conventional commits are rejected there.';

  @override
  String get devBranch => 'Branch';

  @override
  String get devBranchRule =>
      'Use letters, numbers, . _ / -; e.g. feat/12-login';

  @override
  String get devCreateSession => 'Create session';

  @override
  String get devLoading => 'Loading…';

  @override
  String get devChooseFolder => 'Choose folder';

  @override
  String get devFolderUp => 'Up';

  @override
  String get devFolderHome => 'Home';

  @override
  String get devHideHidden => 'Hide hidden';

  @override
  String get devShowHidden => 'Show hidden';

  @override
  String get devNoSubfolders => 'No subfolders.';

  @override
  String get devUseThisFolder => 'Use this folder';

  @override
  String get devCommitPlaceholder => 'feat(scope): what changes';

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
    return '$op: failed';
  }

  @override
  String get devSessionChanges => 'Session changes';

  @override
  String devDiffSummary(int count, String base) {
    return '$count file(s) against $base, including what is not committed yet';
  }

  @override
  String get devNoPr => 'no PR';

  @override
  String get devNoChangesYet => 'No changes yet.';

  @override
  String get devPrDraft => 'draft';

  @override
  String devPrChip(String number, String state) {
    return 'PR #$number · $state';
  }

  @override
  String devPrChecksFailing(int count) {
    return '$count check(s) failing';
  }

  @override
  String get devPrChecksOk => 'checks ok';

  @override
  String get devUntrackedFile => 'New file, not tracked by git yet.';

  @override
  String get devDefinitionNotFound => 'Definition not found.';

  @override
  String devDefinedOutside(String location) {
    return 'Defined outside the project: $location';
  }

  @override
  String get devNothingAboutSymbol => 'Nothing about this symbol.';

  @override
  String get devPickFile => 'Pick a file on the left.';

  @override
  String get devGoToDefinition => 'Go to definition (F12)';

  @override
  String get devAboutSymbol => 'About the symbol (⌘I)';

  @override
  String get devFormat => 'Format (⇧⌥F)';

  @override
  String get devSeverityError => 'error';

  @override
  String get devSeverityWarning => 'warning';

  @override
  String devDiagnostic(String severity, int line, String message) {
    return '$severity · line $line: $message';
  }

  @override
  String get devBack => 'Back';

  @override
  String get devForward => 'Forward';

  @override
  String get devReload => 'Reload';

  @override
  String get devAddress => 'Address';

  @override
  String get devCloseBrowser =>
      'Close the browser (cookies stay in the profile)';

  @override
  String get devOpenWorkspaceBrowser => 'Open the workspace browser';

  @override
  String get devConnectingTerminal => 'Connecting to the terminal…';

  @override
  String get devMessageClaude => 'Message to Claude';

  @override
  String get devNoQuotaReading => 'no quota reading yet';

  @override
  String get devSessions => 'Sessions';

  @override
  String get devPlans => 'Plans';

  @override
  String devDeleteSessionTitle(String name) {
    return 'Delete session $name?';
  }

  @override
  String get devDeleteSessionBody =>
      'Ends the process. The worktree, the commits and the conversation stay.';

  @override
  String get devDelete => 'Delete';

  @override
  String get devNoSessions => 'No sessions in this workspace.';

  @override
  String get devNewSession => 'New session';

  @override
  String devPlanReviewProgress(int approved, int total, int comments) {
    return '$approved/$total sections approved · $comments comments';
  }

  @override
  String devCardsDone(int done, int total) {
    return '$done/$total cards done';
  }

  @override
  String devDeletePlanTitle(String name) {
    return 'Delete plan $name?';
  }

  @override
  String get devDeletePlanBody =>
      'Sessions of running cards are ended. Branches, worktrees and PRs stay.';

  @override
  String get devNoPlans => 'No plans in this workspace.';

  @override
  String get devRetry => 'Try again';

  @override
  String get devColumnBlocked => 'blocked';

  @override
  String get devColumnReady => 'ready';

  @override
  String get devColumnRunning => 'running';

  @override
  String get devColumnReview => 'review';

  @override
  String get devColumnDone => 'done';

  @override
  String plansVersion(int version) {
    return 'plan v$version';
  }

  @override
  String plansRunningSince(String time) {
    return 'running since $time';
  }

  @override
  String plansApprovedCount(int approved, int total) {
    return '$approved/$total sections approved';
  }

  @override
  String get plansPlanningSession => 'Planning session';

  @override
  String get plansClaudeReviewing => 'Claude reviewing…';

  @override
  String get plansAskClaudeReview => 'Ask Claude for a review';

  @override
  String plansAskClaudeReviewCount(int count) {
    return 'Ask Claude for a review ($count)';
  }

  @override
  String plansDrafting(int count) {
    return 'Claude is reading $count sources and writing the sections…';
  }

  @override
  String plansStartLoops(int count) {
    return 'Start execution · $count loops';
  }

  @override
  String plansChangedAfterApprovalCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sections changed after approval',
      one: '1 section changed after approval',
    );
    return '$_temp0';
  }

  @override
  String plansStartApproved(int approved, int total) {
    return 'Start execution · $approved/$total approved';
  }

  @override
  String plansTemplateInstruction(String instruction) {
    return 'Template instruction: $instruction';
  }

  @override
  String get plansChangedAfterApproval => 'changed after approval';

  @override
  String plansOpenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open',
      one: '1 open',
    );
    return '$_temp0';
  }

  @override
  String get plansComment => 'Comment';

  @override
  String get plansApprove => 'Approve';

  @override
  String get plansApprovedSectionPlaceholder =>
      'Approved section: the comment becomes an amendment to the first loop…';

  @override
  String plansCommentOn(String section) {
    return 'Comment on $section…';
  }

  @override
  String plansApprovedAt(String time, String digest) {
    return 'Approved $time · digest $digest';
  }

  @override
  String get plansApproved => 'approved';

  @override
  String get plansCanStartNow => 'can start now';

  @override
  String plansAfterLoops(String loops) {
    return 'after $loops';
  }

  @override
  String plansLoopRef(int number) {
    return 'loop $number';
  }

  @override
  String get plansListAnd => ' and ';

  @override
  String get plansTableTask => 'Task';

  @override
  String get plansTableModel => 'Model';

  @override
  String get plansTableGroup => 'Group';

  @override
  String plansTaskAfter(String tasks) {
    return 'after $tasks';
  }

  @override
  String get plansYourOk => 'your OK';

  @override
  String get plansComments => 'Comments';

  @override
  String get plansHideResolved => 'Hide resolved';

  @override
  String get plansShowResolved => 'Show resolved';

  @override
  String plansFiltering(String section) {
    return 'Filtering: $section';
  }

  @override
  String get plansShowAll => 'Show all';

  @override
  String get plansNoCommentsHere =>
      'No comments here.\nUse \"Comment\" on any section.';

  @override
  String get plansAmendmentsHeader => 'AMENDMENTS FOR THE FIRST LOOP';

  @override
  String get plansClaudeReviewingComments =>
      'Claude is reviewing the comments…';

  @override
  String get plansReviewHint =>
      'On an open section, Claude adjusts the section. On an approved section, nothing changes: the request becomes an amendment to the first loop.';

  @override
  String get plansResolved => 'resolved';

  @override
  String get plansAwaitingClaude => 'waiting for Claude';

  @override
  String get plansReopen => 'Reopen';

  @override
  String get plansResolve => 'Resolve';

  @override
  String get plansReply => 'Reply…';

  @override
  String plansBoardSummary(
    String repo,
    int done,
    int total,
    int running,
    int max,
  ) {
    return '$repo · $done/$total done · $running/$max running';
  }

  @override
  String plansRunReady(int count) {
    return 'Run ready ($count)';
  }

  @override
  String plansBoardHint(String email) {
    return 'Each card runs in its own worktree and session, on the account with the most headroom ($email).';
  }

  @override
  String get plansColumnBlocked => 'Blocked';

  @override
  String get plansColumnReady => 'Ready';

  @override
  String get plansColumnRunning => 'Running';

  @override
  String get plansColumnReview => 'In review';

  @override
  String get plansColumnDone => 'Done';

  @override
  String plansWaitingFor(String cards) {
    return 'waiting for $cards';
  }

  @override
  String get plansNoDependencies => 'no dependencies';

  @override
  String plansDependsOn(String cards) {
    return 'depends on $cards';
  }

  @override
  String get plansRun => 'Run';

  @override
  String get plansOpenSession => 'Open session';

  @override
  String get plansSimulatePr => 'Simulate PR';

  @override
  String get plansSimulateMerge => 'Simulate merge';

  @override
  String plansPrMerged(int number) {
    return 'PR #$number merged';
  }

  @override
  String get plansRetry => 'Try again';

  @override
  String get plansQueued => 'Queued: starts when a slot frees up';

  @override
  String get plansMerged => 'merged';

  @override
  String get plansPhaseZeroSimulation => 'Phase 0 simulation';

  @override
  String get plansAcceptanceCriteria => 'Acceptance criteria';

  @override
  String get plansNoCriteria => 'No criteria defined.';

  @override
  String get plansTasksHeader => 'Tasks · subagents per group';

  @override
  String plansGroupParallel(int group) {
    return 'Group $group · in parallel';
  }

  @override
  String plansGroup(int group) {
    return 'Group $group';
  }

  @override
  String get plansLoopResult => 'Loop result';

  @override
  String get plansDependencies => 'Dependencies';

  @override
  String get plansNoDependenciesLong =>
      'None: can run in parallel with other ready cards.';

  @override
  String get plansSession => 'Session';

  @override
  String get plansCommentsAndNotes => 'Comments and notes';

  @override
  String get plansNoCommentsYet => 'No comments yet.';

  @override
  String get plansAddNote => 'Add a note…';

  @override
  String get plansStateDone => 'done';

  @override
  String get plansStatePending => 'pending';

  @override
  String get plansStateBlocked => 'blocked';

  @override
  String get plansStateReady => 'ready';

  @override
  String get plansStateRunning => 'running';

  @override
  String get plansStateReview => 'in review';

  @override
  String get plansLearnIntro =>
      'Each comment on the cards becomes a change to the skill with the gap. You approve before it is applied.';

  @override
  String get plansLearnEmptyLive =>
      'Claude is reading the comments and skills of the cards.\nProposals show up here; nothing changes without your OK.';

  @override
  String get plansLearnEmpty =>
      'No new comments on the cards.\nComment in a card\'s dialog and run Learn again.';

  @override
  String plansLearnNotApplied(String error) {
    return 'Not applied: $error';
  }

  @override
  String get plansDiscard => 'Discard';

  @override
  String get plansApplyToSkill => 'Apply to skill';

  @override
  String get plansAppliedToSkill => 'Applied to skill';

  @override
  String get plansDiscarded => 'Discarded';

  @override
  String get plansImportedPlan => 'Imported plan';

  @override
  String get plansNewPlan => 'New plan';

  @override
  String get plansFromTemplate => 'From a template';

  @override
  String get plansPasteMarkdown => 'Paste markdown';

  @override
  String get plansCancel => 'Cancel';

  @override
  String get plansImportPlan => 'Import plan';

  @override
  String get plansCreatePlan => 'Create plan';

  @override
  String get plansRepository => 'Repository';

  @override
  String get plansAddRepoFirst =>
      'Add a repository in the sidebar (This Mac) first.';

  @override
  String get plansTemplate => 'Template';

  @override
  String get plansFeatureName => 'Feature name';

  @override
  String get plansSources => 'Sources (Jira, Confluence, Figma), one per line';

  @override
  String get plansWhatToBuild => 'What to build';

  @override
  String get plansImportHint =>
      'Any markdown in plan format: each ## becomes an approvable section, tables and lists become widgets, ```mermaid becomes a diagram and ```loops defines the execution.';

  @override
  String get plansImportPlaceholder => '# Plan name\n\n## Sources\n…';

  @override
  String plansAgo(String duration) {
    return '$duration ago';
  }

  @override
  String get plansYouInitial => 'Y';

  @override
  String get plansWriteComment => 'Write a comment…';

  @override
  String get shellNewWorkspace => 'New workspace';

  @override
  String get shellUsageAndCost => 'Usage and cost';

  @override
  String get shellCatalogTip => 'Catalog of skills, MCPs and envs';

  @override
  String shellSidebarCounts(int accounts, int sessions) {
    return '$accounts accounts · $sessions sessions';
  }

  @override
  String get shellAccounts => 'Accounts';

  @override
  String get shellNewAccount => 'New account';

  @override
  String get shellSessions => 'Sessions';

  @override
  String get shellNewSession => 'New session';

  @override
  String get shellDeleteSession => 'Delete session';

  @override
  String shellDeleteSessionTitle(String name) {
    return 'Delete the session $name?';
  }

  @override
  String get shellDeleteSessionBody =>
      'Ends the process and removes it from the list. The worktree, the commits and the conversation (claude --resume) stay.';

  @override
  String get shellDelete => 'Delete';

  @override
  String get shellRepositories => 'Repositories';

  @override
  String get shellAddRepository => 'Add repository';

  @override
  String get shellPlans => 'Plans';

  @override
  String get shellNewPlan => 'New plan';

  @override
  String get shellDeletePlan => 'Delete plan';

  @override
  String shellDeletePlanTitle(String name) {
    return 'Delete the plan $name?';
  }

  @override
  String get shellDeletePlanBodyRunning =>
      'It has cards running: their sessions are ended. Branches, worktrees and PRs stay.';

  @override
  String get shellDeletePlanBody => 'Branches, worktrees and PRs stay.';

  @override
  String shellAccountTitle(String email) {
    return 'Account $email';
  }

  @override
  String get shellLogoutButton => 'Log out (/logout)';

  @override
  String get shellLogoutHint =>
      'Opens a session in it and runs Claude Code\'s /logout.';

  @override
  String get shellRemoveFromHarness => 'Remove from the harness';

  @override
  String get shellRemoveHint =>
      'Ends its sessions and takes it out of the accounts. The folder and the conversations stay on disk.';

  @override
  String get shellCancel => 'Cancel';

  @override
  String shellLogoutTitle(String email) {
    return 'Log out of $email?';
  }

  @override
  String get shellLogoutDefaultBody =>
      'It is Claude Code\'s default account on this Mac: the login ends outside the harness too.';

  @override
  String get shellLogoutBody => 'This account\'s login leaves Claude Code.';

  @override
  String get shellLogout => 'Log out';

  @override
  String shellRemoveTitle(String email) {
    return 'Remove $email from the harness?';
  }

  @override
  String get shellRemoveBody => 'Its sessions are ended.';

  @override
  String get shellRemove => 'Remove';

  @override
  String get shellNoReadingYet =>
      'no reading yet: the quota arrives with Claude\'s first reply';

  @override
  String shellUpdatedAgo(String duration) {
    return 'updated $duration ago';
  }

  @override
  String shellResetIn(String duration) {
    return 'resets in $duration';
  }

  @override
  String shellExhaustsIn(String duration) {
    return 'at this pace, runs out in ~$duration';
  }

  @override
  String get shellPlanBadge => 'plan';

  @override
  String get shellSearchOrRun => 'Search or run a command…';

  @override
  String get shellExecution => 'Execution';

  @override
  String get shellPlan => 'Plan';

  @override
  String get shellUsage => 'Usage';

  @override
  String get shellCatalog => 'Catalog';

  @override
  String get shellWorkspaceBrowser => 'Workspace browser';

  @override
  String shellToolInUse(String tool, String session) {
    return '$tool · in use by $session';
  }

  @override
  String shellInUseBy(String session) {
    return 'in use by $session';
  }

  @override
  String shellCodePaneTitle(String session) {
    return 'Code · $session';
  }

  @override
  String get shellEmptyPane => 'Empty pane';

  @override
  String get shellChangesAndPr => 'Changes and PR';

  @override
  String get shellCodeTip => 'Code (IDE in the session\'s folder)';

  @override
  String get shellSplitSideBySide => 'Split side by side';

  @override
  String get shellSplitTopBottom => 'Split top and bottom';

  @override
  String get shellClosePane => 'Close pane';

  @override
  String shellTokensCost(String tokens, String cost) {
    return '$tokens tokens · $cost';
  }

  @override
  String shellFiveHourShare(int percent) {
    return '$percent% of the 5h window';
  }

  @override
  String get shellRestartingResumeLine => '↻ restarting with --resume…';

  @override
  String get shellOpenInPane => 'Open in this pane';

  @override
  String get shellSessionMemory => 'Session memory';

  @override
  String get shellSessionMemoryHint =>
      'What the agents store (decisions, preferences, project facts) and the workspace\'s other sessions find.';

  @override
  String get shellMemoryHarness => 'The harness\'s';

  @override
  String get shellMemoryOff => 'Off';

  @override
  String get shellWorkspace => 'Workspace';

  @override
  String get shellWorkspaceHint =>
      'A workspace brings together accounts, sessions, repositories, plans and a browser with its own logins (e.g. Work, Personal).';

  @override
  String get shellName => 'Name';

  @override
  String get shellWorkspaceAccounts => 'Accounts in this workspace';

  @override
  String get shellWorkspaceAccountsHint =>
      'An account lives in one workspace only; checking it here takes it out of the other.';

  @override
  String shellAccountInWorkspace(String email, String workspace) {
    return '$email (in $workspace)';
  }

  @override
  String get shellMonthlyBudget => 'Monthly budget (US\$)';

  @override
  String get shellBudgetHint =>
      'Optional. The app warns at 80% and when the limit is passed.';

  @override
  String get shellBudgetExample => 'e.g. 200';

  @override
  String get shellDeleteWorkspace => 'Delete';

  @override
  String get shellCreate => 'Create';

  @override
  String get shellSave => 'Save';

  @override
  String shellNewAccountBody(String workspace) {
    return 'A Claude Code account with its own config folder (~/.orc/accounts/<name>) in the workspace $workspace. Opens a session in it: log in with /login.';
  }

  @override
  String get shellAccountName => 'Account name';

  @override
  String get shellAccountNameExample => 'work-2';

  @override
  String get shellAccountTaken => 'An account with that name already exists.';

  @override
  String get shellAccountRule => 'Use letters, numbers, - and _.';

  @override
  String get shellCreateAndLogin => 'Create and log in';

  @override
  String shellApprovalRequest(String session, String action) {
    return '$session wants: $action. It stays blocked until you decide (10 min).';
  }

  @override
  String get shellDecline => 'Decline';

  @override
  String get shellApprove => 'Approve';

  @override
  String shellEnvRequest(String session, String env) {
    return '$session asks to store $env in the daemon\'s Keychain. The value does not show here.';
  }

  @override
  String get shellDismiss => 'Dismiss';

  @override
  String get shellSelectSession => 'Select a session';

  @override
  String get shellSessionProfile => 'Session profile';

  @override
  String get shellRestartingWithResume => 'Restarting with --resume…';

  @override
  String get shellApplyHint =>
      'Applying restarts the session with --resume. The context is kept.';

  @override
  String get shellDiscard => 'Discard';

  @override
  String get shellApply => 'Apply';

  @override
  String get shellPairAnother => 'Pair another device';

  @override
  String get shellShowPairingQr => 'Show pairing QR';

  @override
  String get shellPairQrHint =>
      'On the phone: Connect daemon → Scan the QR. Valid once, for 10 minutes.';

  @override
  String get shellCopy => 'Copy';

  @override
  String get shellPairedDevices => 'Paired devices';

  @override
  String shellThisDevice(String name) {
    return '$name (this one)';
  }

  @override
  String get shellRevoke => 'Revoke';

  @override
  String get shellNoDaemon => 'This app was started without the daemon.';

  @override
  String get shellConnectDaemon => 'Connect daemon';

  @override
  String shellConnectedCounts(int accounts, int sessions) {
    return 'Connected: $accounts account(s), $sessions session(s).';
  }

  @override
  String get shellConnecting => 'Connecting…';

  @override
  String get shellPairedOffline => 'Paired, not connected right now.';

  @override
  String get shellNotPaired => 'Not paired yet.';

  @override
  String get shellPairInstructions =>
      'On the Mac where orcd runs: `orcd serve` and, in another terminal, `orcd pair`. Paste the ticket here (valid for 10 minutes, once).';

  @override
  String get shellScanPairQr => 'Scan the `orcd pair` QR';

  @override
  String get shellClose => 'Close';

  @override
  String get shellPairAndConnect => 'Pair and connect';

  @override
  String get shellPointAtQr => 'Point at the orcd pair QR';

  @override
  String get toolsSessionRunning => 'running';

  @override
  String get toolsSessionWaiting => 'waiting for you';

  @override
  String get toolsSessionStarting => 'restarting';

  @override
  String get toolsSessionIdle => 'idle';

  @override
  String get toolsCatalogTitle => 'Catalog';

  @override
  String get toolsCatalogSubtitle =>
      'Configure once; each session turns on what it needs in the profile panel.';

  @override
  String get toolsAdd => 'Add';

  @override
  String get toolsPlanTemplatesHeader => 'PLAN MODE TEMPLATES';

  @override
  String get toolsNewTemplate => 'New template';

  @override
  String get toolsPlanTemplatesHelp =>
      'Markdown with the sections of each kind of work and the instruction for each. Picked in \"New plan\".';

  @override
  String toolsSectionCount(int count) {
    return '$count sections';
  }

  @override
  String get toolsEditMarkdown => 'Edit markdown';

  @override
  String get toolsKindSkills => 'Skills';

  @override
  String get toolsKindMcps => 'MCPs';

  @override
  String get toolsKindEnvs => 'Envs';

  @override
  String get toolsUnused => 'unused';

  @override
  String toolsUsedInSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'in $count sessions',
      one: 'in 1 session',
    );
    return '$_temp0';
  }

  @override
  String get toolsMcpTesting => 'testing…';

  @override
  String toolsMcpConnected(String count) {
    return 'connected · $count tools';
  }

  @override
  String toolsMcpFailed(String reason) {
    return 'failed: $reason';
  }

  @override
  String get toolsTestConnection => 'Test connection';

  @override
  String get toolsSkillFolder => 'Skill folder';

  @override
  String get toolsCommandOrUrl => 'Command or URL';

  @override
  String get toolsEnvValue => 'Value (kept in the Keychain)';

  @override
  String get toolsAddToCatalog => 'Add to catalog';

  @override
  String get toolsName => 'Name';

  @override
  String get toolsDescription => 'Description';

  @override
  String get toolsCancel => 'Cancel';

  @override
  String get toolsNewPlanTemplate => 'New plan mode template';

  @override
  String get toolsEditTemplate => 'Edit template';

  @override
  String get toolsTemplateNameHint => 'Name, e.g.: Back end with deploy';

  @override
  String get toolsTemplateDescriptionHint => 'When to use this template';

  @override
  String get toolsDeleteTemplate => 'Delete template';

  @override
  String get toolsSave => 'Save';

  @override
  String get toolsHarnessUnderstood => 'WHAT THE HARNESS UNDERSTOOD';

  @override
  String toolsReadError(String error) {
    return 'Error reading: $error';
  }

  @override
  String toolsSectionsAndLoops(int sections, int loops) {
    return '$sections sections · $loops loops';
  }

  @override
  String toolsInstruction(String text) {
    return 'instruction: $text';
  }

  @override
  String get toolsBlockText => 'text';

  @override
  String get toolsBlockList => 'list';

  @override
  String get toolsBlockTable => 'table';

  @override
  String get toolsBlockCode => 'code';

  @override
  String get toolsBlockFlowchart => 'flowchart';

  @override
  String get toolsBlockSequence => 'sequence';

  @override
  String get toolsBlockLoops => 'loops';

  @override
  String get toolsSectionEmpty => 'empty';

  @override
  String toolsUsageTitle(String workspace) {
    return 'Usage · $workspace';
  }

  @override
  String get toolsUsageLiveSubtitle =>
      'Claude Code\'s own metrics (OpenTelemetry), by session, account and model.';

  @override
  String get toolsUsageDemoSubtitle =>
      'Demo data; the This Mac workspace shows the real ones.';

  @override
  String toolsDays(int count) {
    return '$count days';
  }

  @override
  String get toolsCost => 'Cost';

  @override
  String get toolsTokens => 'Tokens';

  @override
  String get toolsDailyAverage => 'Daily average';

  @override
  String get toolsCacheRead => 'Read from cache';

  @override
  String get toolsThisMonth => 'This month';

  @override
  String toolsBudgetShare(int percent, String workspace) {
    return '$percent% of $workspace\'s monthly budget';
  }

  @override
  String get toolsTokensByType => 'Tokens by type';

  @override
  String get toolsInput => 'Input';

  @override
  String get toolsOutput => 'Output';

  @override
  String get toolsCacheWrite => 'Written to cache';

  @override
  String get toolsCostPerDay => 'Cost per day (US\$)';

  @override
  String get toolsShowChart => 'Show chart';

  @override
  String get toolsShowTable => 'Show table';

  @override
  String get toolsByAccountModel => 'By account and model';

  @override
  String get toolsAccount => 'Account';

  @override
  String get toolsModel => 'Model';

  @override
  String get toolsNoUsage => 'No usage recorded in this period.';

  @override
  String get toolsByPlan => 'By plan';

  @override
  String get toolsPlan => 'Plan';

  @override
  String get toolsCardsDone => 'Cards done';

  @override
  String get toolsNoPlans => 'No plan running in this period.';

  @override
  String get toolsByProjectBranch => 'By project and branch (cards)';

  @override
  String get toolsProject => 'Project';

  @override
  String get toolsBranch => 'Branch';

  @override
  String get toolsLooseSessions => 'standalone sessions';

  @override
  String get toolsNoTokens => 'No tokens in this period.';

  @override
  String get toolsGroupSessions => 'Sessions';

  @override
  String get toolsGroupPanes => 'Panes';

  @override
  String get toolsGroupProjects => 'Projects';

  @override
  String get toolsGroupCatalog => 'Catalog';

  @override
  String get toolsGroupCode => 'Code';

  @override
  String get toolsGroupUsage => 'Usage';

  @override
  String get toolsGroupWorkspaces => 'Workspaces';

  @override
  String toolsGroupProfileOf(String name) {
    return '$name\'s profile';
  }

  @override
  String toolsGoTo(String name) {
    return 'Go to $name';
  }

  @override
  String get toolsNewSession => 'New session';

  @override
  String get toolsSplitSideBySide => 'Split side by side';

  @override
  String get toolsSplitTopBottom => 'Split top and bottom';

  @override
  String get toolsClosePane => 'Close pane';

  @override
  String get toolsHideProfilePanel => 'Hide profile panel';

  @override
  String get toolsShowProfilePanel => 'Show profile panel';

  @override
  String toolsOpenPlanOf(String name) {
    return 'Open $name\'s plan';
  }

  @override
  String toolsOpenNamed(String name) {
    return 'Open $name';
  }

  @override
  String toolsOpenComments(int count) {
    return '$count open comments';
  }

  @override
  String toolsRunReadyCards(String name) {
    return 'Run $name\'s ready cards';
  }

  @override
  String toolsReadyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ready',
      one: '1 ready',
    );
    return '$_temp0';
  }

  @override
  String get toolsRequestReview => 'Ask Claude to review the comments';

  @override
  String get toolsNewPlanFromTemplate => 'New plan from a template';

  @override
  String get toolsImportPlan => 'Import plan in markdown';

  @override
  String get toolsSearchCodeCmd => 'Search code (⌘⇧F)';

  @override
  String get toolsOpenUsage => 'Open workspace usage and cost';

  @override
  String get toolsOpenCatalog => 'Open catalog of skills, MCPs and envs';

  @override
  String get toolsBackToSessions => 'Back to sessions';

  @override
  String toolsTurnOff(String name) {
    return 'Turn off $name';
  }

  @override
  String toolsTurnOn(String name) {
    return 'Turn on $name';
  }

  @override
  String get toolsApplyChanges => 'Apply changes (restarts with --resume)';

  @override
  String toolsSwitchTo(String name) {
    return 'Switch to $name';
  }

  @override
  String get toolsNothingOpen => 'nothing open';

  @override
  String get toolsSearchNeedsDaemon =>
      'Code search needs the daemon connected.';

  @override
  String toolsSearchIn(String label) {
    return 'Search in $label…';
  }

  @override
  String get toolsSymbols => 'Symbols';

  @override
  String get toolsSearch => 'Search';

  @override
  String toolsResults(String count, String query) {
    return '$count result(s) for \"$query\"';
  }

  @override
  String get devBrowserNoDaemon =>
      'The daemon is not connected: the browser runs there. Connect it in ⚙.';

  @override
  String get devFoldersNoDaemon =>
      'The daemon is not connected: the folders come from it. Connect it in ⚙.';

  @override
  String get toolsSessionEnded => 'ended';

  @override
  String get sessionEndedBanner => 'The session ended.';

  @override
  String get sessionReopen => 'Reopen';

  @override
  String get sessionCloseEnded => 'Close';

  @override
  String get onboardWelcomeTitle => 'Welcome to Orc Harness';

  @override
  String get onboardWelcomeWhy =>
      'Run many Claude Code sessions side by side. First, three permissions, one at a time: each one says why it\'s needed, and you can skip any of them.';

  @override
  String get onboardNotificationsTitle => 'Notifications';

  @override
  String get onboardNotificationsWhy =>
      'So you know when a session is waiting for you, a deploy needs your OK or a card is done. They only show while the app is in the background.';

  @override
  String get onboardServiceTitle => 'Background service';

  @override
  String get onboardServiceWhy =>
      'Sessions run in orcd, a small service that starts when you log in, so they keep going with the app closed. macOS will say a background item was added (you can turn it off in System Settings → General → Login Items). It keeps its key in your Keychain: if asked, choose Always Allow.';

  @override
  String get onboardNetworkTitle => 'Local network';

  @override
  String get onboardNetworkWhy =>
      'The app talks to the service, and later to your phone, over an encrypted connection on your network. macOS will ask whether Orc Harness may find devices on your local network: allow it, or the app can\'t connect.';

  @override
  String get onboardNotNow => 'Not now';

  @override
  String get onboardStart => 'Let\'s go';

  @override
  String get onboardGrant => 'Grant';

  @override
  String get onboardGrantFinish => 'Grant and finish';

  @override
  String get onboardRetry => 'Try again';

  @override
  String onboardStep(int n, int total) {
    return '$n of $total';
  }

  @override
  String onboardFailed(String error) {
    return 'That didn\'t work: $error';
  }

  @override
  String get coreAlertMcpTitle => 'An agent wants an MCP server';

  @override
  String coreAlertMcpBody(String session, String name) {
    return '$session asks to add $name';
  }

  @override
  String shellMcpRequest(String session, String name) {
    return '$session asks to add the MCP server $name';
  }

  @override
  String get shellMcpApprove => 'Approve and restart';

  @override
  String get toolsImportMcps => 'Import from this Mac';

  @override
  String get toolsImportMcpsHint =>
      'MCP servers and skills already on this Mac: every Claude Code setup (~/.claude*), other tools (Claude Desktop, Cursor, Windsurf, VS Code, Gemini CLI, Codex…), your projects and plugins. Secret values go to the Keychain; the catalog keeps only references.';

  @override
  String get toolsImportNone => 'No MCP servers or skills found on this Mac.';

  @override
  String get toolsImportReplaces => '· replaces the one in the catalog';

  @override
  String toolsImportSecrets(String names) {
    return 'To the Keychain: $names';
  }

  @override
  String toolsImportCount(int count) {
    return 'Import $count';
  }

  @override
  String get shellConnectorsTitle => 'claude.ai connectors';

  @override
  String get shellConnectorsHint =>
      'The ones this account added on claude.ai (Gmail, Drive, Slack…). Only the ones you check enter this session.';

  @override
  String get shellConnectorsLoading =>
      'Asking Claude Code (it checks each one)…';

  @override
  String get shellConnectorsNone =>
      'No connectors on this account (or it is logged in with an API key).';

  @override
  String get shellConnectorNeedsAuth =>
      'Not connected: connect it on claude.ai';

  @override
  String get shellConnectorFailed => 'Didn\'t answer the last check';

  @override
  String get shellEmulators => 'Emulators and simulators';

  @override
  String get devEmulatorPick =>
      'Pick a device. It runs here, without its own window.';

  @override
  String get devEmulatorNone =>
      'No emulators or simulators found. Install Xcode (iOS) or Android Studio with an AVD.';

  @override
  String get devEmulatorOn => 'on';

  @override
  String get devEmulatorOff => 'off';

  @override
  String get devEmulatorBooting => 'turning on…';

  @override
  String get devEmulatorBoot => 'Turn on';

  @override
  String get devEmulatorShutdown => 'Turn off';

  @override
  String get devEmulatorHome => 'Home';

  @override
  String get devEmulatorSwitch => 'Other device';

  @override
  String get toolsImportSearch => 'Search by name or source';

  @override
  String get toolsImportInCatalog => '· already in the catalog';
}
