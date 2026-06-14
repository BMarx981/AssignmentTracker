// Polls /api/fetch/status every 2s while a Canvas or Synergy job is running,
// and idles otherwise. Triggers from the UI flip the poll back on.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_models.dart';
import 'api_providers.dart';
import 'data_providers.dart';

class FetchStatusNotifier extends AsyncNotifier<FetchStatus> {
  Timer? _timer;

  @override
  Future<FetchStatus> build() async {
    final client = await ref.watch(apiClientProvider.future);
    ref.onDispose(() => _timer?.cancel());
    return client.fetchStatus();
  }

  bool _isRunning(FetchStatus s) =>
      s.canvas == 'running' || s.synergy == 'running';

  Future<void> _poll() async {
    try {
      final client = await ref.read(apiClientProvider.future);
      final next = await client.fetchStatus();
      final cur = state.value;
      state = AsyncData(next);
      if (cur != null && _isRunning(cur) && !_isRunning(next)) {
        // A job just finished — pull fresh data.
        await ref.read(dataProvider.notifier).refresh();
      }
      if (!_isRunning(next)) {
        _timer?.cancel();
        _timer = null;
      }
    } catch (_) {
      // Swallow transient errors; the user can hit refresh.
    }
  }

  void _ensurePolling() {
    _timer ??= Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  Future<void> triggerCanvas() async {
    final client = await ref.read(apiClientProvider.future);
    await client.triggerCanvasFetch();
    _ensurePolling();
    await _poll();
  }

  Future<void> triggerSynergy() async {
    final client = await ref.read(apiClientProvider.future);
    await client.triggerSynergyFetch();
    _ensurePolling();
    await _poll();
  }
}

final fetchStatusProvider =
    AsyncNotifierProvider<FetchStatusNotifier, FetchStatus>(
        FetchStatusNotifier.new);
