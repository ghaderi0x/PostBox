import 'package:flutter/material.dart';

import 'strings_en.dart';
import 'strings_fa.dart';

/// Hand-written localization (no code generation). Keys are dotted strings;
/// `{0}`, `{1}` are positional arguments. A test checks that English and
/// Persian define exactly the same keys.
class AppStrings {
  AppStrings(this.locale);

  final Locale locale;

  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('fa')];
  static const LocalizationsDelegate<AppStrings> delegate = _AppStringsDelegate();

  static Map<String, String> tableFor(String languageCode) =>
      languageCode == 'fa' ? faStrings : enStrings;

  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings) ?? AppStrings(const Locale('en'));

  String t(String key, [List<String>? args]) {
    final table = tableFor(locale.languageCode);
    var s = table[key] ?? enStrings[key] ?? key;
    if (args != null) {
      for (var i = 0; i < args.length; i++) {
        s = s.replaceAll('{$i}', args[i]);
      }
    }
    return s;
  }
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'fa';

  @override
  Future<AppStrings> load(Locale locale) async => AppStrings(locale);

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}

extension L10nContext on BuildContext {
  String t(String key, [List<String>? args]) => AppStrings.of(this).t(key, args);
}
