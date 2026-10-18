# Custom editor

One widget (`ui/editor/code_editor.dart`) serves request bodies, GraphQL query/variables, large text in the inspector (read-only) and the key/value fields (through the controller only).

## Supported

- Syntax highlighting: JSON, XML/HTML, plain text; `{{variables}}` highlighted in every mode (can be turned off in Settings)
- Line numbers (also correct with word wrap), word wrap toggle (persisted)
- Auto-indent on Enter, expanding `{}` and `[]` on Enter, Tab / Shift+Tab indent and outdent (2 or 4 spaces)
- Bracket matching highlight; auto-close and step-over for `{ [ ( "` in JSON
- Find and replace with regex (`$1`..`$9` in replacements), case toggle, match count, next/previous, Ctrl+F
- Go to line (Ctrl+G)
- Undo/redo (Flutter's `UndoHistoryController`)
- JSON validation with line and column, wavy underline at the error and a clickable message; variables do not make JSON invalid
- JSON format and minify
- Direction: JSON is always LTR; plain text follows the first strong character, so Persian text is right-to-left with proper caret movement from the platform text engine

## Not supported

- **Code folding.** Not implemented.
- **Virtualized editing.** The editable view lays out the whole text. Highlighting stops above 300,000 characters. For read-only large responses the inspector switches to `LinesView`, a virtualized line viewer without highlighting. The line-number gutter is hidden above 5,000 lines; wrapped line measurement stops above 3,000 lines.
- Multiple cursors, column selection, minimap, snippets, code completion.
- XML/HTML pretty-printing and folding.
- Highlighting is paused while an IME composition is active, so very short flicker is expected.
- Pretty-printing JSON uses Dart's number formatting (`1e2` becomes `100.0`).

## Honest status

Logic is unit-tested (`test/ui/editor_logic_test.dart`) and a few widget tests exist, but typing, selection and caret behaviour with real keyboards and mixed Persian/English text still need manual testing.
