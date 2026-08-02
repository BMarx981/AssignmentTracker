import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:assignment_tracker_app/dev/demo_seed.dart';
import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:assignment_tracker_app/router.dart';
import 'package:assignment_tracker_app/state/api_providers.dart';
import 'package:assignment_tracker_app/state/data_providers.dart';
import 'package:assignment_tracker_app/state/fetch_providers.dart';
import 'package:assignment_tracker_app/state/prefs_providers.dart';
import 'package:assignment_tracker_app/state/priority_providers.dart';
import 'package:assignment_tracker_app/state/student_providers.dart';
import 'package:assignment_tracker_app/storage/local_store.dart';
import 'package:assignment_tracker_app/theme/app_theme.dart';
import 'package:assignment_tracker_app/util/format.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.back('/'),
        ),
      ),
      body: LayoutBuilder(builder: (ctx, c) {
        final maxW = c.maxWidth >= 800 ? 720.0 : c.maxWidth;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                _AppearanceSection(),
                SizedBox(height: 20),
                _DateRangeSection(),
                SizedBox(height: 20),
                _GradeBandsSection(),
                SizedBox(height: 20),
                _ScoreThresholdsSection(),
                SizedBox(height: 20),
                _HiddenCoursesSection(),
                SizedBox(height: 20),
                _CredentialsSection(),
                SizedBox(height: 20),
                _FetchSection(),
                if (kDebugMode) ...[
                  SizedBox(height: 20),
                  _DemoDataSection(),
                ],
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// ---------- Appearance ----------

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    return _Section(
      title: 'Appearance',
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<ThemeMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              label: Text('System'),
              icon: Icon(Icons.brightness_auto_outlined, size: 16),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              label: Text('Light'),
              icon: Icon(Icons.light_mode_outlined, size: 16),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              label: Text('Dark'),
              icon: Icon(Icons.dark_mode_outlined, size: 16),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (sel) =>
              ref.read(themeModeProvider.notifier).set(sel.first),
        ),
      ),
    );
  }
}

// ---------- Date range ----------

class _DateRangeSection extends ConsumerWidget {
  const _DateRangeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rangeAsync = ref.watch(dateRangeProvider);
    final range = rangeAsync.value;
    return _Section(
      title: 'Date range',
      child: range == null
          ? const SizedBox(
              height: 24,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          : Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: range.start ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null && range.end != null) {
                      await ref
                          .read(dateRangeProvider.notifier)
                          .setRange(picked, range.end!);
                    }
                  },
                  icon: const Icon(Icons.calendar_month, size: 16),
                  label: Text(
                      'Start: ${range.start != null ? ymd(range.start!) : '—'}'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: range.end ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null && range.start != null) {
                      await ref
                          .read(dateRangeProvider.notifier)
                          .setRange(range.start!, picked);
                    }
                  },
                  icon: const Icon(Icons.calendar_month, size: 16),
                  label: Text(
                      'End: ${range.end != null ? ymd(range.end!) : '—'}'),
                ),
                TextButton(
                  onPressed: () =>
                      ref.read(dateRangeProvider.notifier).reset(),
                  child: const Text('Reset'),
                ),
              ],
            ),
    );
  }
}

// ---------- Grade bands ----------

class _GradeBandsSection extends ConsumerStatefulWidget {
  const _GradeBandsSection();
  @override
  ConsumerState<_GradeBandsSection> createState() => _GradeBandsState();
}

class _GradeBandsState extends ConsumerState<_GradeBandsSection> {
  int? _failing;
  int? _atRisk;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider).value;
    final bands = data?.gradeBands;
    _failing ??= bands?.failing;
    _atRisk ??= bands?.atRisk;

    return _Section(
      title: 'Grade bands',
      child: bands == null
          ? const SizedBox(
              height: 24,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Failing < $_failing%'),
                Slider(
                  value: (_failing ?? bands.failing).toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: '${_failing ?? bands.failing}',
                  onChanged: (v) =>
                      setState(() => _failing = v.round()),
                ),
                Text('At risk < $_atRisk%'),
                Slider(
                  value: (_atRisk ?? bands.atRisk).toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: '${_atRisk ?? bands.atRisk}',
                  onChanged: (v) =>
                      setState(() => _atRisk = v.round()),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: (_failing == bands.failing &&
                            _atRisk == bands.atRisk)
                        ? null
                        : () async {
                            final client =
                                await ref.read(appRepositoryProvider.future);
                            await client.setGradeBands(GradeBands(
                              failing: _failing ?? bands.failing,
                              atRisk: _atRisk ?? bands.atRisk,
                            ));
                            await ref.read(dataProvider.notifier).refresh();
                          },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
    );
  }
}

