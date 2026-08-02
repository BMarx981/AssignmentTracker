// The parent passcode.
//
// This exists so the student can't hand himself a sick day. That's the whole
// threat model: a kid with the app open, not an attacker with the disk. It is
// deliberately NOT a security boundary — anyone who can read the app's
// container can delete `parent_gate.json` and start over, the same way they
// could already read `credentials.json` (see [CredentialsStore] for why that
// tradeoff was made).
//
// Within that scope it still does the right things: the passcode is never
// stored, only a random-salted PBKDF2-style hash of it, and verification is
// constant-time so a wrong guess leaks nothing about how wrong it was.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'local_store.dart';

class ParentGateStore {
  ParentGateStore();

  /// Iteration count for the stretch. High enough that guessing a 4-digit
  /// passcode by brute force is a chore, low enough to stay imperceptible on
  /// a phone (single-digit milliseconds).
  static const _iterations = 100000;

  static final _rng = Random.secure();

  Future<bool> isConfigured() async {
    final raw = await _read();
    return (raw?['hash'] as String?)?.isNotEmpty ?? false;
  }

  /// Replaces the passcode. Callers are responsible for having verified the
  /// old one first when one exists — this does not check.
  Future<void> setPasscode(String passcode) async {
    final salt = List<int>.generate(16, (_) => _rng.nextInt(256));
    final store = await LocalStore.instance();
    await store.writeParentGate(<String, dynamic>{
      'salt': base64Encode(salt),
      'hash': base64Encode(_stretch(passcode, salt)),
      'iterations': _iterations,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// False when nothing is configured — an unset gate verifies nothing, so
  /// callers must check [isConfigured] to distinguish "wrong" from "unset".
  Future<bool> verify(String passcode) async {
    final raw = await _read();
    final saltRaw = raw?['salt'] as String?;
    final hashRaw = raw?['hash'] as String?;
    if (saltRaw == null || hashRaw == null) return false;

    final iterations = (raw?['iterations'] as num?)?.toInt() ?? _iterations;
    final expected = base64Decode(hashRaw);
    final actual = _stretch(passcode, base64Decode(saltRaw), iterations);
    return _constantTimeEquals(expected, actual);
  }

  Future<void> clear() async {
    final store = await LocalStore.instance();
    await store.writeParentGate(const <String, dynamic>{});
  }

  Future<Map<String, dynamic>?> _read() async {
    final store = await LocalStore.instance();
    return store.readParentGate();
  }

  /// Salted, iterated SHA-256. Each round hashes salt + the previous digest,
  /// so the work can't be skipped ahead.
  static Uint8List _stretch(
    String passcode,
    List<int> salt, [
    int iterations = _iterations,
  ]) {
    var digest = sha256.convert([...salt, ...utf8.encode(passcode)]).bytes;
    for (var i = 1; i < iterations; i++) {
      digest = sha256.convert([...salt, ...digest]).bytes;
    }
    return Uint8List.fromList(digest);
  }

  /// Compares every byte regardless of where the first mismatch is, so the
  /// time taken doesn't hint at how close a guess was.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
