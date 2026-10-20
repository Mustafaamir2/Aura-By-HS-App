import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../routes.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/kit.dart';
import '../widgets/shell.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Slide {
  const _Slide(this.eyebrow, this.title, this.accent, this.body);
  final String eyebrow, title, accent, body;
}

const _slides = [
  _Slide('BRIDAL MAKE-UP', 'Enhance your', 'natural beauty', 'Signature HD and airbrush bridal looks, trials and draping — crafted for the most photographed day of your life.'),
  _Slide('SALON SERVICES', 'Book in', 'seconds', 'Hair, skin, nails and mehndi at every Aura branch. Pick your artist and a time that suits you — confirmed instantly.'),
  _Slide('PHOTOGRAPHY STUDIO', 'Your story,', 'beautifully told', 'Studio portraits and bridal packages for the whole wedding week. Pay securely with JazzCash, Easypaisa or card.'),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pc = PageController();
  int _i = 0;

  void _finish() {
    AuraStore.i.finishOnboarding();
    Navigator.of(context).pushReplacementNamed(Routes.auth);
  }

  @override
  Widget build(BuildContext context) {
    final s = _slides[_i];
    return PhoneFrame(
      background: AppColors.maroonInk,
      child: Stack(children: [
        PageView(
          controller: _pc,
          onPageChanged: (i) => setState(() => _i = i),
          children: const [_HeroVisual(), _ServicesVisual(), _StudioVisual()],
        ),
        // Readability gradient under the copy.
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.45, 0.72, 1],
                colors: [Color(0x33000000), Color(0x00000000), Color(0xE62B0709), Color(0xFF240607)],
              ),
            ),
            child: SizedBox.expand(),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Logo(size: 42),
                const Spacer(),
                Pressable(
                  onTap: _finish,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white24)),
                    child: Text('Skip', style: AppText.sans(size: 13, weight: FontWeight.w600, color: Colors.white)),
                  ),
                ),
              ]),
              const Spacer(),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 420),
                transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(a), child: c)),
                child: Column(
                  key: ValueKey(_i),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.eyebrow, style: AppText.eyebrow(size: 11)),
                    const SizedBox(height: 12),
                    Text(s.title, style: AppText.display(size: 34, weight: FontWeight.w500, color: Colors.white, height: 1.08)),
                    Text(s.accent, style: AppText.display(size: 34, weight: FontWeight.w500, color: AppColors.gold, height: 1.12, style: FontStyle.italic)),
                    const SizedBox(height: 14),
                    Text(s.body, style: AppText.sans(size: 14.5, color: Colors.white.withValues(alpha: 0.82), height: 1.5)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(children: [
                for (var k = 0; k < _slides.length; k++)
                  GestureDetector(
                    onTap: () => _pc.animateToPage(k, duration: const Duration(milliseconds: 400), curve: Curves.easeOut),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.only(right: 8),
                      width: k == _i ? 30 : 10,
                      height: 6,
                      decoration: BoxDecoration(color: k == _i ? AppColors.gold : Colors.white30, borderRadius: BorderRadius.circular(9)),
                    ),
                  ),
              ]),
              const SizedBox(height: 20),
              Btn(
                label: _i == _slides.length - 1 ? 'Get started' : 'Next',
                variant: BtnVariant.gold,
                onTap: () => _i == _slides.length - 1 ? _finish() : _pc.nextPage(duration: const Duration(milliseconds: 420), curve: Curves.easeOut),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Slide 1 — the bridal hero photo, full bleed (it is large enough to stay sharp).
class _HeroVisual extends StatelessWidget {
  const _HeroVisual();
  @override
  Widget build(BuildContext context) => const AuraImage('$img/bride-hero.jpg', alignment: Alignment(0, -0.45));
}

/// Slide 2 — a collage of framed service photos at their natural size, so
/// nothing is stretched past its resolution.
class _ServicesVisual extends StatelessWidget {
  const _ServicesVisual();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppGradients.splash),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        final card = w * 0.44;
        return Stack(children: [
          Positioned(top: c.maxHeight * 0.1, left: w * 0.06, child: _Polaroid('$img/hair.jpg', 'Hair styling', card, -0.07)),
          Positioned(top: c.maxHeight * 0.08, right: w * 0.05, child: _Polaroid('$img/facial.jpg', 'Skin & facial', card * 0.92, 0.06)),
          Positioned(top: c.maxHeight * 0.31, left: w * 0.12, child: _Polaroid('$img/nails.jpg', 'Nails', card * 0.88, 0.05)),
          Positioned(top: c.maxHeight * 0.29, right: w * 0.08, child: _Polaroid('$img/mehndi.jpg', 'Mehndi', card * 0.95, -0.05)),
        ]);
      }),
    );
  }
}

/// Slide 3 — the studio and bridal portraits as stacked prints.
class _StudioVisual extends StatelessWidget {
  const _StudioVisual();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppGradients.splash),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        return Stack(children: [
          Positioned(top: c.maxHeight * 0.1, left: w * 0.08, child: _Polaroid('$img/studio.jpg', 'The Aura studio', w * 0.6, -0.06)),
          Positioned(top: c.maxHeight * 0.2, right: w * 0.06, child: _Polaroid('$img/bride-hero.jpg', 'Bridal portraits', w * 0.42, 0.07, tall: true)),
          Positioned(top: c.maxHeight * 0.36, left: w * 0.14, child: _Polaroid('$img/bridal-makeup.jpg', 'Bridal make-up', w * 0.46, 0.04)),
        ]);
      }),
    );
  }
}

class _Polaroid extends StatelessWidget {
  const _Polaroid(this.path, this.caption, this.width, this.angle, {this.tall = false});
  final String path, caption;
  final double width, angle;
  final bool tall;
  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBF5),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 30, offset: Offset(0, 16), spreadRadius: -8)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AspectRatio(aspectRatio: tall ? 0.78 : 1.32, child: AuraImage(path, radius: 10, alignment: tall ? const Alignment(0, -0.4) : Alignment.center)),
          const SizedBox(height: 6),
          Text(caption, style: AppText.display(size: 12.5, weight: FontWeight.w500, color: AppColors.maroon, style: FontStyle.italic)),
        ]),
      ),
    );
  }
}
