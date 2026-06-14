// Owns the assembled DataPayload. Source of truth is the local filesystem
// (canvas_data.json, synergy_data.json, per-student state) — there is no
// background polling because the data only changes when the user fetches or
// mutates. Both paths call `refresh()` after they write.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_models.dart';
import 'api_providers.dart';

class DataNotifier extends AsyncNotifier<DataPayload> {
  @override
  Future<DataPayload> build() async {
    final assembler = await ref.watch(dataAssemblerProvider.future);
    return assembler.assemble();
  }

  /// Re-reads everything from disk. Cheap — no network involved.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final assembler = await ref.read(dataAssemblerProvider.future);
      return assembler.assemble();
    });
  }
}

final dataProvider =
    AsyncNotifierProvider<DataNotifier, DataPayload>(DataNotifier.new);
