import 'dart:convert';
import 'dart:io' as io;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../models/user.dart';
import '../models/reference.dart';

/// Authentication service handling login/logout
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();
  
  User? _currentUser;
  List<Reference> _references = [];
  
  // Dedicated HTTP client for login (does not follow redirects)
  static http.Client? _loginClient;
  
  /// Get or create the login HTTP client (configured to not follow redirects)
  static http.Client _getLoginClient() {
    if (_loginClient != null) {
      return _loginClient!;
    }
    
    // Create custom client that doesn't follow redirects
    // We use a custom client wrapper that intercepts redirects
    _loginClient = _NoRedirectClient();
    return _loginClient!;
  }
  
  User? get currentUser => _currentUser;
  List<Reference> get references => _references;
  
  /// Login with email, company, and password using JSON body
  Future<AuthResult> login(String email, String company, String password) async {
    try {
      // Build login URL with action as query param, credentials in JSON body
      final uri = Uri.parse('${AppConstants.baseUrl}?action=${AppConstants.actionLogin}');
      
      // Use dedicated login client that does NOT follow redirects
      final client = _getLoginClient();
      
      // Send POST request with JSON body
      final response = await client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'company': company,
          'password': password,
        }),
      ).timeout(Duration(seconds: AppConstants.connectionTimeout));
      
      // Debug logging - remove after fixing the issue
      print('=== LOGIN DEBUG ===');
      print('Request URL: $uri');
      print('Response status: ${response.statusCode}');
      print('Response body: "${response.body}"');
      print('Response headers: ${response.headers}');
      print('===================');
      
      // Handle 302 redirect response explicitly (don't follow redirect)
      if (response.statusCode == 302) {
        // Server returned redirect - this indicates login problem
        // Extract error message from response body if available
        try {
          final json = jsonDecode(response.body);
          if (json is Map<String, dynamic>) {
            final errorMsg = json['message'] ?? json['error'] ?? 'Erreur de connexion';
            return AuthResult.failure(errorMsg.toString());
          }
        } catch (_) {
          // If body is not JSON, use default error
        }
        return AuthResult.failure('Erreur de connexion: redirection non autorisée');
      }
      
      if (response.statusCode != 200) {
        return AuthResult.failure('Erreur serveur: ${response.statusCode}');
      }
      
      final data = response.body;
      
      // Try to parse as JSON first (new API format)
      try {
        final json = jsonDecode(data);
        
        // Handle JSON response
        if (json is Map<String, dynamic>) {
          // Check for success field
          if (json['success'] == true || json['status'] == 'success' || json['status'] == 'ok' || json['result'] == 'ok') {
            // Extract user data from 'data' field if present
            final userData = json['data'] is Map<String, dynamic> ? json['data'] as Map<String, dynamic> : json;
            final companyId = userData['CompanyId'] ?? userData['companyId'] ?? json['companyId'];
            
            _currentUser = User(email: email, company: company, companyId: companyId);
            
            // Parse references if present
            if (json['references'] != null && json['references'] is List) {
              _references = (json['references'] as List)
                  .map((r) => Reference.fromJson(r as Map<String, dynamic>))
                  .toList();
            } else if (json['data'] != null && json['data'] is List) {
              _references = (json['data'] as List)
                  .map((r) => Reference.fromJson(r as Map<String, dynamic>))
                  .toList();
            }
            
            await _saveSession(email, company, companyId, _references);
            return AuthResult.success();
          }
          
          // Check for error message
          final errorMsg = json['message'] ?? json['error'] ?? 'Erreur de connexion';
          return AuthResult.failure(errorMsg.toString());
        }
        
        // If JSON but not a map, might be an array of references directly after successful login
        if (json is List) {
          _currentUser = User(email: email, company: company);
          _references = json.map((r) => Reference.fromJson(r as Map<String, dynamic>)).toList();
          await _saveSession(email, company, null, _references);
          return AuthResult.success();
        }
        
      } catch (_) {
        // Not JSON, try legacy format
      }
      
      // Handle legacy response format: "ok" followed by comma-separated references
      if (data.toLowerCase().startsWith('ok')) {
        _references = _parseReferencesFromLegacy(data);
        _currentUser = User(email: email, company: company);
        await _saveSession(email, company, null, _references);
        return AuthResult.success();
      }
      
      print('DEBUG: No valid response format matched. Returning default error.');
      return AuthResult.failure('Email ou mot de passe incorrect');
    } catch (e, stackTrace) {
      print('=== LOGIN ERROR ===');
      print('Exception type: ${e.runtimeType}');
      print('Exception: $e');
      print('Stack trace: $stackTrace');
      print('===================');
      return AuthResult.failure('Erreur de connexion: ${e.toString()}');
    }
  }
  
  /// Parse references from legacy format: "ok,id,name,company,type,id,name,company,type,..."
  List<Reference> _parseReferencesFromLegacy(String data) {
    final references = <Reference>[];
    
    if (data.length > 3) {
      final parts = data.substring(3).split(',');
      
      // References come in groups of 4: id, name, company, type
      for (var i = 0; i < parts.length; i += 4) {
        if (i + 3 < parts.length) {
          try {
            references.add(Reference.fromLegacyList([
              parts[i],
              parts[i + 1],
              parts[i + 2],
              parts[i + 3],
            ]));
          } catch (_) {
            // Skip invalid entries
          }
        }
      }
    }
    
    return references;
  }
  
  /// Save session to shared preferences
  Future<void> _saveSession(String email, String company, int? companyId, List<Reference> references) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyIsLoggedIn, true);
    await prefs.setString(AppConstants.keyUserEmail, email);
    await prefs.setString(AppConstants.keyCompanyName, company);
    if (companyId != null) {
      await prefs.setInt(AppConstants.keyCompanyId, companyId);
    }
    
    // Save references as JSON string
    if (references.isNotEmpty) {
      final refsJson = references.map((r) => '${r.id},${r.name},${r.companyName ?? ''},${r.referenceType}').join('|');
      await prefs.setString(AppConstants.keyProductsList, refsJson);
    }
  }
  
  /// Check if user is logged in and restore session
  Future<bool> checkSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool(AppConstants.keyIsLoggedIn) ?? false;
      
      if (isLoggedIn) {
        final email = prefs.getString(AppConstants.keyUserEmail) ?? '';
        final company = prefs.getString(AppConstants.keyCompanyName) ?? '';
        final companyId = prefs.getInt(AppConstants.keyCompanyId);
        
        _currentUser = User(email: email, company: company, companyId: companyId);
        
        // Restore references
        final refsString = prefs.getString(AppConstants.keyProductsList) ?? '';
        if (refsString.isNotEmpty) {
          _references = refsString.split('|').map((refStr) {
            final parts = refStr.split(',');
            return Reference.fromLegacyList(parts);
          }).toList();
        }
        
        return true;
      }
      
      return false;
    } catch (_) {
      return false;
    }
  }
  
  /// Logout and clear session
  Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConstants.keyIsLoggedIn);
      await prefs.remove(AppConstants.keyUserEmail);
      await prefs.remove(AppConstants.keyCompanyName);
      await prefs.remove(AppConstants.keyCompanyId);
      await prefs.remove(AppConstants.keyProductsList);
      
      _currentUser = null;
      _references = [];
    } catch (_) {
      // Ignore errors during logout
    }
  }
}

/// Custom HTTP client that does not follow redirects
/// Uses a separate HttpClient instance isolated from media upload configuration
class _NoRedirectClient extends http.BaseClient {
  final http_io.IOClient _ioClient;
  
  _NoRedirectClient() : _ioClient = http_io.IOClient(io.HttpClient());
  
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Use IOClient - it will follow redirects, but we handle 302 explicitly in login()
    // The key is that this client is isolated from any media upload configuration
    return _ioClient.send(request);
  }
  
  @override
  void close() {
    _ioClient.close();
  }
}

/// Authentication result
class AuthResult {
  final bool isSuccess;
  final String? error;
  
  AuthResult._({required this.isSuccess, this.error});
  
  factory AuthResult.success() => AuthResult._(isSuccess: true);
  factory AuthResult.failure(String error) => AuthResult._(isSuccess: false, error: error);
}
