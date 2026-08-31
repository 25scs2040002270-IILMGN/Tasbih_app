/// Data model representing a Dhikr (remembrance phrase).
class Dhikr {
  final int? id;
  final String name;
  final String arabic;
  final bool isCustom;
  final String createdAt;

  const Dhikr({
    this.id,
    required this.name,
    required this.arabic,
    this.isCustom = false,
    required this.createdAt,
  });

  Dhikr copyWith({
    int? id,
    String? name,
    String? arabic,
    bool? isCustom,
    String? createdAt,
  }) {
    return Dhikr(
      id: id ?? this.id,
      name: name ?? this.name,
      arabic: arabic ?? this.arabic,
      isCustom: isCustom ?? this.isCustom,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'arabic': arabic,
      'is_custom': isCustom ? 1 : 0,
      'created_at': createdAt,
    };
  }

  factory Dhikr.fromMap(Map<String, dynamic> map) {
    return Dhikr(
      id: map['id'] as int?,
      name: map['name'] as String,
      arabic: map['arabic'] as String? ?? '',
      isCustom: (map['is_custom'] as int? ?? 0) == 1,
      createdAt: map['created_at'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Dhikr && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Dhikr(id: $id, name: $name, isCustom: $isCustom)';
}
