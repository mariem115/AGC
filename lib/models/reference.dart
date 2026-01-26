/// Reference model representing a product/component
class Reference {
  final int id;
  final String name;
  final String? designation;    // e.g., "WIRE" - from API
  final String? projectName;    // e.g., "LAMBORGHINI HURACAN" - from API
  final String? companyName;
  final int referenceType;      // 1=Component, 2=Semi-final, 3=Final (API uses 'type' field)
  
  Reference({
    required this.id,
    required this.name,
    this.designation,
    this.projectName,
    this.companyName,
    required this.referenceType,
  });
  
  /// Display format: "name (designation)" e.g., "1 (WIRE)"
  /// Falls back to just name if designation is null
  String get displayName => designation != null && designation!.isNotEmpty 
      ? '$name ($designation)' 
      : name;
  
  factory Reference.fromJson(Map<String, dynamic> json) {
    return Reference(
      id: json['id'] ?? 0,
      name: json['name']?.toString() ?? '',
      designation: json['designation']?.toString(),
      projectName: json['projectName']?.toString(),
      companyName: json['companyName']?.toString(),
      // API returns 'type' field, fallback to 'referenceType' for compatibility
      referenceType: json['type'] ?? json['referenceType'] ?? 0,
    );
  }
  
  /// Parse from the legacy format: "id,name,company,type"
  factory Reference.fromLegacyList(List<String> data) {
    return Reference(
      id: int.tryParse(data[0]) ?? 0,
      name: data.length > 1 ? data[1] : '',
      designation: null,
      projectName: null,
      companyName: data.length > 2 ? data[2] : null,
      referenceType: data.length > 3 ? (int.tryParse(data[3]) ?? 0) : 0,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'designation': designation,
      'projectName': projectName,
      'companyName': companyName,
      'referenceType': referenceType,
    };
  }
  
  /// Get the type label
  String get typeLabel {
    switch (referenceType) {
      case 1:
        return 'Composant';
      case 2:
        return 'Semi-fini';
      case 3:
        return 'Produit fini';
      default:
        return 'Inconnu';
    }
  }
  
  /// Check if this is a component (type=1 in API)
  bool get isComponent => referenceType == 1;
  
  /// Check if this is a semi-final product (type=2 in API)
  bool get isSemiFinal => referenceType == 2;
  
  /// Check if this is a final product (type=3 in API)
  bool get isFinal => referenceType == 3;
  
  @override
  String toString() {
    return name;
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Reference && other.id == id;
  }
  
  @override
  int get hashCode => id.hashCode;
}

/// Reference type enum for filtering (matches API type values)
enum ReferenceType {
  component(1, 'Composants'),
  semiFinal(2, 'Semi-finis'),
  finalProduct(3, 'Produits finis');
  
  final int value;
  final String label;
  
  const ReferenceType(this.value, this.label);
}