// ---------- Score thresholds (per course) ----------

class _ScoreThresholdsSection extends ConsumerStatefulWidget {
  const _ScoreThresholdsSection();
  @override
  ConsumerState<_ScoreThresholdsSection> createState() =>
      _ScoreThresholdsState();
}

class _ScoreThresholdsState extends ConsumerState<_ScoreThresholdsSection> {
  final _ctrls = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final student = ref.watch(selectedStudentProvider).value;
    final courses = ref.watch(mergedCoursesProvider);
    if (student == null) {
      return const _Section(
          title: 'Score thresholds (graded items below % are still actionable)',
          child: SizedBox.shrink());
    }
    final thresholds = student.scoreThresholds;
    return _Section(
      title: 'Score thresholds',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A graded item is still actionable if its percent is at or below the threshold (0 = off).',
            style: TextStyle(
                fontSize: 12, color: AppColors.of(context).textSecondary),
          ),
          const SizedBox(height: 6),
          for (final c in courses)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(c.name)),
                  SizedBox(
                    width: 60,
                    child: TextField(
                      controller: _ctrls.putIfAbsent(
                        c.name,
                        () => TextEditingController(
                            text: (thresholds[c.name] ?? 0).toString()),
                      ),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        suffixText: '%',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () async {
                final map = <String, int>{};
                for (final entry in _ctrls.entries) {
                  final n = int.tryParse(entry.value.text.trim()) ?? 0;
                  if (n > 0) map[entry.key] = n;
                }
                final client = await ref.read(appRepositoryProvider.future);
                await client.setScoreThresholds(student.studentId, map);
                await ref.read(dataProvider.notifier).refresh();
              },
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Hidden courses ----------

class _HiddenCoursesSection extends ConsumerWidget {
  const _HiddenCoursesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final student = ref.watch(selectedStudentProvider).value;
    if (student == null) {
      return const _Section(title: 'Hidden courses', child: SizedBox.shrink());
    }
    final hiddenAsync = ref.watch(hiddenCoursesProvider(student.studentId));
    final hidden = hiddenAsync.value ?? const <String>{};
    // Show ALL courses (including ones currently hidden by mergedCoursesProvider).
    final allCourses = ref
            .watch(dataProvider)
            .value
            ?.students
            .firstWhere(
              (s) => s.studentId == student.studentId,
              orElse: () => student,
            )
            .synergy
            ?.courses
            .map((c) => c.synergyName)
            .toList() ??
        const <String>[];

    return _Section(
      title: 'Hidden courses',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final name in allCourses)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(name),
              subtitle: Text(hidden.contains(name) ? 'Hidden' : 'Visible',
                  style: const TextStyle(fontSize: 11)),
              value: !hidden.contains(name),
              onChanged: (_) => ref
                  .read(hiddenCoursesProvider(student.studentId).notifier)
                  .toggle(name),
            ),
        ],
      ),
    );
  }
}

// ---------- Credentials ----------

class _CredentialsSection extends ConsumerStatefulWidget {
  const _CredentialsSection();
  @override
  ConsumerState<_CredentialsSection> createState() => _CredentialsState();
}

