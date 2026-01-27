import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/draft_item.dart';

/// Service for storing and retrieving draft metadata
/// Uses SharedPreferences for persistence
class DraftStorageService {
  static final DraftStorageService _instance = DraftStorageService._internal();
  factory DraftStorageService() => _instance;
  DraftStorageService._internal();

  static const String _draftsKey = 'agc_drafts_v2';
  static int _idCounter = 0;

  /// Get all drafts from storage
  Future<List<DraftItem>> getAllDrafts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftsJson = prefs.getString(_draftsKey);

      if (draftsJson == null || draftsJson.isEmpty) {
        return [];
      }

      final List<dynamic> draftsList = jsonDecode(draftsJson);
      final drafts = <DraftItem>[];

      for (final json in draftsList) {
        try {
          final draft = DraftItem.fromJson(json as Map<String, dynamic>);
          if (draft.isDraft) {
            drafts.add(draft);
          }
        } catch (e) {
          // Skip corrupted draft entries
          debugPrint('DraftStorageService: Error parsing draft: $e');
        }
      }

      // Update ID counter
      if (drafts.isNotEmpty) {
        _idCounter = drafts
            .map((d) => d.id ?? 0)
            .reduce((a, b) => a > b ? a : b);
      }

      // Sort by updated date descending
      drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      return drafts;
    } catch (e) {
      debugPrint('DraftStorageService: Error loading drafts: $e');
      return [];
    }
  }

  /// Save drafts to storage
  Future<bool> _saveDrafts(List<DraftItem> drafts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftsJson = jsonEncode(drafts.map((d) => d.toJson()).toList());
      return await prefs.setString(_draftsKey, draftsJson);
    } catch (e) {
      debugPrint('DraftStorageService: Error saving drafts: $e');
      return false;
    }
  }

  /// Get next ID for new draft
  int _getNextId() {
    _idCounter++;
    return _idCounter;
  }

  /// Insert a new draft
  Future<int?> insertDraft(DraftItem draft) async {
    try {
      final drafts = await getAllDrafts();
      final newId = _getNextId();
      final newDraft = draft.copyWith(id: newId);

      drafts.insert(0, newDraft);

      final success = await _saveDrafts(drafts);
      return success ? newId : null;
    } catch (e) {
      debugPrint('DraftStorageService: Error inserting draft: $e');
      return null;
    }
  }

  /// Update an existing draft
  Future<bool> updateDraft(DraftItem draft) async {
    try {
      final drafts = await getAllDrafts();
      final index = drafts.indexWhere((d) => d.id == draft.id);

      if (index == -1) {
        debugPrint(
          'DraftStorageService: Draft not found for update: ${draft.id}',
        );
        return false;
      }

      drafts[index] = draft;
      return await _saveDrafts(drafts);
    } catch (e) {
      debugPrint('DraftStorageService: Error updating draft: $e');
      return false;
    }
  }

  /// Delete a draft by ID
  Future<bool> deleteDraft(int id) async {
    try {
      final drafts = await getAllDrafts();
      final initialLength = drafts.length;
      drafts.removeWhere((d) => d.id == id);

      if (drafts.length == initialLength) {
        debugPrint('DraftStorageService: Draft not found for deletion: $id');
        return false;
      }

      return await _saveDrafts(drafts);
    } catch (e) {
      debugPrint('DraftStorageService: Error deleting draft: $e');
      return false;
    }
  }

  /// Get a draft by ID
  Future<DraftItem?> getDraftById(int id) async {
    try {
      final drafts = await getAllDrafts();
      return drafts.firstWhere(
        (d) => d.id == id,
        orElse: () => throw StateError('Not found'),
      );
    } catch (e) {
      return null;
    }
  }

  /// Get drafts count
  Future<int> getDraftsCount() async {
    final drafts = await getAllDrafts();
    return drafts.length;
  }

  /// Delete all drafts
  Future<bool> deleteAllDrafts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove(_draftsKey);
    } catch (e) {
      debugPrint('DraftStorageService: Error deleting all drafts: $e');
      return false;
    }
  }
}
