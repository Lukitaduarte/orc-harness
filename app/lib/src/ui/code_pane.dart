import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../i18n.dart';
import '../live/daemon_client.dart';
import '../live/lsp_client.dart';

/// The IDE in a pane: the session's folder as a tree, the open files with
/// highlighting, autocomplete and diagnostics from the language server.
class CodePane extends StatefulWidget {
  const CodePane({super.key, required this.daemon, required this.sessionId});

  final DaemonClient daemon;
  final String sessionId;

  @override
  State<CodePane> createState() => _CodePaneState();
}

class _OpenFile {
  _OpenFile(this.path, String text)
    : controller = CodeLineEditingController.fromText(text),
      saved = text;

  final String path;
  final CodeLineEditingController controller;
  String saved;

  /// Text the language server last got, and the tab's last dirty mark.
  late String synced = saved;
  bool shownDirty = false;

  bool get dirty => controller.text != saved;
}

class _CodePaneState extends State<CodePane> {
  final _expanded = <String>{''};
  final _files = <_OpenFile>[];
  int _current = -1;
  String? _error;
  final _prompts = LspPrompts();
  Timer? _debounce;

  /// What the server said about the symbol under the cursor (⌘I).
  String? _info;

  DaemonClient get d => widget.daemon;
  String get sid => widget.sessionId;
  _OpenFile? get _file => _current < 0 ? null : _files[_current];

