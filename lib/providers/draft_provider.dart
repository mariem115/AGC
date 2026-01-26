import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/draft_item.dart';
import '../services/database_service.dart';

/// Draft state provider for managing brouillon items
class DraftProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  bool _isLoading = false;
  String? _error;
  List<DraftItem> _drafts = [];

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<DraftItem> get drafts => _drafts;
  int get draftsCount => _drafts.length;

  /// Load all drafts from database
  Future<void> loadDrafts() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _drafts = await _databaseService.getAllDrafts();
    } catch (e) {
      _error = 'Erreur lors du chargement des brouillons: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Save a new draft
  Future<DraftItem?> saveDraft({
    required String filePath,
    required bool isVideo,
    int? referenceId,
    String? referenceName,
    int? referenceType,
    String? description,
    int qualityStatus = 6,
  }) async {
    _error = null;

    try {
      final now = DateTime.now();
      final draft = DraftItem(
        filePath: filePath,
        isVideo: isVideo,
        referenceId: referenceId,
        referenceName: referenceName,
        referenceType: referenceType,
        description: description,
        qualityStatus: qualityStatus,
        createdAt: now,
        updatedAt: now,
        isDraft: true,
      );

      final id = await _databaseService.insertDraft(draft);
      final savedDraft = draft.copyWith(id: id);
      
      _drafts.insert(0, savedDraft);
      notifyListeners();
      
      return savedDraft;
    } catch (e) {
      _error = 'Erreur lors de la sauvegarde: $e';
      notifyListeners();
      return null;
    }
  }

  /// Update an existing draft
  Future<bool> updateDraft(DraftItem draft) async {
    _error = null;

    try {
      final updatedDraft = draft.copyWith(updatedAt: DateTime.now());
      await _databaseService.updateDraft(updatedDraft);
      
      final index = _drafts.indexWhere((d) => d.id == draft.id);
      if (index != -1) {
        _drafts[index] = updatedDraft;
        // Re-sort by updated date
        _drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        notifyListeners();
      }
      
      return true;
    } catch (e) {
      _error = 'Erreur lors de la mise à jour: $e';
      notifyListeners();
      return false;
    }
  }

  /// Delete a draft (removes from DB and filesystem)
  Future<bool> deleteDraft(DraftItem draft) async {
    _error = null;

    try {
      if (draft.id != null) {
        await _databaseService.deleteDraft(draft.id!);
      }
      
      // Delete the file from filesystem
      await _databaseService.deleteDraftFile(draft.filePath);
      
      _drafts.removeWhere((d) => d.id == draft.id);
      notifyListeners();
      
      return true;
    } catch (e) {
      _error = 'Erreur lors de la suppression: $e';
      notifyListeners();
      return false;
    }
  }

  /// Mark draft as finalized (no longer a draft)
  Future<bool> finalizeDraft(DraftItem draft) async {
    _error = null;

    try {
      final finalizedDraft = draft.copyWith(
        isDraft: false,
        updatedAt: DateTime.now(),
      );
      await _databaseService.updateDraft(finalizedDraft);
      
      _drafts.removeWhere((d) => d.id == draft.id);
      notifyListeners();
      
      return true;
    } catch (e) {
      _error = 'Erreur lors de la finalisation: $e';
      notifyListeners();
      return false;
    }
  }

  /// Get a draft by ID
  Future<DraftItem?> getDraftById(int id) async {
    try {
      return await _databaseService.getDraftById(id);
    } catch (e) {
      _error = 'Erreur: $e';
      notifyListeners();
      return null;
    }
  }

  /// Check if file exists for a draft
  Future<bool> draftFileExists(DraftItem draft) async {
    final file = File(draft.filePath);
    return await file.exists();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Clear all data
  void clear() {
    _drafts = [];
    _error = null;
    notifyListeners();
  }
}
