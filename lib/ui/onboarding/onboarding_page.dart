import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/design/shapes.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../features/collections/application/collections_cubit.dart';
import '../../features/collections/application/sample_data.dart';
import '../../features/settings/application/settings_cubit.dart';
import '../../features/settings/domain/app_settings.dart';
import '../../l10n/strings.dart';
import '../widgets/common.dart';
import '../widgets/soft.dart';

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
      await _pc.animateToPage(page, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
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

  @override
  Widget build(BuildContext context) {
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
                    _StartPage(samples: _samples, onChanged: (v) => setState(() => _samples = v)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: last
                    ? GradientButton(
                        label: context.t('onb.getStarted'),
                        icon: Icons.arrow_forward,
                        onPressed: _busy ? null : () => _finish(withSamples: _samples),
                      )
                    : Row(
                        children: <Widget>[
                          for (var i = 0; i < _pages; i++)
                            AnimatedContainer(
                              duration: context.pb.reducedMotion ? Duration.zero : const Duration(milliseconds: 200),
                              margin: const EdgeInsetsDirectional.only(end: 6),
                              width: i == _page ? 24 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: i == _page ? c.accent : c.border,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          const Spacer(),
                          Semantics(
                            button: true,
                            label: context.t('onb.next'),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => _go(_page + 1),
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: c.accent,
                                  shape: BoxShape.circle,
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(color: c.accent.withAlpha(80), blurRadius: 18, offset: const Offset(0, 8)),
                                  ],
                                ),
                                child: Icon(
                                  Directionality.of(context) == TextDirection.rtl
                                      ? Icons.arrow_back
                                      : Icons.arrow_forward,
                                  color: c.onAccent,
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
        Text(title, style: context.pageTitle.copyWith(fontSize: 30, height: 1.2, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text(subtitle, style: context.body.copyWith(color: context.colors.textSecondary, height: 1.5)),
      ],
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  Widget _mini(BuildContext context, String method, String url, String status, {double angle = 0}) {
    final c = context.colors;
    return Transform.rotate(
      angle: angle,
      child: SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            MethodBadge(method, width: 50),
            Expanded(
              child: Text(url, style: context.mono, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr),
            ),
            Text(status, style: context.statusStyle(200).copyWith(color: c.success)),
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
        SizedBox(
          height: 210,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Transform.translate(offset: const Offset(-8, -64), child: _mini(context, 'GET', '/users/42', '200', angle: -0.05)),
              Transform.translate(offset: const Offset(10, 0), child: _mini(context, 'POST', '/orders', '201', angle: 0.04)),
              Transform.translate(offset: const Offset(-4, 64), child: _mini(context, 'PUT', '/items/7', '200', angle: -0.03)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _Headline(context.t('onb.welcome.title'), context.t('onb.welcome.subtitle')),
        const SizedBox(height: 24),
        Text(context.t('settings.languageLabel'), style: context.formLabel),
        const SizedBox(height: 8),
        SegmentedButton<AppLanguage>(
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          showSelectedIcon: false,
          segments: <ButtonSegment<AppLanguage>>[
            ButtonSegment<AppLanguage>(value: AppLanguage.system, label: Text(context.t('settings.system'))),
            const ButtonSegment<AppLanguage>(value: AppLanguage.en, label: Text('English')),
            const ButtonSegment<AppLanguage>(value: AppLanguage.fa, label: Text('فارسی')),
          ],
          selected: <AppLanguage>{s.language},
          onSelectionChanged: (v) => settings.update((x) => x.copyWith(language: v.first)),
        ),
        const SizedBox(height: 16),
        Text(context.t('settings.themeMode'), style: context.formLabel),
        const SizedBox(height: 8),
        SegmentedButton<AppThemeMode>(
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          showSelectedIcon: false,
          segments: <ButtonSegment<AppThemeMode>>[
            ButtonSegment<AppThemeMode>(value: AppThemeMode.system, label: Text(context.t('settings.system'))),
            ButtonSegment<AppThemeMode>(value: AppThemeMode.light, label: Text(context.t('settings.light'))),
            ButtonSegment<AppThemeMode>(value: AppThemeMode.dark, label: Text(context.t('settings.dark'))),
          ],
          selected: <AppThemeMode>{s.themeMode},
          onSelectionChanged: (v) => settings.update((x) => x.copyWith(themeMode: v.first)),
        ),
      ],
    );
  }
}

class _FeaturesPage extends StatelessWidget {
  const _FeaturesPage();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget feature(IconData icon, Color color, String title, String body) => Padding(
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
                      Text(title, style: context.body.copyWith(fontWeight: FontWeight.w700)),
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
        _Headline(context.t('onb.features.title'), context.t('onb.features.subtitle')),
        const SizedBox(height: 24),
        feature(Icons.folder_copy_outlined, c.accent, context.t('onb.f1.title'), context.t('onb.f1.body')),
        feature(Icons.lock_outline, c.success, context.t('onb.f2.title'), context.t('onb.f2.body')),
        feature(Icons.import_export, c.methodPut, context.t('onb.f3.title'), context.t('onb.f3.body')),
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
        _Headline(context.t('onb.start.title'), context.t('onb.start.subtitle')),
        const SizedBox(height: 24),
        SoftCard(
          onTap: () => onChanged(!samples),
          padding: const EdgeInsets.all(16),
          color: samples ? c.accent.withAlpha(22) : null,
          child: Row(
            children: <Widget>[
              IconTile(icon: Icons.auto_awesome_outlined, color: c.accent, size: 46),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(context.t('onb.start.switch'), style: context.body.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(context.t('onb.start.help'), style: context.secondary.copyWith(height: 1.45)),
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
