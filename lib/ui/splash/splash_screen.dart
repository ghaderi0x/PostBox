import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/design/theme.dart';
import '../widgets/brand.dart';

/// Colours of the splash screen. They are fixed (not theme dependent) so the
/// splash looks the same before the settings are loaded and matches the
/// native splash on Android (see `flutter_native_splash` in pubspec.yaml).
const Color kSplashBackground = Color(0xFF16130F);
const Color kSplashAccent = Color(0xFFFF8A3D);

/// Full-screen start screen: logo, name, version and a thin progress bar.
///
/// With [animate] the logo fades and scales in once. The same screen is used
/// twice during start-up (before and after the services are ready); the
/// second one passes `animate: false` so the logo does not blink.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.animate = true, this.tagline});

  final bool animate;

  /// Short line under the name; omitted when null.
  final String? tagline;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (!widget.animate || reduce) {
      _controller.value = 1;
    } else if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const light = Color(0xFFF3EEE9);
    const muted = Color(0xFFA89E94);
    return Scaffold(
      backgroundColor: kSplashBackground,
      body: Stack(
        children: <Widget>[
          // Soft glow behind the logo.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.15),
                  radius: 0.75,
                  colors: <Color>[
                    kSplashAccent.withValues(alpha: 0.16),
                    kSplashBackground,
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: AnimatedBuilder(
              animation: _fade,
              builder: (context, child) => Opacity(
                opacity: _fade.value,
                child: Transform.scale(
                  scale: 0.9 + 0.1 * _fade.value,
                  child: child,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: const Color(
                            0xFFF4503E,
                          ).withValues(alpha: 0.35),
                          blurRadius: 48,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const BrandLogo(size: 112),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    appName,
                    style: TextStyle(
                      fontFamily: kUiFont,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: light,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  if (widget.tagline != null) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      widget.tagline!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: kUiFont,
                        fontFamilyFallback: <String>[kPersianFont],
                        fontSize: 13,
                        color: muted,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: 120,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: const LinearProgressIndicator(
                        minHeight: 3,
                        color: kSplashAccent,
                        backgroundColor: Color(0xFF3A342D),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: Text(
                'v$appVersionLabel',
                style: TextStyle(
                  fontFamily: kUiFont,
                  fontSize: 12,
                  color: muted,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
