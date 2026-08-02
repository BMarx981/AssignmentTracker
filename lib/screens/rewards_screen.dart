// The cumulative side of the rewards system: where the points went, how far
// the current level is from the next one, the streak, the badge case, and a
// feed of what earned what.
//
// Everything here is a pure read of the ledger — nothing on this screen can
// award, clear, or spend points.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:assignment_tracker_app/domain/rewards.dart';
import 'package:assignment_tracker_app/router.dart';
import 'package:assignment_tracker_app/state/rewards_providers.dart';
import 'package:assignment_tracker_app/state/student_providers.dart';
import 'package:assignment_tracker_app/theme/app_theme.dart';

class RewardsScreen extends ConsumerWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rewards = ref.watch(currentRewardsProvider).value ?? RewardsView.empty;
    final ledger = rewards.ledger;
    final studentName = ref.watch(selectedStudentProvider).value?.name;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rewards'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.back('/'),
        ),
      ),
      body: ledger.isEmpty
          ? const _EmptyState()
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
              children: [
                _LevelCard(ledger: ledger, studentName: studentName),
                const SizedBox(height: 8),
                _CheckInStrip(rewards: rewards),
                const SizedBox(height: 10),
                _StatsRow(rewards: rewards),
                const SizedBox(height: 18),
                const _SectionLabel('Badges'),
                const SizedBox(height: 8),
                _BadgeGrid(rewards: rewards),
                const SizedBox(height: 18),
                const _SectionLabel('Recent'),
                const SizedBox(height: 8),
                for (final event in ledger.recent.take(25))
                  _ActivityRow(event: event),
              ],
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.of(context).textFaint,
        ),
      ),
    );
  }
}

/// The headline card: rank, total, and how far to the next rank.
class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.ledger, required this.studentName});

  final RewardLedger ledger;
  final String? studentName;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final level = ledger.level;
    final next = ledger.nextLevel;
    final fg = colors.reward.foreground;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: colors.reward.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(level.emoji, style: const TextStyle(fontSize: 34)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (studentName != null && studentName!.isNotEmpty)
                      Text(
                        studentName!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                          color: fg.withValues(alpha: 0.75),
                        ),
                      ),
                    Text(
                      level.name,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: fg,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${ledger.totalPoints}',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: fg,
                      height: 1,
                    ),
                  ),
                  Text(
                    'points',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: fg.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ledger.levelProgress,
              minHeight: 8,
              backgroundColor: fg.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(fg),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            next == null
                ? "Top rank. There's nothing above this."
                : '${ledger.pointsToNextLevel} more to ${next.emoji} ${next.name}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

/// The habit hook: today is already banked, so the only thing left to say is
/// what tomorrow is worth — and what breaking the run would cost. Framing it
/// as a standing offer is the point; a streak you can see the price of is one
/// you protect.
class _CheckInStrip extends StatelessWidget {
  const _CheckInStrip({required this.rewards});

  final RewardsView rewards;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final streak = rewards.streak;
    final tomorrow = nextVisitPoints(streak);
    final nextDay = DateTime.now().add(const Duration(days: 1));
    // "Will I lose my streak this weekend?" is the first thing a student
    // wonders, so the answer takes priority over the escalation pitch on the
    // days it actually matters.
    final restTomorrow = rewards.calendar.isRestDay(nextDay);
    // Once tomorrow already pays the maximum there is nothing left to climb
    // toward, so the honest thing to point at is what a missed day costs.
    final atCeiling = tomorrow >= maxVisitPoints;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colors.cardSubtle,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Text('👋', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  streak >= 2
                      ? "Day $streak. Come back tomorrow for +$tomorrow."
                      : 'Come back tomorrow for +$tomorrow.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.textStrong,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  restTomorrow
                      ? "It's the weekend — your run is safe either way, but "
                          'checking in still pays.'
                      : atCeiling
                          ? 'Miss a school day and the check-in drops back '
                              'to +3.'
                          : 'Check-ins are worth more the longer the run '
                              'goes.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Streak / turned-in / asked-a-teacher, the three counts worth surfacing.
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.rewards});

  final RewardsView rewards;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final ledger = rewards.ledger;
    final streak = rewards.streak;
    final best = rewards.bestStreak;
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            emoji: '🔥',
            value: '$streak',
            label: 'day streak',
            accent: colors.streak,
            footnote: best > streak
                ? 'best $best'
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatTile(
            emoji: '✅',
            value: '${ledger.countOf(RewardKind.turnedIn)}',
            label: 'turned in',
            accent: colors.success.foreground,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatTile(
            emoji: '👍',
            value: '${ledger.countOf(RewardKind.teacherEmail)}',
            label: 'teachers asked',
            accent: colors.actionChip.foreground,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.emoji,
    required this.value,
    required this.label,
    required this.accent,
    this.footnote,
  });

  final String emoji;
  final String value;
  final String label;
  final Color accent;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: accent,
              height: 1.1,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          if (footnote != null)
            Text(
              footnote!,
              style: TextStyle(fontSize: 10, color: colors.textFaint),
            ),
        ],
      ),
    );
  }
}

