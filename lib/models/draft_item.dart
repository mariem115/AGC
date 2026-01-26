import 'dart:convert';

/// Draft item model representing a photo/video saved for later editing
class DraftItem {
  final int? id;
  final String filePath;
  final bool isVideo;
  final int? referenceId;
  final String? referenceName;
  final int? referenceType;
  final String? description;
  final int qualityStatus; // 4=Bonne, 5=Mauvaise, 6=Neutre
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDraft;

  DraftItem({
    this.id,
    required this.filePath,
    this.isVideo = false,
    this.referenceId,
    this.referenceName,
    this.referenceType,
    this.description,
    this.qualityStatus = 6, // Default to Neutre
    required this.createdAt,
    required this.updatedAt,
    this.isDraft = true,
  });

  /// Create from database map
  factory DraftItem.fromMap(Map<String, dynamic> map) {
    return DraftItem(
      id: map['id'] as int?,
      filePath: map['file_path'] as String,
      isVideo: (map['is_video'] as int?) == 1,
      referenceId: map['reference_id'] as int?,
      referenceName: map['reference_name'] as String?,
      referenceType: map['reference_type'] as int?,
      description: map['description'] as String?,
      qualityStatus: map['quality_status'] as int? ?? 6,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      isDraft: (map['is_draft'] as int?) == 1,
    );
  }

  /// Convert to database map (SQLite format with int booleans)
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'file_path': filePath,
      'is_video': isVideo ? 1 : 0,
      'reference_id': referenceId,
      'reference_name': referenceName,
      'reference_type': referenceType,
      'description': description,
      'quality_status': qualityStatus,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_draft': isDraft ? 1 : 0,
    };
  }

  /// Convert to JSON map (for web storage)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'file_path': filePath,
      'is_video': isVideo,
      'reference_id': referenceId,
      'reference_name': referenceName,
      'reference_type': referenceType,
      'description': description,
      'quality_status': qualityStatus,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_draft': isDraft,
    };
  }

  /// Create from JSON map (for web storage)
  factory DraftItem.fromJson(Map<String, dynamic> json) {
    return DraftItem(
      id: json['id'] as int?,
      filePath: json['file_path'] as String,
      isVideo: json['is_video'] as bool? ?? false,
      referenceId: json['reference_id'] as int?,
      referenceName: json['reference_name'] as String?,
      referenceType: json['reference_type'] as int?,
      description: json['description'] as String?,
      qualityStatus: json['quality_status'] as int? ?? 6,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      isDraft: json['is_draft'] as bool? ?? true,
    );
  }

  /// Convert to JSON string
  String toJsonString() => jsonEncode(toJson());

  /// Create from JSON string
  factory DraftItem.fromJsonString(String jsonString) {
    return DraftItem.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  /// Create a copy with modified fields
  DraftItem copyWith({
    int? id,
    String? filePath,
    bool? isVideo,
    int? referenceId,
    String? referenceName,
    int? referenceType,
    String? description,
    int? qualityStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDraft,
  }) {
    return DraftItem(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      isVideo: isVideo ?? this.isVideo,
      referenceId: referenceId ?? this.referenceId,
      referenceName: referenceName ?? this.referenceName,
      referenceType: referenceType ?? this.referenceType,
      description: description ?? this.description,
      qualityStatus: qualityStatus ?? this.qualityStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDraft: isDraft ?? this.isDraft,
    );
  }

  /// Get quality status label
  String get qualityLabel {
    switch (qualityStatus) {
      case 4:
        return 'Bonne';
      case 5:
        return 'Mauvaise';
      case 6:
        return 'Neutre';
      default:
        return 'Neutre';
    }
  }

  /// Check if quality is good
  bool get isGood => qualityStatus == 4;

  /// Check if quality is bad
  bool get isBad => qualityStatus == 5;

  /// Check if quality is neutral
  bool get isNeutral => qualityStatus == 6;

  @override
  String toString() {
    return 'DraftItem(id: $id, filePath: $filePath, isVideo: $isVideo, reference: $referenceName)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DraftItem && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
