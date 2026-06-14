import 'package:flutter/material.dart';

import '../domain/priority.dart';
import '../models/api_models.dart';
import '../state/priority_providers.dart';
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

  Color get _tierColor {
    if (index < 3) return const Color(0xFFB71C1C);
    if (index < 6) return const Color(0xFFC77700);
    if (index < 10) return const Color(0xFF2D6CDF);
    return const Color(0xFF999999);
  }

  @override
  Widget build(BuildContext context) {
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
            border: Border(left: BorderSide(color: _tierColor, width: 4)),
            color: Colors.white,
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
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF555555)),
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
                          _sub(c.name),
                          _sub('· due ${it.date ?? '?'}'),
                          _sub('· $standing'),
                          ...statusBadgesFor(it, statusByKey),
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
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sub(String text) => Text(
        text,
        style: const TextStyle(fontSize: 12, color: Color(0xFF555555)),
      );

  String _fmtNum(double n) {
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(1);
  }
}
