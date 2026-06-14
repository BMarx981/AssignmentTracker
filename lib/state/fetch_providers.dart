// Runs Canvas / Synergy fetches in-app, writes the resulting blob to
// LocalStore, and refreshes the data provider. Status is purely local
// ("idle" → "running" → "done" | "error") — there is no server job to poll.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_models.dart';
import 'api_providers.dart';
import 'data_providers.dart';

class FetchStatusNotifier extends Notifier<FetchStatus> {
  @override
  FetchStatus build() =>
      const FetchStatus(canvas: 'idle', synergy: 'idle');

  Future<void> triggerCanvas() async {
    if (state.canvas == 'running') return;
    state = FetchStatus(canvas: 'running', synergy: state.synergy);
    try {
      final client = await ref.read(canvasClientProvider.future);
      if (client == null) {
        throw StateError(
            'Canvas token not set. Add it in Settings → Credentials.');
      }
      final payload = await client.fetchAll();
      final store = await ref.read(localStoreProvider.future);
      await store.writeCanvasData(payload);
      state = FetchStatus(canvas: 'done', synergy: state.synergy);
      await ref.read(dataProvider.notifier).refresh();
    } catch (_) {
      state = FetchStatus(canvas: 'error', synergy: state.synergy);
      rethrow;
    }
  }

  Future<void> triggerSynergy() async {
    if (state.synergy == 'running') return;
    state = FetchStatus(canvas: state.canvas, synergy: 'running');
    try {
      final client = await ref.read(synergyClientProvider.future);
      if (client == null) {
        throw StateError(
            'Synergy username/password not set. Add them in Settings → Credentials.');
      }
      final payload = await client.fetchAll();
      final store = await ref.read(localStoreProvider.future);
      await store.writeSynergyData(payload);
      state = FetchStatus(canvas: state.canvas, synergy: 'done');
      await ref.read(dataProvider.notifier).refresh();
    } catch (_) {
      state = FetchStatus(canvas: state.canvas, synergy: 'error');
      rethrow;
    }
  }
}

final fetchStatusProvider =
    NotifierProvider<FetchStatusNotifier, FetchStatus>(
        FetchStatusNotifier.new);
