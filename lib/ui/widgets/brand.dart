import 'package:flutter/material.dart';

import '../../core/design/typography.dart';

/// The PostBox logo (assets/branding/logo.png). Every place that shows the
/// logo uses this widget so replacing the artwork is a one-file change.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 32, this.semanticLabel = 'PostBox'});

  final double size;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    // The 256 px file is enough up to 128 logical pixels on normal screens.
    final asset = size > 96
        ? 'assets/branding/logo.png'
        : 'assets/branding/logo_256.png';
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      semanticLabel: semanticLabel,
      errorBuilder: (context, error, stack) => SizedBox(
        width: size,
        height: size,
        child: Icon(Icons.inbox_rounded, size: size * 0.7),
      ),
    );
  }
}

/// Logo followed by the app name, for headers.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.logoSize = 30, required this.name});

  final double logoSize;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        BrandLogo(size: logoSize),
        const SizedBox(width: 10),
        Text(
          name,
          style: context.pageTitle.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}
