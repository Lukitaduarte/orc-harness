import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('pt'),
  ];

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System language'**
  String get languageSystem;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// Peon line (Warcraft homage); keep in English in every language
  ///
  /// In en, this message translates to:
  /// **'Ready to work!'**
  String get orcReady;

  /// Peon line; keep in English
  ///
  /// In en, this message translates to:
  /// **'Work, work.'**
  String get orcWorkWork;

  /// Peon line; keep in English
  ///
  /// In en, this message translates to:
  /// **'Zug zug!'**
  String get orcZugZug;

  /// Peon line; keep in English
  ///
  /// In en, this message translates to:
  /// **'Something need doing?'**
  String get orcNeedDoing;

  /// Peon line; keep in English
  ///
  /// In en, this message translates to:
  /// **'Me not that kind of orc!'**
  String get orcNotThatKind;

  /// Peasant line; keep in English
  ///
  /// In en, this message translates to:
  /// **'Job\'s done!'**
  String get orcJobsDone;

  /// No description provided for @coreHaltFailed.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t start: {note}'**
  String coreHaltFailed(String note);

  /// No description provided for @coreHaltStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped: {note}'**
  String coreHaltStopped(String note);

  /// No description provided for @coreUnknownError.
  ///
  /// In en, this message translates to:
  /// **'error'**
  String get coreUnknownError;

  /// No description provided for @coreSessionEnded.
  ///
  /// In en, this message translates to:
  /// **'session ended'**
  String get coreSessionEnded;

  /// Sent to Claude: write it as an instruction
  ///
  /// In en, this message translates to:
  /// **'Card #{number} of plan \"{plan}\": {title} ({type})'**
  String corePromptCard(String number, String plan, String title, String type);

  /// Sent to Claude: write it as an instruction
  ///
  /// In en, this message translates to:
  /// **'Plan: {summary}'**
  String corePromptPlan(String summary);

  /// Sent to Claude: write it as an instruction
  ///
  /// In en, this message translates to:
  /// **'Acceptance criteria:'**
  String get corePromptCriteria;

  /// Sent to Claude: write it as an instruction
  ///
  /// In en, this message translates to:
  /// **'Tasks, by group (subagents, with skill and model):'**
  String get corePromptTasks;

  /// Sent to Claude: write it as an instruction
  ///
  /// In en, this message translates to:
  /// **'- group {group}: {title} · {skill} · {model}'**
  String corePromptTask(String group, String title, String skill, String model);

  /// Sent to Claude: write it as an instruction
  ///
  /// In en, this message translates to:
  /// **' — ask the user for OK first'**
  String get corePromptNeedsOk;

  /// Sent to Claude: write it as an instruction
  ///
  /// In en, this message translates to:
  /// **'Notes:'**
  String get corePromptNotes;

  /// Sent to Claude: write it as an instruction
  ///
  /// In en, this message translates to:
  /// **'Write the plan \"{name}\" filling in each section of the template as its instruction says.'**
  String corePromptDraft(String name);

  /// Sent to Claude: write it as an instruction
  ///
  /// In en, this message translates to:
  /// **'What to build: {description}'**
  String corePromptBuild(String description);

  /// Sent to Claude: write it as an instruction
  ///
  /// In en, this message translates to:
  /// **'Sources:'**
  String get corePromptSources;

  /// Sent to Claude: write it as an instruction
  ///
  /// In en, this message translates to:
  /// **'Revise the plan from these comments and save it with save_plan, answering each one in replies:'**
  String get corePromptReview;

  /// Sent to Claude: write it as an instruction
  ///
  /// In en, this message translates to:
  /// **' (approved: do not change it, record it in amendments)'**
  String get corePromptLocked;

  /// No description provided for @coreAlertWaitingTitle.
  ///
  /// In en, this message translates to:
  /// **'Waiting for you'**
  String get coreAlertWaitingTitle;

  /// No description provided for @coreAlertWaitingBody.
  ///
  /// In en, this message translates to:
  /// **'{session} needs an answer.'**
  String coreAlertWaitingBody(String session);

  /// No description provided for @coreAlertEnvTitle.
  ///
  /// In en, this message translates to:
  /// **'An agent asks for an env'**
  String get coreAlertEnvTitle;

  /// No description provided for @coreAlertEnvBody.
  ///
  /// In en, this message translates to:
  /// **'{session} wants to store {name}. Approve or refuse it in the app.'**
  String coreAlertEnvBody(String session, String name);

  /// No description provided for @coreAlertApprovalTitle.
  ///
  /// In en, this message translates to:
  /// **'Needs your OK'**
  String get coreAlertApprovalTitle;

  /// No description provided for @coreAlertPrTitle.
  ///
  /// In en, this message translates to:
  /// **'PR opened'**
  String get coreAlertPrTitle;

  /// No description provided for @coreAlertPrBody.
  ///
  /// In en, this message translates to:
  /// **'{plan} · card #{number} is in review.'**
  String coreAlertPrBody(String plan, String number);

  /// No description provided for @coreAlertMergedTitle.
  ///
  /// In en, this message translates to:
  /// **'Card merged'**
  String get coreAlertMergedTitle;

  /// No description provided for @coreAlertMergedBody.
  ///
  /// In en, this message translates to:
  /// **'{plan} · card #{number} is done.'**
  String coreAlertMergedBody(String plan, String number);

  /// No description provided for @coreAlertStoppedTitle.
  ///
  /// In en, this message translates to:
  /// **'Card stopped'**
  String get coreAlertStoppedTitle;

  /// No description provided for @coreAlertStoppedBody.
  ///
  /// In en, this message translates to:
  /// **'{plan} · card #{number}: {note}.'**
  String coreAlertStoppedBody(String plan, String number, String note);

  /// No description provided for @coreBudgetOverTitle.
  ///
  /// In en, this message translates to:
  /// **'Budget exceeded'**
  String get coreBudgetOverTitle;

  /// No description provided for @coreBudget80Title.
  ///
  /// In en, this message translates to:
  /// **'Budget at 80%'**
  String get coreBudget80Title;

  /// No description provided for @coreBudgetBody.
  ///
  /// In en, this message translates to:
  /// **'{workspace}: US\${spent} of US\${budget} this month.'**
  String coreBudgetBody(String workspace, String spent, String budget);

  /// No description provided for @coreEnvWithValue.
  ///
  /// In en, this message translates to:
  /// **'daemon Keychain · has a value'**
  String get coreEnvWithValue;

  /// No description provided for @coreEnvNoValue.
  ///
  /// In en, this message translates to:
  /// **'daemon Keychain · no value yet'**
  String get coreEnvNoValue;

  /// No description provided for @coreAmendment.
  ///
  /// In en, this message translates to:
  /// **'Amendment: {text}'**
  String coreAmendment(String text);

  /// No description provided for @coreCommentOn.
  ///
  /// In en, this message translates to:
  /// **'Comment on {section}: {text}'**
  String coreCommentOn(String section, String text);

  /// No description provided for @coreImportedPlan.
  ///
  /// In en, this message translates to:
  /// **'Imported plan'**
  String get coreImportedPlan;

  /// No description provided for @devRepoBase.
  ///
  /// In en, this message translates to:
  /// **'base {branch}'**
  String devRepoBase(String branch);

  /// No description provided for @devNewWorktreeSession.
  ///
  /// In en, this message translates to:
  /// **'New session in a worktree'**
  String get devNewWorktreeSession;

  /// No description provided for @devTrustWorktreesHint.
  ///
  /// In en, this message translates to:
  /// **'Claude Code asks whether it trusts each new folder. Answer \"Yes\" once in this session and all of the harness\'s worktrees become trusted.'**
  String get devTrustWorktreesHint;

  /// No description provided for @devTrustWorktrees.
  ///
  /// In en, this message translates to:
  /// **'Trust the worktrees'**
  String get devTrustWorktrees;

  /// No description provided for @devAddRepository.
  ///
  /// In en, this message translates to:
  /// **'Add repository'**
  String get devAddRepository;

  /// No description provided for @devAddRepositoryHint.
  ///
  /// In en, this message translates to:
  /// **'A local clone. Sessions work in its worktrees, one per branch.'**
  String get devAddRepositoryHint;

  /// No description provided for @devName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get devName;

  /// No description provided for @devClonePath.
  ///
  /// In en, this message translates to:
  /// **'Clone path'**
  String get devClonePath;

  /// No description provided for @devClonePathPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'~/Project/my-repo'**
  String get devClonePathPlaceholder;

  /// No description provided for @devChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose…'**
  String get devChoose;

  /// No description provided for @devBaseBranch.
  ///
  /// In en, this message translates to:
  /// **'Base branch'**
  String get devBaseBranch;

  /// No description provided for @devCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get devCancel;

  /// No description provided for @devAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get devAdd;

  /// No description provided for @devNewSessionIn.
  ///
  /// In en, this message translates to:
  /// **'New session in {project}'**
  String devNewSessionIn(String project);

  /// No description provided for @devNewWorktreeHint.
  ///
  /// In en, this message translates to:
  /// **'Creates (or reuses) the branch\'s worktree. Commits that don\'t follow conventional commits are rejected there.'**
  String get devNewWorktreeHint;

  /// No description provided for @devBranch.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get devBranch;

  /// No description provided for @devBranchRule.
  ///
  /// In en, this message translates to:
  /// **'Use letters, numbers, . _ / -; e.g. feat/12-login'**
  String get devBranchRule;

  /// No description provided for @devCreateSession.
  ///
  /// In en, this message translates to:
  /// **'Create session'**
  String get devCreateSession;

  /// No description provided for @devLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get devLoading;

  /// No description provided for @devChooseFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose folder'**
  String get devChooseFolder;

  /// No description provided for @devFolderUp.
  ///
  /// In en, this message translates to:
  /// **'Up'**
  String get devFolderUp;

  /// No description provided for @devFolderHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get devFolderHome;

  /// No description provided for @devHideHidden.
  ///
  /// In en, this message translates to:
  /// **'Hide hidden'**
  String get devHideHidden;

  /// No description provided for @devShowHidden.
  ///
  /// In en, this message translates to:
  /// **'Show hidden'**
  String get devShowHidden;

  /// No description provided for @devNoSubfolders.
  ///
  /// In en, this message translates to:
  /// **'No subfolders.'**
  String get devNoSubfolders;

  /// No description provided for @devUseThisFolder.
  ///
  /// In en, this message translates to:
  /// **'Use this folder'**
  String get devUseThisFolder;

  /// No description provided for @devCommitPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'feat(scope): what changes'**
  String get devCommitPlaceholder;

  /// No description provided for @devCommit.
  ///
  /// In en, this message translates to:
  /// **'Commit'**
  String get devCommit;

  /// No description provided for @devPush.
  ///
  /// In en, this message translates to:
  /// **'Push'**
  String get devPush;

  /// No description provided for @devMergeSquash.
  ///
  /// In en, this message translates to:
  /// **'Merge (squash)'**
  String get devMergeSquash;

  /// op is the git operation name from the daemon
  ///
  /// In en, this message translates to:
  /// **'{op}: ok'**
  String devGitResultOk(String op);

  /// op is the git operation name from the daemon
  ///
  /// In en, this message translates to:
  /// **'{op}: failed'**
  String devGitResultFailed(String op);

  /// No description provided for @devSessionChanges.
  ///
  /// In en, this message translates to:
  /// **'Session changes'**
  String get devSessionChanges;

  /// No description provided for @devDiffSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} file(s) against {base}, including what is not committed yet'**
  String devDiffSummary(int count, String base);

  /// No description provided for @devNoPr.
  ///
  /// In en, this message translates to:
  /// **'no PR'**
  String get devNoPr;

  /// No description provided for @devNoChangesYet.
  ///
  /// In en, this message translates to:
  /// **'No changes yet.'**
  String get devNoChangesYet;

  /// No description provided for @devPrDraft.
  ///
  /// In en, this message translates to:
  /// **'draft'**
  String get devPrDraft;

  /// No description provided for @devPrChip.
  ///
  /// In en, this message translates to:
  /// **'PR #{number} · {state}'**
  String devPrChip(String number, String state);

  /// No description provided for @devPrChecksFailing.
  ///
  /// In en, this message translates to:
  /// **'{count} check(s) failing'**
  String devPrChecksFailing(int count);

  /// No description provided for @devPrChecksOk.
  ///
  /// In en, this message translates to:
  /// **'checks ok'**
  String get devPrChecksOk;

  /// No description provided for @devUntrackedFile.
  ///
  /// In en, this message translates to:
  /// **'New file, not tracked by git yet.'**
  String get devUntrackedFile;

  /// No description provided for @devDefinitionNotFound.
  ///
  /// In en, this message translates to:
  /// **'Definition not found.'**
  String get devDefinitionNotFound;

  /// No description provided for @devDefinedOutside.
  ///
  /// In en, this message translates to:
  /// **'Defined outside the project: {location}'**
  String devDefinedOutside(String location);

  /// No description provided for @devNothingAboutSymbol.
  ///
  /// In en, this message translates to:
  /// **'Nothing about this symbol.'**
  String get devNothingAboutSymbol;

  /// No description provided for @devPickFile.
  ///
  /// In en, this message translates to:
  /// **'Pick a file on the left.'**
  String get devPickFile;

  /// No description provided for @devGoToDefinition.
  ///
  /// In en, this message translates to:
  /// **'Go to definition (F12)'**
  String get devGoToDefinition;

  /// No description provided for @devAboutSymbol.
  ///
  /// In en, this message translates to:
  /// **'About the symbol (⌘I)'**
  String get devAboutSymbol;

  /// No description provided for @devFormat.
  ///
  /// In en, this message translates to:
  /// **'Format (⇧⌥F)'**
  String get devFormat;

  /// No description provided for @devSeverityError.
  ///
  /// In en, this message translates to:
  /// **'error'**
  String get devSeverityError;

  /// No description provided for @devSeverityWarning.
  ///
  /// In en, this message translates to:
  /// **'warning'**
  String get devSeverityWarning;

  /// No description provided for @devDiagnostic.
  ///
  /// In en, this message translates to:
  /// **'{severity} · line {line}: {message}'**
  String devDiagnostic(String severity, int line, String message);

  /// No description provided for @devBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get devBack;

  /// No description provided for @devForward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get devForward;

  /// No description provided for @devReload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get devReload;

  /// No description provided for @devAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get devAddress;

  /// No description provided for @devCloseBrowser.
  ///
  /// In en, this message translates to:
  /// **'Close the browser (cookies stay in the profile)'**
  String get devCloseBrowser;

  /// No description provided for @devOpenWorkspaceBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open the workspace browser'**
  String get devOpenWorkspaceBrowser;

  /// No description provided for @devConnectingTerminal.
  ///
  /// In en, this message translates to:
  /// **'Connecting to the terminal…'**
  String get devConnectingTerminal;

  /// No description provided for @devMessageClaude.
  ///
  /// In en, this message translates to:
  /// **'Message to Claude'**
  String get devMessageClaude;

  /// No description provided for @devNoQuotaReading.
  ///
  /// In en, this message translates to:
  /// **'no quota reading yet'**
  String get devNoQuotaReading;

  /// No description provided for @devSessions.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get devSessions;

  /// No description provided for @devPlans.
  ///
  /// In en, this message translates to:
  /// **'Plans'**
  String get devPlans;

  /// No description provided for @devDeleteSessionTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete session {name}?'**
  String devDeleteSessionTitle(String name);

  /// No description provided for @devDeleteSessionBody.
  ///
  /// In en, this message translates to:
  /// **'Ends the process. The worktree, the commits and the conversation stay.'**
  String get devDeleteSessionBody;

  /// No description provided for @devDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get devDelete;

  /// No description provided for @devNoSessions.
  ///
  /// In en, this message translates to:
  /// **'No sessions in this workspace.'**
  String get devNoSessions;

  /// No description provided for @devNewSession.
  ///
  /// In en, this message translates to:
  /// **'New session'**
  String get devNewSession;

  /// No description provided for @devPlanReviewProgress.
  ///
  /// In en, this message translates to:
  /// **'{approved}/{total} sections approved · {comments} comments'**
  String devPlanReviewProgress(int approved, int total, int comments);

  /// No description provided for @devCardsDone.
  ///
  /// In en, this message translates to:
  /// **'{done}/{total} cards done'**
  String devCardsDone(int done, int total);

  /// No description provided for @devDeletePlanTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete plan {name}?'**
  String devDeletePlanTitle(String name);

  /// No description provided for @devDeletePlanBody.
  ///
  /// In en, this message translates to:
  /// **'Sessions of running cards are ended. Branches, worktrees and PRs stay.'**
  String get devDeletePlanBody;

  /// No description provided for @devNoPlans.
  ///
  /// In en, this message translates to:
  /// **'No plans in this workspace.'**
  String get devNoPlans;

  /// No description provided for @devRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get devRetry;

  /// No description provided for @devColumnBlocked.
  ///
  /// In en, this message translates to:
  /// **'blocked'**
  String get devColumnBlocked;

  /// No description provided for @devColumnReady.
  ///
  /// In en, this message translates to:
  /// **'ready'**
  String get devColumnReady;

  /// No description provided for @devColumnRunning.
  ///
  /// In en, this message translates to:
  /// **'running'**
  String get devColumnRunning;

  /// No description provided for @devColumnReview.
  ///
  /// In en, this message translates to:
  /// **'review'**
  String get devColumnReview;

  /// No description provided for @devColumnDone.
  ///
  /// In en, this message translates to:
  /// **'done'**
  String get devColumnDone;

  /// No description provided for @plansVersion.
  ///
  /// In en, this message translates to:
  /// **'plan v{version}'**
  String plansVersion(int version);

  /// No description provided for @plansRunningSince.
  ///
  /// In en, this message translates to:
  /// **'running since {time}'**
  String plansRunningSince(String time);

  /// No description provided for @plansApprovedCount.
  ///
  /// In en, this message translates to:
  /// **'{approved}/{total} sections approved'**
  String plansApprovedCount(int approved, int total);

  /// No description provided for @plansPlanningSession.
  ///
  /// In en, this message translates to:
  /// **'Planning session'**
  String get plansPlanningSession;

  /// No description provided for @plansClaudeReviewing.
  ///
  /// In en, this message translates to:
  /// **'Claude reviewing…'**
  String get plansClaudeReviewing;

  /// No description provided for @plansAskClaudeReview.
  ///
  /// In en, this message translates to:
  /// **'Ask Claude for a review'**
  String get plansAskClaudeReview;

  /// No description provided for @plansAskClaudeReviewCount.
  ///
  /// In en, this message translates to:
  /// **'Ask Claude for a review ({count})'**
  String plansAskClaudeReviewCount(int count);

  /// No description provided for @plansDrafting.
  ///
  /// In en, this message translates to:
  /// **'Claude is reading {count} sources and writing the sections…'**
  String plansDrafting(int count);

  /// No description provided for @plansStartLoops.
  ///
  /// In en, this message translates to:
  /// **'Start execution · {count} loops'**
  String plansStartLoops(int count);

  /// No description provided for @plansChangedAfterApprovalCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 section changed after approval} other{{count} sections changed after approval}}'**
  String plansChangedAfterApprovalCount(int count);

  /// No description provided for @plansStartApproved.
  ///
  /// In en, this message translates to:
  /// **'Start execution · {approved}/{total} approved'**
  String plansStartApproved(int approved, int total);

  /// No description provided for @plansTemplateInstruction.
  ///
  /// In en, this message translates to:
  /// **'Template instruction: {instruction}'**
  String plansTemplateInstruction(String instruction);

  /// No description provided for @plansChangedAfterApproval.
  ///
  /// In en, this message translates to:
  /// **'changed after approval'**
  String get plansChangedAfterApproval;

  /// No description provided for @plansOpenCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 open} other{{count} open}}'**
  String plansOpenCount(int count);

  /// No description provided for @plansComment.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get plansComment;

  /// No description provided for @plansApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get plansApprove;

  /// No description provided for @plansApprovedSectionPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Approved section: the comment becomes an amendment to the first loop…'**
  String get plansApprovedSectionPlaceholder;

  /// No description provided for @plansCommentOn.
  ///
  /// In en, this message translates to:
  /// **'Comment on {section}…'**
  String plansCommentOn(String section);

  /// No description provided for @plansApprovedAt.
  ///
  /// In en, this message translates to:
  /// **'Approved {time} · digest {digest}'**
  String plansApprovedAt(String time, String digest);

  /// No description provided for @plansApproved.
  ///
  /// In en, this message translates to:
  /// **'approved'**
  String get plansApproved;

  /// No description provided for @plansCanStartNow.
  ///
  /// In en, this message translates to:
  /// **'can start now'**
  String get plansCanStartNow;

  /// No description provided for @plansAfterLoops.
  ///
  /// In en, this message translates to:
  /// **'after {loops}'**
  String plansAfterLoops(String loops);

  /// No description provided for @plansLoopRef.
  ///
  /// In en, this message translates to:
  /// **'loop {number}'**
  String plansLoopRef(int number);

  /// Joins items of a list (loop 1 and loop 2); keep the surrounding spaces
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get plansListAnd;

  /// No description provided for @plansTableTask.
  ///
  /// In en, this message translates to:
  /// **'Task'**
  String get plansTableTask;

  /// No description provided for @plansTableModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get plansTableModel;

  /// No description provided for @plansTableGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get plansTableGroup;

  /// No description provided for @plansTaskAfter.
  ///
  /// In en, this message translates to:
  /// **'after {tasks}'**
  String plansTaskAfter(String tasks);

  /// Badge: the task needs the user's approval
  ///
  /// In en, this message translates to:
  /// **'your OK'**
  String get plansYourOk;

  /// No description provided for @plansComments.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get plansComments;

  /// No description provided for @plansHideResolved.
  ///
  /// In en, this message translates to:
  /// **'Hide resolved'**
  String get plansHideResolved;

  /// No description provided for @plansShowResolved.
  ///
  /// In en, this message translates to:
  /// **'Show resolved'**
  String get plansShowResolved;

  /// No description provided for @plansFiltering.
  ///
  /// In en, this message translates to:
  /// **'Filtering: {section}'**
  String plansFiltering(String section);

  /// No description provided for @plansShowAll.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get plansShowAll;

  /// No description provided for @plansNoCommentsHere.
  ///
  /// In en, this message translates to:
  /// **'No comments here.\nUse \"Comment\" on any section.'**
  String get plansNoCommentsHere;

  /// No description provided for @plansAmendmentsHeader.
  ///
  /// In en, this message translates to:
  /// **'AMENDMENTS FOR THE FIRST LOOP'**
  String get plansAmendmentsHeader;

  /// No description provided for @plansClaudeReviewingComments.
  ///
  /// In en, this message translates to:
  /// **'Claude is reviewing the comments…'**
  String get plansClaudeReviewingComments;

  /// No description provided for @plansReviewHint.
  ///
  /// In en, this message translates to:
  /// **'On an open section, Claude adjusts the section. On an approved section, nothing changes: the request becomes an amendment to the first loop.'**
  String get plansReviewHint;

  /// No description provided for @plansResolved.
  ///
  /// In en, this message translates to:
  /// **'resolved'**
  String get plansResolved;

  /// No description provided for @plansAwaitingClaude.
  ///
  /// In en, this message translates to:
  /// **'waiting for Claude'**
  String get plansAwaitingClaude;

  /// No description provided for @plansReopen.
  ///
  /// In en, this message translates to:
  /// **'Reopen'**
  String get plansReopen;

  /// No description provided for @plansResolve.
  ///
  /// In en, this message translates to:
  /// **'Resolve'**
  String get plansResolve;

  /// No description provided for @plansReply.
  ///
  /// In en, this message translates to:
  /// **'Reply…'**
  String get plansReply;

  /// No description provided for @plansBoardSummary.
  ///
  /// In en, this message translates to:
  /// **'{repo} · {done}/{total} done · {running}/{max} running'**
  String plansBoardSummary(
    String repo,
    int done,
    int total,
    int running,
    int max,
  );

  /// No description provided for @plansRunReady.
  ///
  /// In en, this message translates to:
  /// **'Run ready ({count})'**
  String plansRunReady(int count);

  /// No description provided for @plansBoardHint.
  ///
  /// In en, this message translates to:
  /// **'Each card runs in its own worktree and session, on the account with the most headroom ({email}).'**
  String plansBoardHint(String email);

  /// No description provided for @plansColumnBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get plansColumnBlocked;

  /// No description provided for @plansColumnReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get plansColumnReady;

  /// No description provided for @plansColumnRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get plansColumnRunning;

  /// No description provided for @plansColumnReview.
  ///
  /// In en, this message translates to:
  /// **'In review'**
  String get plansColumnReview;

  /// No description provided for @plansColumnDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get plansColumnDone;

  /// No description provided for @plansWaitingFor.
  ///
  /// In en, this message translates to:
  /// **'waiting for {cards}'**
  String plansWaitingFor(String cards);

  /// No description provided for @plansNoDependencies.
  ///
  /// In en, this message translates to:
  /// **'no dependencies'**
  String get plansNoDependencies;

  /// No description provided for @plansDependsOn.
  ///
  /// In en, this message translates to:
  /// **'depends on {cards}'**
  String plansDependsOn(String cards);

  /// No description provided for @plansRun.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get plansRun;

  /// No description provided for @plansOpenSession.
  ///
  /// In en, this message translates to:
  /// **'Open session'**
  String get plansOpenSession;

  /// No description provided for @plansSimulatePr.
  ///
  /// In en, this message translates to:
  /// **'Simulate PR'**
  String get plansSimulatePr;

  /// No description provided for @plansSimulateMerge.
  ///
  /// In en, this message translates to:
  /// **'Simulate merge'**
  String get plansSimulateMerge;

  /// No description provided for @plansPrMerged.
  ///
  /// In en, this message translates to:
  /// **'PR #{number} merged'**
  String plansPrMerged(int number);

  /// No description provided for @plansRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get plansRetry;

  /// No description provided for @plansQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued: starts when a slot frees up'**
  String get plansQueued;

  /// No description provided for @plansMerged.
  ///
  /// In en, this message translates to:
  /// **'merged'**
  String get plansMerged;

  /// No description provided for @plansPhaseZeroSimulation.
  ///
  /// In en, this message translates to:
  /// **'Phase 0 simulation'**
  String get plansPhaseZeroSimulation;

  /// No description provided for @plansAcceptanceCriteria.
  ///
  /// In en, this message translates to:
  /// **'Acceptance criteria'**
  String get plansAcceptanceCriteria;

  /// No description provided for @plansNoCriteria.
  ///
  /// In en, this message translates to:
  /// **'No criteria defined.'**
  String get plansNoCriteria;

  /// No description provided for @plansTasksHeader.
  ///
  /// In en, this message translates to:
  /// **'Tasks · subagents per group'**
  String get plansTasksHeader;

  /// No description provided for @plansGroupParallel.
  ///
  /// In en, this message translates to:
  /// **'Group {group} · in parallel'**
  String plansGroupParallel(int group);

  /// No description provided for @plansGroup.
  ///
  /// In en, this message translates to:
  /// **'Group {group}'**
  String plansGroup(int group);

  /// No description provided for @plansLoopResult.
  ///
  /// In en, this message translates to:
  /// **'Loop result'**
  String get plansLoopResult;

  /// No description provided for @plansDependencies.
  ///
  /// In en, this message translates to:
  /// **'Dependencies'**
  String get plansDependencies;

  /// No description provided for @plansNoDependenciesLong.
  ///
  /// In en, this message translates to:
  /// **'None: can run in parallel with other ready cards.'**
  String get plansNoDependenciesLong;

  /// No description provided for @plansSession.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get plansSession;

  /// No description provided for @plansCommentsAndNotes.
  ///
  /// In en, this message translates to:
  /// **'Comments and notes'**
  String get plansCommentsAndNotes;

  /// No description provided for @plansNoCommentsYet.
  ///
  /// In en, this message translates to:
  /// **'No comments yet.'**
  String get plansNoCommentsYet;

  /// No description provided for @plansAddNote.
  ///
  /// In en, this message translates to:
  /// **'Add a note…'**
  String get plansAddNote;

  /// No description provided for @plansStateDone.
  ///
  /// In en, this message translates to:
  /// **'done'**
  String get plansStateDone;

  /// No description provided for @plansStatePending.
  ///
  /// In en, this message translates to:
  /// **'pending'**
  String get plansStatePending;

  /// No description provided for @plansStateBlocked.
  ///
  /// In en, this message translates to:
  /// **'blocked'**
  String get plansStateBlocked;

  /// No description provided for @plansStateReady.
  ///
  /// In en, this message translates to:
  /// **'ready'**
  String get plansStateReady;

  /// No description provided for @plansStateRunning.
  ///
  /// In en, this message translates to:
  /// **'running'**
  String get plansStateRunning;

  /// No description provided for @plansStateReview.
  ///
  /// In en, this message translates to:
  /// **'in review'**
  String get plansStateReview;

  /// No description provided for @plansLearnIntro.
  ///
  /// In en, this message translates to:
  /// **'Each comment on the cards becomes a change to the skill with the gap. You approve before it is applied.'**
  String get plansLearnIntro;

  /// No description provided for @plansLearnEmptyLive.
  ///
  /// In en, this message translates to:
  /// **'Claude is reading the comments and skills of the cards.\nProposals show up here; nothing changes without your OK.'**
  String get plansLearnEmptyLive;

  /// No description provided for @plansLearnEmpty.
  ///
  /// In en, this message translates to:
  /// **'No new comments on the cards.\nComment in a card\'s dialog and run Learn again.'**
  String get plansLearnEmpty;

  /// No description provided for @plansLearnNotApplied.
  ///
  /// In en, this message translates to:
  /// **'Not applied: {error}'**
  String plansLearnNotApplied(String error);

  /// No description provided for @plansDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get plansDiscard;

  /// No description provided for @plansApplyToSkill.
  ///
  /// In en, this message translates to:
  /// **'Apply to skill'**
  String get plansApplyToSkill;

  /// No description provided for @plansAppliedToSkill.
  ///
  /// In en, this message translates to:
  /// **'Applied to skill'**
  String get plansAppliedToSkill;

  /// No description provided for @plansDiscarded.
  ///
  /// In en, this message translates to:
  /// **'Discarded'**
  String get plansDiscarded;

  /// Name of a pasted plan without a # title
  ///
  /// In en, this message translates to:
  /// **'Imported plan'**
  String get plansImportedPlan;

  /// No description provided for @plansNewPlan.
  ///
  /// In en, this message translates to:
  /// **'New plan'**
  String get plansNewPlan;

  /// No description provided for @plansFromTemplate.
  ///
  /// In en, this message translates to:
  /// **'From a template'**
  String get plansFromTemplate;

  /// No description provided for @plansPasteMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Paste markdown'**
  String get plansPasteMarkdown;

  /// No description provided for @plansCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get plansCancel;

  /// No description provided for @plansImportPlan.
  ///
  /// In en, this message translates to:
  /// **'Import plan'**
  String get plansImportPlan;

  /// No description provided for @plansCreatePlan.
  ///
  /// In en, this message translates to:
  /// **'Create plan'**
  String get plansCreatePlan;

  /// No description provided for @plansRepository.
  ///
  /// In en, this message translates to:
  /// **'Repository'**
  String get plansRepository;

  /// No description provided for @plansAddRepoFirst.
  ///
  /// In en, this message translates to:
  /// **'Add a repository in the sidebar (This Mac) first.'**
  String get plansAddRepoFirst;

  /// No description provided for @plansTemplate.
  ///
  /// In en, this message translates to:
  /// **'Template'**
  String get plansTemplate;

  /// No description provided for @plansFeatureName.
  ///
  /// In en, this message translates to:
  /// **'Feature name'**
  String get plansFeatureName;

  /// No description provided for @plansSources.
  ///
  /// In en, this message translates to:
  /// **'Sources (Jira, Confluence, Figma), one per line'**
  String get plansSources;

  /// No description provided for @plansWhatToBuild.
  ///
  /// In en, this message translates to:
  /// **'What to build'**
  String get plansWhatToBuild;

  /// No description provided for @plansImportHint.
  ///
  /// In en, this message translates to:
  /// **'Any markdown in plan format: each ## becomes an approvable section, tables and lists become widgets, ```mermaid becomes a diagram and ```loops defines the execution.'**
  String get plansImportHint;

  /// No description provided for @plansImportPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'# Plan name\n\n## Sources\n…'**
  String get plansImportPlaceholder;

  /// No description provided for @plansAgo.
  ///
  /// In en, this message translates to:
  /// **'{duration} ago'**
  String plansAgo(String duration);

  /// Avatar initial for comments written by the user (You)
  ///
  /// In en, this message translates to:
  /// **'Y'**
  String get plansYouInitial;

  /// No description provided for @plansWriteComment.
  ///
  /// In en, this message translates to:
  /// **'Write a comment…'**
  String get plansWriteComment;

  /// No description provided for @shellNewWorkspace.
  ///
  /// In en, this message translates to:
  /// **'New workspace'**
  String get shellNewWorkspace;

  /// No description provided for @shellUsageAndCost.
  ///
  /// In en, this message translates to:
  /// **'Usage and cost'**
  String get shellUsageAndCost;

  /// No description provided for @shellCatalogTip.
  ///
  /// In en, this message translates to:
  /// **'Catalog of skills, MCPs and envs'**
  String get shellCatalogTip;

  /// No description provided for @shellSidebarCounts.
  ///
  /// In en, this message translates to:
  /// **'{accounts} accounts · {sessions} sessions'**
  String shellSidebarCounts(int accounts, int sessions);

  /// No description provided for @shellAccounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get shellAccounts;

  /// No description provided for @shellNewAccount.
  ///
  /// In en, this message translates to:
  /// **'New account'**
  String get shellNewAccount;

  /// No description provided for @shellSessions.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get shellSessions;

  /// No description provided for @shellNewSession.
  ///
  /// In en, this message translates to:
  /// **'New session'**
  String get shellNewSession;

  /// No description provided for @shellDeleteSession.
  ///
  /// In en, this message translates to:
  /// **'Delete session'**
  String get shellDeleteSession;

  /// No description provided for @shellDeleteSessionTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete the session {name}?'**
  String shellDeleteSessionTitle(String name);

  /// No description provided for @shellDeleteSessionBody.
  ///
  /// In en, this message translates to:
  /// **'Ends the process and removes it from the list. The worktree, the commits and the conversation (claude --resume) stay.'**
  String get shellDeleteSessionBody;

  /// No description provided for @shellDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get shellDelete;

  /// No description provided for @shellRepositories.
  ///
  /// In en, this message translates to:
  /// **'Repositories'**
  String get shellRepositories;

  /// No description provided for @shellAddRepository.
  ///
  /// In en, this message translates to:
  /// **'Add repository'**
  String get shellAddRepository;

  /// No description provided for @shellPlans.
  ///
  /// In en, this message translates to:
  /// **'Plans'**
  String get shellPlans;

  /// No description provided for @shellNewPlan.
  ///
  /// In en, this message translates to:
  /// **'New plan'**
  String get shellNewPlan;

  /// No description provided for @shellDeletePlan.
  ///
  /// In en, this message translates to:
  /// **'Delete plan'**
  String get shellDeletePlan;

  /// No description provided for @shellDeletePlanTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete the plan {name}?'**
  String shellDeletePlanTitle(String name);

  /// No description provided for @shellDeletePlanBodyRunning.
  ///
  /// In en, this message translates to:
  /// **'It has cards running: their sessions are ended. Branches, worktrees and PRs stay.'**
  String get shellDeletePlanBodyRunning;

  /// No description provided for @shellDeletePlanBody.
  ///
  /// In en, this message translates to:
  /// **'Branches, worktrees and PRs stay.'**
  String get shellDeletePlanBody;

  /// No description provided for @shellAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Account {email}'**
  String shellAccountTitle(String email);

  /// No description provided for @shellLogoutButton.
  ///
  /// In en, this message translates to:
  /// **'Log out (/logout)'**
  String get shellLogoutButton;

  /// No description provided for @shellLogoutHint.
  ///
  /// In en, this message translates to:
  /// **'Opens a session in it and runs Claude Code\'s /logout.'**
  String get shellLogoutHint;

  /// No description provided for @shellRemoveFromHarness.
  ///
  /// In en, this message translates to:
  /// **'Remove from the harness'**
  String get shellRemoveFromHarness;

  /// No description provided for @shellRemoveHint.
  ///
  /// In en, this message translates to:
  /// **'Ends its sessions and takes it out of the accounts. The folder and the conversations stay on disk.'**
  String get shellRemoveHint;

  /// No description provided for @shellCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get shellCancel;

  /// No description provided for @shellLogoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Log out of {email}?'**
  String shellLogoutTitle(String email);

  /// No description provided for @shellLogoutDefaultBody.
  ///
  /// In en, this message translates to:
  /// **'It is Claude Code\'s default account on this Mac: the login ends outside the harness too.'**
  String get shellLogoutDefaultBody;

  /// No description provided for @shellLogoutBody.
  ///
  /// In en, this message translates to:
  /// **'This account\'s login leaves Claude Code.'**
  String get shellLogoutBody;

  /// No description provided for @shellLogout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get shellLogout;

  /// No description provided for @shellRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {email} from the harness?'**
  String shellRemoveTitle(String email);

  /// No description provided for @shellRemoveBody.
  ///
  /// In en, this message translates to:
  /// **'Its sessions are ended.'**
  String get shellRemoveBody;

  /// No description provided for @shellRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get shellRemove;

  /// No description provided for @shellNoReadingYet.
  ///
  /// In en, this message translates to:
  /// **'no reading yet: the quota arrives with Claude\'s first reply'**
  String get shellNoReadingYet;

  /// No description provided for @shellUpdatedAgo.
  ///
  /// In en, this message translates to:
  /// **'updated {duration} ago'**
  String shellUpdatedAgo(String duration);

  /// No description provided for @shellResetIn.
  ///
  /// In en, this message translates to:
  /// **'resets in {duration}'**
  String shellResetIn(String duration);

  /// No description provided for @shellExhaustsIn.
  ///
  /// In en, this message translates to:
  /// **'at this pace, runs out in ~{duration}'**
  String shellExhaustsIn(String duration);

  /// Badge on a project still being planned
  ///
  /// In en, this message translates to:
  /// **'plan'**
  String get shellPlanBadge;

  /// No description provided for @shellSearchOrRun.
  ///
  /// In en, this message translates to:
  /// **'Search or run a command…'**
  String get shellSearchOrRun;

  /// No description provided for @shellExecution.
  ///
  /// In en, this message translates to:
  /// **'Execution'**
  String get shellExecution;

  /// No description provided for @shellPlan.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get shellPlan;

  /// No description provided for @shellUsage.
  ///
  /// In en, this message translates to:
  /// **'Usage'**
  String get shellUsage;

  /// No description provided for @shellCatalog.
  ///
  /// In en, this message translates to:
  /// **'Catalog'**
  String get shellCatalog;

  /// No description provided for @shellWorkspaceBrowser.
  ///
  /// In en, this message translates to:
  /// **'Workspace browser'**
  String get shellWorkspaceBrowser;

  /// No description provided for @shellToolInUse.
  ///
  /// In en, this message translates to:
  /// **'{tool} · in use by {session}'**
  String shellToolInUse(String tool, String session);

  /// No description provided for @shellInUseBy.
  ///
  /// In en, this message translates to:
  /// **'in use by {session}'**
  String shellInUseBy(String session);

  /// No description provided for @shellCodePaneTitle.
  ///
  /// In en, this message translates to:
  /// **'Code · {session}'**
  String shellCodePaneTitle(String session);

  /// No description provided for @shellEmptyPane.
  ///
  /// In en, this message translates to:
  /// **'Empty pane'**
  String get shellEmptyPane;

  /// No description provided for @shellChangesAndPr.
  ///
  /// In en, this message translates to:
  /// **'Changes and PR'**
  String get shellChangesAndPr;

  /// No description provided for @shellCodeTip.
  ///
  /// In en, this message translates to:
  /// **'Code (IDE in the session\'s folder)'**
  String get shellCodeTip;

  /// No description provided for @shellSplitSideBySide.
  ///
  /// In en, this message translates to:
  /// **'Split side by side'**
  String get shellSplitSideBySide;

  /// No description provided for @shellSplitTopBottom.
  ///
  /// In en, this message translates to:
  /// **'Split top and bottom'**
  String get shellSplitTopBottom;

  /// No description provided for @shellClosePane.
  ///
  /// In en, this message translates to:
  /// **'Close pane'**
  String get shellClosePane;

  /// No description provided for @shellTokensCost.
  ///
  /// In en, this message translates to:
  /// **'{tokens} tokens · {cost}'**
  String shellTokensCost(String tokens, String cost);

  /// No description provided for @shellFiveHourShare.
  ///
  /// In en, this message translates to:
  /// **'{percent}% of the 5h window'**
  String shellFiveHourShare(int percent);

  /// No description provided for @shellRestartingResumeLine.
  ///
  /// In en, this message translates to:
  /// **'↻ restarting with --resume…'**
  String get shellRestartingResumeLine;

  /// No description provided for @shellOpenInPane.
  ///
  /// In en, this message translates to:
  /// **'Open in this pane'**
  String get shellOpenInPane;

  /// No description provided for @shellSessionMemory.
  ///
  /// In en, this message translates to:
  /// **'Session memory'**
  String get shellSessionMemory;

  /// No description provided for @shellSessionMemoryHint.
  ///
  /// In en, this message translates to:
  /// **'What the agents store (decisions, preferences, project facts) and the workspace\'s other sessions find.'**
  String get shellSessionMemoryHint;

  /// No description provided for @shellMemoryHarness.
  ///
  /// In en, this message translates to:
  /// **'The harness\'s'**
  String get shellMemoryHarness;

  /// No description provided for @shellMemoryOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get shellMemoryOff;

  /// No description provided for @shellWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get shellWorkspace;

  /// No description provided for @shellWorkspaceHint.
  ///
  /// In en, this message translates to:
  /// **'A workspace brings together accounts, sessions, repositories, plans and a browser with its own logins (e.g. Work, Personal).'**
  String get shellWorkspaceHint;

  /// No description provided for @shellName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get shellName;

  /// No description provided for @shellWorkspaceAccounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts in this workspace'**
  String get shellWorkspaceAccounts;

  /// No description provided for @shellWorkspaceAccountsHint.
  ///
  /// In en, this message translates to:
  /// **'An account lives in one workspace only; checking it here takes it out of the other.'**
  String get shellWorkspaceAccountsHint;

  /// No description provided for @shellAccountInWorkspace.
  ///
  /// In en, this message translates to:
  /// **'{email} (in {workspace})'**
  String shellAccountInWorkspace(String email, String workspace);

  /// No description provided for @shellMonthlyBudget.
  ///
  /// In en, this message translates to:
  /// **'Monthly budget (US\$)'**
  String get shellMonthlyBudget;

  /// No description provided for @shellBudgetHint.
  ///
  /// In en, this message translates to:
  /// **'Optional. The app warns at 80% and when the limit is passed.'**
  String get shellBudgetHint;

  /// No description provided for @shellBudgetExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. 200'**
  String get shellBudgetExample;

  /// No description provided for @shellDeleteWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get shellDeleteWorkspace;

  /// No description provided for @shellCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get shellCreate;

  /// No description provided for @shellSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get shellSave;

  /// No description provided for @shellNewAccountBody.
  ///
  /// In en, this message translates to:
  /// **'A Claude Code account with its own config folder (~/.orc/accounts/<name>) in the workspace {workspace}. Opens a session in it: log in with /login.'**
  String shellNewAccountBody(String workspace);

  /// No description provided for @shellAccountName.
  ///
  /// In en, this message translates to:
  /// **'Account name'**
  String get shellAccountName;

  /// No description provided for @shellAccountNameExample.
  ///
  /// In en, this message translates to:
  /// **'work-2'**
  String get shellAccountNameExample;

  /// No description provided for @shellAccountTaken.
  ///
  /// In en, this message translates to:
  /// **'An account with that name already exists.'**
  String get shellAccountTaken;

  /// No description provided for @shellAccountRule.
  ///
  /// In en, this message translates to:
  /// **'Use letters, numbers, - and _.'**
  String get shellAccountRule;

  /// No description provided for @shellCreateAndLogin.
  ///
  /// In en, this message translates to:
  /// **'Create and log in'**
  String get shellCreateAndLogin;

  /// No description provided for @shellApprovalRequest.
  ///
  /// In en, this message translates to:
  /// **'{session} wants: {action}. It stays blocked until you decide (10 min).'**
  String shellApprovalRequest(String session, String action);

  /// No description provided for @shellDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get shellDecline;

  /// No description provided for @shellApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get shellApprove;

  /// No description provided for @shellEnvRequest.
  ///
  /// In en, this message translates to:
  /// **'{session} asks to store {env} in the daemon\'s Keychain. The value does not show here.'**
  String shellEnvRequest(String session, String env);

  /// No description provided for @shellDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get shellDismiss;

  /// No description provided for @shellSelectSession.
  ///
  /// In en, this message translates to:
  /// **'Select a session'**
  String get shellSelectSession;

  /// No description provided for @shellSessionProfile.
  ///
  /// In en, this message translates to:
  /// **'Session profile'**
  String get shellSessionProfile;

  /// No description provided for @shellRestartingWithResume.
  ///
  /// In en, this message translates to:
  /// **'Restarting with --resume…'**
  String get shellRestartingWithResume;

  /// No description provided for @shellApplyHint.
  ///
  /// In en, this message translates to:
  /// **'Applying restarts the session with --resume. The context is kept.'**
  String get shellApplyHint;

  /// No description provided for @shellDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get shellDiscard;

  /// No description provided for @shellApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get shellApply;

  /// No description provided for @shellPairAnother.
  ///
  /// In en, this message translates to:
  /// **'Pair another device'**
  String get shellPairAnother;

  /// No description provided for @shellShowPairingQr.
  ///
  /// In en, this message translates to:
  /// **'Show pairing QR'**
  String get shellShowPairingQr;

  /// No description provided for @shellPairQrHint.
  ///
  /// In en, this message translates to:
  /// **'On the phone: Connect daemon → Scan the QR. Valid once, for 10 minutes.'**
  String get shellPairQrHint;

  /// No description provided for @shellCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get shellCopy;

  /// No description provided for @shellPairedDevices.
  ///
  /// In en, this message translates to:
  /// **'Paired devices'**
  String get shellPairedDevices;

  /// No description provided for @shellThisDevice.
  ///
  /// In en, this message translates to:
  /// **'{name} (this one)'**
  String shellThisDevice(String name);

  /// No description provided for @shellRevoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get shellRevoke;

  /// No description provided for @shellNoDaemon.
  ///
  /// In en, this message translates to:
  /// **'This app was started without the daemon.'**
  String get shellNoDaemon;

  /// No description provided for @shellConnectDaemon.
  ///
  /// In en, this message translates to:
  /// **'Connect daemon'**
  String get shellConnectDaemon;

  /// No description provided for @shellConnectedCounts.
  ///
  /// In en, this message translates to:
  /// **'Connected: {accounts} account(s), {sessions} session(s).'**
  String shellConnectedCounts(int accounts, int sessions);

  /// No description provided for @shellConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get shellConnecting;

  /// No description provided for @shellPairedOffline.
  ///
  /// In en, this message translates to:
  /// **'Paired, not connected right now.'**
  String get shellPairedOffline;

  /// No description provided for @shellNotPaired.
  ///
  /// In en, this message translates to:
  /// **'Not paired yet.'**
  String get shellNotPaired;

  /// No description provided for @shellPairInstructions.
  ///
  /// In en, this message translates to:
  /// **'On the Mac where orcd runs: `orcd serve` and, in another terminal, `orcd pair`. Paste the ticket here (valid for 10 minutes, once).'**
  String get shellPairInstructions;

  /// No description provided for @shellScanPairQr.
  ///
  /// In en, this message translates to:
  /// **'Scan the `orcd pair` QR'**
  String get shellScanPairQr;

  /// No description provided for @shellClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get shellClose;

  /// No description provided for @shellPairAndConnect.
  ///
  /// In en, this message translates to:
  /// **'Pair and connect'**
  String get shellPairAndConnect;

  /// No description provided for @shellPointAtQr.
  ///
  /// In en, this message translates to:
  /// **'Point at the orcd pair QR'**
  String get shellPointAtQr;

  /// Session state label
  ///
  /// In en, this message translates to:
  /// **'running'**
  String get toolsSessionRunning;

  /// Session state label
  ///
  /// In en, this message translates to:
  /// **'waiting for you'**
  String get toolsSessionWaiting;

  /// Session state label
  ///
  /// In en, this message translates to:
  /// **'restarting'**
  String get toolsSessionStarting;

  /// Session state label
  ///
  /// In en, this message translates to:
  /// **'idle'**
  String get toolsSessionIdle;

  /// No description provided for @toolsCatalogTitle.
  ///
  /// In en, this message translates to:
  /// **'Catalog'**
  String get toolsCatalogTitle;

  /// No description provided for @toolsCatalogSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Configure once; each session turns on what it needs in the profile panel.'**
  String get toolsCatalogSubtitle;

  /// No description provided for @toolsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get toolsAdd;

  /// No description provided for @toolsPlanTemplatesHeader.
  ///
  /// In en, this message translates to:
  /// **'PLAN MODE TEMPLATES'**
  String get toolsPlanTemplatesHeader;

  /// No description provided for @toolsNewTemplate.
  ///
  /// In en, this message translates to:
  /// **'New template'**
  String get toolsNewTemplate;

  /// No description provided for @toolsPlanTemplatesHelp.
  ///
  /// In en, this message translates to:
  /// **'Markdown with the sections of each kind of work and the instruction for each. Picked in \"New plan\".'**
  String get toolsPlanTemplatesHelp;

  /// No description provided for @toolsSectionCount.
  ///
  /// In en, this message translates to:
  /// **'{count} sections'**
  String toolsSectionCount(int count);

  /// No description provided for @toolsEditMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Edit markdown'**
  String get toolsEditMarkdown;

  /// No description provided for @toolsKindSkills.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get toolsKindSkills;

  /// No description provided for @toolsKindMcps.
  ///
  /// In en, this message translates to:
  /// **'MCPs'**
  String get toolsKindMcps;

  /// No description provided for @toolsKindEnvs.
  ///
  /// In en, this message translates to:
  /// **'Envs'**
  String get toolsKindEnvs;

  /// No description provided for @toolsUnused.
  ///
  /// In en, this message translates to:
  /// **'unused'**
  String get toolsUnused;

  /// No description provided for @toolsUsedInSessions.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{in 1 session} other{in {count} sessions}}'**
  String toolsUsedInSessions(int count);

  /// No description provided for @toolsMcpTesting.
  ///
  /// In en, this message translates to:
  /// **'testing…'**
  String get toolsMcpTesting;

  /// No description provided for @toolsMcpConnected.
  ///
  /// In en, this message translates to:
  /// **'connected · {count} tools'**
  String toolsMcpConnected(String count);

  /// No description provided for @toolsMcpFailed.
  ///
  /// In en, this message translates to:
  /// **'failed: {reason}'**
  String toolsMcpFailed(String reason);

  /// No description provided for @toolsTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get toolsTestConnection;

  /// No description provided for @toolsSkillFolder.
  ///
  /// In en, this message translates to:
  /// **'Skill folder'**
  String get toolsSkillFolder;

  /// No description provided for @toolsCommandOrUrl.
  ///
  /// In en, this message translates to:
  /// **'Command or URL'**
  String get toolsCommandOrUrl;

  /// No description provided for @toolsEnvValue.
  ///
  /// In en, this message translates to:
  /// **'Value (kept in the Keychain)'**
  String get toolsEnvValue;

  /// No description provided for @toolsAddToCatalog.
  ///
  /// In en, this message translates to:
  /// **'Add to catalog'**
  String get toolsAddToCatalog;

  /// No description provided for @toolsName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get toolsName;

  /// No description provided for @toolsDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get toolsDescription;

  /// No description provided for @toolsCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get toolsCancel;

  /// No description provided for @toolsNewPlanTemplate.
  ///
  /// In en, this message translates to:
  /// **'New plan mode template'**
  String get toolsNewPlanTemplate;

  /// No description provided for @toolsEditTemplate.
  ///
  /// In en, this message translates to:
  /// **'Edit template'**
  String get toolsEditTemplate;

  /// No description provided for @toolsTemplateNameHint.
  ///
  /// In en, this message translates to:
  /// **'Name, e.g.: Back end with deploy'**
  String get toolsTemplateNameHint;

  /// No description provided for @toolsTemplateDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'When to use this template'**
  String get toolsTemplateDescriptionHint;

  /// No description provided for @toolsDeleteTemplate.
  ///
  /// In en, this message translates to:
  /// **'Delete template'**
  String get toolsDeleteTemplate;

  /// No description provided for @toolsSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get toolsSave;

  /// No description provided for @toolsHarnessUnderstood.
  ///
  /// In en, this message translates to:
  /// **'WHAT THE HARNESS UNDERSTOOD'**
  String get toolsHarnessUnderstood;

  /// No description provided for @toolsReadError.
  ///
  /// In en, this message translates to:
  /// **'Error reading: {error}'**
  String toolsReadError(String error);

  /// No description provided for @toolsSectionsAndLoops.
  ///
  /// In en, this message translates to:
  /// **'{sections} sections · {loops} loops'**
  String toolsSectionsAndLoops(int sections, int loops);

  /// No description provided for @toolsInstruction.
  ///
  /// In en, this message translates to:
  /// **'instruction: {text}'**
  String toolsInstruction(String text);

  /// No description provided for @toolsBlockText.
  ///
  /// In en, this message translates to:
  /// **'text'**
  String get toolsBlockText;

  /// No description provided for @toolsBlockList.
  ///
  /// In en, this message translates to:
  /// **'list'**
  String get toolsBlockList;

  /// No description provided for @toolsBlockTable.
  ///
  /// In en, this message translates to:
  /// **'table'**
  String get toolsBlockTable;

  /// No description provided for @toolsBlockCode.
  ///
  /// In en, this message translates to:
  /// **'code'**
  String get toolsBlockCode;

  /// No description provided for @toolsBlockFlowchart.
  ///
  /// In en, this message translates to:
  /// **'flowchart'**
  String get toolsBlockFlowchart;

  /// No description provided for @toolsBlockSequence.
  ///
  /// In en, this message translates to:
  /// **'sequence'**
  String get toolsBlockSequence;

  /// No description provided for @toolsBlockLoops.
  ///
  /// In en, this message translates to:
  /// **'loops'**
  String get toolsBlockLoops;

  /// No description provided for @toolsSectionEmpty.
  ///
  /// In en, this message translates to:
  /// **'empty'**
  String get toolsSectionEmpty;

  /// No description provided for @toolsUsageTitle.
  ///
  /// In en, this message translates to:
  /// **'Usage · {workspace}'**
  String toolsUsageTitle(String workspace);

  /// No description provided for @toolsUsageLiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Claude Code\'s own metrics (OpenTelemetry), by session, account and model.'**
  String get toolsUsageLiveSubtitle;

  /// No description provided for @toolsUsageDemoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Demo data; the This Mac workspace shows the real ones.'**
  String get toolsUsageDemoSubtitle;

  /// No description provided for @toolsDays.
  ///
  /// In en, this message translates to:
  /// **'{count} days'**
  String toolsDays(int count);

  /// No description provided for @toolsCost.
  ///
  /// In en, this message translates to:
  /// **'Cost'**
  String get toolsCost;

  /// No description provided for @toolsTokens.
  ///
  /// In en, this message translates to:
  /// **'Tokens'**
  String get toolsTokens;

  /// No description provided for @toolsDailyAverage.
  ///
  /// In en, this message translates to:
  /// **'Daily average'**
  String get toolsDailyAverage;

  /// No description provided for @toolsCacheRead.
  ///
  /// In en, this message translates to:
  /// **'Read from cache'**
  String get toolsCacheRead;

  /// No description provided for @toolsThisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get toolsThisMonth;

  /// No description provided for @toolsBudgetShare.
  ///
  /// In en, this message translates to:
  /// **'{percent}% of {workspace}\'s monthly budget'**
  String toolsBudgetShare(int percent, String workspace);

  /// No description provided for @toolsTokensByType.
  ///
  /// In en, this message translates to:
  /// **'Tokens by type'**
  String get toolsTokensByType;

  /// No description provided for @toolsInput.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get toolsInput;

  /// No description provided for @toolsOutput.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get toolsOutput;

  /// No description provided for @toolsCacheWrite.
  ///
  /// In en, this message translates to:
  /// **'Written to cache'**
  String get toolsCacheWrite;

  /// No description provided for @toolsCostPerDay.
  ///
  /// In en, this message translates to:
  /// **'Cost per day (US\$)'**
  String get toolsCostPerDay;

  /// No description provided for @toolsShowChart.
  ///
  /// In en, this message translates to:
  /// **'Show chart'**
  String get toolsShowChart;

  /// No description provided for @toolsShowTable.
  ///
  /// In en, this message translates to:
  /// **'Show table'**
  String get toolsShowTable;

  /// No description provided for @toolsByAccountModel.
  ///
  /// In en, this message translates to:
  /// **'By account and model'**
  String get toolsByAccountModel;

  /// No description provided for @toolsAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get toolsAccount;

  /// No description provided for @toolsModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get toolsModel;

  /// No description provided for @toolsNoUsage.
  ///
  /// In en, this message translates to:
  /// **'No usage recorded in this period.'**
  String get toolsNoUsage;

  /// No description provided for @toolsByPlan.
  ///
  /// In en, this message translates to:
  /// **'By plan'**
  String get toolsByPlan;

  /// No description provided for @toolsPlan.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get toolsPlan;

  /// No description provided for @toolsCardsDone.
  ///
  /// In en, this message translates to:
  /// **'Cards done'**
  String get toolsCardsDone;

  /// No description provided for @toolsNoPlans.
  ///
  /// In en, this message translates to:
  /// **'No plan running in this period.'**
  String get toolsNoPlans;

  /// No description provided for @toolsByProjectBranch.
  ///
  /// In en, this message translates to:
  /// **'By project and branch (cards)'**
  String get toolsByProjectBranch;

  /// No description provided for @toolsProject.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get toolsProject;

  /// No description provided for @toolsBranch.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get toolsBranch;

  /// No description provided for @toolsLooseSessions.
  ///
  /// In en, this message translates to:
  /// **'standalone sessions'**
  String get toolsLooseSessions;

  /// No description provided for @toolsNoTokens.
  ///
  /// In en, this message translates to:
  /// **'No tokens in this period.'**
  String get toolsNoTokens;

  /// No description provided for @toolsGroupSessions.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get toolsGroupSessions;

  /// No description provided for @toolsGroupPanes.
  ///
  /// In en, this message translates to:
  /// **'Panes'**
  String get toolsGroupPanes;

  /// No description provided for @toolsGroupProjects.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get toolsGroupProjects;

  /// No description provided for @toolsGroupCatalog.
  ///
  /// In en, this message translates to:
  /// **'Catalog'**
  String get toolsGroupCatalog;

  /// No description provided for @toolsGroupCode.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get toolsGroupCode;

  /// No description provided for @toolsGroupUsage.
  ///
  /// In en, this message translates to:
  /// **'Usage'**
  String get toolsGroupUsage;

  /// No description provided for @toolsGroupWorkspaces.
  ///
  /// In en, this message translates to:
  /// **'Workspaces'**
  String get toolsGroupWorkspaces;

  /// No description provided for @toolsGroupProfileOf.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s profile'**
  String toolsGroupProfileOf(String name);

  /// No description provided for @toolsGoTo.
  ///
  /// In en, this message translates to:
  /// **'Go to {name}'**
  String toolsGoTo(String name);

  /// No description provided for @toolsNewSession.
  ///
  /// In en, this message translates to:
  /// **'New session'**
  String get toolsNewSession;

  /// No description provided for @toolsSplitSideBySide.
  ///
  /// In en, this message translates to:
  /// **'Split side by side'**
  String get toolsSplitSideBySide;

  /// No description provided for @toolsSplitTopBottom.
  ///
  /// In en, this message translates to:
  /// **'Split top and bottom'**
  String get toolsSplitTopBottom;

  /// No description provided for @toolsClosePane.
  ///
  /// In en, this message translates to:
  /// **'Close pane'**
  String get toolsClosePane;

  /// No description provided for @toolsHideProfilePanel.
  ///
  /// In en, this message translates to:
  /// **'Hide profile panel'**
  String get toolsHideProfilePanel;

  /// No description provided for @toolsShowProfilePanel.
  ///
  /// In en, this message translates to:
  /// **'Show profile panel'**
  String get toolsShowProfilePanel;

  /// No description provided for @toolsOpenPlanOf.
  ///
  /// In en, this message translates to:
  /// **'Open {name}\'s plan'**
  String toolsOpenPlanOf(String name);

  /// No description provided for @toolsOpenNamed.
  ///
  /// In en, this message translates to:
  /// **'Open {name}'**
  String toolsOpenNamed(String name);

  /// No description provided for @toolsOpenComments.
  ///
  /// In en, this message translates to:
  /// **'{count} open comments'**
  String toolsOpenComments(int count);

  /// No description provided for @toolsRunReadyCards.
  ///
  /// In en, this message translates to:
  /// **'Run {name}\'s ready cards'**
  String toolsRunReadyCards(String name);

  /// No description provided for @toolsReadyCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 ready} other{{count} ready}}'**
  String toolsReadyCount(int count);

  /// No description provided for @toolsRequestReview.
  ///
  /// In en, this message translates to:
  /// **'Ask Claude to review the comments'**
  String get toolsRequestReview;

  /// No description provided for @toolsNewPlanFromTemplate.
  ///
  /// In en, this message translates to:
  /// **'New plan from a template'**
  String get toolsNewPlanFromTemplate;

  /// No description provided for @toolsImportPlan.
  ///
  /// In en, this message translates to:
  /// **'Import plan in markdown'**
  String get toolsImportPlan;

  /// No description provided for @toolsSearchCodeCmd.
  ///
  /// In en, this message translates to:
  /// **'Search code (⌘⇧F)'**
  String get toolsSearchCodeCmd;

  /// No description provided for @toolsOpenUsage.
  ///
  /// In en, this message translates to:
  /// **'Open workspace usage and cost'**
  String get toolsOpenUsage;

  /// No description provided for @toolsOpenCatalog.
  ///
  /// In en, this message translates to:
  /// **'Open catalog of skills, MCPs and envs'**
  String get toolsOpenCatalog;

  /// No description provided for @toolsBackToSessions.
  ///
  /// In en, this message translates to:
  /// **'Back to sessions'**
  String get toolsBackToSessions;

  /// No description provided for @toolsTurnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off {name}'**
  String toolsTurnOff(String name);

  /// No description provided for @toolsTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on {name}'**
  String toolsTurnOn(String name);

  /// No description provided for @toolsApplyChanges.
  ///
  /// In en, this message translates to:
  /// **'Apply changes (restarts with --resume)'**
  String get toolsApplyChanges;

  /// No description provided for @toolsSwitchTo.
  ///
  /// In en, this message translates to:
  /// **'Switch to {name}'**
  String toolsSwitchTo(String name);

  /// No description provided for @toolsNothingOpen.
  ///
  /// In en, this message translates to:
  /// **'nothing open'**
  String get toolsNothingOpen;

  /// No description provided for @toolsSearchNeedsDaemon.
  ///
  /// In en, this message translates to:
  /// **'Code search needs the daemon connected.'**
  String get toolsSearchNeedsDaemon;

  /// No description provided for @toolsSearchIn.
  ///
  /// In en, this message translates to:
  /// **'Search in {label}…'**
  String toolsSearchIn(String label);

  /// No description provided for @toolsSymbols.
  ///
  /// In en, this message translates to:
  /// **'Symbols'**
  String get toolsSymbols;

  /// No description provided for @toolsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get toolsSearch;

  /// No description provided for @toolsResults.
  ///
  /// In en, this message translates to:
  /// **'{count} result(s) for \"{query}\"'**
  String toolsResults(String count, String query);

  /// No description provided for @devBrowserNoDaemon.
  ///
  /// In en, this message translates to:
  /// **'The daemon is not connected: the browser runs there. Connect it in ⚙.'**
  String get devBrowserNoDaemon;

  /// No description provided for @devFoldersNoDaemon.
  ///
  /// In en, this message translates to:
  /// **'The daemon is not connected: the folders come from it. Connect it in ⚙.'**
  String get devFoldersNoDaemon;

  /// Session state label: the process exited
  ///
  /// In en, this message translates to:
  /// **'ended'**
  String get toolsSessionEnded;

  /// Shown over a terminal whose Claude process exited
  ///
  /// In en, this message translates to:
  /// **'The session ended.'**
  String get sessionEndedBanner;

  /// Button: start the ended session again, resuming its conversation
  ///
  /// In en, this message translates to:
  /// **'Reopen'**
  String get sessionReopen;

  /// Button: remove the ended session
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get sessionCloseEnded;

  /// Onboarding, first screen title
  ///
  /// In en, this message translates to:
  /// **'Welcome to Orc Harness'**
  String get onboardWelcomeTitle;

  /// Onboarding, first screen text
  ///
  /// In en, this message translates to:
  /// **'Run many Claude Code sessions side by side. First, three permissions, one at a time: each one says why it\'s needed, and you can skip any of them.'**
  String get onboardWelcomeWhy;

  /// Onboarding step title
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get onboardNotificationsTitle;

  /// Onboarding: why notifications
  ///
  /// In en, this message translates to:
  /// **'So you know when a session is waiting for you, a deploy needs your OK or a card is done. They only show while the app is in the background.'**
  String get onboardNotificationsWhy;

  /// Onboarding step title
  ///
  /// In en, this message translates to:
  /// **'Background service'**
  String get onboardServiceTitle;

  /// Onboarding: why the background service
  ///
  /// In en, this message translates to:
  /// **'Sessions run in orcd, a small service that starts when you log in, so they keep going with the app closed. macOS will say a background item was added (you can turn it off in System Settings → General → Login Items). It keeps its key in your Keychain: if asked, choose Always Allow.'**
  String get onboardServiceWhy;

  /// Onboarding step title
  ///
  /// In en, this message translates to:
  /// **'Local network'**
  String get onboardNetworkTitle;

  /// Onboarding: why local network
  ///
  /// In en, this message translates to:
  /// **'The app talks to the service, and later to your phone, over an encrypted connection on your network. macOS will ask whether Orc Harness may find devices on your local network: allow it, or the app can\'t connect.'**
  String get onboardNetworkWhy;

  /// Onboarding: skip this step
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get onboardNotNow;

  /// Onboarding: leave the welcome
  ///
  /// In en, this message translates to:
  /// **'Let\'s go'**
  String get onboardStart;

  /// Onboarding: bring up the native prompt
  ///
  /// In en, this message translates to:
  /// **'Grant'**
  String get onboardGrant;

  /// Onboarding: last step's button
  ///
  /// In en, this message translates to:
  /// **'Grant and finish'**
  String get onboardGrantFinish;

  /// Onboarding: retry after an error
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get onboardRetry;

  /// Onboarding progress
  ///
  /// In en, this message translates to:
  /// **'{n} of {total}'**
  String onboardStep(int n, int total);

  /// Onboarding: an error
  ///
  /// In en, this message translates to:
  /// **'That didn\'t work: {error}'**
  String onboardFailed(String error);

  /// Notification title: an agent asks to add an MCP server
  ///
  /// In en, this message translates to:
  /// **'An agent wants an MCP server'**
  String get coreAlertMcpTitle;

  /// Notification body
  ///
  /// In en, this message translates to:
  /// **'{session} asks to add {name}'**
  String coreAlertMcpBody(String session, String name);

  /// Notice above the panes
  ///
  /// In en, this message translates to:
  /// **'{session} asks to add the MCP server {name}'**
  String shellMcpRequest(String session, String name);

  /// Button: add the MCP and restart that session (resuming its conversation)
  ///
  /// In en, this message translates to:
  /// **'Approve and restart'**
  String get shellMcpApprove;

  /// Button and dialog title: bring MCP servers already set up in Claude Code into the catalog
  ///
  /// In en, this message translates to:
  /// **'Import from this Mac'**
  String get toolsImportMcps;

  /// Import dialog hint
  ///
  /// In en, this message translates to:
  /// **'MCP servers and skills already on this Mac: every Claude Code setup (~/.claude*), other tools (Claude Desktop, Cursor, Windsurf, VS Code, Gemini CLI, Codex…), your projects and plugins. Secret values go to the Keychain; the catalog keeps only references.'**
  String get toolsImportMcpsHint;

  /// Import dialog: nothing found
  ///
  /// In en, this message translates to:
  /// **'No MCP servers or skills found on this Mac.'**
  String get toolsImportNone;

  /// Import row: a catalog MCP has this name
  ///
  /// In en, this message translates to:
  /// **'· replaces the one in the catalog'**
  String get toolsImportReplaces;

  /// Import row: env names whose values move to the Keychain
  ///
  /// In en, this message translates to:
  /// **'To the Keychain: {names}'**
  String toolsImportSecrets(String names);

  /// Import dialog button
  ///
  /// In en, this message translates to:
  /// **'Import {count}'**
  String toolsImportCount(int count);

  /// Profile panel section title
  ///
  /// In en, this message translates to:
  /// **'claude.ai connectors'**
  String get shellConnectorsTitle;

  /// Profile panel connectors hint
  ///
  /// In en, this message translates to:
  /// **'The ones this account added on claude.ai (Gmail, Drive, Slack…). Only the ones you check enter this session.'**
  String get shellConnectorsHint;

  /// Connectors loading
  ///
  /// In en, this message translates to:
  /// **'Asking Claude Code (it checks each one)…'**
  String get shellConnectorsLoading;

  /// No connectors
  ///
  /// In en, this message translates to:
  /// **'No connectors on this account (or it is logged in with an API key).'**
  String get shellConnectorsNone;

  /// Connector status
  ///
  /// In en, this message translates to:
  /// **'Not connected: connect it on claude.ai'**
  String get shellConnectorNeedsAuth;

  /// Connector status
  ///
  /// In en, this message translates to:
  /// **'Didn\'t answer the last check'**
  String get shellConnectorFailed;

  /// Toolbar tool and pane title
  ///
  /// In en, this message translates to:
  /// **'Emulators and simulators'**
  String get shellEmulators;

  /// Emulator pane: device list hint
  ///
  /// In en, this message translates to:
  /// **'Pick a device. It runs here, without its own window.'**
  String get devEmulatorPick;

  /// Emulator pane: nothing found
  ///
  /// In en, this message translates to:
  /// **'No emulators or simulators found. Install Xcode (iOS) or Android Studio with an AVD.'**
  String get devEmulatorNone;

  /// Device state
  ///
  /// In en, this message translates to:
  /// **'on'**
  String get devEmulatorOn;

  /// Device state
  ///
  /// In en, this message translates to:
  /// **'off'**
  String get devEmulatorOff;

  /// Device state
  ///
  /// In en, this message translates to:
  /// **'turning on…'**
  String get devEmulatorBooting;

  /// Button
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get devEmulatorBoot;

  /// Button
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get devEmulatorShutdown;

  /// Device home button
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get devEmulatorHome;

  /// Back to the device list
  ///
  /// In en, this message translates to:
  /// **'Other device'**
  String get devEmulatorSwitch;

  /// Import dialog
  ///
  /// In en, this message translates to:
  /// **'Search by name or source'**
  String get toolsImportSearch;

  /// Import dialog
  ///
  /// In en, this message translates to:
  /// **'· already in the catalog'**
  String get toolsImportInCatalog;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
