/// Data model representing a single counting session.
class Session {
  final int? id;
  final int dhikrId;
  final String dhikrName;
  final int count;
  final int target;

  /// ISO8601 date string (e.g., "2026-08-28").
  final String date;

  /// ISO8601 datetime string when the session was created.
  final String createdAt;

  /// ISO8601 datetime string when the session was last updated.
  final String updatedAt;

  const Session({
    this.id,
    required this.dhikrId,
    required this.dhikrName,
    required this.count,
    required this.target,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
  });

  Session copyWith({
    int? id,
    int? dhikrId,
    String? dhikrName,
    int? count,
    int? target,
    String? date,
    String? createdAt,
    String? updatedAt,
  }) {
    return Session(
      id: id ?? this.id,
      dhikrId: dhikrId ?? this.dhikrId,
      dhikrName: dhikrName ?? this.dhikrName,
      count: count ?? this.count,
      target: target ?? this.target,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'dhikr_id': dhikrId,
      'dhikr_name': dhikrName,
      'count': count,
      'target': target,
      'date': date,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory Session.fromMap(Map<String, dynamic> map) {
    return Session(
      id: map['id'] as int?,
      dhikrId: map['dhikr_id'] as int,
      dhikrName: map['dhikr_name'] as String? ?? '',
      count: map['count'] as int? ?? 0,
      target: map['target'] as int? ?? 33,
      date: map['date'] as String,
      createdAt: map['created_at'] as String? ?? DateTime.now().toIso8601String(),
      updatedAt: map['updated_at'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  @override
  String toString() =>
      'Session(id: $id, dhikr: $dhikrName, count: $count, target: $target, date: $date)';
}
