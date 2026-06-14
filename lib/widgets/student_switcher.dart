import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/data_providers.dart';
import '../state/student_providers.dart';

/// Dropdown menu in the AppBar for switching students. Renders nothing when
/// there's only one student.
class StudentSwitcher extends ConsumerWidget {
  const StudentSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(dataProvider);
    final students = dataAsync.value?.students ?? const [];
    if (students.length <= 1) return const SizedBox.shrink();
    final selectedId = ref.watch(selectedStudentIdProvider) ??
        ref.watch(selectedStudentProvider).value?.studentId;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedId,
          dropdownColor: Theme.of(context).colorScheme.surface,
          items: [
            for (final s in students)
              DropdownMenuItem(value: s.studentId, child: Text(s.name)),
          ],
          onChanged: (id) {
            if (id != null) {
              ref.read(selectedStudentIdProvider.notifier).select(id);
            }
          },
        ),
      ),
    );
  }
}
