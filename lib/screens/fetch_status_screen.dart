import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/fetch_error.dart';
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (anyRunning) ...[
            const _RunningBanner(),
            const SizedBox(height: 16),
          ],
          _SourceCard(
            name: 'Canvas',
            state: s.canvas,
            error: s.canvasError,
            running: canvasRunning,
            onRetry: () => ref
                .read(fetchStatusProvider.notifier)
                .triggerCanvas()
                .catchError((_) {}),
            onOpenSettings: () => context.go('/settings'),
          ),
          const SizedBox(height: 12),
          _SourceCard(
            name: 'Synergy',
            state: s.synergy,
            error: s.synergyError,
            running: synergyRunning,
            onRetry: () => ref
                .read(fetchStatusProvider.notifier)
                .triggerSynergy()
                .catchError((_) {}),
            onOpenSettings: () => context.go('/settings'),
          ),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.name,
    required this.state,
    required this.error,
    required this.running,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final String name;
  final String state;
  final FetchError? error;
  final bool running;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                _StatusChip(state: state, running: running),
                const Spacer(),
                if (state != 'running')
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Fetch'),
                  ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              _FriendlyError(error: error!, onOpenSettings: onOpenSettings),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.state, required this.running});

  final String state;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      'running' => ('Fetching…', const Color(0xFF1B3F88)),
      'done' => ('Up to date', const Color(0xFF065F46)),
      'error' => ('Failed', const Color(0xFF8A1A1A)),
      _ => ('Not fetched yet', const Color(0xFF666666)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (running) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 6),
          ],
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _FriendlyError extends StatefulWidget {
  const _FriendlyError({required this.error, required this.onOpenSettings});

  final FetchError error;
  final VoidCallback onOpenSettings;

  @override
  State<_FriendlyError> createState() => _FriendlyErrorState();
}

class _FriendlyErrorState extends State<_FriendlyError> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEECEC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF8A1A1A).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(e.icon, color: const Color(0xFF8A1A1A), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(e.headline,
                    style: const TextStyle(
                        color: Color(0xFF8A1A1A),
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.body,
                    style: const TextStyle(
                        color: Color(0xFF4A1818), fontSize: 14)),
                if (e.suggestions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...e.suggestions.map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ',
                                style: TextStyle(color: Color(0xFF4A1818))),
                            Expanded(
                                child: Text(s,
                                    style: const TextStyle(
                                        color: Color(0xFF4A1818),
                                        fontSize: 13))),
                          ],
                        ),
                      )),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (e.kind == FetchErrorKind.auth)
                      OutlinedButton.icon(
                        onPressed: widget.onOpenSettings,
                        icon: const Icon(Icons.settings_outlined, size: 16),
                        label: const Text('Open Settings'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF8A1A1A),
                          side: const BorderSide(color: Color(0xFF8A1A1A)),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    const Spacer(),
                    if (e.technicalDetails != null)
                      TextButton(
                        onPressed: () =>
                            setState(() => _showDetails = !_showDetails),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF8A1A1A),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: Text(_showDetails
                            ? 'Hide technical details'
                            : 'Show technical details'),
                      ),
                  ],
                ),
                if (_showDetails && e.technicalDetails != null) ...[
                  const SizedBox(height: 8),
                  _TechnicalDetails(text: e.technicalDetails!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TechnicalDetails extends StatelessWidget {
  const _TechnicalDetails({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1010),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: text)),
            icon: const Icon(Icons.copy_outlined,
                size: 14, color: Color(0xFFEFD9D9)),
            label: const Text('Copy',
                style: TextStyle(color: Color(0xFFEFD9D9))),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
            ),
          ),
          SelectableText(
            text,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Color(0xFFEFD9D9),
              height: 1.4,
            ),
          ),
        ],
      ),
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
