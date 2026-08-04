// lib/shared/models/notification_model.dart

class NotificationModel {
  final String id;
  final String companyId;
  final String userId;
  final String type;
  final String title;
  final String? body;
  final DateTime? readAt;
  final DateTime createdAt;
  final String? relatedId;
  final String? relatedType;

  NotificationModel({
    required this.id,
    required this.companyId,
    required this.userId,
    required this.type,
    required this.title,
    this.body,
    this.readAt,
    required this.createdAt,
    this.relatedId,
    this.relatedType,
  });

  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    return NotificationModel(
      id: map['id']?.toString() ?? '',
      companyId: map['company_id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      body: map['body']?.toString(),
      readAt: map['read_at'] != null
          ? DateTime.tryParse(map['read_at'].toString())
          : null,
      createdAt: DateTime.parse(map['created_at']),
      relatedId: map['related_id']?.toString(),
      relatedType: map['related_type']?.toString(),
    );
  }

  bool get isUnread => readAt == null;
}