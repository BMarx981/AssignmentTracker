// Parent controls: the passcode, and the excused days it protects.
//
// The excused day is the one thing in this app the student must not be able to
// grant himself — a sick day that costs nothing is only meaningful if it can't
// be handed out from the inside. Everything reachable from here is behind the
// passcode; everything else in the app stays open.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:assignment_tracker_app/router.dart';
import 'package:assignment_tracker_app/state/excused_days_providers.dart';
import 'package:assignment_tracker_app/state/parent_gate_provider.dart';
import 'package:assignment_tracker_app/state/student_providers.dart';
import 'package:assignment_tracker_app/theme/app_theme.dart';
import 'package:assignment_tracker_app/util/format.dart';

class ParentControlsScreen extends ConsumerWidget {
  const ParentControlsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked = ref.watch(parentUnlockedProvider);
    final configured = ref.watch(parentPasscodeSetProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parent controls'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.back('/'),
        ),
        actions: [
          if (unlocked)
            IconButton(
              tooltip: 'Lock',
              icon: const Icon(Icons.lock_outline),
              onPressed: () => ref.read(parentUnlockedProvider.notifier).lock(),
            ),
        ],
      ),
      body: configured.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (hasPasscode) {
          if (!hasPasscode) return const _CreatePasscode();
          if (!unlocked) return const _PasscodePrompt();
          return const _Unlocked();
        },
      ),
    );
  }
}

// ---------- gate ----------

/// First run. Whoever gets here first sets the code — there is no identity to
/// check against, so the honest thing is to say so and get it set early.
class _CreatePasscode extends ConsumerStatefulWidget {
  const _CreatePasscode();

  @override
  ConsumerState<_CreatePasscode> createState() => _CreatePasscodeState();
}

class _CreatePasscodeState extends ConsumerState<_CreatePasscode> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final a = _first.text;
    final b = _second.text;
    if (a.length < 4) {
      setState(() => _error = 'Use at least 4 characters.');
      return;
    }
    if (a != b) {
      setState(() => _error = "Those don't match.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await ref.read(parentUnlockedProvider.notifier).setPasscode(a);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return _GatePanel(
      icon: Icons.lock_open_outlined,
      title: 'Set a parent passcode',
      body: 'Excused days are set here, so this needs a code your student '
          "doesn't know. Set it now, before handing the device back.",
      children: [
        TextField(
          controller: _first,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Passcode',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _second,
          obscureText: true,
          onSubmitted: (_) => _save(),
          decoration: const InputDecoration(
            labelText: 'Again',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: colors.dangerText)),
        ],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving…' : 'Set passcode'),
          ),
        ),
      ],
    );
  }
}

class _PasscodePrompt extends ConsumerStatefulWidget {
  const _PasscodePrompt();

  @override
  ConsumerState<_PasscodePrompt> createState() => _PasscodePromptState();
}

class _PasscodePromptState extends ConsumerState<_PasscodePrompt> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final notifier = ref.read(parentUnlockedProvider.notifier);
    final cooldown = notifier.cooldown;
    if (cooldown != null) {
      setState(() => _error =
          'Too many tries. Wait ${cooldown.inSeconds + 1}s and try again.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await notifier.unlock(_controller.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) {
        _controller.clear();
        final left = notifier.attemptsLeft;
        _error = left > 0
            ? "That's not it. $left ${left == 1 ? 'try' : 'tries'} left."
            : 'Too many tries. Wait a minute and try again.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return _GatePanel(
      icon: Icons.lock_outline,
      title: 'Parent passcode',
      body: 'Excused days are behind this.',
      children: [
        TextField(
          controller: _controller,
          obscureText: true,
          autofocus: true,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            labelText: 'Passcode',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: colors.dangerText)),
        ],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'Checking…' : 'Unlock'),
          ),
        ),
      ],
    );
  }
}

