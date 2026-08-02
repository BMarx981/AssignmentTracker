// The gate's job is to keep a student from handing himself a sick day, so
// what matters is that a wrong code never opens it, the right one always
// does, and the code itself never appears on disk.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:assignment_tracker_app/storage/local_store.dart';
import 'package:assignment_tracker_app/storage/parent_gate_store.dart';

class _TempPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TempPathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  late Directory tempDir;
  late LocalStore store;
  final gate = ParentGateStore();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('parent_gate_test');
    PathProviderPlatform.instance = _TempPathProvider(tempDir.path);
    store = await LocalStore.instance();
  });

  setUp(() => gate.clear());

  tearDownAll(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('nothing is configured until a passcode is set', () async {
    expect(await gate.isConfigured(), isFalse);
    await gate.setPasscode('hunter2');
    expect(await gate.isConfigured(), isTrue);
  });

  test('the right passcode opens it and a wrong one never does', () async {
    await gate.setPasscode('hunter2');
    expect(await gate.verify('hunter2'), isTrue);
    expect(await gate.verify('hunter3'), isFalse);
    expect(await gate.verify('HUNTER2'), isFalse);
    expect(await gate.verify(''), isFalse);
    expect(await gate.verify('hunter2 '), isFalse);
  });

  test('an unset gate verifies nothing, including the empty string', () async {
    expect(await gate.verify(''), isFalse);
    expect(await gate.verify('anything'), isFalse);
  });

  test('the passcode itself is never written to disk', () async {
    await gate.setPasscode('hunter2');
    final raw = jsonEncode(await store.readParentGate());
    expect(raw.contains('hunter2'), isFalse);
    expect(raw.contains('salt'), isTrue);
    expect(raw.contains('hash'), isTrue);
  });

  test('two identical passcodes hash differently, so a salt is really used',
      () async {
    await gate.setPasscode('hunter2');
    final first = (await store.readParentGate())!;
    await gate.setPasscode('hunter2');
    final second = (await store.readParentGate())!;

    expect(first['salt'], isNot(second['salt']));
    expect(first['hash'], isNot(second['hash']));
    // Both still open the same door.
    expect(await gate.verify('hunter2'), isTrue);
  });

  test('changing the passcode retires the old one', () async {
    await gate.setPasscode('first-code');
    await gate.setPasscode('second-code');
    expect(await gate.verify('first-code'), isFalse);
    expect(await gate.verify('second-code'), isTrue);
  });

  test('a corrupted gate file fails closed rather than opening', () async {
    await gate.setPasscode('hunter2');
    await store.writeParentGate({'salt': 'not-base64!!', 'hash': 'garbage'});
    // Whatever it does, it must not report a match.
    expect(
      await gate.verify('hunter2').catchError((_) => false),
      isFalse,
    );
  });
}
