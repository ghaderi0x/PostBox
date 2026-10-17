import 'package:flutter/material.dart';

import 'core/design/theme.dart';
import 'core/design/tokens.dart';

void main() => runApp(const PostBoxApp());

class PostBoxApp extends StatelessWidget {
  const PostBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PostBox',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const _ShellPage(),
    );
  }
}

/// Temporary shell for phase P0/P2. The request workspace arrives in P3.
class _ShellPage extends StatelessWidget {
  const _ShellPage();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: Center(
        child: Text(
          'PostBox',
          style: TextStyle(
            color: c.accent,
            fontSize: 28,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
