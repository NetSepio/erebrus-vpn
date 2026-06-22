import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/premium_widgets.dart';

/// First-launch onboarding — the "agentic internet" story across 4 steps,
/// ending at login. Ships the `immersive` variant from the design handoff:
/// a floating, breathing network-mesh graphic over a warm radial backdrop.
///
/// [onDone] is called when the user finishes (last step → "Get started") or
/// taps SKIP; the caller persists the "onboarding seen" flag and routes to login.
class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingStep {
  const _OnboardingStep({required this.tag, required this.title, this.body, this.bullets});
  final String tag;
  final String title;
  final String? body;
  final List<String>? bullets;
}

const List<_OnboardingStep> _kSteps = [
  _OnboardingStep(
    tag: '01 / WELCOME',
    title: 'A private internet for everything you own',
    body:
        'Erebrus builds a secure private network for your devices, apps, files, AI models and team — private by design, simple to join.',
  ),
  _OnboardingStep(
    tag: '02 / THE AGENTIC INTERNET',
    title: 'Where your apps, devices and AI find each other',
    body:
        'Not just browsing websites. Your services securely discover one another, talk, and take action for you — inside a network you control.',
  ),
  _OnboardingStep(
    tag: '03 / HOW IT WORKS',
    title: 'Connect once. Access everything.',
    bullets: [
      'Connect once',
      'Discover trusted services',
      'Access private apps',
      'Use sovereign AI',
      'Protect everything with AI security',
    ],
  ),
  _OnboardingStep(
    tag: '04 / GET STARTED',
    title: 'Own your network. Protect your world.',
    body:
        'Join a node, discover services, or run your own in minutes. Sovereign infrastructure for the AI age.',
  ),
];

class _OnboardingViewState extends State<OnboardingView> with TickerProviderStateMixin {
  int _step = 0;

  late final AnimationController _float =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat(reverse: true);
  late final AnimationController _breathe =
      AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat(reverse: true);

  bool get _isLast => _step == _kSteps.length - 1;

  @override
  void dispose() {
    _float.dispose();
    _breathe.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      widget.onDone();
    } else {
      setState(() => _step++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _kSteps[_step];
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.84),
            radius: 1.15,
            colors: [Color(0xFF1C1208), AppColors.bg],
            stops: [0.0, 0.55],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // top bar
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 18, 28, 18),
                child: Row(
                  children: [
                    const BrandLockup(),
                    const Spacer(),
                    if (!_isLast)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onDone,
                        child: Text('SKIP',
                            style: mono(size: 12, weight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 12 * 0.1)),
                      ),
                  ],
                ),
              ),
              // mesh graphic
              Expanded(
                child: Center(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_float, _breathe]),
                    builder: (context, child) {
                      final dy = -7 * math.sin(_float.value * math.pi);
                      final scale = 1 + 0.06 * (0.5 - 0.5 * math.cos(_breathe.value * math.pi));
                      return Transform.translate(
                        offset: Offset(0, dy),
                        child: Transform.scale(scale: scale, child: child),
                      );
                    },
                    child: SizedBox(
                      width: 380,
                      height: 380,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          _RingCircle(size: 380, color: AppColors.accent.withValues(alpha: 0.04)),
                          _RingCircle(size: 300, color: AppColors.accent.withValues(alpha: 0.07)),
                          CustomPaint(size: const Size(260, 260), painter: _MeshPainter()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // text block
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 30),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  switchInCurve: Curves.easeOut,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Column(
                    key: ValueKey(_step),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(step.tag,
                          style: mono(size: 12, weight: FontWeight.w600, color: AppColors.accent, letterSpacing: 12 * 0.18)),
                      const SizedBox(height: 16),
                      Text(
                        step.title,
                        style: grotesk(size: 31, weight: FontWeight.w600, letterSpacing: -0.62, height: 1.12),
                      ),
                      const SizedBox(height: 14),
                      if (step.body != null)
                        Text(step.body!, style: grotesk(size: 15.5, weight: FontWeight.w400, color: AppColors.textSecondary, height: 1.55))
                      else if (step.bullets != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final b in step.bullets!)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 11),
                                child: _Bullet(label: b),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              // footer: dots + cta
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                child: Row(
                  children: [
                    Row(
                      children: [
                        for (var i = 0; i < _kSteps.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 7),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              height: 6,
                              width: i == _step ? 22 : 6,
                              decoration: BoxDecoration(
                                color: i == _step ? AppColors.accent : Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    PrimaryButton(
                      label: _isLast ? 'Get started' : 'Continue',
                      trailingIcon: Icons.arrow_forward,
                      onPressed: _next,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(Icons.check, size: 14, color: AppColors.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: grotesk(size: 15.5, weight: FontWeight.w400, color: const Color(0xFFD8D7D2))),
        ),
      ],
    );
  }
}

/// A faint concentric ring behind the mesh.
class _RingCircle extends StatelessWidget {
  const _RingCircle({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1),
      ),
    );
  }
}

/// The 260×260 network mesh: a central orange node with a soft glow halo, six
/// evenly-spaced ring nodes connected by thin orange lines, and a faint outer
/// circle.
class _MeshPainter extends CustomPainter {
  static const _accent = AppColors.accent;
  static const int _n = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);
    const r = 92.0;

    final nodes = List.generate(_n, (i) {
      final a = (math.pi * 2 * i / _n) - math.pi / 2;
      return Offset(cx + r * math.cos(a), cy + r * math.sin(a));
    });

    // faint outer circle (r 92 @ 0.16)
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _accent.withValues(alpha: 0.16),
    );

    // connecting lines center → nodes
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _accent.withValues(alpha: 0.35);
    for (final node in nodes) {
      canvas.drawLine(center, node, linePaint);
    }

    // glow halo (r 22 @ 0.16)
    canvas.drawCircle(center, 22, Paint()..color = _accent.withValues(alpha: 0.16));

    // outer ring nodes (r 6, dark fill, orange stroke 1.6)
    final nodeFill = Paint()..color = AppColors.bg;
    final nodeStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = _accent;
    for (final node in nodes) {
      canvas.drawCircle(node, 6, nodeFill);
      canvas.drawCircle(node, 6, nodeStroke);
    }

    // central node (r 11, solid orange)
    canvas.drawCircle(center, 11, Paint()..color = _accent);
  }

  @override
  bool shouldRepaint(covariant _MeshPainter oldDelegate) => false;
}
