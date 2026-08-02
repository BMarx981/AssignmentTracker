import 'package:flutter/material.dart';

import '../domain/priority.dart';
import '../models/api_models.dart';
import '../state/priority_providers.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import 'status_badges.dart';

class PriorityListItem extends StatelessWidget {
  final int index;
  final RankedItem ranked;
  final Map<String, LocalStatus> statusByKey;
  final VoidCallback? onTap;

  const PriorityListItem({
    super.key,
    required this.index,
    required this.ranked,
    required this.statusByKey,
    this.onTap,
  });

  Color _tierColor(AppColors c) {
    if (index < 3) return c.tierHigh;
    if (index < 6) return c.tierMedium;
    if (index < 10) return c.tierLow;
    return c.tierRest;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final it = ranked.item;
    final c = ranked.course;
    final ls = getLocalStatus(it, statusByKey);
    final dep = ls != null;
    final standing = c.policyHalfCredit && c.synergyAltHalfCreditPercent != null
        ? 'class ${pctText(c.synergyAltHalfCreditPercent)} (history rule)'
        : 'class ${pctText(c.synergyPercent ?? c.canvasAvgWithMissing)}';

    return Opacity(
      opacity: dep ? 0.7 : 1.0,
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            border:
                Border(left: BorderSide(color: _tierColor(colors), width: 4)),
            color: colors.card,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(6),
              bottomRight: Radius.circular(6),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: colors.textMuted),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      it.name,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        children: [
                          _sub(context, c.name),
                          _sub(context, '· due ${it.date ?? '?'}'),
                          _sub(context, '· $standing'),
                          ...statusBadgesFor(context, it, statusByKey),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    it.pointsPossible != null
                        ? '${_fmtNum(it.pointsPossible!)} pts'
                        : '—',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.textStrong),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sub(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
            fontSize: 12, color: AppColors.of(context).textMuted),
      );

  String _fmtNum(double n) {
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(1);
  }
}
