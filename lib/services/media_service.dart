import 'dart:io';
import 'package:flutter/foundation.dart';
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
  
  /// Upload media (image or video) to the server
  /// All fields are converted to strings explicitly to avoid serialization issues
  /// 
  /// Parameters:
  /// - [file]: The media file to upload
  /// - [referenceId]: ID of the reference this media belongs to
  /// - [referenceType]: Type of reference (1=Component, 2=Semi-final, 3=Final)
  /// - [mediaType]: Quality status (4=OK, 5=NOK, 6=Neutral)
  /// - [fileName]: Name for the uploaded file
  /// - [isVideo]: Whether this is a video (affects file field name)
  Future<UploadResult> uploadMedia({
    required File file,
    required int referenceId,
    required int referenceType,
    required int mediaType,
    required String fileName,
    bool isVideo = false,
  }) async {
    try {
      final fileBytes = await file.readAsBytes();
      
      // Build clean payload with explicit string conversion
      // This ensures only primitive String values are sent to avoid _Namespace errors
      final fields = <String, String>{
        'referenceId': referenceId.toString(),
        'referenceType': referenceType.toString(),
        'mediaType': mediaType.toString(),
        'imageName': fileName, // Field name stays 'imageName' for backend compatibility
        'length': fileBytes.length.toString(),
      };
      
      // DEBUG: Log payload before sending to help diagnose serialization issues
      debugPrint('=== UPLOAD PAYLOAD (${isVideo ? "VIDEO" : "IMAGE"}) ===');
      debugPrint('referenceId: ${fields['referenceId']} (${fields['referenceId'].runtimeType})');
      debugPrint('referenceType: ${fields['referenceType']} (${fields['referenceType'].runtimeType})');
      debugPrint('mediaType: ${fields['mediaType']} (${fields['mediaType'].runtimeType})');
      debugPrint('fileName: ${fields['imageName']} (${fields['imageName'].runtimeType})');
      debugPrint('length: ${fields['length']} (${fields['length'].runtimeType})');
      debugPrint('isVideo: $isVideo');
      debugPrint('======================');
      
      // Use same endpoint and file field for both - backend handles both media types
      final response = await _api.uploadFile(
        action: AppConstants.actionUploadImage,
        file: file,
        fields: fields,
        fileField: 'image', // Same field for both as confirmed by user
      );
      
      if (!response.isSuccess) {
        return UploadResult.failure(response.error ?? 'Erreur lors de l\'upload');
      }
      
      final data = response.data;
      
      // Check response - success returns the new media ID
      if (data is String) {
        if (data == '-1') {
          return UploadResult.failure('Erreur lors de l\'upload');
        }
        
        final mediaId = int.tryParse(data);
        if (mediaId != null) {
          return UploadResult.success(mediaId);
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
  
  /// Legacy method for backward compatibility - calls uploadMedia
  @Deprecated('Use uploadMedia instead')
  Future<UploadResult> uploadImage({
    required File file,
    required int referenceId,
    required int referenceType,
    required int mediaType,
    required String imageName,
  }) {
    return uploadMedia(
      file: file,
      referenceId: referenceId,
      referenceType: referenceType,
      mediaType: mediaType,
      fileName: imageName,
      isVideo: false,
    );
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
  
  /// Get local media (images and videos) from the app directory
  Future<List<MediaItem>> getLocalMedia() async {
    try {
      final directory = await _getLocalMediaDirectory();
      if (!await directory.exists()) {
        return [];
      }
      
      final files = directory.listSync()
          .whereType<File>()
          .where((f) => _isMediaFile(f.path))
          .toList();
      
      // Sort by modification time (newest first)
      files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      
      return files.map((f) => MediaItem.local(
        path: f.path,
        name: f.path.split(Platform.pathSeparator).last,
        isVideo: _isVideoFile(f.path),
      )).toList();
    } catch (_) {
      return [];
    }
  }
  
  /// Legacy method for backward compatibility
  Future<List<MediaItem>> getLocalImages() => getLocalMedia();
  
  /// Save media locally (image or video)
  /// Preserves original file extension for proper media type handling
  Future<String?> saveMediaLocally(File media, String name, {bool isVideo = false}) async {
    try {
      final directory = await _getLocalMediaDirectory();
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      
      // Determine file extension from original file or use default based on media type
      final originalExt = _getFileExtension(media.path);
      final extension = originalExt.isNotEmpty ? originalExt : (isVideo ? '.mp4' : '.png');
      final fileName = '${name}_${DateTime.now().millisecondsSinceEpoch}$extension';
      final newPath = '${directory.path}${Platform.pathSeparator}$fileName';
      
      await media.copy(newPath);
      return newPath;
    } catch (_) {
      return null;
    }
  }
  
  /// Legacy method for backward compatibility
  Future<String?> saveImageLocally(File image, String name) {
    return saveMediaLocally(image, name, isVideo: false);
  }
  
  /// Get file extension from path
  String _getFileExtension(String path) {
    final lastDot = path.lastIndexOf('.');
    if (lastDot == -1 || lastDot == path.length - 1) return '';
    return path.substring(lastDot).toLowerCase();
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
  
  /// Check if file is a video
  bool _isVideoFile(String path) {
    final ext = path.toLowerCase();
    return ext.endsWith('.mp4') || 
           ext.endsWith('.mov') || 
           ext.endsWith('.avi') ||
           ext.endsWith('.mkv') ||
           ext.endsWith('.webm') ||
           ext.endsWith('.3gp');
  }
  
  /// Check if file is any supported media type (image or video)
  bool _isMediaFile(String path) {
    return _isImageFile(path) || _isVideoFile(path);
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
