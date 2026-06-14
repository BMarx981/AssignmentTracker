import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/merged.dart';
import '../domain/priority.dart';
import '../models/api_models.dart';
import '../util/format.dart';

/// Builds the teacher sign-off PDF for one student. Pure function over the
/// same domain models the UI consumes. The result is one document; printing
/// emits a single PDF that the OS can hand to the share/print sheet.
Future<Uint8List> buildSignOffPdf({
  required Student student,
  required List<MergedCourse> courses,
  required GradeBands bands,
  required Map<String, int> thresholds,
  required DateRange range,
  required DateTime today,
}) async {
  final doc = pw.Document(title: 'Sign-off Form — ${student.name}');

  // Sort alphabetically — matches dashboard.html buildPrintForm() order.
  final ordered = [...courses]..sort((a, b) => a.name.compareTo(b.name));
  final dateStr = ymd(today);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter.copyWith(
        marginLeft: 36,
        marginRight: 36,
        marginTop: 36,
        marginBottom: 36,
      ),
      header: (_) => pw.SizedBox.shrink(),
      footer: (_) => pw.Container(
        alignment: pw.Alignment.center,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text(
          'One signature per teacher confirms current outstanding work and recovery plan.',
          style: pw.TextStyle(
              fontSize: 9, color: PdfColors.grey700, fontStyle: pw.FontStyle.italic),
        ),
      ),
      build: (ctx) => [
        _header(student.name, dateStr, ordered.length),
        pw.SizedBox(height: 10),
        for (final c in ordered)
          _courseBlock(c, student, thresholds, range),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _header(String name, String dateStr, int classCount) {
  return pw.Container(
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: PdfColors.black, width: 1.5),
      ),
    ),
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Assignment Sign-off Form — $name',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Generated $dateStr · $classCount class${classCount == 1 ? '' : 'es'}',
          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ],
    ),
  );
}

pw.Widget _courseBlock(
  MergedCourse c,
  Student student,
  Map<String, int> thresholds,
  DateRange range,
) {
  final outstanding = [
    for (final it in c.items)
      if (range.contains(it.date) &&
          (isActionable(it, c.name, thresholds) ||
              it.status == 'half_credit_missing' ||
              it.status == 'not_graded'))
        it
  ]..sort((a, b) => (a.date ?? '').compareTo(b.date ?? ''));

  final gradeStr = c.synergyPercent != null
      ? '${pctText(c.synergyPercent)}${(c.synergyLetter ?? '').isNotEmpty ? ' (${c.synergyLetter})' : ''}'
      : (c.canvasAvgWithMissing != null
          ? '${pctText(c.canvasAvgWithMissing)} (Canvas worst-case)'
          : '—');

  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 14),
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.black, width: 1),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(c.name,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text(
          '${(c.teacher ?? '').isNotEmpty ? 'Teacher: ${c.teacher} · ' : ''}Current grade: $gradeStr',
          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
        ),
        pw.SizedBox(height: 6),
        if (outstanding.isEmpty)
          pw.Text(
            'No outstanding work flagged in tracker. Please confirm with teacher.',
            style: pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey800,
                fontStyle: pw.FontStyle.italic),
          )
        else
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final it in outstanding)
                _itemRow(it, student.comments[it.key] ?? const [],
                    student.assignmentStatus),
            ],
          ),
        pw.SizedBox(height: 8),
        pw.Text('Teacher notes / plan to recover:',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        _line(),
        pw.SizedBox(height: 6),
        _line(),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _line(),
                  pw.SizedBox(height: 2),
                  pw.Text('Teacher signature',
                      style: pw.TextStyle(
                          fontSize: 8, color: PdfColors.grey700)),
                ],
              ),
            ),
            pw.SizedBox(width: 18),
            pw.SizedBox(
              width: 140,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _line(),
                  pw.SizedBox(height: 2),
                  pw.Text('Date',
                      style: pw.TextStyle(
                          fontSize: 8, color: PdfColors.grey700)),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _itemRow(
  MergedItem it,
  List<CommentThread> threads,
  Map<String, LocalStatus> statusByKey,
) {
  final due = (it.date != null && it.date!.isNotEmpty) ? 'due ${it.date} · ' : '';
  final pts = it.pointsPossible != null ? ' (${_numStr(it.pointsPossible!)} pts)' : '';
  final ls = getLocalStatus(it, statusByKey);

  String? claim;
  PdfColor? claimColor;
  if (ls != null) {
    if (ls.submittedDate != null && ls.submittedDate!.isNotEmpty) {
      claim = ' · Felix says submitted ${fmtPlanDate(ls.submittedDate)}';
      claimColor = PdfColors.green800;
    } else if (ls.plannedDate != null && ls.plannedDate!.isNotEmpty) {
      claim = ' · Felix plans by ${fmtPlanDate(ls.plannedDate)}';
      claimColor = PdfColors.blue800;
    } else if (ls.status == 'submitted_pending_feedback') {
      claim = ' · Felix says already submitted';
      claimColor = PdfColors.green800;
    } else if (ls.status == 'complete_pending_submission') {
      claim = ' · Felix says complete, not yet submitted';
      claimColor = PdfColors.blue800;
    }
  }

  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 11,
          height: 11,
          margin: const pw.EdgeInsets.only(top: 1, right: 6),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.black, width: 1.2),
          ),
        ),
        pw.SizedBox(
          width: 96,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Date: ',
                  style: pw.TextStyle(fontSize: 8.5)),
              pw.Expanded(
                child: pw.Container(
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: PdfColors.black),
                    ),
                  ),
                  height: 11,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 6),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.RichText(
                text: pw.TextSpan(children: [
                  pw.TextSpan(
                    text: '$due${it.name}$pts',
                    style: pw.TextStyle(fontSize: 10, height: 1.35),
                  ),
                  if (claim != null)
                    pw.TextSpan(
                      text: claim,
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: claimColor),
                    ),
                ]),
              ),
              if (threads.isNotEmpty)
                pw.Container(
                  margin: const pw.EdgeInsets.only(top: 3, left: 4),
                  padding: const pw.EdgeInsets.only(left: 6),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      left: pw.BorderSide(color: PdfColors.grey500, width: 1.5),
                    ),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      for (final t in threads)
                        pw.Text(
                          '📝 ${t.text}',
                          style: pw.TextStyle(
                              fontSize: 9,
                              fontStyle: pw.FontStyle.italic,
                              color: PdfColors.grey800),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Widget _line() => pw.Container(
      height: 12,
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black)),
      ),
    );

String _numStr(double n) {
  if (n == n.roundToDouble()) return n.toInt().toString();
  return n.toStringAsFixed(1);
}
