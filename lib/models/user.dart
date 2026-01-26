/// User model for authentication
class User {
  final String email;
  final String company;
  final int? companyId;
  
  User({
    required this.email,
    required this.company,
    this.companyId,
  });
  
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      email: json['email'] ?? '',
      company: json['company'] ?? '',
      companyId: json['companyId'],
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'company': company,
      'companyId': companyId,
    };
  }
  
  @override
  String toString() {
    return 'User(email: $email, company: $company, companyId: $companyId)';
  }
}
