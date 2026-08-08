// lib/shared/models/shift_comment_model.dart

class ShiftComment {
  final String id;
  final String shiftId;
  final String userId;
  final String body;
  final DateTime createdAt;

  const ShiftComment({
    required this.id,
    required this.shiftId,
    required this.userId,
    required this.body,
    required this.createdAt,
  });

  factory ShiftComment.fromMap(Map<String, dynamic> map) {
    return ShiftComment(
      id: map['id']?.toString() ?? '',
      shiftId: map['shift_id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      body: map['body']?.toString() ?? '',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}