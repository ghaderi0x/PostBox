import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/services.dart';
import 'features/workspaces/workspace_registry.dart';
import 'ui/splash/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PostBoxRoot());
}

/// Owns the services of the active workspace. Switching workspaces builds new
/// services (a different database file) and rebuilds the app below it.
class PostBoxRoot extends StatefulWidget {
  const PostBoxRoot({super.key});

  @override
  State<PostBoxRoot> createState() => _PostBoxRootState();
}

class _PostBoxRootState extends State<PostBoxRoot> {
  AppServices? _services;
  WorkspaceManager? _manager;
  Object? _error;
  final Stopwatch _sinceStart = Stopwatch()..start();
  bool _firstOpen = true;

  @override
  void initState() {
    super.initState();
    _open(null);
  }

  Future<void> _open(String? workspaceId) async {
    try {
      final registry = _manager?.registry ?? await WorkspaceRegistry.load();
      if (workspaceId != null) await registry.setActive(workspaceId);
      final dir = _manager?.directory ?? await getApplicationSupportDirectory();
      await Directory(dir.path).create(recursive: true);
      final services = await AppServices.create(registry: registry);
      if (_firstOpen) {
        // Keep the splash visible long enough to be seen, not just flash.
        _firstOpen = false;
        final remaining = services.splashMinimum - _sinceStart.elapsed;
        if (remaining > Duration.zero) await Future<void>.delayed(remaining);
      }
      final old = _services;
      if (!mounted) {
        services.close();
        return;
      }
      setState(() {
        _manager = WorkspaceManager(
          registry: registry,
          directory: dir,
          switchTo: _open,
        );
        _services = services;
        _error = null;
      });
      // Close the old database only after the old widgets are gone.
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.close());
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _services?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) return StartupErrorApp(error: error);
    final services = _services;
    final manager = _manager;
    if (services == null || manager == null) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'PostBox',
        home: SplashScreen(),
      );
    }
    return PostBoxApp(
      key: ValueKey<String>(services.workspaceId),
      services: services,
      workspaces: manager,
    );
  }
}
