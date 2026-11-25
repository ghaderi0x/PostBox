import 'package:flutter/material.dart';

/// Semantic color tokens. Widgets read these through `context.colors`,
/// never raw colors.
@immutable
class PostBoxColors {
  const PostBoxColors({
    required this.surfaceBase,
    required this.surfaceRaised,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.onAccent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.methodGet,
    required this.methodPost,
    required this.methodPut,
    required this.methodPatch,
    required this.methodDelete,
    required this.synKey,
    required this.synString,
    required this.synNumber,
    required this.synLiteral,
    required this.synPunct,
    required this.synVariable,
    required this.synError,
  });

  final Color surfaceBase;
  final Color surfaceRaised;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color onAccent;
  final Color success;
  final Color warning;
  final Color danger;
  final Color methodGet;
  final Color methodPost;
  final Color methodPut;
  final Color methodPatch;
  final Color methodDelete;
  final Color synKey;
  final Color synString;
  final Color synNumber;
  final Color synLiteral;
  final Color synPunct;
  final Color synVariable;
  final Color synError;

  Color methodColor(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return methodGet;
      case 'POST':
        return methodPost;
      case 'PUT':
        return methodPut;
      case 'PATCH':
        return methodPatch;
      case 'DELETE':
        return methodDelete;
      default:
        return textSecondary;
    }
  }

  Color statusColor(int status) {
    if (status >= 200 && status < 300) return success;
    if (status >= 300 && status < 400) return methodPut;
    if (status >= 400 && status < 500) return warning;
    return danger;
  }
}

/// Theme extension carrying tokens and a few appearance metrics.
@immutable
class PostBoxTheme extends ThemeExtension<PostBoxTheme> {
  const PostBoxTheme({
    required this.colors,
    required this.codeFontSize,
    required this.reducedMotion,
  });

  final PostBoxColors colors;
  final double codeFontSize;
  final bool reducedMotion;

  @override
  PostBoxTheme copyWith({
    PostBoxColors? colors,
    double? codeFontSize,
    bool? reducedMotion,
  }) => PostBoxTheme(
    colors: colors ?? this.colors,
    codeFontSize: codeFontSize ?? this.codeFontSize,
    reducedMotion: reducedMotion ?? this.reducedMotion,
  );

  @override
  PostBoxTheme lerp(ThemeExtension<PostBoxTheme>? other, double t) =>
      other is PostBoxTheme && t >= 0.5 ? other : this;
}

extension PostBoxContext on BuildContext {
  PostBoxTheme get pb => Theme.of(this).extension<PostBoxTheme>()!;
  PostBoxColors get colors => pb.colors;
}

/// The app header is the surface colour with a clear touch of the accent, so
/// the top bar (and the Windows title bar, which copies it) reads as "the app
/// colour" in every theme.
extension PostBoxHeaderColors on PostBoxColors {
  Color get header => Color.alphaBlend(accent.withAlpha(46), surfaceBase);
  Color get headerBorder => accent.withAlpha(110);
}
