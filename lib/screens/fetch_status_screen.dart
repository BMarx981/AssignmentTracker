import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/fetch_providers.dart';

class FetchStatusScreen extends ConsumerWidget {
  const FetchStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(fetchStatusProvider);
    final canvasRunning = s.canvas == 'running';
    final synergyRunning = s.synergy == 'running';
    final anyRunning = canvasRunning || synergyRunning;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fetch status'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/settings'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (anyRunning)
              const _RunningBanner()
            else
              const SizedBox.shrink(),
            const SizedBox(height: 16),
            _row('Canvas', s.canvas),
            const SizedBox(height: 8),
            _row('Synergy', s.synergy),
            const SizedBox(height: 24),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: canvasRunning
                      ? null
                      : () => ref
                          .read(fetchStatusProvider.notifier)
                          .triggerCanvas()
                          .catchError((_) {}),
                  icon: const Icon(Icons.download),
                  label: const Text('Fetch Canvas'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: synergyRunning
                      ? null
                      : () => ref
                          .read(fetchStatusProvider.notifier)
                          .triggerSynergy()
                          .catchError((_) {}),
                  icon: const Icon(Icons.download),
                  label: const Text('Fetch Synergy'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String name, String state) {
    Color color;
    switch (state) {
      case 'running':
        color = const Color(0xFF1B3F88);
        break;
      case 'done':
        color = const Color(0xFF065F46);
        break;
      case 'error':
        color = const Color(0xFF8A1A1A);
        break;
      default:
        color = const Color(0xFF666666);
    }
    return Row(
      children: [
        SizedBox(
            width: 100,
            child: Text(name,
                style: const TextStyle(fontWeight: FontWeight.w600))),
        if (state == 'running') ...[
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
        ],
        Text(state, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _RunningBanner extends StatelessWidget {
  const _RunningBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EEFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1B3F88).withValues(alpha: 0.2)),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Fetching… this can take 10–30 seconds.',
              style: TextStyle(
                color: Color(0xFF1B3F88),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
