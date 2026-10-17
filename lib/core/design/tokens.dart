import 'package:flutter/material.dart';

/// Semantic color tokens. Widgets read these, never raw colors.
@immutable
class PostBoxColors extends ThemeExtension<PostBoxColors> {
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

  static const PostBoxColors orangeLight = PostBoxColors(
    surfaceBase: Color(0xFFFAF8F6),
    surfaceRaised: Color(0xFFFFFFFF),
    border: Color(0xFFE6E0DA),
    textPrimary: Color(0xFF1F1B17),
    textSecondary: Color(0xFF6B625A),
    accent: Color(0xFFD9560B),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF1B7F4B),
    warning: Color(0xFF9A6700),
    danger: Color(0xFFC62828),
    methodGet: Color(0xFF1B7F4B),
    methodPost: Color(0xFFB45309),
    methodPut: Color(0xFF1D5FBF),
    methodPatch: Color(0xFF6D3FC4),
    methodDelete: Color(0xFFC62828),
  );

  static const PostBoxColors orangeDark = PostBoxColors(
    surfaceBase: Color(0xFF16130F),
    surfaceRaised: Color(0xFF211D18),
    border: Color(0xFF3A342D),
    textPrimary: Color(0xFFF3EEE9),
    textSecondary: Color(0xFFA89E94),
    accent: Color(0xFFFF8A3D),
    onAccent: Color(0xFF1A0E05),
    success: Color(0xFF4CC38A),
    warning: Color(0xFFE3B341),
    danger: Color(0xFFFF6B6B),
    methodGet: Color(0xFF4CC38A),
    methodPost: Color(0xFFFFA94D),
    methodPut: Color(0xFF6EA8FE),
    methodPatch: Color(0xFFB794F6),
    methodDelete: Color(0xFFFF6B6B),
  );

  @override
  PostBoxColors copyWith({
    Color? surfaceBase,
    Color? surfaceRaised,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? accent,
    Color? onAccent,
    Color? success,
    Color? warning,
    Color? danger,
    Color? methodGet,
    Color? methodPost,
    Color? methodPut,
    Color? methodPatch,
    Color? methodDelete,
  }) {
    return PostBoxColors(
      surfaceBase: surfaceBase ?? this.surfaceBase,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      methodGet: methodGet ?? this.methodGet,
      methodPost: methodPost ?? this.methodPost,
      methodPut: methodPut ?? this.methodPut,
      methodPatch: methodPatch ?? this.methodPatch,
      methodDelete: methodDelete ?? this.methodDelete,
    );
  }

  @override
  PostBoxColors lerp(ThemeExtension<PostBoxColors>? other, double t) {
    if (other is! PostBoxColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return PostBoxColors(
      surfaceBase: l(surfaceBase, other.surfaceBase),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      border: l(border, other.border),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      methodGet: l(methodGet, other.methodGet),
      methodPost: l(methodPost, other.methodPost),
      methodPut: l(methodPut, other.methodPut),
      methodPatch: l(methodPatch, other.methodPatch),
      methodDelete: l(methodDelete, other.methodDelete),
    );
  }
}

extension PostBoxColorsContext on BuildContext {
  PostBoxColors get colors => Theme.of(this).extension<PostBoxColors>()!;
}
