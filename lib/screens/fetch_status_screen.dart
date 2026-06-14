import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/fetch_providers.dart';

class FetchStatusScreen extends ConsumerWidget {
  const FetchStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(fetchStatusProvider);
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
        child: statusAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Failed to load status: $e'),
          data: (s) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('Canvas', s.canvas),
              const SizedBox(height: 8),
              _row('Synergy', s.synergy),
              const SizedBox(height: 24),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: () => ref
                        .read(fetchStatusProvider.notifier)
                        .triggerCanvas(),
                    icon: const Icon(Icons.download),
                    label: const Text('Fetch Canvas'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => ref
                        .read(fetchStatusProvider.notifier)
                        .triggerSynergy(),
                    icon: const Icon(Icons.download),
                    label: const Text('Fetch Synergy'),
                  ),
                ],
              ),
            ],
          ),
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
