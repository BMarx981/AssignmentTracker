// Runs Canvas / Synergy fetches in-app, writes the resulting blob to
// LocalStore, and refreshes the data provider. Status is purely local
// ("idle" → "running" → "done" | "error") — there is no server job to poll.
// Failures are translated to friendly FetchError objects the UI can render
// without exposing stack traces by default.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/fetch_error.dart';
import 'api_providers.dart';
import 'data_providers.dart';

/// Local-only superset of the old wire `FetchStatus` — adds typed errors.
class FetchState {
  const FetchState({
    this.canvas = 'idle',
    this.synergy = 'idle',
    this.canvasError,
    this.synergyError,
  });

  final String canvas; // idle | running | done | error
  final String synergy;
  final FetchError? canvasError;
  final FetchError? synergyError;

  FetchState copyWith({
    String? canvas,
    String? synergy,
    Object? canvasError = _unset,
    Object? synergyError = _unset,
  }) {
    return FetchState(
      canvas: canvas ?? this.canvas,
      synergy: synergy ?? this.synergy,
      canvasError: canvasError == _unset
          ? this.canvasError
          : canvasError as FetchError?,
      synergyError: synergyError == _unset
          ? this.synergyError
          : synergyError as FetchError?,
    );
  }
}

const _unset = Object();

class FetchStatusNotifier extends Notifier<FetchState> {
  @override
  FetchState build() => const FetchState();

  Future<void> triggerCanvas() async {
    if (state.canvas == 'running') return;
    state = state.copyWith(canvas: 'running', canvasError: null);
    try {
      final client = await ref.read(canvasClientProvider.future);
      if (client == null) {
        throw _NotConfigured(
            'Canvas token not set. Add it in Settings → Credentials.');
      }
      final payload = await client.fetchAll();
      final store = await ref.read(localStoreProvider.future);
      await store.writeCanvasData(payload);
      state = state.copyWith(canvas: 'done', canvasError: null);
      await ref.read(dataProvider.notifier).refresh();
    } catch (e, st) {
      state = state.copyWith(
        canvas: 'error',
        canvasError: _classify(e, st, source: 'Canvas'),
      );
      rethrow;
    }
  }

  Future<void> triggerSynergy() async {
    if (state.synergy == 'running') return;
    state = state.copyWith(synergy: 'running', synergyError: null);
    try {
      final client = await ref.read(synergyClientProvider.future);
      if (client == null) {
        throw _NotConfigured(
            'Synergy username/password not set. Add them in Settings → Credentials.');
      }
      final payload = await client.fetchAll();
      final store = await ref.read(localStoreProvider.future);
      await store.writeSynergyData(payload);
      state = state.copyWith(synergy: 'done', synergyError: null);
      await ref.read(dataProvider.notifier).refresh();
    } catch (e, st) {
      state = state.copyWith(
        synergy: 'error',
        synergyError: _classify(e, st, source: 'Synergy'),
      );
      rethrow;
    }
  }

  FetchError _classify(Object e, StackTrace st, {required String source}) {
    if (e is _NotConfigured) {
      return FetchError(
        kind: FetchErrorKind.auth,
        icon: Icons.settings_outlined,
        headline: 'Add your $source credentials',
        body: e.message,
        suggestions: const [
          'Open Settings and fill in the fields under Credentials.',
        ],
      );
    }
    return FetchError.from(e, st, source: source);
  }
}

class _NotConfigured implements Exception {
  _NotConfigured(this.message);
  final String message;
  @override
  String toString() => message;
}

final fetchStatusProvider =
    NotifierProvider<FetchStatusNotifier, FetchState>(
        FetchStatusNotifier.new);
