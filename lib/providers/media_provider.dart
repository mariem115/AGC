import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/media_item.dart';
import '../services/media_service.dart';

/// Media state provider
class MediaProvider extends ChangeNotifier {
  final MediaService _mediaService = MediaService();
  
  bool _isLoading = false;
  bool _isUploading = false;
  double _uploadProgress = 0;
  String? _error;
  
  List<MediaItem> _localImages = [];
  List<String> _serverMediaIds = [];
  
  bool get isLoading => _isLoading;
  bool get isUploading => _isUploading;
  double get uploadProgress => _uploadProgress;
  String? get error => _error;
  List<MediaItem> get localImages => _localImages;
  List<String> get serverMediaIds => _serverMediaIds;
  
  /// Load local images
  Future<void> loadLocalImages() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      _localImages = await _mediaService.getLocalImages();
    } catch (e) {
      _error = 'Erreur lors du chargement des images: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// Load server media for a reference
  Future<void> loadServerMedia(int referenceId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      _serverMediaIds = await _mediaService.getMediaIds(referenceId);
    } catch (e) {
      _error = 'Erreur lors du chargement des médias: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// Upload image
  Future<bool> uploadImage({
    required File file,
    required int referenceId,
    required int referenceType,
    required int mediaType,
    required String imageName,
  }) async {
    _isUploading = true;
    _uploadProgress = 0;
    _error = null;
    notifyListeners();
    
    try {
      final result = await _mediaService.uploadImage(
        file: file,
        referenceId: referenceId,
        referenceType: referenceType,
        mediaType: mediaType,
        imageName: imageName,
      );
      
      if (!result.isSuccess) {
        _error = result.error;
        return false;
      }
      
      _uploadProgress = 1.0;
      return true;
    } catch (e) {
      _error = 'Erreur lors de l\'upload: $e';
      return false;
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }
  
  /// Save image locally
  Future<String?> saveImageLocally(File image, String name) async {
    try {
      final path = await _mediaService.saveImageLocally(image, name);
      if (path != null) {
        await loadLocalImages();
      }
      return path;
    } catch (e) {
      _error = 'Erreur lors de la sauvegarde: $e';
      notifyListeners();
      return null;
    }
  }
  
  /// Delete local image
  Future<bool> deleteLocalImage(String path) async {
    try {
      final success = await _mediaService.deleteLocalImage(path);
      if (success) {
        _localImages.removeWhere((item) => item.path == path);
        notifyListeners();
      }
      return success;
    } catch (e) {
      _error = 'Erreur lors de la suppression: $e';
      notifyListeners();
      return false;
    }
  }
  
  /// Get image URL
  String getImageUrl(int imageId, {bool thumbnail = false}) {
    return _mediaService.getImageUrl(imageId, thumbnail: thumbnail);
  }
  
  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
  
  /// Clear data
  void clear() {
    _localImages = [];
    _serverMediaIds = [];
    _error = null;
    notifyListeners();
  }
}
