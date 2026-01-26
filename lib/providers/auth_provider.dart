import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../models/reference.dart';
import '../services/auth_service.dart';

/// Authentication state provider
class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  
  bool _isLoading = false;
  bool _isLoggedIn = false;
  String? _error;
  
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _isLoggedIn;
  String? get error => _error;
  User? get currentUser => _authService.currentUser;
  List<Reference> get references => _authService.references;
  
  /// Initialize provider and check for existing session
  Future<bool> init() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      _isLoggedIn = await _authService.checkSession();
      return _isLoggedIn;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// Login with credentials
  Future<bool> login(String email, String company, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      final result = await _authService.login(email, company, password);
      
      if (result.isSuccess) {
        _isLoggedIn = true;
        _error = null;
      } else {
        _isLoggedIn = false;
        _error = result.error;
      }
      
      return result.isSuccess;
    } catch (e) {
      _error = 'Erreur de connexion: $e';
      _isLoggedIn = false;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// Logout
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      await _authService.logout();
      _isLoggedIn = false;
      _error = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
