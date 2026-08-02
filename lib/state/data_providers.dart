// Owns the assembled DataPayload. Source of truth is the local filesystem
// (canvas_data.json, synergy_data.json, per-student state) — there is no
// background polling because the data only changes when the user fetches or
// mutates. Both paths call `refresh()` after they write.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:assignment_tracker_app/models/api_models.dart';
import 'api_providers.dart';

class DataNotifier extends AsyncNotifier<DataPayload> {
  @override
  Future<DataPayload> build() async {
    final assembler = await ref.watch(dataAssemblerProvider.future);
    return assembler.assemble();
  }

  /// Re-reads everything from disk. Cheap — no network involved, so it does
  /// NOT emit an intermediate [AsyncLoading]: the old payload stays on screen
  /// until the new one replaces it.
  ///
  /// Emitting a valueless loading state here made every consumer branching on
  /// `.when(loading: ...)` swap to a spinner, unmounting the dashboard subtree
  /// and remounting it when the data landed. That remount is what tripped
  /// "setState() called during build" — the derived providers go inactive
  /// while unmounted, so the scheduler skips their refresh, and the first
  /// `ref.watch` of the fresh subtree ends up flushing them mid-build.
  /// Callers that want a progress indicator own one (RefreshIndicator, the
  /// fetch buttons in settings).
  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      final assembler = await ref.read(dataAssemblerProvider.future);
      return assembler.assemble();
    });
  }
}

final dataProvider =
    AsyncNotifierProvider<DataNotifier, DataPayload>(DataNotifier.new);
