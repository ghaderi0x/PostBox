import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../features/auth/oauth_service.dart';
import '../../features/requests/domain/request_models.dart';
import '../../l10n/strings.dart';
import '../widgets/common.dart';

class AuthEditor extends StatefulWidget {
  const AuthEditor({
    super.key,
    required this.auth,
    required this.onChanged,
    this.allowInherit = true,
    this.inheritLabelKey = 'auth.inherit',
    this.inheritHint,
  });

  final AuthConfig auth;
  final ValueChanged<AuthConfig> onChanged;

  /// Offers the "inherit" choice (request level: use the folder or collection
  /// auth; folder and collection level: not set here, ask the parent).
  final bool allowInherit;
  final String inheritLabelKey;

  /// Explains where an inherited auth comes from.
  final String? inheritHint;

  @override
  State<AuthEditor> createState() => _AuthEditorState();
}

class _AuthEditorState extends State<AuthEditor> {
  final Map<String, TextEditingController> _c =
      <String, TextEditingController>{};
  final Set<String> _revealed = <String>{};
  bool _busy = false;
  String? _error;

  TextEditingController _ctl(String key, String value) =>
      _c.putIfAbsent(key, () => TextEditingController(text: value));

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _text(
    String key,
    String label,
    String value,
    AuthConfig Function(String) apply, {
    bool secret = false,
    String? hint,
  }) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _ctl(key, value),
        obscureText: secret && !_revealed.contains(key),
        enableSuggestions: !secret,
        autocorrect: false,
        style: context.mono,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixIcon: secret
              ? IconButton(
                  tooltip: context.t('auth.reveal'),
                  icon: Icon(
                    _revealed.contains(key)
                        ? Icons.visibility_off
                        : Icons.visibility,
                    size: 18,
                    color: c.textSecondary,
                  ),
                  onPressed: () => setState(() {
                    if (!_revealed.remove(key)) _revealed.add(key);
                  }),
                )
              : null,
        ),
        onChanged: (v) => widget.onChanged(apply(v)),
      ),
    );
  }

  String _oauthError(String code, String detail) {
    final key = 'oauth.err.$code';
    final s = context.t(key);
    return s == key
        ? '${context.t('oauth.err.generic')} ($code)'
        : (detail.isEmpty ? s : '$s: $detail');
  }

  Future<void> _authorize() async {
    final svc = context.read<OAuthService>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = await svc.authorize(widget.auth);
      widget.onChanged(
        widget.auth.copyWith(
          accessToken: t.accessToken,
          refreshToken: t.refreshToken ?? '',
          expiresAtMs: t.expiresAtMs,
        ),
      );
    } on OAuthException catch (e) {
      setState(() => _error = _oauthError(e.code, e.detail));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    final svc = context.read<OAuthService>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = await svc.refresh(widget.auth);
      widget.onChanged(
        widget.auth.copyWith(
          accessToken: t.accessToken,
          refreshToken: t.refreshToken ?? '',
          expiresAtMs: t.expiresAtMs,
        ),
      );
    } on OAuthException catch (e) {
      setState(() => _error = _oauthError(e.code, e.detail));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.auth;
    final c = context.colors;
    const typeLabels = <AuthType, String>{
      AuthType.none: 'auth.none',
      AuthType.basic: 'auth.basic',
      AuthType.bearer: 'auth.bearer',
      AuthType.apiKey: 'auth.apiKey',
      AuthType.oauth2: 'auth.oauth2',
    };
    final labels = <AuthType, String>{
      ...typeLabels,
      AuthType.inherit: widget.inheritLabelKey,
    };

    final fields = <Widget>[];
    switch (a.type) {
      case AuthType.none:
        fields.add(Text(context.t('auth.noneHint'), style: context.secondary));
      case AuthType.inherit:
        fields.add(
          Text(
            widget.inheritHint ?? context.t('auth.inheritHint'),
            style: context.secondary,
          ),
        );
      case AuthType.basic:
        fields.add(
          _text(
            'user',
            context.t('auth.username'),
            a.username,
            (v) => a.copyWith(username: v),
          ),
        );
        fields.add(
          _text(
            'pass',
            context.t('auth.password'),
            a.password,
            (v) => a.copyWith(password: v),
            secret: true,
          ),
        );
      case AuthType.bearer:
        fields.add(
          _text(
            'token',
            context.t('auth.token'),
            a.token,
            (v) => a.copyWith(token: v),
            secret: true,
          ),
        );
      case AuthType.apiKey:
        fields.add(
          _text(
            'keyName',
            context.t('auth.keyName'),
            a.apiKeyName,
            (v) => a.copyWith(apiKeyName: v),
          ),
        );
        fields.add(
          _text(
            'keyValue',
            context.t('auth.keyValue'),
            a.apiKeyValue,
            (v) => a.copyWith(apiKeyValue: v),
            secret: true,
          ),
        );
        fields.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SegmentedButton<bool>(
              segments: <ButtonSegment<bool>>[
                ButtonSegment<bool>(
                  value: true,
                  label: Text(context.t('auth.inHeader')),
                ),
                ButtonSegment<bool>(
                  value: false,
                  label: Text(context.t('auth.inQuery')),
                ),
              ],
              selected: <bool>{a.apiKeyInHeader},
              onSelectionChanged: (s) =>
                  widget.onChanged(a.copyWith(apiKeyInHeader: s.first)),
            ),
          ),
        );
      case AuthType.oauth2:
        fields.add(InfoBanner(context.t('oauth.info')));
        fields.add(const SizedBox(height: 10));
        fields.add(
          _text(
            'authUrl',
            context.t('oauth.authUrl'),
            a.authUrl,
            (v) => a.copyWith(authUrl: v),
            hint: 'https://…/authorize',
          ),
        );
        fields.add(
          _text(
            'tokenUrl',
            context.t('oauth.tokenUrl'),
            a.tokenUrl,
            (v) => a.copyWith(tokenUrl: v),
            hint: 'https://…/token',
          ),
        );
        fields.add(
          _text(
            'clientId',
            context.t('oauth.clientId'),
            a.clientId,
            (v) => a.copyWith(clientId: v),
          ),
        );
        fields.add(
          _text(
            'clientSecret',
            context.t('oauth.clientSecret'),
            a.clientSecret,
            (v) => a.copyWith(clientSecret: v),
            secret: true,
          ),
        );
        fields.add(
          _text(
            'scope',
            context.t('oauth.scope'),
            a.scope,
            (v) => a.copyWith(scope: v),
          ),
        );
        final has = a.accessToken.isNotEmpty;
        String status;
        if (!has) {
          status = context.t('oauth.noToken');
        } else if (a.expiresAtMs > 0) {
          final mins =
              ((a.expiresAtMs - DateTime.now().millisecondsSinceEpoch) / 60000)
                  .round();
          status = mins <= 0
              ? context.t('oauth.expired')
              : context.t('oauth.expiresIn', <String>['$mins']);
        } else {
          status = context.t('oauth.tokenPresent');
        }
        fields.add(
          Row(
            children: <Widget>[
              Icon(
                has ? Icons.verified_user_outlined : Icons.lock_outline,
                size: 18,
                color: has ? c.success : c.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(status, style: context.body)),
            ],
          ),
        );
        fields.add(const SizedBox(height: 10));
        fields.add(
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.icon(
                onPressed: _busy ? null : _authorize,
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login, size: 18),
                label: Text(context.t('oauth.getToken')),
              ),
              OutlinedButton(
                onPressed: _busy || a.refreshToken.isEmpty ? null : _refresh,
                child: Text(context.t('oauth.refresh')),
              ),
              OutlinedButton(
                onPressed: has
                    ? () => widget.onChanged(
                        a.copyWith(
                          accessToken: '',
                          refreshToken: '',
                          expiresAtMs: 0,
                        ),
                      )
                    : null,
                child: Text(context.t('oauth.clear')),
              ),
            ],
          ),
        );
        if (_error != null) {
          fields.add(const SizedBox(height: 10));
          fields.add(ErrorBanner(message: _error!));
        }
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        DropdownButtonFormField<AuthType>(
          initialValue: a.type,
          decoration: InputDecoration(labelText: context.t('auth.type')),
          items: <DropdownMenuItem<AuthType>>[
            for (final t in AuthType.values)
              if (t != AuthType.inherit || widget.allowInherit)
                DropdownMenuItem<AuthType>(
                  value: t,
                  child: Text(context.t(labels[t]!)),
                ),
          ],
          onChanged: (t) {
            if (t != null) widget.onChanged(a.copyWith(type: t));
          },
        ),
        const SizedBox(height: 14),
        ...fields,
        if (a.type != AuthType.none && a.type != AuthType.oauth2) ...<Widget>[
          const SizedBox(height: 4),
          Text(context.t('auth.secretNote'), style: context.secondary),
        ],
      ],
    );
  }
}
