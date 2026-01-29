import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../../config/theme.dart';
import '../../models/draft_item.dart';
import '../../providers/draft_provider.dart';
import '../../providers/media_provider.dart';
import '../../services/crop_service.dart';
import '../../services/media_service.dart';
import '../../utils/download_helper.dart' as download_helper;
import '../../widgets/create_details_modal.dart';
import '../../widgets/zoom_select_screen.dart';

/// Photo/Video review screen after capture or when editing a draft
class PhotoReviewScreen extends StatefulWidget {
  final String imagePath;
  final bool isVideo;
  final int? draftId;

  const PhotoReviewScreen({
    super.key,
    required this.imagePath,
    this.isVideo = false,
    this.draftId,
  });

  @override
  State<PhotoReviewScreen> createState() => _PhotoReviewScreenState();
}

class _PhotoReviewScreenState extends State<PhotoReviewScreen> {
  VideoPlayerController? _videoController;
  bool _isVideoPlaying = false;
  DraftItem? _existingDraft;
  bool _isLoading = false;
  bool _isSaving = false;
  
  /// Working media path - may be different from widget.imagePath if cropped
  String? _workingMediaPath;
  
  /// Whether we're currently using a cropped version (always an image)
  bool _isUsingCroppedMedia = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // Load existing draft if editing
    if (widget.draftId != null) {
      setState(() => _isLoading = true);
      final draft = await context.read<DraftProvider>().getDraftById(
        widget.draftId!,
      );
      setState(() {
        _existingDraft = draft;
        _isLoading = false;
      });
    }

    // Initialize video player if needed
    if (widget.isVideo) {
      // On web, use networkUrl since dart:io File is not supported
      if (kIsWeb) {
        _videoController =
            VideoPlayerController.networkUrl(Uri.parse(widget.imagePath))
              ..initialize().then((_) {
                if (mounted) {
                  setState(() {});
                  _videoController!.setLooping(true);
                }
              });
      } else {
        _videoController = VideoPlayerController.file(File(widget.imagePath))
          ..initialize().then((_) {
            if (mounted) {
              setState(() {});
              _videoController!.setLooping(true);
            }
          });
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    // Clean up temporary cropped file if exists
    _cleanupTempCroppedFile();
    super.dispose();
  }
  
  /// Clean up temporary cropped file
  Future<void> _cleanupTempCroppedFile() async {
    if (_workingMediaPath != null && _isUsingCroppedMedia) {
      try {
        final file = File(_workingMediaPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('Error cleaning up temp cropped file: $e');
      }
    }
  }

  void _toggleVideoPlayback() {
    if (_videoController == null) return;

    setState(() {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
        _isVideoPlaying = false;
      } else {
        _videoController!.play();
        _isVideoPlaying = true;
      }
    });
  }

  /// Get proper file extension from path or default based on media type
  String _getFileExtension(String path) {
    final ext = p.extension(path).toLowerCase();
    if (ext.isNotEmpty) return ext;
    return widget.isVideo ? '.mp4' : '.png';
  }

  Future<void> _downloadMedia() async {
    try {
      if (kIsWeb) {
        // Web: use download helper with proper filename and extension
        final extension = _getFileExtension(widget.imagePath);
        final filename =
            'AGC_${DateTime.now().millisecondsSinceEpoch}$extension';
        download_helper.downloadFile(widget.imagePath, filename);
      } else {
        // Mobile: save to device gallery with proper extension
        await _saveToGallery();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kIsWeb
                  ? (widget.isVideo ? 'Vidéo téléchargée' : 'Photo téléchargée')
                  : (widget.isVideo
                        ? 'Vidéo téléchargée dans la galerie'
                        : 'Photo téléchargée dans la galerie'),
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors du téléchargement: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Save media to device gallery with proper filename and extension
  Future<void> _saveToGallery() async {
    final file = File(widget.imagePath);
    if (!await file.exists()) {
      throw Exception('Fichier non trouvé');
    }

    final extension = _getFileExtension(widget.imagePath);
    final name = 'AGC_${DateTime.now().millisecondsSinceEpoch}$extension';

    // Determine the file path to save - ensure it has a proper extension
    String filePathToSave = widget.imagePath;
    File? tempFile;

    // If the original file doesn't have an extension, copy it to a temp file with the correct extension
    final currentExt = p.extension(widget.imagePath).toLowerCase();
    if (currentExt.isEmpty) {
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}${Platform.pathSeparator}$name';
      tempFile = await file.copy(tempPath);
      filePathToSave = tempPath;
    }

    try {
      // Use gal package to save to gallery
      if (widget.isVideo) {
        await Gal.putVideo(filePathToSave);
      } else {
        await Gal.putImage(filePathToSave);
      }
    } finally {
      // Clean up temp file if created
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {
          // Ignore cleanup errors
        }
      }
    }
  }

  /// Get the current media path (cropped or original)
  String get _currentMediaPath => _workingMediaPath ?? widget.imagePath;
  
  /// Whether the current media is a video (false if cropped, since crop produces image)
  bool get _currentIsVideo => _isUsingCroppedMedia ? false : widget.isVideo;

  void _openCreateDetailsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CreateDetailsModal(
        imagePath: _currentMediaPath,
        isVideo: _currentIsVideo,
        existingDraft: _existingDraft,
        onSaveDraft: _onSaveDraft,
        onSaveFinal: _onSaveFinal,
      ),
    );
  }
  
