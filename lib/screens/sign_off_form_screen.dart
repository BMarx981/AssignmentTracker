import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import 'package:assignment_tracker_app/pdf/sign_off_form_pdf.dart';
import 'package:assignment_tracker_app/state/data_providers.dart';
import 'package:assignment_tracker_app/state/prefs_providers.dart';
import 'package:assignment_tracker_app/state/priority_providers.dart';
import 'package:assignment_tracker_app/state/student_providers.dart';

class SignOffFormScreen extends ConsumerWidget {
  const SignOffFormScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final student = ref.watch(selectedStudentProvider).value;
    final bands = ref.watch(dataProvider).value?.gradeBands;
    final courses = ref.watch(mergedCoursesProvider);
    final range = ref.watch(dateRangeProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign-off form'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: (student == null || bands == null || range == null)
          ? const Center(child: CircularProgressIndicator())
          : PdfPreview(
              build: (format) => buildSignOffPdf(
                student: student,
                courses: courses,
                bands: bands,
                thresholds: student.scoreThresholds,
                range: range,
                today: DateTime.now(),
              ),
              canChangePageFormat: false,
              canChangeOrientation: false,
              allowPrinting: true,
              allowSharing: true,
              pdfFileName: 'signoff_${_sanitize(student.name)}.pdf',
            ),
    );
  }

  String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
}
