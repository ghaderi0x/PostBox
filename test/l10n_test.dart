import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/features/testing/domain/assertions.dart';
import 'package:postbox/features/http/domain/http_engine.dart';
import 'package:postbox/features/settings/domain/app_settings.dart';
import 'package:postbox/l10n/strings.dart';
import 'package:postbox/l10n/strings_en.dart';
import 'package:postbox/l10n/strings_fa.dart';

void main() {
  final placeholder = RegExp(r'\{\d\}');

  test('English and Persian define exactly the same keys', () {
    expect(faStrings.keys.toSet().difference(enStrings.keys.toSet()), isEmpty);
    expect(enStrings.keys.toSet().difference(faStrings.keys.toSet()), isEmpty);
  });

  test('no empty strings and placeholders match', () {
    for (final k in enStrings.keys) {
      expect(enStrings[k]!.trim(), isNotEmpty, reason: 'en $k');
      expect(faStrings[k]!.trim(), isNotEmpty, reason: 'fa $k');
      final en = placeholder.allMatches(enStrings[k]!).map((m) => m[0]).toSet();
      final fa = placeholder.allMatches(faStrings[k]!).map((m) => m[0]).toSet();
      expect(fa, en, reason: 'placeholders differ for $k');
    }
  });

  test('Persian values contain Persian script (except brand/format names)', () {
    final persian = RegExp(r'[\u0600-\u06FF]');
    var withScript = 0;
    for (final v in faStrings.values) {
      if (persian.hasMatch(v)) withScript++;
    }
    expect(withScript / faStrings.length, greaterThan(0.9));
  });

  test('dynamic key families are complete', () {
    for (final k in AssertionKind.values) {
      expect(enStrings.containsKey('tests.kind.${k.name}'), isTrue, reason: k.name);
    }
    for (final k in HttpFailureKind.values) {
      expect(enStrings.containsKey('err.http.${k.name}'), isTrue, reason: k.name);
    }
    for (final k in ThemePreset.values) {
      expect(enStrings.containsKey('preset.${k.name}'), isTrue, reason: k.name);
    }
    for (final k in RedirectPolicy.values) {
      expect(enStrings.containsKey('redirect.${k.name}'), isTrue, reason: k.name);
    }
    for (final code in const <String>[
      'empty_url', 'invalid_url', 'unsupported_scheme', 'missing_host', 'unresolved_url',
      'request_too_large', 'graphql_vars_invalid', 'file_missing',
    ]) {
      expect(enStrings.containsKey('err.build.$code'), isTrue, reason: code);
    }
    for (final code in const <String>[
      'missing_client_id', 'invalid_auth_url', 'invalid_token_url', 'insecure_endpoint', 'browser_failed',
      'timeout', 'provider_error', 'state_mismatch', 'missing_code', 'token_request_failed', 'token_error',
      'token_response_invalid', 'no_refresh_token',
    ]) {
      expect(enStrings.containsKey('oauth.err.$code'), isTrue, reason: code);
    }
  });

  test('AppStrings substitutes arguments and falls back to the key', () {
    final fa = AppStrings(const Locale('fa'));
    expect(fa.t('runner.summary', <String>['1', '2', '3']), contains('1'));
    expect(AppStrings(const Locale('en')).t('no.such.key'), 'no.such.key');
    expect(AppStrings(const Locale('de')).t('common.save'), 'Save');
  });
}
