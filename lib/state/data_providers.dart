// Owns /api/data — polls every 60s with ETag (the ETagInterceptor turns 304s
// into cache hits), and exposes a typed DataPayload to the UI. Refresh on
// demand via `ref.read(dataProvider.notifier).refresh()`.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_models.dart';
import 'api_providers.dart';

class DataNotifier extends AsyncNotifier<DataPayload> {
  Timer? _timer;

  @override
  Future<DataPayload> build() async {
    final client = await ref.watch(apiClientProvider.future);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _poll());
    ref.onDispose(() => _timer?.cancel());
    return client.data();
  }

  Future<void> _poll() async {
    try {
      final client = await ref.read(apiClientProvider.future);
      final next = await client.data();
      // Only update when the payload actually differs — the ETag interceptor
      // already shields us from network bytes, but identity-equal data should
      // not retrigger listeners either.
      final cur = state.value;
      if (cur != null && _shallowEqualPayload(cur, next)) {
        return;
      }
      state = AsyncData(next);
    } catch (_) {
      // Swallow transient polling errors; the next tick will retry.
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final client = await ref.read(apiClientProvider.future);
      return client.data();
    });
  }
}

bool _shallowEqualPayload(DataPayload a, DataPayload b) {
  if (a.students.length != b.students.length) return false;
  for (var i = 0; i < a.students.length; i++) {
    if (a.students[i].studentId != b.students[i].studentId) {
      return false;
    }
    if (a.students[i].assignmentStatus.length !=
        b.students[i].assignmentStatus.length) {
      return false;
    }
  }
  return a.gradeBands.failing == b.gradeBands.failing &&
      a.gradeBands.atRisk == b.gradeBands.atRisk;
}

final dataProvider =
    AsyncNotifierProvider<DataNotifier, DataPayload>(DataNotifier.new);
