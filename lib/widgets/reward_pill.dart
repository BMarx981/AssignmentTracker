// The always-visible entry point to the rewards system: a compact points +
// streak chip that taps through to the rewards screen.
//
// Lives in the dashboard's summary block rather than the app bar — the app bar
// already carries five actions, and a score belongs next to "here's how you're
// doing", not in a row of tools.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:assignment_tracker_app/state/rewards_providers.dart';
import 'package:assignment_tracker_app/theme/app_theme.dart';

class RewardPill extends ConsumerWidget {
  const RewardPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final rewards = ref.watch(currentRewardsProvider).value ?? RewardsView.empty;
    final ledger = rewards.ledger;
    final streak = rewards.streak;
    final fg = colors.reward.foreground;

    return InkWell(
      onTap: () => context.push('/rewards'),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: colors.reward.background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: fg.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ledger.level.emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              '${ledger.totalPoints}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
            // A 1-day streak is just "you did a thing today" — not worth the
            // pixels. It shows up once it's actually a streak.
            if (streak >= 2) ...[
              const SizedBox(width: 8),
              Container(
                width: 1,
                height: 12,
                color: fg.withValues(alpha: 0.25),
              ),
              const SizedBox(width: 8),
              Text('🔥', style: TextStyle(fontSize: 12, color: colors.streak)),
              const SizedBox(width: 3),
              Text(
                '$streak',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
