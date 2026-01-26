/// Media item model representing an image or video
class MediaItem {
  final int id;
  final String? name;
  final String? path;
  final int? referenceId;
  final int? mediaType; // 1=Photo, 4=OK, 5=NOK, 6=Neutral
  final DateTime? createdAt;
  final bool isLocal;
  
  MediaItem({
    required this.id,
    this.name,
    this.path,
    this.referenceId,
    this.mediaType,
    this.createdAt,
    this.isLocal = false,
  });
  
  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: json['id'] ?? 0,
      name: json['name'],
      path: json['path'],
      referenceId: json['referenceId'],
      mediaType: json['mediaType'],
      createdAt: json['createdAt'] != null 
          ? DateTime.tryParse(json['createdAt']) 
          : null,
      isLocal: json['isLocal'] ?? false,
    );
  }
  
  factory MediaItem.local({
    required String path,
    String? name,
  }) {
    return MediaItem(
      id: DateTime.now().millisecondsSinceEpoch,
      name: name,
      path: path,
      isLocal: true,
      createdAt: DateTime.now(),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'referenceId': referenceId,
      'mediaType': mediaType,
      'createdAt': createdAt?.toIso8601String(),
      'isLocal': isLocal,
    };
  }
  
  /// Get the media type label
  String get mediaTypeLabel {
    switch (mediaType) {
      case 1:
        return 'Photo';
      case 4:
        return 'OK';
      case 5:
        return 'NOK';
      case 6:
        return 'Neutre';
      default:
        return 'Photo';
    }
  }
  
  /// Check if this is an OK status
  bool get isOK => mediaType == 4;
  
  /// Check if this is a NOK status
  bool get isNOK => mediaType == 5;
  
  /// Check if this is neutral
  bool get isNeutral => mediaType == 6;
  
  @override
  String toString() {
    return 'MediaItem(id: $id, name: $name, isLocal: $isLocal)';
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MediaItem && other.id == id && other.isLocal == isLocal;
  }
  
  @override
  int get hashCode => id.hashCode ^ isLocal.hashCode;
}

/// Media type enum for categorization
enum MediaType {
  photo(1, 'Photo'),
  ok(4, 'OK'),
  nok(5, 'NOK'),
  neutral(6, 'Neutre');
  
  final int value;
  final String label;
  
  const MediaType(this.value, this.label);
}
