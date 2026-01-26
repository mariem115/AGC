import 'package:flutter/foundation.dart';
import '../models/reference.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';

/// References state provider with filtering and API fetching
class ReferencesProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  
  String _searchQuery = '';
  bool _showComponents = true;
  bool _showSemiFinal = true;
  bool _showFinal = true;
  Reference? _selectedReference;
  
  // Fetched references from API (separate from login cached references)
  List<Reference> _fetchedReferences = [];
  bool _isLoading = false;
  String? _error;
  
  String get searchQuery => _searchQuery;
  bool get showComponents => _showComponents;
  bool get showSemiFinal => _showSemiFinal;
  bool get showFinal => _showFinal;
  Reference? get selectedReference => _selectedReference;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  /// Get all references - prefer fetched, fallback to cached from login
  List<Reference> get allReferences => 
      _fetchedReferences.isNotEmpty ? _fetchedReferences : _authService.references;
  
  /// Get the companyId from the logged-in user
  int? get companyId => _authService.currentUser?.companyId;
  
  /// Fetch fresh references from API using companyId
  /// Call this when opening the modal to get up-to-date data
  Future<void> fetchReferences() async {
    final cid = companyId;
    if (cid == null) {
      _error = 'Utilisateur non connecté ou companyId manquant';
      notifyListeners();
      return;
    }
    
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      final response = await _apiService.getAllReferencesByCompany(cid);
      
      if (response.isSuccess && response.data != null) {
        final data = response.data;
        
        // Handle response format: { "status": "success", "data": [...] }
        if (data is Map<String, dynamic>) {
          if (data['status'] == 'success' && data['data'] is List) {
            _fetchedReferences = (data['data'] as List)
                .map((r) => Reference.fromJson(r as Map<String, dynamic>))
                .toList();
          } else if (data['data'] is List) {
            // Fallback: just try data field
            _fetchedReferences = (data['data'] as List)
                .map((r) => Reference.fromJson(r as Map<String, dynamic>))
                .toList();
          }
        } else if (data is List) {
          // Direct list response
          _fetchedReferences = data
              .map((r) => Reference.fromJson(r as Map<String, dynamic>))
              .toList();
        }
      } else {
        _error = response.error ?? 'Erreur lors du chargement des références';
      }
    } catch (e) {
      _error = 'Erreur: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// Get filtered references
  List<Reference> get filteredReferences {
    return allReferences.where((ref) {
      // Filter by type
      final matchesType = (_showComponents && ref.isComponent) ||
                          (_showSemiFinal && ref.isSemiFinal) ||
                          (_showFinal && ref.isFinal);
      
      // Filter by search query
      final matchesSearch = _searchQuery.isEmpty ||
          ref.name.toLowerCase().contains(_searchQuery.toLowerCase());
      
      return matchesType && matchesSearch;
    }).toList();
  }
  
  /// Set search query
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }
  
  /// Toggle component filter
  void toggleComponents(bool value) {
    _showComponents = value;
    notifyListeners();
  }
  
  /// Toggle semi-final filter
  void toggleSemiFinal(bool value) {
    _showSemiFinal = value;
    notifyListeners();
  }
  
  /// Toggle final product filter
  void toggleFinal(bool value) {
    _showFinal = value;
    notifyListeners();
  }
  
  /// Select a reference
  void selectReference(Reference? reference) {
    _selectedReference = reference;
    notifyListeners();
  }
  
  /// Clear selection
  void clearSelection() {
    _selectedReference = null;
    notifyListeners();
  }
  
  /// Clear all filters
  void clearFilters() {
    _searchQuery = '';
    _showComponents = true;
    _showSemiFinal = true;
    _showFinal = true;
    notifyListeners();
  }
}
