import 'package:flutter/material.dart';

import 'theme.dart';
import 'tokens.dart';

/// Defined text roles. Use these instead of ad-hoc TextStyles.
extension PostBoxText on BuildContext {
  TextStyle get pageTitle => Theme.of(
    this,
  ).textTheme.titleLarge!.copyWith(fontSize: 18, fontWeight: FontWeight.w600);

  TextStyle get sectionHeading => Theme.of(this).textTheme.titleSmall!.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: colors.textSecondary,
  );

  TextStyle get body =>
      Theme.of(this).textTheme.bodyMedium!.copyWith(fontSize: 14);

  TextStyle get secondary => Theme.of(
    this,
  ).textTheme.bodySmall!.copyWith(fontSize: 12.5, color: colors.textSecondary);

  TextStyle get formLabel => Theme.of(this).textTheme.labelMedium!.copyWith(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: colors.textSecondary,
  );

  TextStyle get errorText =>
      body.copyWith(color: colors.danger, fontWeight: FontWeight.w500);

  TextStyle get mono => TextStyle(
    fontFamily: kMonoFont,
    fontFamilyFallback: kMonoFallback,
    fontSize: 13,
    height: 1.4,
    color: colors.textPrimary,
  );

  /// URLs share the code font.
  TextStyle get urlStyle => mono.copyWith(fontSize: 14);

  /// Editor text. Size comes from settings.
  TextStyle get codeStyle => mono.copyWith(fontSize: pb.codeFontSize);

  TextStyle get methodBadge => mono.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.3,
  );

  TextStyle statusStyle(int status) => mono.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: colors.statusColor(status),
  );

  TextStyle get timingStyle =>
      mono.copyWith(fontSize: 12, color: colors.textSecondary);
}
