import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/app/app.dart';
import 'package:postbox/app/services.dart';
import 'package:postbox/core/design/theme.dart';
import 'package:postbox/features/settings/domain/app_settings.dart';
import 'package:postbox/l10n/strings.dart';
import 'package:postbox/ui/editor/code_editor.dart';
import 'package:postbox/ui/editor/code_editor_controller.dart';
import 'package:postbox/ui/editor/highlighter.dart';

Widget host(Widget child, {Locale locale = const Locale('en'), double width = 600, double height = 400}) {
  return MaterialApp(
    theme: buildTheme(
      brightness: Brightness.light,
      settings: const AppSettings(),
      persianUi: locale.languageCode == 'fa',
    ),
    locale: locale,
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: SizedBox(width: width, height: height, child: child)),
  );
}

void setSize(WidgetTester tester, double w, double h) {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('CodeEditor', () {
    testWidgets('shows a line and column for invalid JSON, and nothing for valid JSON', (tester) async {
      final c = CodeEditorController(text: '{"a":}');
      addTearDown(c.dispose);
      await tester.pumpWidget(host(CodeEditor(controller: c)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Line 1'), findsOneWidget);

      c.text = '{"a": 1}';
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Line 1'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('find bar counts matches', (tester) async {
      final c = CodeEditorController(text: 'aXa', language: CodeLanguage.text);
      addTearDown(c.dispose);
      await tester.pumpWidget(host(CodeEditor(controller: c, language: CodeLanguage.text)));
      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), 'a');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('1/2'), findsOneWidget);
      expect(c.matches.length, 2);
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pump();
      expect(find.text('2/2'), findsOneWidget);
      // Closing the bar clears the highlights.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(c.matches, isEmpty);
    });

    testWidgets('word wrap button reports the new value', (tester) async {
      final c = CodeEditorController(text: 'x');
      addTearDown(c.dispose);
      bool? wrap;
      await tester.pumpWidget(host(CodeEditor(controller: c, onWrapChanged: (v) => wrap = v)));
      await tester.tap(find.byIcon(Icons.wrap_text));
      await tester.pump();
      expect(wrap, isTrue);
    });

    testWidgets('read-only editors have no undo, redo or format buttons', (tester) async {
      final c = CodeEditorController(text: '{"a":1}');
      addTearDown(c.dispose);
      await tester.pumpWidget(host(CodeEditor(controller: c, readOnly: true)));
      expect(find.byIcon(Icons.undo), findsNothing);
      expect(find.byIcon(Icons.redo), findsNothing);
      expect(find.byIcon(Icons.format_align_left), findsNothing);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('Persian text in an RTL app lays out without errors', (tester) async {
      final c = CodeEditorController(text: 'سلام دنیا {"a": 1} hello', language: CodeLanguage.text);
      addTearDown(c.dispose);
      await tester.pumpWidget(host(CodeEditor(controller: c, language: CodeLanguage.text), locale: const Locale('fa')));
      await tester.pump(const Duration(milliseconds: 400));
      final ctx = tester.element(find.byType(CodeEditor));
      expect(Directionality.of(ctx), TextDirection.rtl);
      c.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('long lines and many lines do not overflow', (tester) async {
      final long = List<String>.filled(3, 'x' * 600).join('\n');
      final c = CodeEditorController(text: long, language: CodeLanguage.text);
      addTearDown(c.dispose);
      await tester.pumpWidget(host(CodeEditor(controller: c, language: CodeLanguage.text)));
      expect(tester.takeException(), isNull);

      final many = List<String>.generate(6000, (i) => 'line $i').join('\n');
      final c2 = CodeEditorController(text: many, language: CodeLanguage.text);
      addTearDown(c2.dispose);
      await tester.pumpWidget(host(CodeEditor(
        controller: c2,
        language: CodeLanguage.text,
        options: const EditorOptions(wordWrap: true),
      )));
      expect(tester.takeException(), isNull);
    });
  });

  group('App', () {
    testWidgets('desktop layout starts, creates a collection and opens settings', (tester) async {
      setSize(tester, 1280, 800);
      final services = AppServices.inMemory();
      await tester.pumpWidget(PostBoxApp(services: services));
      await tester.pumpAndSettle();
      expect(find.text('PostBox'), findsWidgets);
      expect(find.text('Send'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('New collection').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'My API');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('My API'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sending to a closed port shows a connection error', (tester) async {
      setSize(tester, 1280, 800);
      final services = AppServices.inMemory();
      await tester.pumpWidget(PostBoxApp(services: services));
      await tester.pumpAndSettle();

      final urlField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'https://api.example.com/v1/users',
      );
      await tester.enterText(urlField, 'http://127.0.0.1:1/');
      await tester.tap(find.text('Send').first);
      for (var i = 0; i < 30 && find.text('Could not connect').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Could not connect'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone layout has bottom navigation and switches pages', (tester) async {
      setSize(tester, 400, 800);
      final services = AppServices.inMemory();
      await tester.pumpWidget(PostBoxApp(services: services));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      await tester.tap(find.text('Response'));
      await tester.pumpAndSettle();
      expect(find.text('No response yet'), findsOneWidget);
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(find.text('No collections yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Persian UI is right-to-left and translated', (tester) async {
      setSize(tester, 1280, 800);
      final services = AppServices.inMemory();
      await services.settingsRepository.save(const AppSettings(language: AppLanguage.fa));
      await tester.pumpWidget(PostBoxApp(services: services));
      await tester.pumpAndSettle();
      expect(find.text('ارسال'), findsWidgets);
      final ctx = tester.element(find.byType(Scaffold).first);
      expect(Directionality.of(ctx), TextDirection.rtl);
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone layout in Persian with large text scale does not overflow', (tester) async {
      setSize(tester, 360, 740);
      final services = AppServices.inMemory();
      await services.settingsRepository.save(const AppSettings(language: AppLanguage.fa, fontScale: 1.4));
      await tester.pumpWidget(PostBoxApp(services: services));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('کتابخانه'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
