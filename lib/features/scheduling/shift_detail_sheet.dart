// lib/features/scheduling/shift_detail_sheet.dart
//
// Shared between manager and employee scheduling screens — opened
// via long-press on a shift block (a gesture neither screen used
// before, so nothing existing was touched to add this). Shows
// comments and/or checklist, whichever the company has enabled;
// shows nothing extra (just the shift info) if neither is on.

import 'package:flutter/material.dart';

import '../../core/services/session_service.dart';
import '../../core/services/shift_comment_service.dart';
import '../../core/services/shift_checklist_service.dart';
import '../../shared/models/shift_model.dart';
import '../../shared/models/shift_comment_model.dart';
import '../../shared/models/shift_checklist_model.dart';

Future<void> showShiftDetailSheet(BuildContext context, ShiftModel shift) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ShiftDetailSheet(shift: shift),
  );
}

class _ShiftDetailSheet extends StatefulWidget {
  final ShiftModel shift;
  const _ShiftDetailSheet({required this.shift});

  @override
  State<_ShiftDetailSheet> createState() => _ShiftDetailSheetState();
}

class _ShiftDetailSheetState extends State<_ShiftDetailSheet> {
  bool loading = true;
  bool commentsEnabled = false;
  bool checklistEnabled = false;

  List<ShiftComment> comments = [];
  List<ShiftChecklistItem> checklistItems = [];
  Set<String> completedItemIds = {};

  final _commentController = TextEditingController();
  bool posting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final companyId = SessionService.activeCompanyId;
    if (companyId == null) {
      setState(() => loading = false);
      return;
    }

    try {
      commentsEnabled = await ShiftCommentService.isEnabled(companyId);
      checklistEnabled = await ShiftChecklistService.isEnabled(companyId);

      if (commentsEnabled) {
        comments = await ShiftCommentService.getComments(widget.shift.id);
      }

      if (checklistEnabled) {
        final results = await Future.wait([
          ShiftChecklistService.getItems(companyId),
          ShiftChecklistService.getCompletions(widget.shift.id),
        ]);
        checklistItems = results[0] as List<ShiftChecklistItem>;
        final completions = results[1] as List<ShiftChecklistCompletion>;
        completedItemIds = completions.map((c) => c.itemId).toSet();
      }
    } catch (_) {
      // Leave whatever loaded — partial data is fine here.
    }

    if (mounted) setState(() => loading = false);
  }

  Future<void> _postComment() async {
    final companyId = SessionService.activeCompanyId;
    final userId = SessionService.activeUserId;
    final body = _commentController.text.trim();
    if (companyId == null || userId == null || body.isEmpty) return;

    setState(() => posting = true);

    try {
      await ShiftCommentService.postComment(
        shiftId: widget.shift.id,
        companyId: companyId,
        userId: userId,
        body: body,
      );
      _commentController.clear();
      comments = await ShiftCommentService.getComments(widget.shift.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't post: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => posting = false);
    }
  }

  Future<void> _toggleChecklistItem(ShiftChecklistItem item, bool checked) async {
    final userId = SessionService.activeUserId;
    if (userId == null) return;

    setState(() {
      if (checked) {
        completedItemIds.add(item.id);
      } else {
        completedItemIds.remove(item.id);
      }
    });

    try {
      if (checked) {
        await ShiftChecklistService.checkItem(
          shiftId: widget.shift.id,
          itemId: item.id,
          userId: userId,
        );
      } else {
        await ShiftChecklistService.uncheckItem(
          shiftId: widget.shift.id,
          itemId: item.id,
        );
      }
    } catch (e) {
      // Revert on failure so UI matches what's actually saved.
      setState(() {
        if (checked) {
          completedItemIds.remove(item.id);
        } else {
          completedItemIds.add(item.id);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _fmt(DateTime d) {
    final h = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    final period = d.hour >= 12 ? "PM" : "AM";
    return "${d.month}/${d.day} $h:${d.minute.toString().padLeft(2, '0')} $period";
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${_fmt(widget.shift.startTime)} – ${_fmt(widget.shift.endTime)}",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Divider(),
                  if (!commentsEnabled && !checklistEnabled)
                    const Expanded(
                      child: Center(
                        child: Text(
                          "Comments and checklists aren't turned on for "
                          "this company yet.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ),
                    ),
                  if (checklistEnabled) ...[
                    const Text("Checklist", style: TextStyle(fontWeight: FontWeight.w600)),
                    if (checklistItems.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text("No checklist items set up yet",
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                      )
                    else
                      ...checklistItems.map((item) => CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(item.label, style: const TextStyle(fontSize: 13)),
                            value: completedItemIds.contains(item.id),
                            onChanged: (v) => _toggleChecklistItem(item, v ?? false),
                          )),
                    if (commentsEnabled) const Divider(),
                  ],
                  if (commentsEnabled) ...[
                    const Text("Comments", style: TextStyle(fontWeight: FontWeight.w600)),
                    Expanded(
                      child: comments.isEmpty
                          ? const Center(
                              child: Text("No comments yet",
                                  style: TextStyle(color: Colors.grey, fontSize: 12)),
                            )
                          : ListView.builder(
                              itemCount: comments.length,
                              itemBuilder: (context, i) {
                                final c = comments[i];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_fmt(c.createdAt),
                                          style: const TextStyle(
                                              fontSize: 10, color: Colors.grey)),
                                      Text(c.body, style: const TextStyle(fontSize: 13)),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _commentController,
                            decoration: const InputDecoration(hintText: "Add a comment..."),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: posting ? null : _postComment,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}