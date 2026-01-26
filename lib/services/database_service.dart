import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/draft_item.dart';

/// Database service for local storage
/// Uses SQLite on mobile and SharedPreferences on web
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  // Mobile: SQLite database
  static Database? _database;
  static const String _databaseName = 'agc_drafts.db';
  static const int _databaseVersion = 1;

  // Web: SharedPreferences key
  static const String _webDraftsKey = 'agc_drafts';
  static int _webIdCounter = 0;

  // ========== DATABASE INITIALIZATION ==========

  /// Get database instance (mobile only)
  Future<Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError('SQLite database is not available on web');
    }
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize the database (mobile only)
  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Create database tables
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE drafts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT NOT NULL,
        is_video INTEGER DEFAULT 0,
        reference_id INTEGER,
        reference_name TEXT,
        reference_type INTEGER,
        description TEXT,
        quality_status INTEGER DEFAULT 6,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_draft INTEGER DEFAULT 1
      )
    ''');
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Add migration logic here for future versions
  }

  // ========== WEB STORAGE HELPERS ==========

  /// Get drafts from SharedPreferences (web)
  Future<List<DraftItem>> _getWebDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final draftsJson = prefs.getString(_webDraftsKey);
    if (draftsJson == null || draftsJson.isEmpty) {
      return [];
    }
    try {
      final List<dynamic> draftsList = jsonDecode(draftsJson);
      final drafts = draftsList
          .map((json) => DraftItem.fromJson(json as Map<String, dynamic>))
          .toList();
      
      // Update ID counter
      if (drafts.isNotEmpty) {
        _webIdCounter = drafts.map((d) => d.id ?? 0).reduce((a, b) => a > b ? a : b);
      }
      
      return drafts;
    } catch (e) {
      debugPrint('Error parsing web drafts: $e');
      return [];
    }
  }

  /// Save drafts to SharedPreferences (web)
  Future<void> _saveWebDrafts(List<DraftItem> drafts) async {
    final prefs = await SharedPreferences.getInstance();
    final draftsJson = jsonEncode(drafts.map((d) => d.toJson()).toList());
    await prefs.setString(_webDraftsKey, draftsJson);
  }

  /// Get next ID for web drafts
  int _getNextWebId() {
    _webIdCounter++;
    return _webIdCounter;
  }

  // ========== DRAFT OPERATIONS ==========

  /// Insert a new draft
  Future<int> insertDraft(DraftItem draft) async {
    if (kIsWeb) {
      final drafts = await _getWebDrafts();
      final newId = _getNextWebId();
      final newDraft = draft.copyWith(id: newId);
      drafts.insert(0, newDraft);
      await _saveWebDrafts(drafts);
      return newId;
    } else {
      final db = await database;
      return await db.insert('drafts', draft.toMap());
    }
  }

  /// Update an existing draft
  Future<int> updateDraft(DraftItem draft) async {
    if (kIsWeb) {
      final drafts = await _getWebDrafts();
      final index = drafts.indexWhere((d) => d.id == draft.id);
      if (index != -1) {
        drafts[index] = draft;
        await _saveWebDrafts(drafts);
        return 1;
      }
      return 0;
    } else {
      final db = await database;
      return await db.update(
        'drafts',
        draft.toMap(),
        where: 'id = ?',
        whereArgs: [draft.id],
      );
    }
  }

  /// Delete a draft by ID
  Future<int> deleteDraft(int id) async {
    if (kIsWeb) {
      final drafts = await _getWebDrafts();
      final initialLength = drafts.length;
      drafts.removeWhere((d) => d.id == id);
      await _saveWebDrafts(drafts);
      return initialLength - drafts.length;
    } else {
      final db = await database;
      return await db.delete(
        'drafts',
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  /// Get all drafts (is_draft = 1)
  Future<List<DraftItem>> getAllDrafts() async {
    if (kIsWeb) {
      final drafts = await _getWebDrafts();
      return drafts.where((d) => d.isDraft).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } else {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'drafts',
        where: 'is_draft = ?',
        whereArgs: [1],
        orderBy: 'updated_at DESC',
      );
      return List.generate(maps.length, (i) => DraftItem.fromMap(maps[i]));
    }
  }

  /// Get a draft by ID
  Future<DraftItem?> getDraftById(int id) async {
    if (kIsWeb) {
      final drafts = await _getWebDrafts();
      try {
        return drafts.firstWhere((d) => d.id == id);
      } catch (_) {
        return null;
      }
    } else {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'drafts',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (maps.isEmpty) return null;
      return DraftItem.fromMap(maps.first);
    }
  }

  /// Get drafts count
  Future<int> getDraftsCount() async {
    if (kIsWeb) {
      final drafts = await _getWebDrafts();
      return drafts.where((d) => d.isDraft).length;
    } else {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM drafts WHERE is_draft = 1',
      );
      return Sqflite.firstIntValue(result) ?? 0;
    }
  }

  /// Delete all drafts
  Future<int> deleteAllDrafts() async {
    if (kIsWeb) {
      final drafts = await _getWebDrafts();
      final count = drafts.length;
      await _saveWebDrafts([]);
      return count;
    } else {
      final db = await database;
      return await db.delete('drafts');
    }
  }

  /// Delete draft file from filesystem (mobile only)
  Future<bool> deleteDraftFile(String filePath) async {
    if (kIsWeb) {
      // Web doesn't use local files in the same way
      return true;
    }
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error deleting file: $e');
      return false;
    }
  }

  /// Close database connection
  Future<void> close() async {
    if (kIsWeb) {
      // SharedPreferences doesn't need to be closed
      return;
    }
    final db = await database;
    db.close();
    _database = null;
  }
}