class _GatePanel extends StatelessWidget {
  const _GatePanel({
    required this.icon,
    required this.title,
    required this.body,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: 44, color: colors.iconMuted),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
              const SizedBox(height: 20),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- unlocked ----------

class _Unlocked extends ConsumerWidget {
  const _Unlocked();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final student = ref.watch(selectedStudentProvider).value;
    final excused = ref.watch(currentExcusedDaysProvider).value ?? const [];

    return LayoutBuilder(builder: (ctx, c) {
      final maxW = c.maxWidth >= 800 ? 720.0 : c.maxWidth;
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ExcusedDaysSection(
                studentName: student?.name,
                excused: excused,
                onAdd: student == null
                    ? null
                    : () => _addDay(context, ref, student.studentId),
                onRemove: student == null
                    ? null
                    : (date) => ref
                        .read(excusedDaysProvider(student.studentId).notifier)
                        .unexcuse(date),
              ),
              const SizedBox(height: 20),
              const _ChangePasscodeSection(),
            ],
          ),
        ),
      );
    });
  }

  Future<void> _addDay(
    BuildContext context,
    WidgetRef ref,
    String studentId,
  ) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      // Backdated for the day you forgot to mark, and a short way forward for
      // an absence you already know about.
      firstDate: now.subtract(const Duration(days: 90)),
      lastDate: now.add(const Duration(days: 14)),
      helpText: 'Excuse a day',
    );
    if (picked == null || !context.mounted) return;

    final reason = await _askReason(context);
    if (reason == null) return;
    await ref
        .read(excusedDaysProvider(studentId).notifier)
        .excuse(picked, reason: reason);
  }

  /// Returns null if cancelled, or the (possibly empty) reason.
  Future<String?> _askReason(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Why?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Sick, family trip, …',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Excuse it'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }
}

class _ExcusedDaysSection extends StatelessWidget {
  const _ExcusedDaysSection({
    required this.studentName,
    required this.excused,
    required this.onAdd,
    required this.onRemove,
  });

  final String? studentName;
  final List<ExcusedDay> excused;
  final VoidCallback? onAdd;
  final void Function(String date)? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final who = studentName == null ? 'this student' : studentName!;

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
          const Text(
            'Excused days',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'An excused day is skipped by the streak instead of breaking it. '
            "It earns nothing on its own — $who just doesn't get knocked back "
            'to zero for it. Weekends are already skipped automatically.',
            style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
          ),
          const SizedBox(height: 12),
          if (excused.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'No excused days yet.',
                style: TextStyle(fontSize: 13, color: colors.textFaint),
              ),
            )
          else
            for (final day in excused)
              _ExcusedRow(
                day: day,
                onRemove:
                    onRemove == null ? null : () => onRemove!(day.date),
              ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.event_busy_outlined, size: 18),
              label: const Text('Excuse a day'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExcusedRow extends StatelessWidget {
  const _ExcusedRow({required this.day, required this.onRemove});

  final ExcusedDay day;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: colors.cardSubtle,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fmtPlanDate(day.date),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textStrong,
                  ),
                ),
                if (day.reason.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      day.reason,
                      style:
                          TextStyle(fontSize: 11.5, color: colors.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close, size: 18),
            color: colors.textSecondary,
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _ChangePasscodeSection extends ConsumerStatefulWidget {
  const _ChangePasscodeSection();

  @override
  ConsumerState<_ChangePasscodeSection> createState() =>
      _ChangePasscodeSectionState();
}

class _ChangePasscodeSectionState
    extends ConsumerState<_ChangePasscodeSection> {
  final _controller = TextEditingController();
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    if (_controller.text.length < 4) {
      setState(() => _message = 'Use at least 4 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    await ref
        .read(parentUnlockedProvider.notifier)
        .setPasscode(_controller.text);
    if (!mounted) return;
    _controller.clear();
    setState(() {
      _busy = false;
      _message = 'Passcode updated.';
    });
  }

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
          const Text(
            'Change passcode',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            obscureText: true,
            onSubmitted: (_) => _change(),
            decoration: const InputDecoration(
              labelText: 'New passcode',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(
              _message!,
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _busy ? null : _change,
              child: Text(_busy ? 'Saving…' : 'Update'),
            ),
          ),
        ],
      ),
    );
  }
}
