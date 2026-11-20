import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../features/settings/application/settings_cubit.dart';
import 'code_editor.dart';
import 'code_editor_controller.dart';
import 'highlighter.dart';

/// [CodeEditor] configured from the user's editor settings. The wrap toggle
/// in the toolbar writes back to settings.
class SettingsCodeEditor extends StatelessWidget {
  const SettingsCodeEditor({
    super.key,
    required this.controller,
    this.language = CodeLanguage.json,
    this.readOnly = false,
    this.hintText,
    this.minHeight = 120,
  });

  final CodeEditorController controller;
  final CodeLanguage language;
  final bool readOnly;
  final String? hintText;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsCubit>().state;
    return CodeEditor(
      controller: controller,
      language: language,
      readOnly: readOnly,
      hintText: hintText,
      minHeight: minHeight,
      options: EditorOptions(
        wordWrap: s.editorWordWrap,
        lineNumbers: s.editorLineNumbers,
        tabSize: s.editorTabSize,
        autoClose: s.editorAutoClose,
        highlightVariables: s.editorHighlightVariables,
        reducedMotion: s.reducedMotion,
      ),
      onWrapChanged: (v) => context.read<SettingsCubit>().update(
        (x) => x.copyWith(editorWordWrap: v),
      ),
    );
  }
}
