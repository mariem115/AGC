import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:idb_shim/idb_browser.dart';
import 'package:idb_shim/idb_shim.dart';

/// Service for storing and retrieving media blobs in IndexedDB (web)
/// Falls back to no-op on mobile platforms (files are stored directly)
class MediaBlobService {
  static final MediaBlobService _instance = MediaBlobService._internal();
  factory MediaBlobService() => _instance;
  MediaBlobService._internal();

  static const String _dbName = 'agc_media_blobs';
  static const int _dbVersion = 1;
  static const String _storeName = 'blobs';

  Database? _database;

  /// Initialize the IndexedDB database (web only)
  Future<Database?> get database async {
    if (!kIsWeb) return null;

    if (_database != null) return _database;

    try {
      final idbFactory = getIdbFactory();
      if (idbFactory == null) {
        debugPrint('MediaBlobService: IndexedDB not available');
        return null;
      }

      _database = await idbFactory.open(
        _dbName,
        version: _dbVersion,
        onUpgradeNeeded: (VersionChangeEvent event) {
          final db = event.database;
          if (!db.objectStoreNames.contains(_storeName)) {
            db.createObjectStore(_storeName);
          }
        },
      );

      return _database;
    } catch (e) {
      debugPrint('MediaBlobService: Error opening database: $e');
      return null;
    }
  }

  /// Generate a unique blob key
  String generateBlobKey({bool isVideo = false}) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = isVideo ? 'mp4' : 'png';
    return 'blob_${timestamp}_$extension';
  }

  /// Store a blob in IndexedDB
  /// Returns the key used to store the blob, or null on failure
  Future<String?> storeBlob(String key, Uint8List data) async {
    if (!kIsWeb) {
      // On mobile, we don't use IndexedDB - files are stored directly
      return key;
    }

    try {
      final db = await database;
      if (db == null) return null;

      final transaction = db.transaction(_storeName, idbModeReadWrite);
      final store = transaction.objectStore(_storeName);

      await store.put(data, key);
      await transaction.completed;

      debugPrint(
        'MediaBlobService: Stored blob with key: $key (${data.length} bytes)',
      );
      return key;
    } catch (e) {
      debugPrint('MediaBlobService: Error storing blob: $e');
      return null;
    }
  }

  /// Retrieve a blob from IndexedDB
  /// Returns null if not found or on failure
  Future<Uint8List?> getBlob(String key) async {
    if (!kIsWeb) return null;

    try {
      final db = await database;
      if (db == null) return null;

      final transaction = db.transaction(_storeName, idbModeReadOnly);
      final store = transaction.objectStore(_storeName);

      final result = await store.getObject(key);
      await transaction.completed;

      if (result == null) {
        debugPrint('MediaBlobService: Blob not found for key: $key');
        return null;
      }

      // Handle different possible return types
      if (result is Uint8List) {
        return result;
      } else if (result is List) {
        return Uint8List.fromList(result.cast<int>());
      }

      debugPrint(
        'MediaBlobService: Unexpected blob type: ${result.runtimeType}',
      );
      return null;
    } catch (e) {
      debugPrint('MediaBlobService: Error getting blob: $e');
      return null;
    }
  }

  /// Check if a blob exists in IndexedDB
  Future<bool> hasBlob(String key) async {
    if (!kIsWeb) return false;

    try {
      final db = await database;
      if (db == null) return false;

      final transaction = db.transaction(_storeName, idbModeReadOnly);
      final store = transaction.objectStore(_storeName);

      final result = await store.getObject(key);
      await transaction.completed;

      return result != null;
    } catch (e) {
      debugPrint('MediaBlobService: Error checking blob: $e');
      return false;
    }
  }

  /// Delete a blob from IndexedDB
  Future<bool> deleteBlob(String key) async {
    if (!kIsWeb) return true;

    try {
      final db = await database;
      if (db == null) return false;

      final transaction = db.transaction(_storeName, idbModeReadWrite);
      final store = transaction.objectStore(_storeName);

      await store.delete(key);
      await transaction.completed;

      debugPrint('MediaBlobService: Deleted blob with key: $key');
      return true;
    } catch (e) {
      debugPrint('MediaBlobService: Error deleting blob: $e');
      return false;
    }
  }

  /// Delete multiple blobs from IndexedDB
  Future<void> deleteBlobs(List<String> keys) async {
    for (final key in keys) {
      await deleteBlob(key);
    }
  }

  /// Clear all blobs from IndexedDB
  Future<bool> clearAllBlobs() async {
    if (!kIsWeb) return true;

    try {
      final db = await database;
      if (db == null) return false;

      final transaction = db.transaction(_storeName, idbModeReadWrite);
      final store = transaction.objectStore(_storeName);

      await store.clear();
      await transaction.completed;

      debugPrint('MediaBlobService: Cleared all blobs');
      return true;
    } catch (e) {
      debugPrint('MediaBlobService: Error clearing blobs: $e');
      return false;
    }
  }

  /// Close the database connection
  Future<void> close() async {
    _database?.close();
    _database = null;
  }
}
