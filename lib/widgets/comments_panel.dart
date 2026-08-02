import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:assignment_tracker_app/domain/merged.dart';
import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:assignment_tracker_app/state/assignment_actions.dart';
import 'package:assignment_tracker_app/state/student_providers.dart';
import 'package:assignment_tracker_app/theme/app_theme.dart';
import 'package:assignment_tracker_app/util/format.dart';

/// Bottom sheet on mobile, side-anchored Dialog on web/desktop.
Future<void> showCommentsPanel(
    BuildContext context, MergedItem item, MergedCourse course) async {
  final colors = AppColors.of(context);
  final isWide = MediaQuery.of(context).size.width >= 800;
  if (isWide || kIsWeb && MediaQuery.of(context).size.width >= 600) {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: colors.card,
            elevation: 6,
            child: SizedBox(
              width: 420,
              height: double.infinity,
              child: _CommentsPanelContent(item: item, course: course),
            ),
          ),
        );
      },
    );
  } else {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: FractionallySizedBox(
            heightFactor: 0.85,
            child: _CommentsPanelContent(item: item, course: course),
          ),
        );
      },
    );
  }
}

class _CommentsPanelContent extends ConsumerStatefulWidget {
  final MergedItem item;
  final MergedCourse course;
  const _CommentsPanelContent({required this.item, required this.course});

  @override
  ConsumerState<_CommentsPanelContent> createState() =>
      _CommentsPanelContentState();
}

class _CommentsPanelContentState extends ConsumerState<_CommentsPanelContent> {
  final _newCtrl = TextEditingController();
  final _replyCtrls = <String, TextEditingController>{};
  final _openReplyFor = <String>{};
  bool _busy = false;

  @override
  void dispose() {
    _newCtrl.dispose();
    for (final c in _replyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final student = ref.watch(selectedStudentProvider).value;
    final threads = student?.comments[widget.item.key] ?? const [];
    final actions = ref.read(assignmentActionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(widget.course.name,
                        style: TextStyle(
                            fontSize: 12, color: colors.textSecondary)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: threads.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('No comments yet — be the first.',
                        style: TextStyle(color: colors.textSecondary)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  children: [
                    for (final t in threads) _thread(context, actions, t),
                  ],
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _newCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Add a comment…',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final text = _newCtrl.text.trim();
                          if (text.isEmpty) return;
                          setState(() => _busy = true);
                          try {
                            await actions.postComment(
                                key: widget.item.key, text: text);
                            _newCtrl.clear();
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  child: const Text('Post'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _thread(
      BuildContext context, AssignmentActions actions, CommentThread t) {
    final colors = AppColors.of(context);
    final replyCtrl =
        _replyCtrls.putIfAbsent(t.id, () => TextEditingController());
    final showReply = _openReplyFor.contains(t.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.cardSubtle,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _meta(context, t.author, t.createdAt,
              onDelete: () => actions.deleteComment(
                  key: widget.item.key, commentId: t.id)),
          const SizedBox(height: 4),
          Text(t.text, style: const TextStyle(fontSize: 13)),
          for (final r in t.replies)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 16),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.card,
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _meta(context, r.author, r.createdAt,
                        onDelete: () => actions.deleteComment(
                              key: widget.item.key,
                              commentId: t.id,
                              replyId: r.id,
                            )),
                    const SizedBox(height: 2),
                    Text(r.text,
                        style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton(
                style: TextButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                onPressed: () => setState(() {
                  if (!_openReplyFor.add(t.id)) _openReplyFor.remove(t.id);
                }),
                child: const Text('↩ Reply',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (showReply) ...[
            const SizedBox(height: 4),
            TextField(
              controller: replyCtrl,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Write a reply…',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final text = replyCtrl.text.trim();
                        if (text.isEmpty) return;
                        setState(() => _busy = true);
                        try {
                          await actions.postReply(
                              key: widget.item.key,
                              parentId: t.id,
                              text: text);
                          replyCtrl.clear();
                          _openReplyFor.remove(t.id);
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                child: const Text('Post reply'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _meta(BuildContext context, String author, String createdAt,
      {required VoidCallback onDelete}) {
    final colors = AppColors.of(context);
    return Row(
      children: [
        Text(author,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        Text(fmtCommentDate(createdAt),
            style: TextStyle(fontSize: 11, color: colors.textSecondary)),
        const Spacer(),
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 24),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: onDelete,
          child: Text('Delete',
              style: TextStyle(fontSize: 11, color: colors.dangerText)),
        ),
      ],
    );
  }
}
