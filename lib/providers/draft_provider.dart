import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/draft_item.dart';
import '../services/database_service.dart';
import '../services/draft_storage_service.dart';
import '../services/media_blob_service.dart';

/// Draft state provider for managing brouillon items
class DraftProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();
  final DraftStorageService _draftStorageService = DraftStorageService();
  final MediaBlobService _mediaBlobService = MediaBlobService();

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
      if (kIsWeb) {
        // Use DraftStorageService for web
        _drafts = await _draftStorageService.getAllDrafts();
      } else {
        // Use DatabaseService for mobile (SQLite)
        _drafts = await _databaseService.getAllDrafts();
      }
    } catch (e) {
      _error = 'Erreur lors du chargement des brouillons: $e';
      debugPrint('DraftProvider: $error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Save a new draft
  /// On web, also stores the file blob in IndexedDB
  Future<DraftItem?> saveDraft({
    required String filePath,
    required bool isVideo,
    int? referenceId,
    String? referenceName,
    int? referenceType,
    String? description,
    int qualityStatus = 6,
    Uint8List? fileBytes, // For web: the actual file bytes
  }) async {
    _error = null;

    try {
      final now = DateTime.now();
      String? blobKey;

      // On web, store the file bytes in IndexedDB
      if (kIsWeb && fileBytes != null) {
        blobKey = _mediaBlobService.generateBlobKey(isVideo: isVideo);
        final storedKey = await _mediaBlobService.storeBlob(blobKey, fileBytes);
        if (storedKey == null) {
          throw Exception('Failed to store file blob in IndexedDB');
        }
        debugPrint('DraftProvider: Stored blob with key: $blobKey');
      }

      final draft = DraftItem(
        filePath: filePath,
        blobKey: blobKey,
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

      int? id;
      if (kIsWeb) {
        id = await _draftStorageService.insertDraft(draft);
      } else {
        id = await _databaseService.insertDraft(draft);
      }

      if (id == null) {
        throw Exception('Failed to save draft');
      }

      final savedDraft = draft.copyWith(id: id);

      _drafts.insert(0, savedDraft);
      notifyListeners();

      return savedDraft;
    } catch (e) {
      _error = 'Erreur lors de la sauvegarde: $e';
      debugPrint('DraftProvider: $error');
      notifyListeners();
      return null;
    }
  }

  /// Update an existing draft
  Future<bool> updateDraft(DraftItem draft) async {
    _error = null;

    try {
      final updatedDraft = draft.copyWith(updatedAt: DateTime.now());

      bool success;
      if (kIsWeb) {
        success = await _draftStorageService.updateDraft(updatedDraft);
      } else {
        final result = await _databaseService.updateDraft(updatedDraft);
        success = result > 0;
      }

      if (!success) {
        throw Exception('Failed to update draft');
      }

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
      debugPrint('DraftProvider: $error');
      notifyListeners();
      return false;
    }
  }

  /// Delete a draft (removes from DB and filesystem/IndexedDB)
  Future<bool> deleteDraft(DraftItem draft) async {
    _error = null;

    try {
      if (draft.id != null) {
        if (kIsWeb) {
          await _draftStorageService.deleteDraft(draft.id!);
          // Also delete the blob from IndexedDB
          if (draft.blobKey != null) {
            await _mediaBlobService.deleteBlob(draft.blobKey!);
          }
        } else {
          await _databaseService.deleteDraft(draft.id!);
          // Delete the file from filesystem
          await _databaseService.deleteDraftFile(draft.filePath);
        }
      }

      _drafts.removeWhere((d) => d.id == draft.id);
      notifyListeners();

      return true;
    } catch (e) {
      _error = 'Erreur lors de la suppression: $e';
      debugPrint('DraftProvider: $error');
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

      if (kIsWeb) {
        await _draftStorageService.updateDraft(finalizedDraft);
      } else {
        await _databaseService.updateDraft(finalizedDraft);
      }

      _drafts.removeWhere((d) => d.id == draft.id);
      notifyListeners();

      return true;
    } catch (e) {
      _error = 'Erreur lors de la finalisation: $e';
      debugPrint('DraftProvider: $error');
      notifyListeners();
      return false;
    }
  }

  /// Get a draft by ID
  Future<DraftItem?> getDraftById(int id) async {
    try {
      if (kIsWeb) {
        return await _draftStorageService.getDraftById(id);
      } else {
        return await _databaseService.getDraftById(id);
      }
    } catch (e) {
      _error = 'Erreur: $e';
      debugPrint('DraftProvider: $error');
      notifyListeners();
      return null;
    }
  }

  /// Get blob data for a draft (web only)
  /// Returns the file bytes stored in IndexedDB
  Future<Uint8List?> getBlobData(DraftItem draft) async {
    if (!kIsWeb) return null;
    if (draft.blobKey == null) return null;

    try {
      return await _mediaBlobService.getBlob(draft.blobKey!);
    } catch (e) {
      debugPrint('DraftProvider: Error getting blob data: $e');
      return null;
    }
  }

  /// Check if file exists for a draft
  Future<bool> draftFileExists(DraftItem draft) async {
    if (kIsWeb) {
      // On web, check if blob exists in IndexedDB
      if (draft.blobKey == null) return false;
      return await _mediaBlobService.hasBlob(draft.blobKey!);
    } else {
      final file = File(draft.filePath);
      return await file.exists();
    }
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
