import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_info.dart';
import '../../core/design/shapes.dart';
import '../../core/platform/platform_info.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../features/collections/application/collections_cubit.dart';
import '../../features/collections/application/sample_data.dart';
import '../../features/settings/application/settings_cubit.dart';
import '../../features/settings/domain/app_settings.dart';
import '../../l10n/strings.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/soft.dart';
import '../widgets/pressable.dart';

/// First-run welcome tour: three pages, skippable, shown once.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const int _pages = 3;
  final PageController _pc = PageController();
  int _page = 0;
  bool _samples = true;
  bool _busy = false;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<void> _go(int page) async {
    if (context.pb.reducedMotion) {
      _pc.jumpToPage(page);
    } else {
      await _pc.animateToPage(
        page,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _finish({required bool withSamples}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final settings = context.read<SettingsCubit>();
    final collections = context.read<CollectionsCubit>();
    final names = SampleNames(
      collection: context.t('sample.collection'),
      get: context.t('sample.get'),
      post: context.t('sample.post'),
      bearer: context.t('sample.bearer'),
      notFound: context.t('sample.notFound'),
      folder: context.t('sample.folder'),
      uuid: context.t('sample.uuid'),
      echo: context.t('sample.echo'),
    );
    if (withSamples) await createSampleCollection(collections, names);
    // Switching the flag swaps this page for the app.
    await settings.update((s) => s.copyWith(onboardingDone: true));
  }

  Future<void> _openAuthor() async {
    try {
      await launchUrl(
        Uri.parse(authorUrl),
        mode: LaunchMode.externalApplication,
      );
    } on Object {
      // No browser available: nothing to do.
    }
  }

  void _next() {
    if (_page == _pages - 1) {
      unawaited(_finish(withSamples: _samples));
    } else {
      unawaited(_go(_page + 1));
    }
  }

  void _back() {
    if (_page > 0) unawaited(_go(_page - 1));
  }

  /// Windows and Linux: a centred two-column window instead of a phone page.
  /// Left: the brand and the three steps. Right: the current page with
  /// Back / Next buttons. Arrow keys, Enter and Esc work.
  Widget _desktop(BuildContext context) {
    final c = context.colors;
    final last = _page == _pages - 1;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    const stepKeys = <String>['onb.step1', 'onb.step2', 'onb.step3'];
    const stepIcons = <IconData>[
      Icons.waving_hand_outlined,
      Icons.auto_awesome_outlined,
      Icons.rocket_launch_outlined,
    ];
    Widget step(int i) {
      final active = i == _page;
      final done = i < _page;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Pressable(
          borderRadius: BorderRadius.circular(Radii.sm),
          onTap: _busy ? null : () => _go(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: active ? c.accent.withAlpha(30) : null,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active || done ? c.accent : Colors.transparent,
                    border: Border.all(
                      color: active || done ? c.accent : c.border,
                    ),
                  ),
                  child: Icon(
                    done ? Icons.check : stepIcons[i],
                    size: 15,
                    color: active || done ? c.onAccent : c.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.t(stepKeys[i]),
                    style: context.body.copyWith(
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? c.accent : c.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final side = Container(
      width: 300,
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 20),
      decoration: BoxDecoration(
        color: c.surfaceBase,
        border: BorderDirectional(end: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const BrandLogo(size: 64),
          const SizedBox(height: 14),
          Text(
            appName,
            style: context.pageTitle.copyWith(
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.t('about.tagline'),
            style: context.secondary.copyWith(height: 1.45),
          ),
          const SizedBox(height: 28),
          for (var i = 0; i < _pages; i++) step(i),
          const Spacer(),
          Pressable(
            borderRadius: BorderRadius.circular(Radii.sm),
            onTap: _openAuthor,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(
                children: <Widget>[
                  Icon(Icons.code, size: 16, color: c.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.t('about.madeBy', <String>[authorName]),
                      style: context.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final pages = PageView(
      controller: _pc,
      onPageChanged: (i) => setState(() => _page = i),
      children: <Widget>[
        const _Centered(child: _WelcomePage()),
        const _Centered(child: _FeaturesPage()),
        _Centered(
          child: _StartPage(
            samples: _samples,
            onChanged: (v) => setState(() => _samples = v),
          ),
        ),
      ],
    );

    return Scaffold(
      body: AccentGlow(
        height: 360,
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            SingleActivator(
              rtl
                  ? LogicalKeyboardKey.arrowLeft
                  : LogicalKeyboardKey.arrowRight,
            ): _next,
            SingleActivator(
              rtl
                  ? LogicalKeyboardKey.arrowRight
                  : LogicalKeyboardKey.arrowLeft,
            ): _back,
            const SingleActivator(LogicalKeyboardKey.enter): _next,
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (!_busy) unawaited(_finish(withSamples: false));
            },
          },
          child: Focus(
            autofocus: true,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 1000,
                  maxHeight: 640,
                ),
                child: Container(
                  margin: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: c.surfaceRaised,
                    borderRadius: BorderRadius.circular(Radii.xl),
                    border: Border.all(color: c.border),
                    boxShadow: softShadow(context),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Row(
                    children: <Widget>[
                      side,
                      Expanded(
                        child: Column(
                          children: <Widget>[
                            Expanded(child: pages),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(28, 8, 28, 22),
                              child: Row(
                                children: <Widget>[
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _finish(withSamples: false),
                                    child: Text(context.t('onb.skip')),
                                  ),
                                  const Spacer(),
                                  if (_page > 0)
                                    Padding(
                                      padding: const EdgeInsetsDirectional.only(
                                        end: 10,
                                      ),
                                      child: OutlinedButton(
                                        onPressed: _busy ? null : _back,
                                        child: Text(context.t('onb.back')),
                                      ),
                                    ),
                                  SizedBox(
                                    width: 200,
                                    child: GradientButton(
                                      label: last
                                          ? context.t('onb.getStarted')
                                          : context.t('onb.next'),
                                      icon: rtl
                                          ? Icons.arrow_back
                                          : Icons.arrow_forward,
                                      onPressed: _busy ? null : _next,
                                    ),
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
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Two-column window on Windows/Linux; phone layout when the window is
    // narrow (and in the phone-sized widget tests).
    if (isDesktopPlatform && MediaQuery.of(context).size.width >= 760) {
      return _desktop(context);
    }
    final c = context.colors;
    final last = _page == _pages - 1;
    return Scaffold(
      body: AccentGlow(
        height: 360,
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: TextButton(
                    onPressed: _busy ? null : () => _finish(withSamples: false),
                    child: Text(context.t('onb.skip')),
                  ),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pc,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: <Widget>[
                    const _WelcomePage(),
                    const _FeaturesPage(),
                    _StartPage(
                      samples: _samples,
                      onChanged: (v) => setState(() => _samples = v),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: last
                    ? GradientButton(
                        label: context.t('onb.getStarted'),
                        icon: Icons.arrow_forward,
                        onPressed: _busy
                            ? null
                            : () => _finish(withSamples: _samples),
                      )
                    : Row(
                        children: <Widget>[
                          for (var i = 0; i < _pages; i++)
                            AnimatedContainer(
                              duration: context.pb.reducedMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 200),
                              margin: const EdgeInsetsDirectional.only(end: 6),
                              width: i == _page ? 24 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: i == _page ? c.accent : c.border,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          const Spacer(),
                          Tooltip(
                            message: context.t('onb.next'),
                            child: Semantics(
                              button: true,
                              label: context.t('onb.next'),
                              child: Pressable(
                                circle: true,
                                onTap: () => _go(_page + 1),
                                child: Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: c.accent,
                                    shape: BoxShape.circle,
                                    boxShadow: <BoxShadow>[
                                      BoxShadow(
                                        color: c.accent.withAlpha(80),
                                        blurRadius: 18,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Directionality.of(context) ==
                                            TextDirection.rtl
                                        ? Icons.arrow_back
                                        : Icons.arrow_forward,
                                    color: c.onAccent,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline(this.title, this.subtitle);
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: context.pageTitle.copyWith(
            fontSize: 30,
            height: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: context.body.copyWith(
            color: context.colors.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  Widget _mini(
    BuildContext context,
    String method,
    String url,
    String status, {
    double angle = 0,
  }) {
    final c = context.colors;
    return Transform.rotate(
      angle: angle,
      child: SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            MethodBadge(method, width: 50),
            Expanded(
              child: Text(
                url,
                style: context.mono,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
              ),
            ),
            Text(
              status,
              style: context.statusStyle(200).copyWith(color: c.success),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsCubit>();
    final s = settings.state;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      children: <Widget>[
        const Center(child: BrandLogo(size: 84)),
        const SizedBox(height: 14),
        SizedBox(
          height: 190,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Transform.translate(
                offset: const Offset(-8, -64),
                child: _mini(context, 'GET', '/users/42', '200', angle: -0.05),
              ),
              Transform.translate(
                offset: const Offset(10, 0),
                child: _mini(context, 'POST', '/orders', '201', angle: 0.04),
              ),
              Transform.translate(
                offset: const Offset(-4, 64),
                child: _mini(context, 'PUT', '/items/7', '200', angle: -0.03),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _Headline(
          context.t('onb.welcome.title'),
          context.t('onb.welcome.subtitle'),
        ),
        const SizedBox(height: 24),
        Text(context.t('settings.languageLabel'), style: context.formLabel),
        const SizedBox(height: 8),
        SegmentedButton<AppLanguage>(
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          showSelectedIcon: false,
          segments: <ButtonSegment<AppLanguage>>[
            ButtonSegment<AppLanguage>(
              value: AppLanguage.system,
              label: Text(context.t('settings.system')),
            ),
            const ButtonSegment<AppLanguage>(
              value: AppLanguage.en,
              label: Text('English'),
            ),
            const ButtonSegment<AppLanguage>(
              value: AppLanguage.fa,
              label: Text('فارسی'),
            ),
          ],
          selected: <AppLanguage>{s.language},
          onSelectionChanged: (v) =>
              settings.update((x) => x.copyWith(language: v.first)),
        ),
        const SizedBox(height: 16),
        Text(context.t('settings.themeMode'), style: context.formLabel),
        const SizedBox(height: 8),
        _ThemeChoice(
          value: s.themeMode,
          onChanged: (v) => settings.update((x) => x.copyWith(themeMode: v)),
        ),
        const SizedBox(height: 6),
        Text(context.t('onb.themeHint'), style: context.secondary),
      ],
    );
  }
}

class _FeaturesPage extends StatelessWidget {
  const _FeaturesPage();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget feature(
      IconData icon,
      Color color,
      String title,
      String body,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SoftCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            IconTile(icon: icon, color: color, size: 46),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: context.body.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(body, style: context.secondary.copyWith(height: 1.45)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      children: <Widget>[
        _Headline(
          context.t('onb.features.title'),
          context.t('onb.features.subtitle'),
        ),
        const SizedBox(height: 24),
        feature(
          Icons.folder_copy_outlined,
          c.accent,
          context.t('onb.f1.title'),
          context.t('onb.f1.body'),
        ),
        feature(
          Icons.lock_outline,
          c.success,
          context.t('onb.f2.title'),
          context.t('onb.f2.body'),
        ),
        feature(
          Icons.import_export,
          c.methodPut,
          context.t('onb.f3.title'),
          context.t('onb.f3.body'),
        ),
      ],
    );
  }
}

class _StartPage extends StatelessWidget {
  const _StartPage({required this.samples, required this.onChanged});
  final bool samples;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      children: <Widget>[
        _Headline(
          context.t('onb.start.title'),
          context.t('onb.start.subtitle'),
        ),
        const SizedBox(height: 24),
        SoftCard(
          onTap: () => onChanged(!samples),
          padding: const EdgeInsets.all(16),
          color: samples ? c.accent.withAlpha(22) : null,
          child: Row(
            children: <Widget>[
              IconTile(
                icon: Icons.auto_awesome_outlined,
                color: c.accent,
                size: 46,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      context.t('onb.start.switch'),
                      style: context.body.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.t('onb.start.help'),
                      style: context.secondary.copyWith(height: 1.45),
                    ),
                  ],
                ),
              ),
              Switch(value: samples, onChanged: onChanged),
            ],
          ),
        ),
        const SizedBox(height: 16),
        InfoBanner(context.t('onb.start.note')),
      ],
    );
  }
}

/// Three preview tiles (dark, light, system) for choosing the theme.
class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({required this.value, required this.onChanged});

  final AppThemeMode value;
  final ValueChanged<AppThemeMode> onChanged;

  static const Color _darkBg = Color(0xFF16130F);
  static const Color _darkBar = Color(0xFF211D18);
  static const Color _darkLine = Color(0xFF3A342D);
  static const Color _lightBg = Color(0xFFFAF7F3);
  static const Color _lightBar = Color(0xFFFFFFFF);
  static const Color _lightLine = Color(0xFFE3DCD3);
  static const Color _accent = Color(0xFFFF8A3D);

  Widget _mock(Color bg, Color bar, Color line) => Container(
    color: bg,
    padding: const EdgeInsets.all(8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(height: 8, color: bar),
        const SizedBox(height: 6),
        Container(height: 5, width: 40, color: line),
        const SizedBox(height: 4),
        Container(height: 5, width: 56, color: line),
        const Spacer(),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Container(
            height: 8,
            width: 22,
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget tile(AppThemeMode mode, String labelKey, Widget preview) {
      final selected = value == mode;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          label: context.t(labelKey),
          child: Pressable(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onChanged(mode),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? c.accent : c.border,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 72,
                      width: double.infinity,
                      child: preview,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      if (selected)
                        Icon(Icons.check_circle, size: 14, color: c.accent),
                      if (selected) const SizedBox(width: 4),
                      Text(
                        context.t(labelKey),
                        style: context.secondary.copyWith(
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected ? c.accent : c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: <Widget>[
        tile(
          AppThemeMode.dark,
          'settings.dark',
          _mock(_darkBg, _darkBar, _darkLine),
        ),
        tile(
          AppThemeMode.light,
          'settings.light',
          _mock(_lightBg, _lightBar, _lightLine),
        ),
        tile(
          AppThemeMode.system,
          'settings.system',
          Row(
            children: <Widget>[
              Expanded(child: _mock(_darkBg, _darkBar, _darkLine)),
              Expanded(child: _mock(_lightBg, _lightBar, _lightLine)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Keeps a page at a comfortable reading width inside the desktop window.
class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
      child: Padding(padding: const EdgeInsets.only(top: 20), child: child),
    ),
  );
}
