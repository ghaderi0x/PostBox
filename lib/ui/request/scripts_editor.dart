import 'package:flutter/material.dart';

import '../../core/design/typography.dart';
import '../../l10n/strings.dart';
import '../editor/code_editor.dart';
import '../editor/code_editor_controller.dart';
import '../editor/highlighter.dart';

/// Pre-request and post-response scripts (PostBox Script, see
/// docs/SCRIPTING.md). Used for requests, folders and collections.
class ScriptsEditor extends StatefulWidget {
  const ScriptsEditor({
    super.key,
    required this.pre,
    required this.post,
    required this.onChanged,
  });

  final String pre;
  final String post;

  /// Called with the new (pre, post) pair.
  final void Function(String pre, String post) onChanged;

  @override
  State<ScriptsEditor> createState() => _ScriptsEditorState();
}

class _ScriptsEditorState extends State<ScriptsEditor> {
  late final CodeEditorController _pre = CodeEditorController(
    text: widget.pre,
    language: CodeLanguage.text,
  );
  late final CodeEditorController _post = CodeEditorController(
    text: widget.post,
    language: CodeLanguage.text,
  );
  bool _showPost = false;

  @override
  void initState() {
    super.initState();
    _pre.highlightVariables = false;
    _post.highlightVariables = false;
    _pre.addListener(_emit);
    _post.addListener(_emit);
  }

  void _emit() {
    if (_pre.text != widget.pre || _post.text != widget.post) {
      widget.onChanged(_pre.text, _post.text);
    }
  }

  @override
  void dispose() {
    _pre.dispose();
    _post.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: <ButtonSegment<bool>>[
              ButtonSegment<bool>(
                value: false,
                label: Text(context.t('script.pre')),
              ),
              ButtonSegment<bool>(
                value: true,
                label: Text(context.t('script.post')),
              ),
            ],
            selected: <bool>{_showPost},
            onSelectionChanged: (s) => setState(() => _showPost = s.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            context.t(_showPost ? 'script.postHint' : 'script.preHint'),
            style: context.secondary,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: CodeEditor(
              key: ValueKey<bool>(_showPost),
              controller: _showPost ? _post : _pre,
              language: CodeLanguage.text,
              hintText: _showPost
                  ? 'test("status is 200", response.status == 200);'
                  : 'request.headers.set("X-Time", str(now()));',
            ),
          ),
        ),
      ],
    );
  }
}
