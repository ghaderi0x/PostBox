import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_info.dart';
import '../../core/design/shapes.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/platform/platform_info.dart';
import '../../core/util/format.dart';
import '../../features/settings/application/settings_cubit.dart';
import '../../features/update/update_service.dart';
import '../../l10n/strings.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/soft.dart';

/// The start-up check runs once per app launch, not once per workspace.
bool _checkedThisLaunch = false;

/// Silent check used when the app opens. Shows the update card only when a
/// newer release exists and the user has not skipped it.
Future<void> checkForUpdatesOnStartup(
  BuildContext context, {
  UpdateService? service,
}) async {
  if (_checkedThisLaunch) return;
  _checkedThisLaunch = true;
  final settings = context.read<SettingsCubit>();
  if (!settings.state.checkUpdates) return;
  final svc = service ?? UpdateService();
  final release = await svc.fetchLatest();
  if (release == null || !context.mounted) return;
  if (!UpdateService.isNewer(release.version, appVersion)) return;
  if (settings.state.skippedVersion == release.version) return;
  await showUpdateDialog(context, release, service: svc);
}

/// Manual check from Settings. Always reports the result.
Future<void> checkForUpdatesManually(
  BuildContext context, {
  UpdateService? service,
}) async {
  final svc = service ?? UpdateService();
  final release = await svc.fetchLatest();
  if (!context.mounted) return;
  if (release == null) {
    await showToast(context, context.t('update.checkFailed'));
    return;
  }
  if (!UpdateService.isNewer(release.version, appVersion)) {
    await showToast(context, context.t('update.upToDate'));
    return;
  }
  await showUpdateDialog(context, release, service: svc);
}

Future<void> showUpdateDialog(
  BuildContext context,
  ReleaseInfo release, {
  UpdateService? service,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: context.t('update.title'),
    barrierColor: Colors.black54,
    transitionDuration: context.pb.reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) => Center(
      child: _UpdateCard(release: release, service: service ?? UpdateService()),
    ),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween<double>(
          begin: 0.96,
          end: 1,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );
}

enum _Phase { idle, downloading, launching, failed }

class _UpdateCard extends StatefulWidget {
  const _UpdateCard({required this.release, required this.service});

  final ReleaseInfo release;
  final UpdateService service;

  @override
  State<_UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<_UpdateCard> {
  _Phase _phase = _Phase.idle;
  double _progress = 0;
  String _error = '';
  bool _cancelled = false;

  late final UpdatePlatform _platform = UpdateService.detectPlatform();
  late final ReleaseAsset? _asset = UpdateService.pickInstaller(
    widget.release,
    _platform,
  );

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on Object {
      // Nothing useful to show: the browser or store app is missing.
    }
  }

  /// Opens the store app when it is installed, else its web page.
  Future<void> _openStore(String scheme, String webUrl) async {
    try {
      final ok = await launchUrl(
        Uri.parse('$scheme://details?id=$androidPackageId'),
        mode: LaunchMode.externalApplication,
      );
      if (ok) return;
    } on Object {
      // Not installed: use the web page below.
    }
    await _open(webUrl);
  }

