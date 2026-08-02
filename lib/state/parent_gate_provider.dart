// Parent gate state: whether a passcode exists, and whether this session has
// already been unlocked.
//
// The unlock is per-app-session and lives only in memory — closing the app
// relocks. That's the point: the student picking the phone back up should
// find the door shut.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:assignment_tracker_app/storage/parent_gate_store.dart';

final parentGateStoreProvider =
    Provider<ParentGateStore>((_) => ParentGateStore());

/// Whether a passcode has ever been set. Invalidated when one is.
final parentPasscodeSetProvider = FutureProvider<bool>((ref) async {
  return ref.watch(parentGateStoreProvider).isConfigured();
});

/// Guesses are cheap to make and expensive to allow, so the gate slows down
/// after a few misses. In-memory only — this deters tapping, not disassembly.
class ParentUnlockNotifier extends Notifier<bool> {
  static const maxAttempts = 5;
  static const lockout = Duration(minutes: 1);

  int _failures = 0;
  DateTime? _lockedUntil;

  @override
  bool build() => false;

  /// Remaining lockout, or null when guesses are allowed.
  Duration? get cooldown {
    final until = _lockedUntil;
    if (until == null) return null;
    final left = until.difference(DateTime.now());
    if (left <= Duration.zero) {
      _lockedUntil = null;
      _failures = 0;
      return null;
    }
    return left;
  }

  int get attemptsLeft => maxAttempts - _failures;

  Future<bool> unlock(String passcode) async {
    if (cooldown != null) return false;
    final ok = await ref.read(parentGateStoreProvider).verify(passcode);
    if (ok) {
      _failures = 0;
      _lockedUntil = null;
      state = true;
      return true;
    }
    _failures++;
    if (_failures >= maxAttempts) {
      _lockedUntil = DateTime.now().add(lockout);
    }
    return false;
  }

  /// Setting a passcode implies the setter is the parent, so it unlocks too —
  /// otherwise they'd be asked for the code they just typed twice.
  Future<void> setPasscode(String passcode) async {
    await ref.read(parentGateStoreProvider).setPasscode(passcode);
    ref.invalidate(parentPasscodeSetProvider);
    _failures = 0;
    _lockedUntil = null;
    state = true;
  }

  void lock() => state = false;
}

final parentUnlockedProvider =
    NotifierProvider<ParentUnlockNotifier, bool>(ParentUnlockNotifier.new);