  @override
  void initState() {
    super.initState();
    d.listDir(sid, '');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final f in _files) {
      f.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _open(String path) async {
    final at = _files.indexWhere((f) => f.path == path);
    if (at >= 0) return setState(() => _current = at);
    try {
      final text = await d.readFile(sid, path);
      final f = _OpenFile(path, text);
      f.controller.addListener(() => _edited(f));
      setState(() {
        _files.add(f);
        _current = _files.length - 1;
        _error = null;
      });
      final lang = languageOf(path);
      if (lang != null) d.lsp(sid, lang).open(path, lang, text);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  /// Keeps the server in sync and asks for completions at the cursor.
  void _edited(_OpenFile f) {
    // The editor notifies mid-build (selection too): repaint the tab after
    // the frame, and only when its unsaved mark changes.
    if (f.dirty != f.shownDirty) {
      f.shownDirty = f.dirty;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    final text = f.controller.text;
    final lang = languageOf(f.path);
    if (lang == null || text == f.synced) return;
    f.synced = text;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () async {
      final lsp = d.lsp(sid, lang);
      lsp.change(f.path, f.controller.text);
      final sel = f.controller.selection;
      final items = await lsp.complete(
        f.path,
        sel.extentIndex,
        sel.extentOffset,
      );
      _prompts.update(items);
    });
  }

  void _save() {
    final f = _file;
    if (f == null) return;
    d.writeFile(sid, f.path, f.controller.text);
    f
      ..saved = f.controller.text
      ..shownDirty = false;
    final lang = languageOf(f.path);
    if (lang != null) d.lsp(sid, lang).saved(f.path);
    setState(() {});
  }

  (String, LspClient)? _lspFor(_OpenFile f) {
    final lang = languageOf(f.path);
    return lang == null ? null : (lang, d.lsp(sid, lang));
  }

  /// F12: opens the definition of the symbol under the cursor.
  Future<void> _definition() async {
    final f = _file;
    final l = f == null ? null : _lspFor(f);
    if (f == null || l == null) return;
    l.$2.change(f.path, f.controller.text);
    final sel = f.controller.selection;
    final found = await l.$2.definition(
      f.path,
      sel.extentIndex,
      sel.extentOffset,
    );
    if (found.isEmpty) {
      return setState(() => _info = context.l10n.devDefinitionNotFound);
    }
    final (uri, line, character) = found.first;
    final rel = l.$2.relativeOf(uri);
    if (rel == null) {
      return setState(
        () => _info = context.l10n.devDefinedOutside(
          '${Uri.parse(uri).path}:${line + 1}',
        ),
      );
    }
    await _open(rel);
    final target = _file;
    if (target == null || target.path != rel) return;
    target.controller.selection = CodeLineSelection.collapsed(
      index: line,
      offset: character,
    );
    target.controller.makeCursorCenterIfInvisible();
  }

  /// ⌘I: what the server knows about the symbol under the cursor.
  Future<void> _hover() async {
    final f = _file;
    final l = f == null ? null : _lspFor(f);
    if (f == null || l == null) return;
    final sel = f.controller.selection;
    final text = await l.$2.hover(f.path, sel.extentIndex, sel.extentOffset);
    if (!mounted) return;
    setState(() => _info = text ?? context.l10n.devNothingAboutSymbol);
  }

  /// ⇧⌥F: formats the file with the language server.
  Future<void> _format() async {
    final f = _file;
    final l = f == null ? null : _lspFor(f);
    if (f == null || l == null) return;
    l.$2.change(f.path, f.controller.text);
    final formatted = await l.$2.format(f.path, f.controller.text);
    if (formatted != null && formatted != f.controller.text) {
      f.controller.text = formatted;
    }
  }

  void _close(int i) {
    // re_editor's cursor blink outlives a focused editor that goes away.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _files.removeAt(i).controller.dispose();
      _current = math.min(_current, _files.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
      const SingleActivator(LogicalKeyboardKey.f12): _definition,
      const SingleActivator(LogicalKeyboardKey.keyI, meta: true): _hover,
      const SingleActivator(LogicalKeyboardKey.keyF, shift: true, alt: true):
          _format,
    },
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 220,
          child: ListenableBuilder(
            listenable: d,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: _tree('', 0),
            ),
          ),
        ),
        const VerticalDivider(),
        Expanded(child: _editorArea(context)),
      ],
    ),
  );

  List<Widget> _tree(String dir, int depth) {
    final entries = d.dirs[(sid, dir)];
    if (entries == null) return const [];
    return [
      for (final e in entries) ...[
        _treeRow(dir, e, depth),
        if (e['dir'] == true && _expanded.contains(_join(dir, e['name'])))
          ..._tree(_join(dir, e['name']), depth + 1),
      ],
    ];
  }

  static String _join(String dir, Object? name) =>
      dir.isEmpty ? '$name' : '$dir/$name';

  Widget _treeRow(String dir, Map<String, dynamic> e, int depth) {
    final path = _join(dir, e['name']);
    final isDir = e['dir'] == true;
    final open = _expanded.contains(path);
    final current = _file?.path == path;
    return GestureDetector(
      onTap: () {
        if (!isDir) {
          _open(path);
          return;
        }
        setState(() => open ? _expanded.remove(path) : _expanded.add(path));
        if (!open) d.listDir(sid, path);
      },
      child: Container(
        color: current ? Theme.of(context).colorScheme.accent : null,
        padding: EdgeInsets.fromLTRB(8.0 + depth * 12, 3, 8, 3),
        child: Row(
          children: [
            Icon(
              isDir
                  ? (open ? LucideIcons.folderOpen : LucideIcons.folder)
                  : LucideIcons.file,
              size: 13,
            ),
            const Gap(6),
            Expanded(
              child: Text(
                '${e['name']}',
                overflow: TextOverflow.ellipsis,
              ).xSmall(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editorArea(BuildContext context) {
    final f = _file;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 34,
          child: Row(
            children: [
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [for (final (i, o) in _files.indexed) _tab(i, o)],
                ),
              ),
              _openIn(),
            ],
          ),
        ),
        const Divider(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_error!).xSmall().muted(),
          ),
        Expanded(
          child: f == null
              ? Center(child: Text(context.l10n.devPickFile))
              : _editor(context, f),
        ),
        if (_info != null)
          Container(
            constraints: const BoxConstraints(maxHeight: 140),
            padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
            color: Theme.of(context).colorScheme.muted,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(_info!).mono().xSmall(),
                  ),
                ),
                GhostButton(
                  density: ButtonDensity.icon,
                  size: ButtonSize.small,
                  onPressed: () => setState(() => _info = null),
                  child: const Icon(LucideIcons.x, size: 12),
                ),
              ],
            ),
          ),
        if (f != null) _diagnostics(f),
      ],
    );
  }

  Widget _tab(int i, _OpenFile o) {
    final name = o.path.split('/').last;
    final on = i == _current;
    return GestureDetector(
      onTap: () => setState(() => _current = i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: on
              ? Border(
                  bottom: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            Text(o.dirty ? '● $name' : name).xSmall(),
            const Gap(4),
            GestureDetector(
              onTap: () => _close(i),
              child: const Icon(LucideIcons.x, size: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _langTool(IconData icon, String tip, VoidCallback onPressed) =>
      Tooltip(
        tooltip: (context) => TooltipContainer(child: Text(tip)),
        child: GhostButton(
          density: ButtonDensity.icon,
          size: ButtonSize.small,
          onPressed: onPressed,
          child: Icon(icon, size: 13),
        ),
      );

  /// Opens the session's folder (or its iOS/Android project) elsewhere.
  Widget _openIn() {
    Widget item(String label, String path, String app) => GhostButton(
      size: ButtonSize.small,
      onPressed: () => d.openExternal(sid, path, app),
      child: Text(label).xSmall(),
    );
    final root = d.dirs[(sid, '')] ?? const [];
    bool has(String n) => root.any((e) => e['name'] == n);
    final f = _file;
    return Row(
      children: [
        if (f != null && languageOf(f.path) != null) ...[
          _langTool(
            LucideIcons.squareArrowOutUpRight,
            context.l10n.devGoToDefinition,
            _definition,
          ),
          _langTool(LucideIcons.info, context.l10n.devAboutSymbol, _hover),
          _langTool(LucideIcons.wandSparkles, context.l10n.devFormat, _format),
        ],
        if (has('ios')) item('Xcode', 'ios/Runner.xcworkspace', 'xcode'),
        if (has('android')) item('Android Studio', 'android', 'android-studio'),
        item('Zed', '', 'zed'),
        item('Finder', '', 'finder'),
      ],
    );
  }

  Widget _editor(BuildContext context, _OpenFile f) {
    final dark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    final mode = _highlight(f.path);
    final scheme = Theme.of(context).colorScheme;
    return CodeAutocomplete(
      viewBuilder: (context, notifier, onSelected) =>
          _PromptList(notifier: notifier, onSelected: onSelected),
      promptsBuilder: _prompts,
      child: CodeEditor(
        key: ValueKey(f.path),
        controller: f.controller,
        wordWrap: false,
        style: CodeEditorStyle(
          fontSize: 13,
          fontFamily: Theme.of(context).typography.mono.fontFamily,
          backgroundColor: scheme.background,
          codeTheme: mode == null
              ? null
              : CodeHighlightTheme(
                  languages: {'code': CodeHighlightThemeMode(mode: mode)},
                  theme: dark ? atomOneDarkTheme : atomOneLightTheme,
                ),
        ),
        indicatorBuilder: (context, editing, chunk, notifier) => Row(
          children: [
            DefaultCodeLineNumber(controller: editing, notifier: notifier),
            DefaultCodeChunkIndicator(
              width: 16,
              controller: chunk,
              notifier: notifier,
            ),
          ],
        ),
      ),
    );
  }

  static Mode? _highlight(String path) => switch (path.split('.').last) {
    'dart' => langDart,
    'ts' || 'tsx' || 'js' || 'jsx' => langTypescript,
    'kt' || 'kts' => langKotlin,
    'swift' => langSwift,
    'json' || 'arb' => langJson,
    'yaml' || 'yml' => langYaml,
    'md' => langMarkdown,
    'xml' || 'plist' => langXml,
    _ => null,
  };

  Widget _diagnostics(_OpenFile f) {
    final lang = languageOf(f.path);
    if (lang == null) return const SizedBox.shrink();
    final lsp = d.lsp(sid, lang);
    return ListenableBuilder(
      listenable: lsp,
      builder: (context, _) {
        final list = lsp.diagnostics[lsp.uriOf(f.path)] ?? const [];
        if (list.isEmpty) return const SizedBox.shrink();
        return Container(
          constraints: const BoxConstraints(maxHeight: 120),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Theme.of(context).colorScheme.border),
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.all(6),
            children: [
              for (final g in list)
                Text(
                  context.l10n.devDiagnostic(
                    g['severity'] == 1
                        ? context.l10n.devSeverityError
                        : context.l10n.devSeverityWarning,
                    (g['range']['start']['line'] as int) + 1,
                    '${g['message']}',
                  ),
                ).xSmall(),
            ],
          ),
        );
      },
    );
  }
}

/// Autocomplete from the language server: the last completion list for
/// the cursor, filtered by the word being typed.
class LspPrompts implements CodeAutocompletePromptsBuilder {
  List<CodePrompt> _items = const [];

  void update(List<Map<String, dynamic>> items) {
    _items = [
      for (final i in items.take(300))
        CodeFieldPrompt(
          word: (i['filterText'] ?? i['label']).toString(),
          type: (i['detail'] ?? '').toString(),
          customAutocomplete: CodeAutocompleteResult.fromWord(
            plainInsert(
              (i['insertText'] ?? i['textEdit']?['newText'] ?? i['label'])
                  .toString(),
            ),
          ),
        ),
    ];
  }

  @override
  CodeAutocompleteEditingValue? build(
    BuildContext context,
    CodeLine codeLine,
    CodeLineSelection selection,
  ) {
    final before = codeLine.text.substring(
      0,
      math.min(selection.extentOffset, codeLine.text.length),
    );
    final word = RegExp(r'[A-Za-z0-9_$]*$').firstMatch(before)!.group(0)!;
    final afterDot = before.endsWith('.');
    if (word.isEmpty && !afterDot) return null;
    final prompts = _items
        .where((p) => word.isEmpty || p.match(word))
        .take(50)
        .toList();
    if (prompts.isEmpty) return null;
    return CodeAutocompleteEditingValue(
      input: word,
      prompts: prompts,
      index: 0,
    );
  }
}

class _PromptList extends StatelessWidget implements PreferredSizeWidget {
  const _PromptList({required this.notifier, required this.onSelected});

  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;

  @override
  Size get preferredSize =>
      Size(360, math.min(notifier.value.prompts.length, 8) * 26.0 + 8);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints.loose(preferredSize),
      decoration: BoxDecoration(
        color: scheme.popover,
        border: Border.all(color: scheme.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ValueListenableBuilder(
        valueListenable: notifier,
        builder: (context, value, _) => ListView(
          padding: const EdgeInsets.all(4),
          children: [
            for (final (i, p) in value.prompts.indexed)
              GestureDetector(
                onTap: () => onSelected(value.copyWith(index: i).autocomplete),
                child: Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  color: i == value.index ? scheme.accent : null,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.word,
                          overflow: TextOverflow.ellipsis,
                        ).xSmall().mono(),
                      ),
                      if (p is CodeFieldPrompt)
                        Flexible(
                          child: Text(
                            p.type,
                            overflow: TextOverflow.ellipsis,
                          ).xSmall().muted(),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