  /// Open zoom and select mode for cropping
  /// Only available on mobile (not web)
  Future<void> _openZoomSelectMode() async {
    if (kIsWeb) {
      // Web not supported for this feature
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Recadrage non disponible sur le web'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
      return;
    }
    
    final result = await Navigator.push<ZoomSelectResult>(
      context,
      MaterialPageRoute(
        builder: (context) => ZoomSelectScreen(
          mediaPath: widget.imagePath,
          isVideo: widget.isVideo,
          videoController: widget.isVideo ? _videoController : null,
        ),
      ),
    );
    
    if (result != null && mounted) {
      // Store the cropped media path
      setState(() {
        _workingMediaPath = result.croppedPath;
        _isUsingCroppedMedia = true;
      });
      
      // Immediately open the create details modal with cropped media
      _openCreateDetailsModal();
    }
  }

  /// Copy temp file to persistent storage for drafts
  Future<String?> _copyToPersistentStorage(String tempPath) async {
    try {
      final tempFile = File(tempPath);
      if (!await tempFile.exists()) return null;

      final appDir = await getApplicationDocumentsDirectory();
      final draftsDir = Directory(
        '${appDir.path}${Platform.pathSeparator}AGC${Platform.pathSeparator}drafts',
      );
      if (!await draftsDir.exists()) {
        await draftsDir.create(recursive: true);
      }

      final ext = _getFileExtension(tempPath);
      final newPath =
          '${draftsDir.path}${Platform.pathSeparator}draft_${DateTime.now().millisecondsSinceEpoch}$ext';
      await tempFile.copy(newPath);

      return newPath;
    } catch (e) {
      debugPrint('Error copying to persistent storage: $e');
      return null;
    }
  }

