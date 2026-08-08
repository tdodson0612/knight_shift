// lib/shared/models/shift_checklist_model.dart

class ShiftChecklistItem {
  final String id;
  final String companyId;
  final String label;
  final int sortOrder;

  const ShiftChecklistItem({
    required this.id,
    required this.companyId,
    required this.label,
    required this.sortOrder,
  });

  factory ShiftChecklistItem.fromMap(Map<String, dynamic> map) {
    return ShiftChecklistItem(
      id: map['id']?.toString() ?? '',
      companyId: map['company_id']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      sortOrder: (map['sort_order'] ?? 0) is int
          ? map['sort_order'] as int
          : (map['sort_order'] as num).toInt(),
    );
  }
}

class ShiftChecklistCompletion {
  final String id;
  final String shiftId;
  final String itemId;
  final String? completedBy;
  final DateTime completedAt;

  const ShiftChecklistCompletion({
    required this.id,
    required this.shiftId,
    required this.itemId,
    this.completedBy,
    required this.completedAt,
  });

  factory ShiftChecklistCompletion.fromMap(Map<String, dynamic> map) {
    return ShiftChecklistCompletion(
      id: map['id']?.toString() ?? '',
      shiftId: map['shift_id']?.toString() ?? '',
      itemId: map['item_id']?.toString() ?? '',
      completedBy: map['completed_by']?.toString(),
      completedAt: DateTime.tryParse(map['completed_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}