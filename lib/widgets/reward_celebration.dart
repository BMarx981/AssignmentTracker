// The celebration that fires when points land.
//
// [RewardHost] sits above the Navigator (installed from `MaterialApp.builder`)
// rather than inside any one screen, because the action that earns the points
// usually closes what you were looking at — the catch-up row's sheet pops
// itself the moment you answer. Hosting the toast above the router means the
// animation survives that, and every entry point gets it for free.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:assignment_tracker_app/domain/rewards.dart';
import 'package:assignment_tracker_app/state/rewards_providers.dart';
import 'package:assignment_tracker_app/theme/app_theme.dart';

class RewardHost extends ConsumerStatefulWidget {
  const RewardHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<RewardHost> createState() => _RewardHostState();
}

class _RewardHostState extends ConsumerState<RewardHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _plainDuration);

  static const _plainDuration = Duration(milliseconds: 2400);
  static const _milestoneDuration = Duration(milliseconds: 3600);

  RewardOutcome? _current;
  List<_Particle> _particles = const [];

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener(_onStatus);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final finished = _current;
    if (finished == null) return;
    setState(() => _current = null);
    ref.read(rewardFeedProvider.notifier).clear(finished);
  }

  void _show(RewardOutcome outcome) {
    // Milestones hold longer and get confetti; ordinary awards stay brief so
    // clearing three things in a row doesn't turn into three modal pauses.
    _controller.duration =
        outcome.isMilestone ? _milestoneDuration : _plainDuration;
    setState(() {
      _current = outcome;
      _particles = outcome.isMilestone ? _Particle.spray() : const [];
    });
    _controller.forward(from: 0);
    if (outcome.isMilestone) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.mediumImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<RewardOutcome?>(rewardFeedProvider, (_, next) {
      if (next != null) _show(next);
    });

    final outcome = _current;
    return Stack(
      children: [
        widget.child,
        if (outcome != null)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 12,
            right: 12,
            // Purely decorative — taps must reach whatever is underneath.
            child: IgnorePointer(
              child: _RewardToast(
                outcome: outcome,
                animation: _controller,
                particles: _particles,
              ),
            ),
          ),
      ],
    );
  }
}

/// The card itself: a spring in, a hold, and a fade out, all driven off one
/// controller so the confetti stays in step with the copy.
class _RewardToast extends StatelessWidget {
  const _RewardToast({
    required this.outcome,
    required this.animation,
    required this.particles,
  });

  final RewardOutcome outcome;
  final Animation<double> animation;
  final List<_Particle> particles;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final v = animation.value;
        final entry = _phase(v, 0, 0.18, Curves.easeOutBack);
        final exit = _phase(v, 0.86, 1, Curves.easeIn);
        // easeOutBack overshoots past 1, which is what gives the pop — clamp
        // only where the value has to stay legal (opacity).
        final opacity = (entry * (1 - exit)).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, -28 * (1 - entry)),
            child: Transform.scale(
              scale: 0.94 + 0.06 * entry,
              child: child,
            ),
          ),
        );
      },
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          if (particles.isNotEmpty)
            Positioned.fill(
              child: CustomPaint(
                painter: _ConfettiPainter(
                  particles: particles,
                  animation: animation,
                  colors: colors.confetti,
                ),
              ),
            ),
          _Card(outcome: outcome, colors: colors),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.outcome, required this.colors});

  final RewardOutcome outcome;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final badge = outcome.newBadges.isEmpty ? null : outcome.newBadges.first;
    final level = outcome.newLevel;

    return Material(
      color: colors.reward.background,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colors.reward.foreground.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              level?.emoji ?? badge?.emoji ?? outcome.event.kind.emoji,
              style: const TextStyle(fontSize: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    level != null
                        ? 'Level up — ${level.name}!'
                        : badge != null
                            ? 'Badge unlocked: ${badge.name}'
                            : outcome.headline,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: colors.reward.foreground,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _subtitle(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.reward.foreground.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colors.reward.foreground.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '+${outcome.event.points}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: colors.reward.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Second line: the streak when there is one to brag about, otherwise the
  /// running total. Never both — the card has one line of room.
  String _subtitle() {
    if (outcome.streak >= 2) {
      return '🔥 ${outcome.streak}-day streak · ${outcome.totalPoints} pts';
    }
    return '${outcome.totalPoints} points total';
  }
}

/// Remaps [v] onto [begin]..[end] and runs it through [curve]. Stands in for
/// a CurvedAnimation(Interval) so the toast doesn't allocate — and leak —
/// animation objects on every rebuild.
double _phase(double v, double begin, double end, Curve curve) =>
    curve.transform(((v - begin) / (end - begin)).clamp(0.0, 1.0));

// ---------- confetti ----------

class _Particle {
  const _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.spin,
    required this.colorIndex,
  });

  final double angle;
  final double speed;
  final double size;
  final double spin;
  final int colorIndex;

  /// A fan of particles thrown up and out from behind the card.
  static List<_Particle> spray({int count = 26}) {
    final rng = math.Random();
    return List.generate(count, (i) {
      // Bias upward: a burst that only rains down reads as a failure state.
      final angle = -math.pi / 2 + (rng.nextDouble() - 0.5) * math.pi * 1.15;
      return _Particle(
        angle: angle,
        speed: 90 + rng.nextDouble() * 130,
        size: 4 + rng.nextDouble() * 5,
        spin: (rng.nextDouble() - 0.5) * 12,
        colorIndex: i,
      );
    });
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({
    required this.particles,
    required this.animation,
    required this.colors,
  }) : super(repaint: animation);

  final List<_Particle> particles;
  final Animation<double> animation;
  final List<Color> colors;

  /// Fraction of the whole sequence the burst occupies.
  static const _burstWindow = 0.55;

  @override
  void paint(Canvas canvas, Size size) {
    final t = (animation.value / _burstWindow).clamp(0.0, 1.0);
    if (t <= 0 || t >= 1) return;

    final origin = Offset(size.width / 2, size.height * 0.5);
    final fade = t < 0.7 ? 1.0 : 1 - (t - 0.7) / 0.3;
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      // Ballistic: constant velocity along the launch angle, gravity pulling
      // the vertical component back down over the life of the burst.
      final dx = math.cos(p.angle) * p.speed * t;
      final dy = math.sin(p.angle) * p.speed * t + 190 * t * t;
      final center = origin + Offset(dx, dy);

      paint.color =
          colors[p.colorIndex % colors.length].withValues(alpha: fade);

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(p.spin * t);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 1.6,
          ),
          const Radius.circular(1.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) =>
      old.particles != particles || old.colors != colors;
}