class _CredentialsState extends ConsumerState<_CredentialsSection> {
  final _canvasToken = TextEditingController();
  final _canvasUrl = TextEditingController();
  final _synUser = TextEditingController();
  final _synPass = TextEditingController();
  final _synUrl = TextEditingController();
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _canvasToken.dispose();
    _canvasUrl.dispose();
    _synUser.dispose();
    _synPass.dispose();
    _synUrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final client = await ref.read(appRepositoryProvider.future);
      final c = await client.getCredentials();
      if (!mounted) return;
      _canvasToken.text = c.canvasToken ?? '';
      _canvasUrl.text = c.canvasBaseUrl ?? '';
      _synUser.text = c.synergyUsername ?? '';
      _synPass.text = c.synergyPassword ?? '';
      _synUrl.text = c.synergyBaseUrl ?? '';
      setState(() => _loaded = true);
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const _Section(
          title: 'Credentials',
          child: SizedBox(
              height: 24,
              child:
                  Center(child: CircularProgressIndicator(strokeWidth: 2))));
    }
    return _Section(
      title: 'Credentials',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field('Canvas token', _canvasToken, obscure: true),
          _field('Canvas base URL', _canvasUrl),
          const SizedBox(height: 6),
          _field('Synergy username', _synUser),
          _field('Synergy password', _synPass, obscure: true),
          _field('Synergy base URL', _synUrl),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        final client =
                            await ref.read(appRepositoryProvider.future);
                        await client.setCredentials(Credentials(
                          canvasToken: _canvasToken.text.trim().isEmpty
                              ? null
                              : _canvasToken.text.trim(),
                          canvasBaseUrl: _canvasUrl.text.trim().isEmpty
                              ? null
                              : _canvasUrl.text.trim(),
                          synergyUsername: _synUser.text.trim().isEmpty
                              ? null
                              : _synUser.text.trim(),
                          synergyPassword: _synPass.text.isEmpty
                              ? null
                              : _synPass.text,
                          synergyBaseUrl: _synUrl.text.trim().isEmpty
                              ? null
                              : _synUrl.text.trim(),
                        ));
                        // Round-trip read to verify the write actually landed
                        // — silent keychain failures are a real failure mode
                        // on macOS without the right entitlements.
                        final readBack = await client.getCredentials();
                        final ok = (readBack.canvasToken ?? '') ==
                                _canvasToken.text.trim() &&
                            (readBack.synergyUsername ?? '') ==
                                _synUser.text.trim();
                        if (!mounted) return;
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(ok
                              ? 'Saved.'
                              : 'Save did not stick — keychain write failed.'),
                          backgroundColor: ok
                              ? null
                              : Theme.of(context).colorScheme.error,
                        ));
                      } catch (e) {
                        if (!mounted) return;
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Save failed: $e'),
                          backgroundColor:
                              Theme.of(context).colorScheme.error,
                        ));
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

// ---------- Fetch buttons ----------

class _FetchSection extends ConsumerWidget {
  const _FetchSection();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Section(
      title: 'Fetch data',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: () {
              context.push('/fetch');
              // Fire-and-forget: the fetch screen reflects state.canvas live.
              // Swallow errors here; the screen surfaces 'error' state.
              ref
                  .read(fetchStatusProvider.notifier)
                  .triggerCanvas()
                  .catchError((_) {});
            },
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Fetch Canvas'),
          ),
          FilledButton.icon(
            onPressed: () {
              context.push('/fetch');
              ref
                  .read(fetchStatusProvider.notifier)
                  .triggerSynergy()
                  .catchError((_) {});
            },
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Fetch Synergy'),
          ),
          OutlinedButton.icon(
            onPressed: () => context.push('/fetch'),
            icon: const Icon(Icons.info_outline),
            label: const Text('View status'),
          ),
        ],
      ),
    );
  }
}

// ---------- Demo data (debug builds only) ----------

/// Seeds synthetic Canvas + Synergy data so the app can be exercised without
/// live credentials — over the summer a real fetch returns nothing in range.
/// Gated on [kDebugMode] at the call site so it never ships in a release build.
class _DemoDataSection extends ConsumerStatefulWidget {
  const _DemoDataSection();
  @override
  ConsumerState<_DemoDataSection> createState() => _DemoDataState();
}

class _DemoDataState extends ConsumerState<_DemoDataSection> {
  bool _busy = false;

  Future<void> _run(
      Future<void> Function(LocalStore store) action, String done) async {
    setState(() => _busy = true);
    try {
      final store = await ref.read(localStoreProvider.future);
      await action(store);
      // The old selection may point at a student that no longer exists.
      ref.invalidate(selectedStudentIdProvider);
      await ref.read(dataProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed: $e'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Demo data (debug only)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Replaces stored Canvas/Synergy data with two synthetic students. '
            'Due dates are generated relative to today, so seeded work always '
            'lands inside the current date range. Credentials are left alone.',
            style: TextStyle(
                fontSize: 12, color: AppColors.of(context).textSecondary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run((s) => seedDemoData(s), 'Demo data loaded.'),
                icon: const Icon(Icons.science_outlined),
                label: const Text('Load demo data'),
              ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run((s) => clearDemoData(s), 'Local data cleared.'),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear local data'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
