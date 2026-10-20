import 'dart:math';

import 'package:flutter/material.dart';

import '../routes.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/shell.dart';

/// Opening animation: the gold ring monogram spins in over bridal maroon, a
/// light sweep crosses it, halos breathe, gold dust rises, the name lifts in,
/// then the app moves on to onboarding, sign-in or home.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))..forward();
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

  @override
  void initState() {
    super.initState();
    _intro.addStatusListener((s) {
      if (s != AnimationStatus.completed || !mounted) return;
      final st = AuraStore.i;
      Navigator.of(context).pushReplacementNamed(!st.onboarded ? Routes.onboarding : !st.authed ? Routes.auth : Routes.main);
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  double _seg(double v, double a, double b, [Curve c = Curves.easeOutCubic]) => c.transform(((v - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return PhoneFrame(
      background: AppColors.maroonInk,
      child: AnimatedBuilder(
        animation: Listenable.merge([_intro, _loop]),
        builder: (context, _) {
          final t = _intro.value;
          final ring = _seg(t, 0, 0.4, Curves.easeOutBack);
          final shine = _seg(t, 0.3, 0.6, Curves.easeInOut);
          final name = _seg(t, 0.25, 0.5);
          final tag = _seg(t, 0.35, 0.6);
          final bar = _seg(t, 0.1, 0.95, Curves.easeInOut);
          return Container(
            decoration: const BoxDecoration(gradient: AppGradients.splash),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Rising gold dust.
                for (var i = 0; i < 18; i++) _Spark(i: i, v: _loop.value),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 240,
                      height: 240,
                      child: Stack(alignment: Alignment.center, children: [
                        for (final (delay, size) in const [(0.0, 190.0), (0.3, 230.0)])
                          Builder(builder: (_) {
                            final p = (_loop.value + delay) % 1;
                            return Opacity(
                              opacity: (0.45 * (1 - p)) * ring,
                              child: Container(
                                width: size * (0.85 + 0.25 * p),
                                height: size * (0.85 + 0.25 * p),
                                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.gold, width: 1)),
                              ),
                            );
                          }),
                        Transform.rotate(
                          angle: (1 - ring) * -pi / 2,
                          child: Transform.scale(
                            scale: 0.4 + 0.6 * ring,
                            child: Opacity(
                              opacity: ring.clamp(0, 1),
                              child: Container(
                                width: 132,
                                height: 132,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.55)),
                                  boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 50, offset: Offset(0, 20), spreadRadius: -10)],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Stack(fit: StackFit.expand, children: [
                                  ColoredBox(color: AppColors.maroonInk),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Image.asset('assets/images/aura-mark.png', fit: BoxFit.contain),
                                  ),
                                  // Light sweep.
                                  FractionalTranslation(
                                    translation: Offset(-1.4 + 2.8 * shine, 0),
                                    child: Transform.rotate(
                                      angle: -0.35,
                                      child: Container(
                                        width: 60,
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(colors: [Color(0x00FFF0C8), Color(0x99FFF0C8), Color(0x00FFF0C8)]),
                                        ),
                                      ),
                                    ),
                                  ),
                                ]),
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 18),
                    Opacity(
                      opacity: name,
                      child: Transform.translate(
                        offset: Offset(0, 16 * (1 - name)),
                        child: RichText(
                          text: TextSpan(style: AppText.display(size: 38, weight: FontWeight.w500, color: Colors.white), children: [
                            const TextSpan(text: 'Aura '),
                            TextSpan(text: 'by HS', style: AppText.display(size: 38, weight: FontWeight.w500, color: AppColors.gold)),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Opacity(
                      opacity: tag,
                      child: Text('BRIDAL MAKE-UP · SALON · PHOTOGRAPHY', style: AppText.eyebrow(size: 10, color: AppColors.goldLight)),
                    ),
                  ],
                ),
                Positioned(
                  bottom: 64,
                  child: Container(
                    width: 130,
                    height: 2,
                    decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(2)),
                    alignment: Alignment.centerLeft,
                    child: Container(width: 130 * bar, height: 2, decoration: BoxDecoration(gradient: AppGradients.gold, borderRadius: BorderRadius.circular(2))),
                  ),
                ),
                Positioned(
                  bottom: 32,
                  child: Opacity(opacity: tag * 0.6, child: Text('Enhance your natural beauty', style: AppText.sans(size: 11.5, color: Colors.white))),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Spark extends StatelessWidget {
  const _Spark({required this.i, required this.v});
  final int i;
  final double v;
  @override
  Widget build(BuildContext context) {
    final p = (v + i * 0.137) % 1;
    final x = ((i * 37) % 100) / 100;
    final y = 0.45 + ((i * 53) % 50) / 100;
    return Positioned.fill(
      child: Align(
        alignment: Alignment(x * 2 - 1, (y - p * 0.25) * 2 - 1),
        child: Opacity(
          opacity: sin(p * pi).clamp(0, 1) * 0.9,
          child: Container(width: 3 + (i % 3).toDouble(), height: 3 + (i % 3).toDouble(), decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle)),
        ),
      ),
    );
  }
}