/// Locked badges stay visible with their progress showing — a badge case with
/// blanks in it is the part that makes the next one feel worth chasing.
class _BadgeGrid extends StatelessWidget {
  const _BadgeGrid({required this.rewards});

  final RewardsView rewards;

  @override
  Widget build(BuildContext context) {
    final badges = rewards.badges;
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 640 ? 4 : 3;
        return GridView.count(
          crossAxisCount: cols,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.95,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [for (final b in badges) _BadgeTile(badge: b)],
        );
      },
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge});

  final RewardBadge badge;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final earned = badge.earned;

    return Tooltip(
      message: badge.description,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: earned ? colors.reward.background : colors.cardSubtle,
          border: Border.all(
            color: earned
                ? colors.reward.foreground.withValues(alpha: 0.4)
                : colors.border,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Medallion(emoji: badge.emoji, earned: earned),
            const SizedBox(height: 6),
            Text(
              badge.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: earned
                    ? colors.reward.foreground
                    : colors.textSecondary,
              ),
            ),
            if (!earned && badge.target > 1) ...[
              const SizedBox(height: 4),
              Text(
                '${badge.progress.clamp(0, badge.target)} / ${badge.target}',
                style: TextStyle(fontSize: 10, color: colors.textFaint),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Locked badges keep their emoji but drain to grey, so the case reads as
/// "not yet" rather than "unknown".
class _Medallion extends StatelessWidget {
  const _Medallion({required this.emoji, required this.earned});

  final String emoji;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    final medal = Text(emoji, style: const TextStyle(fontSize: 26));
    if (earned) return medal;
    return Opacity(
      opacity: 0.35,
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix(_greyscale),
        child: medal,
      ),
    );
  }
}

/// Luminance-preserving desaturation, for locked badges.
const _greyscale = <double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
];

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.event});

  final RewardEvent event;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(event.kind.emoji, style: const TextStyle(fontSize: 17)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.label.isEmpty ? event.kind.verb : event.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textStrong,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${event.kind.verb} · ${_relative(event.at)}',
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            '+${event.points}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: colors.reward.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// "just now" / "3h ago" / "yesterday" / "12 days ago".
String _relative(DateTime utc) {
  final diff = DateTime.now().difference(utc.toLocal());
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 30) return '${diff.inDays} days ago';
  final months = (diff.inDays / 30).floor();
  return months <= 1 ? 'a month ago' : '$months months ago';
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🌱', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 16),
            const Text(
              'No points yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Plan something, turn something in, or email a teacher — '
              'every one of those earns points and they add up from there.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final kind in RewardKind.values)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: colors.reward.background,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${kind.emoji} ${kind.verb} +${kind.points}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.reward.foreground,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