  Future<void> _install() async {
    final asset = _asset;
    if (asset == null) {
      await _open(widget.release.pageUrl);
      return;
    }
    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
    });
    try {
      final file = await widget.service.download(
        widget.release,
        asset,
        onProgress: (v) {
          if (mounted) setState(() => _progress = v);
        },
        isCancelled: () => _cancelled,
      );
      if (!mounted) return;
      setState(() => _phase = _Phase.launching);
      await widget.service.launchInstaller(file, _platform);
      // Windows must close the app so the installer can replace its files.
      if (_platform == UpdatePlatform.windows) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        exit(0);
      }
      if (mounted) Navigator.of(context).pop();
    } on UpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = e.message == 'checksum'
            ? context.t('update.checksum')
            : context.t('update.failed');
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = context.t('update.failed');
      });
    }
  }

  Future<void> _skip() async {
    await context.read<SettingsCubit>().update(
      (s) => s.copyWith(skippedVersion: widget.release.version),
    );
    if (mounted) Navigator.of(context).pop();
  }

  /// Release notes as plain text: Markdown marks are stripped, nothing is
  /// rendered as HTML.
  String get _notes {
    final raw = widget.release.notes;
    if (raw.isEmpty) return context.t('update.noNotes');
    final cleaned = raw
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAllMapped(RegExp(r'^#{1,6}\s*', multiLine: true), (_) => '')
        .replaceAll('**', '')
        .replaceAll('`', '')
        .replaceAllMapped(RegExp(r'^\s*[-*]\s+', multiLine: true), (_) => '• ');
    return cleaned.length > 1200 ? '${cleaned.substring(0, 1200)}…' : cleaned;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fmt = Fmt(
      persianDigits: context.watch<SettingsCubit>().state.persianDigits,
    );
    final busy = _phase == _Phase.downloading || _phase == _Phase.launching;
    final isAndroid = isAndroidPlatform;
    final asset = _asset;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Material(
          color: c.surfaceRaised,
          elevation: 12,
          borderRadius: BorderRadius.circular(Radii.xl),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      c.accent.withAlpha(70),
                      c.accent.withAlpha(10),
                    ],
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    const BrandLogo(size: 56),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            context.t('update.title'),
                            style: context.pageTitle.copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                _chip(context, 'v$appVersionLabel', false),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  child: Icon(
                                    Icons.arrow_forward,
                                    size: 14,
                                    color: c.textSecondary,
                                  ),
                                ),
                                _chip(
                                  context,
                                  'v${widget.release.version}',
                                  true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      context.t('update.whatsNew'),
                      style: context.sectionHeading,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 170),
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: c.surfaceBase,
                        borderRadius: BorderRadius.circular(Radii.md),
                        border: Border.all(color: c.border),
                      ),
                      child: Scrollbar(
                        child: SingleChildScrollView(
                          child: Text(
                            _notes,
                            style: context.secondary.copyWith(
                              height: 1.5,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (asset != null && asset.size > 0 && !isAndroid)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          fmt.bytes(asset.size),
                          style: context.secondary,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                child: _actions(context, busy, isAndroid),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String text, bool strong) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: strong ? c.accent : c.border.withAlpha(120),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        text,
        style: context.mono.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: strong ? c.onAccent : c.textSecondary,
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, bool busy, bool isAndroid) {
    final c = context.colors;
    if (busy) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: _phase == _Phase.launching ? null : _progress,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _phase == _Phase.launching
                ? context.t('update.installing')
                : context.t('update.downloading', <String>[
                    Fmt(
                      persianDigits: context
                          .read<SettingsCubit>()
                          .state
                          .persianDigits,
                    ).integer((_progress * 100).round()),
                  ]),
            textAlign: TextAlign.center,
            style: context.secondary,
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_phase == _Phase.failed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              _error,
              textAlign: TextAlign.center,
              style: context.errorText,
            ),
          ),
        if (isAndroid) ...<Widget>[
          Text(
            context.t('update.storeHint'),
            textAlign: TextAlign.center,
            style: context.secondary,
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: GradientButton(
                  label: context.t('update.myket'),
                  icon: Icons.storefront_outlined,
                  onPressed: () => _openStore('myket', myketUrl),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GradientButton(
                  label: context.t('update.bazaar'),
                  icon: Icons.shopping_bag_outlined,
                  onPressed: () => _openStore('bazaar', bazaarUrl),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => _open(widget.release.pageUrl),
            child: Text(context.t('update.openPage')),
          ),
        ] else
          GradientButton(
            label: _phase == _Phase.failed
                ? context.t('update.retry')
                : (_asset == null
                      ? context.t('update.openPage')
                      : context.t('update.now')),
            icon: _asset == null ? Icons.open_in_new : Icons.system_update_alt,
            onPressed: _install,
          ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            TextButton(
              onPressed: _skip,
              child: Text(
                context.t('update.skip'),
                style: TextStyle(color: c.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.t('update.later')),
            ),
          ],
        ),
      ],
    );
  }
}
