import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/services.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/util/redact.dart';
import '../../features/http/domain/cookie_jar.dart';
import '../../features/settings/application/settings_cubit.dart';
import '../../l10n/strings.dart';
import '../widgets/common.dart';

/// Cookie manager: shows the cookies PostBox stored from responses, lets the
/// user delete one or all of them and switch the cookie jar off.
class CookiesPage extends StatefulWidget {
  const CookiesPage({super.key});

  @override
  State<CookiesPage> createState() => _CookiesPageState();
}

class _CookiesPageState extends State<CookiesPage> {
  final Set<String> _revealed = <String>{};

  CookieJar get _jar => context.read<AppServices>().cookieJar;

  Future<void> _clearAll() async {
    final ok = await confirmDestructive(
      context,
      title: context.t('cookies.clearAll'),
      message: context.t('cookies.clearConfirm'),
      confirmLabel: context.t('common.delete'),
    );
    if (!ok) return;
    _jar.clear();
    if (mounted) setState(() {});
  }

  String _expiry(StoredCookie c) {
    final e = c.expires;
    if (e == null) return context.t('cookies.session');
    final l = e.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final settings = context.watch<SettingsCubit>().state;
    final all = _jar.all();
    final byDomain = <String, List<StoredCookie>>{};
    for (final cookie in all) {
      byDomain.putIfAbsent(cookie.domain, () => <StoredCookie>[]).add(cookie);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('cookies.title')),
        actions: <Widget>[
          IconButton(
            tooltip: context.t('cookies.clearAll'),
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: all.isEmpty ? null : _clearAll,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.t('cookies.useJar')),
            subtitle: Text(
              context.t('cookies.useJarHint'),
              style: context.secondary,
            ),
            value: settings.useCookieJar,
            onChanged: (v) => context.read<SettingsCubit>().update(
              (s) => s.copyWith(useCookieJar: v),
            ),
          ),
          const SizedBox(height: 8),
          if (all.isEmpty)
            EmptyState(
              icon: Icons.cookie_outlined,
              title: context.t('cookies.empty'),
              message: context.t('cookies.emptyHint'),
            )
          else
            for (final e in byDomain.entries)
              ExpansionTile(
                initiallyExpanded: byDomain.length <= 3,
                tilePadding: EdgeInsets.zero,
                title: Text(
                  e.key,
                  style: context.body.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  context.t('cookies.count', <String>['${e.value.length}']),
                  style: context.secondary,
                ),
                children: <Widget>[
                  for (final cookie in e.value)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(cookie.name, style: context.mono),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            _revealed.contains(cookie.key)
                                ? cookie.value
                                : Redactor.mask,
                            style: context.mono.copyWith(
                              fontSize: 12,
                              color: c.textSecondary,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            <String>[
                              cookie.path,
                              _expiry(cookie),
                              if (cookie.secure) 'Secure',
                              if (cookie.httpOnly) 'HttpOnly',
                              if (cookie.hostOnly)
                                context.t('cookies.hostOnly'),
                              if (cookie.sameSite.isNotEmpty)
                                'SameSite=${cookie.sameSite}',
                            ].join('  ·  '),
                            style: context.secondary,
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            tooltip: _revealed.contains(cookie.key)
                                ? context.t('cookies.hide')
                                : context.t('cookies.show'),
                            icon: Icon(
                              _revealed.contains(cookie.key)
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 18,
                            ),
                            onPressed: () => setState(() {
                              if (!_revealed.remove(cookie.key)) {
                                _revealed.add(cookie.key);
                              }
                            }),
                          ),
                          IconButton(
                            tooltip: context.t('common.delete'),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () {
                              _jar.delete(cookie);
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
        ],
      ),
    );
  }
}
