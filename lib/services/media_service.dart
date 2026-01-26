import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../config/constants.dart';
import '../models/media_item.dart';
import 'api_service.dart';

/// Service for handling media operations (upload, download, local storage)
class MediaService {
  static final MediaService _instance = MediaService._internal();
  factory MediaService() => _instance;
  MediaService._internal();
  
  final ApiService _api = ApiService();
  
  /// Upload an image to the server
  Future<UploadResult> uploadImage({
    required File file,
    required int referenceId,
    required int referenceType,
    required int mediaType,
    required String imageName,
  }) async {
    try {
      final fileBytes = await file.readAsBytes();
      
      final response = await _api.uploadFile(
        action: AppConstants.actionUploadImage,
        file: file,
        fields: {
          'referenceId': referenceId.toString(),
          'referenceType': referenceType.toString(),
          'mediaType': mediaType.toString(),
          'imageName': imageName,
          'length': fileBytes.length.toString(),
        },
      );
      
      if (!response.isSuccess) {
        return UploadResult.failure(response.error ?? 'Erreur lors de l\'upload');
      }
      
      final data = response.data;
      
      // Check response - success returns the new image ID
      if (data is String) {
        if (data == '-1') {
          return UploadResult.failure('Erreur lors de l\'upload');
        }
        
        final imageId = int.tryParse(data);
        if (imageId != null) {
          return UploadResult.success(imageId);
        }
      }
      
      if (data is int) {
        return UploadResult.success(data);
      }
      
      return UploadResult.failure('Réponse invalide du serveur');
    } catch (e) {
      return UploadResult.failure('Erreur: $e');
    }
  }
  
  /// Get media IDs for a reference
  Future<List<String>> getMediaIds(int referenceId) async {
    try {
      final response = await _api.get(
        AppConstants.actionGetIds,
        {'productId': referenceId.toString()},
      );
      
      if (!response.isSuccess) {
        return [];
      }
      
      final data = response.data;
      
      // Parse legacy format: "ok|id1|id2|id3|..."
      if (data is String && data.startsWith('ok')) {
        final parts = data.substring(2).split('|');
        return parts.where((p) => p.isNotEmpty).toList();
      }
      
      // Handle JSON format
      if (data is List) {
        return data.map((e) => e.toString()).toList();
      }
      
      return [];
    } catch (_) {
      return [];
    }
  }
  
  /// Get image URL for server images
  String getImageUrl(int imageId, {bool thumbnail = false}) {
    return _api.getImageUrl(imageId, thumbnail: thumbnail);
  }
  
  /// Get local images from the app directory
  Future<List<MediaItem>> getLocalImages() async {
    try {
      final directory = await _getLocalMediaDirectory();
      if (!await directory.exists()) {
        return [];
      }
      
      final files = directory.listSync()
          .whereType<File>()
          .where((f) => _isImageFile(f.path))
          .toList();
      
      // Sort by modification time (newest first)
      files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      
      return files.map((f) => MediaItem.local(
        path: f.path,
        name: f.path.split(Platform.pathSeparator).last,
      )).toList();
    } catch (_) {
      return [];
    }
  }
  
  /// Save image locally
  Future<String?> saveImageLocally(File image, String name) async {
    try {
      final directory = await _getLocalMediaDirectory();
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      
      final fileName = '${name}_${DateTime.now().millisecondsSinceEpoch}.png';
      final newPath = '${directory.path}${Platform.pathSeparator}$fileName';
      
      await image.copy(newPath);
      return newPath;
    } catch (_) {
      return null;
    }
  }
  
  /// Delete local image
  Future<bool> deleteLocalImage(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
  
  /// Get the local media directory
  Future<Directory> _getLocalMediaDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}${Platform.pathSeparator}AGC');
  }
  
  /// Check if file is an image
  bool _isImageFile(String path) {
    final ext = path.toLowerCase();
    return ext.endsWith('.png') || 
           ext.endsWith('.jpg') || 
           ext.endsWith('.jpeg') ||
           ext.endsWith('.gif') ||
           ext.endsWith('.webp');
  }
}

/// Upload result wrapper
class UploadResult {
  final bool isSuccess;
  final int? imageId;
  final String? error;
  
  UploadResult._({required this.isSuccess, this.imageId, this.error});
  
  factory UploadResult.success(int imageId) => 
      UploadResult._(isSuccess: true, imageId: imageId);
  
  factory UploadResult.failure(String error) => 
      UploadResult._(isSuccess: false, error: error);
}