  Future<void> _onSaveDraft(DraftItem draft) async {
    setState(() => _isSaving = true);
    Navigator.pop(context); // Close modal

    final draftProvider = context.read<DraftProvider>();

    try {
      String persistentPath = draft.filePath;
      Uint8List? fileBytes;

      // On web, we need to fetch the file bytes from the blob URL
      // and store them in IndexedDB for persistence across page refreshes
      if (kIsWeb && _existingDraft == null) {
        try {
          final response = await http.get(Uri.parse(widget.imagePath));
          if (response.statusCode == 200) {
            fileBytes = response.bodyBytes;
            debugPrint(
              'PhotoReviewScreen: Fetched ${fileBytes.length} bytes from blob URL',
            );
          } else {
            throw Exception('Failed to fetch file bytes from blob URL');
          }
        } catch (e) {
          debugPrint('PhotoReviewScreen: Error fetching blob URL: $e');
          throw Exception('Impossible de récupérer les données du fichier');
        }
      }

      // Copy temp file to persistent location (mobile only)
      if (!kIsWeb && _existingDraft == null) {
        // Only copy for new drafts, not when updating existing ones
        final copied = await _copyToPersistentStorage(draft.filePath);
        if (copied != null) {
          persistentPath = copied;
        } else {
          // File copy failed on mobile - cannot save draft without persistent file
          throw Exception(
            'Impossible de copier le fichier vers le stockage persistant',
          );
        }
      }

      if (_existingDraft != null) {
        // Update existing draft (path is already persistent)
        final success = await draftProvider.updateDraft(draft);
        if (!success) {
          throw Exception(
            draftProvider.error ?? 'Échec de la mise à jour du brouillon',
          );
        }
      } else {
        // Save new draft with persistent path and file bytes (for web)
        final savedDraft = await draftProvider.saveDraft(
          filePath: persistentPath,
          isVideo: draft.isVideo,
          referenceId: draft.referenceId,
          referenceName: draft.referenceName,
          referenceType: draft.referenceType,
          description: draft.description,
          qualityStatus: draft.qualityStatus,
          fileBytes: fileBytes, // Pass file bytes for IndexedDB storage on web
        );

        // Check if save was successful
        if (savedDraft == null) {
          throw Exception(
            draftProvider.error ?? 'Échec de la sauvegarde du brouillon',
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Brouillon sauvegardé'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
        Navigator.pop(context); // Go back
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la sauvegarde: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _onSaveFinal(DraftItem draft) async {
    setState(() => _isSaving = true);
    Navigator.pop(context); // Close modal

    final mediaProvider = context.read<MediaProvider>();
    final draftProvider = context.read<DraftProvider>();
    final mediaService = MediaService();
    final cropService = CropService();

    // Validate required fields before proceeding
    // This prevents _Namespace errors by ensuring we have valid primitive data
    if (draft.referenceId == null || draft.referenceType == null) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Référence invalide - veuillez réessayer'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
      return;
    }

    // DEBUG: Log draft data to help diagnose serialization issues
    debugPrint('=== SAVE FINAL DEBUG ===');
    debugPrint(
      'referenceId: ${draft.referenceId} (${draft.referenceId.runtimeType})',
    );
    debugPrint(
      'referenceType: ${draft.referenceType} (${draft.referenceType.runtimeType})',
    );
    debugPrint(
      'qualityStatus: ${draft.qualityStatus} (${draft.qualityStatus.runtimeType})',
    );
    debugPrint(
      'referenceName: ${draft.referenceName} (${draft.referenceName.runtimeType})',
    );
    debugPrint(
      'description: ${draft.description} (${draft.description.runtimeType})',
    );
    debugPrint('isUsingCroppedMedia: $_isUsingCroppedMedia');
    debugPrint('========================');

    // Track temporary composite file for cleanup
    String? compositeFilePath;

    try {
      String savedPath = draft.filePath;

      // === Step 1: Upload to server (mobile only - web doesn't support dart:io File) ===
      // On web, files are blob URLs that can't be accessed via dart:io
      // This prevents "Unsupported operation: _Namespace" error on web platform
      if (!kIsWeb) {
        // Determine what file to upload:
        // - If using cropped media, generate composite image first
        // - Otherwise, upload the original file
        File fileToUpload;
        
        if (_isUsingCroppedMedia && _workingMediaPath != null) {
          // Generate composite image with original + cropped detail + metadata
          debugPrint('Generating composite image...');
          compositeFilePath = await cropService.generateCompositeImage(
            originalPath: widget.imagePath,
            croppedPath: _workingMediaPath!,
            qualityStatus: draft.qualityStatus,
            description: draft.description,
            referenceName: draft.referenceName,
            createdAt: draft.createdAt,
          );
          
          if (compositeFilePath == null) {
            throw Exception('Échec de la génération de l\'image composite');
          }
          
          debugPrint('Composite image generated at: $compositeFilePath');
          fileToUpload = File(compositeFilePath);
        } else {
          fileToUpload = File(draft.filePath);
        }
        
        if (await fileToUpload.exists()) {
          // Prepare file name for upload
          final ext = _getFileExtension(fileToUpload.path);
          final imageName = 'AGC_${DateTime.now().millisecondsSinceEpoch}$ext';

          // Extract primitive values explicitly to avoid serialization issues
          final int refId = draft.referenceId!;
          final int refType = draft.referenceType!;
          final int quality = draft.qualityStatus;

          // Upload to server with:
          // - referenceId: selected reference ID (int)
          // - referenceType: selected reference type (1=Component, 2=Semi-final, 3=Final)
          // - mediaType: quality status (4=Bonne/OK, 5=Mauvaise/NOK, 6=Neutre/Neutral)
          // - isVideo: false for composite images (always an image)
          final uploadResult = await mediaService.uploadMedia(
            file: fileToUpload,
            referenceId: refId,
            referenceType: refType,
            mediaType: quality,
            fileName: imageName,
            isVideo: false, // Composite is always an image
          );

          if (!uploadResult.isSuccess) {
            // Server upload failed - show error but continue with local save
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Erreur serveur: ${uploadResult.error ?? "Upload échoué"}\nSauvegarde locale en cours...',
                  ),
                  backgroundColor: AppColors.warning,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          } else {
            debugPrint('Upload success! Image ID: ${uploadResult.imageId}');
          }
        }
      }

      // === Step 2: Save locally ===
      // Save the composite image (or original file) to persistent storage
      if (!kIsWeb) {
        // Determine which file to save locally
        File fileToSave;
        if (compositeFilePath != null) {
          fileToSave = File(compositeFilePath);
        } else {
          fileToSave = File(draft.filePath);
        }
        
        if (await fileToSave.exists()) {
          final saved = await mediaProvider.saveMediaLocally(
            fileToSave,
            draft.referenceName ?? 'AGC_Photo',
            isVideo: false, // Composite is always an image
          );
          if (saved != null) {
            savedPath = saved;
          }
        }
      }

      // === Step 3: Update local database ===
      if (_existingDraft != null) {
        // Mark existing draft as finalized with updated path
        await draftProvider.finalizeDraft(draft.copyWith(filePath: savedPath));
      } else {
        // Save as new finalized record (isDraft will be set to false after)
        final savedDraft = await draftProvider.saveDraft(
          filePath: savedPath,
          isVideo: false, // Composite is always an image
          referenceId: draft.referenceId,
          referenceName: draft.referenceName,
          referenceType: draft.referenceType,
          description: draft.description,
          qualityStatus: draft.qualityStatus,
        );
        if (savedDraft != null) {
          await draftProvider.finalizeDraft(savedDraft);
        }
      }

      // Refresh gallery to show the new image
      await mediaProvider.loadLocalImages();

      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Média sauvegardé avec succès'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
        Navigator.pop(context); // Go back
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la sauvegarde: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      // Clean up temporary composite file
      if (compositeFilePath != null) {
        await cropService.cleanupTempFile(compositeFilePath);
      }
    }
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: AppColors.error),
            SizedBox(width: 12),
            Text(
              'Supprimer',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Text(
          widget.isVideo
              ? 'Voulez-vous vraiment supprimer cette vidéo ?'
              : 'Voulez-vous vraiment supprimer cette photo ?',
          style: const TextStyle(fontFamily: 'Poppins'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              await _deleteMedia();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMedia() async {
    setState(() => _isSaving = true);
    try {
      // Delete existing draft if editing
      if (_existingDraft != null) {
        await context.read<DraftProvider>().deleteDraft(_existingDraft!);
      } else if (!kIsWeb) {
        // Only delete file on mobile (web uses blob URLs that don't need deletion)
        try {
          final file = File(widget.imagePath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (fileError) {
          // Ignore file deletion errors, the important thing is to navigate back
          debugPrint('Could not delete file: $fileError');
        }
      }
      // On web, just navigate back without file deletion

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isVideo ? 'Vidéo supprimée' : 'Photo supprimée',
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la suppression: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _existingDraft != null
              ? 'Modifier le média'
              : (widget.isVideo ? 'Aperçu vidéo' : 'Aperçu photo'),
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // Download/Share button
          IconButton(
            onPressed: _isSaving ? null : _downloadMedia,
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.download_rounded,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            tooltip: 'Télécharger',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Media preview
                Expanded(child: _buildMediaPreview()),

                // Action buttons
                _buildActionButtons(),
              ],
            ),
    );
  }

  Widget _buildMediaPreview() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Media content
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: widget.isVideo ? _buildVideoPreview() : _buildImagePreview(),
          ),
          
          // Zoom/Crop icon (only on mobile, not web)
          // For videos, position below the video indicator; for images, top-right
          if (!kIsWeb)
            Positioned(
              top: widget.isVideo ? 52 : 12, // Below video indicator if video
              right: 12,
              child: _buildZoomIcon(),
            ),
        ],
      ),
    );
  }
  
  /// Build the zoom/crop icon button
  Widget _buildZoomIcon() {
    return GestureDetector(
      onTap: _isSaving ? null : _openZoomSelectMode,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.crop_free_rounded,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    final errorWidget = Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 64,
            color: AppColors.textLight.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          const Text(
            'Impossible de charger l\'image',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );

    if (kIsWeb) {
      return Image.network(
        widget.imagePath,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => errorWidget,
      );
    }

    return Image.file(
      File(widget.imagePath),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => errorWidget,
    );
  }

  Widget _buildVideoPreview() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),
        // Play/Pause button overlay
        GestureDetector(
          onTap: _toggleVideoPlayback,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isVideoPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 36,
            ),
          ),
        ),
        // Video indicator
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam_rounded, color: Colors.white, size: 16),
                SizedBox(width: 4),
                Text(
                  'Vidéo',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Main action button - Crée Détails
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _openCreateDetailsModal,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.edit_note_rounded),
                label: Text(
                  _isSaving
                      ? 'Sauvegarde...'
                      : (_existingDraft != null
                            ? 'Modifier Détails'
                            : 'Crée Détails'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Delete button
            TextButton.icon(
              onPressed: _isSaving ? null : _showDeleteConfirmation,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Supprimer'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
                textStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
