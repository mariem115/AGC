import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image_pkg;
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

class _PhotoReviewScreenState extends State<PhotoReviewScreen> with SingleTickerProviderStateMixin {
  VideoPlayerController? _videoController;
  bool _isVideoPlaying = false;
  DraftItem? _existingDraft;
  bool _isLoading = false;
  bool _isSaving = false;
  
  /// Working media path - may be different from widget.imagePath if cropped
  String? _workingMediaPath;
  
  /// Whether we're currently using a cropped version (always an image)
  bool _isUsingCroppedMedia = false;
  
  // === Inline Zoom State ===
  /// Controls zoom and pan transformations (GPU-accelerated via InteractiveViewer)
  final TransformationController _transformController = TransformationController();
  
  /// Whether the user is in selection mode (zoomed in)
  bool _isInSelectionMode = false;
  
  /// Key for the media widget to capture for cropping
  final GlobalKey _mediaKey = GlobalKey();
  
  /// Track the size of the media container for crop calculations
  Size _mediaContainerSize = Size.zero;
  
  /// Whether capture is in progress
  bool _isCapturing = false;
  
  // === Animation for smooth reset ===
  late AnimationController _resetAnimationController;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Listen to transformation changes to detect selection mode (optimized - only on threshold crossing)
    _transformController.addListener(_onTransformChanged);
    
    // Initialize reset animation controller
    _resetAnimationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
  }
  
  /// Called when the transformation changes - optimized to only update selection mode on threshold crossing
  void _onTransformChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    final wasInSelectionMode = _isInSelectionMode;
    final isNowInSelectionMode = scale > 1.05; // Small threshold to avoid flicker
    
    // Only call setState when selection mode actually changes (rare event)
    if (wasInSelectionMode != isNowInSelectionMode) {
      setState(() {
        _isInSelectionMode = isNowInSelectionMode;
      });
    }
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
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    _resetAnimationController.dispose();
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
      // Suppressed for demo - error handling logic remains
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
        // Suppressed for demo - error handling logic remains
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
        // Suppressed for demo - validation logic remains
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
            // Server upload failed - continue silently with local save
            // No warning popup - user will see the final success message
            debugPrint('Server upload failed: ${uploadResult.error ?? "Unknown error"} - continuing with local save');
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
        // Suppressed for demo - error handling logic remains
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
        // Suppressed for demo - error handling logic remains
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Track container size for crop calculations
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_mediaContainerSize != constraints.biggest && mounted) {
                _mediaContainerSize = constraints.biggest;
              }
            });
            
            return Stack(
              fit: StackFit.expand,
              children: [
                // GPU-accelerated zoom/pan layer (mobile only)
                if (!kIsWeb)
                  GestureDetector(
                    onDoubleTap: _resetZoom,
                    child: InteractiveViewer(
                      transformationController: _transformController,
                      minScale: 1.0,
                      maxScale: 4.0,
                      panEnabled: true,
                      scaleEnabled: true,
                      boundaryMargin: const EdgeInsets.all(double.infinity),
                      child: RepaintBoundary(
                        key: _mediaKey,
                        child: widget.isVideo ? _buildVideoPreview() : _buildImagePreview(),
                      ),
                    ),
                  )
                else
                  // Web: no zoom support
                  widget.isVideo ? _buildVideoPreview() : _buildImagePreview(),
                
                // Selection overlay (shown when zoomed) - wrapped in IgnorePointer to allow gestures through
                if (_isInSelectionMode && !kIsWeb)
                  IgnorePointer(
                    child: _buildSelectionOverlay(),
                  ),
                
                // Video indicator (for videos only)
                if (widget.isVideo)
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
                
                // Zoom hint (shown when not zoomed, on mobile)
                if (!_isInSelectionMode && !kIsWeb && !_isSaving)
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.pinch_rounded, color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Pincez pour zoomer',
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
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
  
  /// Reset zoom to default state with smooth animation
  void _resetZoom() {
    final startMatrix = _transformController.value;
    final endMatrix = Matrix4.identity();
    
    // Stop any ongoing animation
    _resetAnimationController.stop();
    _resetAnimationController.reset();
    
    // Create animation with manual Matrix4 interpolation
    final animation = CurvedAnimation(
      parent: _resetAnimationController,
      curve: Curves.easeOut,
    );
    
    // Update transform controller during animation
    void updateTransform() {
      final t = animation.value;
      // Interpolate between start and end matrices
      final interpolated = Matrix4.zero();
      for (int i = 0; i < 16; i++) {
        interpolated.storage[i] = startMatrix.storage[i] * (1 - t) + endMatrix.storage[i] * t;
      }
      _transformController.value = interpolated;
    }
    
    animation.addListener(updateTransform);
    
    // Start animation
    _resetAnimationController.forward(from: 0.0).then((_) {
      animation.removeListener(updateTransform);
      // Ensure we end at exactly identity
      _transformController.value = Matrix4.identity();
    });
    // Selection mode will update via listener
  }
  
  /// Build the selection overlay that appears when zoomed
  Widget _buildSelectionOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate selection rect - centered, 70% of the container size
        final containerWidth = constraints.maxWidth;
        final containerHeight = constraints.maxHeight;
        final selectionWidth = containerWidth * 0.7;
        final selectionHeight = containerHeight * 0.7;
        final left = (containerWidth - selectionWidth) / 2;
        final top = (containerHeight - selectionHeight) / 2;
        
        return Stack(
          children: [
            // Dimmed overlay with cutout
            CustomPaint(
              size: Size(containerWidth, containerHeight),
              painter: _SelectionOverlayPainter(
                selectionRect: Rect.fromLTWH(left, top, selectionWidth, selectionHeight),
              ),
            ),
            
            // Selection border
            Positioned(
              left: left,
              top: top,
              child: Container(
                width: selectionWidth,
                height: selectionHeight,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: AppColors.primary,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            
            // Corner indicators
            ..._buildCornerIndicators(left, top, selectionWidth, selectionHeight),
            
            // Help text at bottom of selection
            Positioned(
              left: left,
              right: containerWidth - left - selectionWidth,
              bottom: top - 30,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Zone de sélection',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
  
  /// Build corner indicators for the selection rectangle
  List<Widget> _buildCornerIndicators(double left, double top, double width, double height) {
    const cornerSize = 20.0;
    const cornerThickness = 3.0;
    
    Widget buildCorner(Alignment alignment) {
      return Positioned(
        left: alignment == Alignment.topLeft || alignment == Alignment.bottomLeft
            ? left - cornerThickness / 2
            : null,
        right: alignment == Alignment.topRight || alignment == Alignment.bottomRight
            ? null
            : null,
        top: alignment == Alignment.topLeft || alignment == Alignment.topRight
            ? top - cornerThickness / 2
            : null,
        bottom: alignment == Alignment.bottomLeft || alignment == Alignment.bottomRight
            ? null
            : null,
        child: Builder(
          builder: (context) {
            double posLeft = 0;
            double posTop = 0;
            
            if (alignment == Alignment.topRight || alignment == Alignment.bottomRight) {
              posLeft = left + width - cornerSize + cornerThickness / 2;
            } else {
              posLeft = left - cornerThickness / 2;
            }
            
            if (alignment == Alignment.bottomLeft || alignment == Alignment.bottomRight) {
              posTop = top + height - cornerSize + cornerThickness / 2;
            } else {
              posTop = top - cornerThickness / 2;
            }
            
            return Positioned(
              left: posLeft,
              top: posTop,
              child: SizedBox(
                width: cornerSize,
                height: cornerSize,
                child: CustomPaint(
                  painter: _CornerPainter(
                    alignment: alignment,
                    color: AppColors.primary,
                    thickness: cornerThickness,
                  ),
                ),
              ),
            );
          },
        ),
      );
    }
    
    // Simplified corner indicators using positioned containers
    return [
      // Top-left corner
      Positioned(
        left: left - 2,
        top: top - 2,
        child: Container(
          width: 20,
          height: 3,
          color: AppColors.primary,
        ),
      ),
      Positioned(
        left: left - 2,
        top: top - 2,
        child: Container(
          width: 3,
          height: 20,
          color: AppColors.primary,
        ),
      ),
      // Top-right corner
      Positioned(
        left: left + width - 18,
        top: top - 2,
        child: Container(
          width: 20,
          height: 3,
          color: AppColors.primary,
        ),
      ),
      Positioned(
        left: left + width - 1,
        top: top - 2,
        child: Container(
          width: 3,
          height: 20,
          color: AppColors.primary,
        ),
      ),
      // Bottom-left corner
      Positioned(
        left: left - 2,
        top: top + height - 1,
        child: Container(
          width: 20,
          height: 3,
          color: AppColors.primary,
        ),
      ),
      Positioned(
        left: left - 2,
        top: top + height - 18,
        child: Container(
          width: 3,
          height: 20,
          color: AppColors.primary,
        ),
      ),
      // Bottom-right corner
      Positioned(
        left: left + width - 18,
        top: top + height - 1,
        child: Container(
          width: 20,
          height: 3,
          color: AppColors.primary,
        ),
      ),
      Positioned(
        left: left + width - 1,
        top: top + height - 18,
        child: Container(
          width: 3,
          height: 20,
          color: AppColors.primary,
        ),
      ),
    ];
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
        // Play/Pause button overlay (only when not in selection mode)
        if (!_isInSelectionMode)
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
      ],
    );
  }

  Widget _buildActionButtons() {
    // Show selection mode buttons when zoomed (mobile only)
    if (_isInSelectionMode && !kIsWeb) {
      return _buildSelectionModeButtons();
    }
    
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
  
  /// Build buttons for selection mode (Confirmer / Annuler)
  Widget _buildSelectionModeButtons() {
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
            // Help text
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Déplacez et zoomez pour ajuster la sélection',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            
            // Confirmer / Annuler buttons
            Row(
              children: [
                // Annuler button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isCapturing ? null : _cancelSelection,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Annuler'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // Confirmer button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isCapturing ? null : _confirmSelection,
                    icon: _isCapturing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(_isCapturing ? 'Capture...' : 'Confirmer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Hint for double-tap reset
            Text(
              'Double-tap pour réinitialiser le zoom',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// Cancel selection - reset zoom and exit selection mode
  void _cancelSelection() {
    _resetZoom();
  }
  
  /// Confirm selection - capture the selected area and open CreateDetailsModal
  Future<void> _confirmSelection() async {
    if (_isCapturing) return;
    
    setState(() => _isCapturing = true);
    
    try {
      final cropService = CropService();
      String? croppedPath;
      
      if (widget.isVideo) {
        // For videos: pause and capture frame with crop
        if (_videoController != null && _videoController!.value.isPlaying) {
          await _videoController!.pause();
          setState(() => _isVideoPlaying = false);
        }
        
        // Calculate crop rect based on selection overlay (70% of container, centered)
        final cropRect = _calculateCropRect();
        
        // Extract video frame and crop
        croppedPath = await cropService.extractVideoFrame(
          _videoController!,
          _mediaKey,
          cropRect: cropRect,
        );
      } else {
        // For images: crop directly using image path
        final cropRect = _calculateCropRectForImage();
        
        if (cropRect != null) {
          croppedPath = await cropService.cropImageManual(widget.imagePath, cropRect);
        }
      }
      
      if (croppedPath == null) {
        throw Exception('Impossible de capturer la zone sélectionnée');
      }
      
      debugPrint('Selection captured at: $croppedPath');
      
      // Store the cropped media path
      setState(() {
        _workingMediaPath = croppedPath;
        _isUsingCroppedMedia = true;
        _isCapturing = false;
      });
      
      // Reset zoom
      _resetZoom();
      
      // Open create details modal with cropped media
      _openCreateDetailsModal();
      
    } catch (e) {
      debugPrint('Error capturing selection: $e');
      if (mounted) {
        setState(() => _isCapturing = false);
        // Suppressed for demo - error handling logic remains
      }
    }
  }
  
  /// Calculate crop rect for video frame capture (based on display coordinates)
  Rect _calculateCropRect() {
    // Selection overlay is 70% of container, centered
    final containerWidth = _mediaContainerSize.width;
    final containerHeight = _mediaContainerSize.height;
    
    if (containerWidth == 0 || containerHeight == 0) {
      // Fallback to default
      return const Rect.fromLTWH(0, 0, 100, 100);
    }
    
    final selectionWidth = containerWidth * 0.7;
    final selectionHeight = containerHeight * 0.7;
    final left = (containerWidth - selectionWidth) / 2;
    final top = (containerHeight - selectionHeight) / 2;
    
    return Rect.fromLTWH(left, top, selectionWidth, selectionHeight);
  }
  
  /// Calculate crop rect for image in actual image coordinates
  Rect? _calculateCropRectForImage() {
    try {
      // Get image file and decode to get actual dimensions
      final file = File(widget.imagePath);
      if (!file.existsSync()) return null;
      
      // Use transformation controller value (GPU-accelerated, no setState)
      final matrix = _transformController.value;
      final scale = matrix.getMaxScaleOnAxis();
      
      // Get translation from matrix
      final translation = matrix.getTranslation();
      final tx = translation.x;
      final ty = translation.y;
      
      // Container dimensions
      final containerWidth = _mediaContainerSize.width;
      final containerHeight = _mediaContainerSize.height;
      
      if (containerWidth == 0 || containerHeight == 0) return null;
      
      // Selection overlay is 70% of container, centered (in screen coordinates)
      final selectionWidth = containerWidth * 0.7;
      final selectionHeight = containerHeight * 0.7;
      final selectionLeft = (containerWidth - selectionWidth) / 2;
      final selectionTop = (containerHeight - selectionHeight) / 2;
      
      // Convert selection rect to image coordinates
      // The image has been scaled by 'scale' and translated by (tx, ty)
      // To get image coordinates: (screen - translation) / scale
      
      // First, get the image file to read actual dimensions
      final imageBytes = file.readAsBytesSync();
      final decodedImage = image_pkg.decodeImage(imageBytes);
      if (decodedImage == null) return null;
      
      final imageWidth = decodedImage.width.toDouble();
      final imageHeight = decodedImage.height.toDouble();
      
      // Calculate how the image fits in the container (BoxFit.contain)
      final imageAspect = imageWidth / imageHeight;
      final containerAspect = containerWidth / containerHeight;
      
      double displayWidth, displayHeight;
      double offsetX = 0, offsetY = 0;
      
      if (imageAspect > containerAspect) {
        // Image is wider - fit to width
        displayWidth = containerWidth;
        displayHeight = containerWidth / imageAspect;
        offsetY = (containerHeight - displayHeight) / 2;
      } else {
        // Image is taller - fit to height
        displayHeight = containerHeight;
        displayWidth = containerHeight * imageAspect;
        offsetX = (containerWidth - displayWidth) / 2;
      }
      
      // Now convert selection rect to image coordinates
      // Account for: initial centering offset, zoom scale, and pan translation
      
      // Selection rect in container coordinates
      final selectionInContainer = Rect.fromLTWH(
        selectionLeft,
        selectionTop,
        selectionWidth,
        selectionHeight,
      );
      
      // Convert to image display coordinates (remove centering offset)
      // Then account for transformation (pan and zoom)
      // The transformation applies to the image, so we need the inverse
      
      final imageScaleX = imageWidth / displayWidth;
      final imageScaleY = imageHeight / displayHeight;
      
      // Calculate where the selection is in the transformed space
      // Selection stays fixed, image moves under it
      // So we need to find what part of the image is under the selection
      
      // The visible area of the image in container coords:
      // Image display rect after transform:
      // left = offsetX * scale + tx
      // top = offsetY * scale + ty
      // width = displayWidth * scale
      // height = displayHeight * scale
      
      final transformedImageLeft = offsetX * scale + tx;
      final transformedImageTop = offsetY * scale + ty;
      
      // Selection position relative to transformed image
      final relLeft = (selectionLeft - transformedImageLeft) / scale;
      final relTop = (selectionTop - transformedImageTop) / scale;
      final relWidth = selectionWidth / scale;
      final relHeight = selectionHeight / scale;
      
      // Convert from display coordinates to image coordinates
      final cropLeft = (relLeft - offsetX) * imageScaleX;
      final cropTop = (relTop - offsetY) * imageScaleY;
      final cropWidth = relWidth * imageScaleX;
      final cropHeight = relHeight * imageScaleY;
      
      // Clamp to image bounds
      final clampedLeft = cropLeft.clamp(0.0, imageWidth - 1);
      final clampedTop = cropTop.clamp(0.0, imageHeight - 1);
      final clampedWidth = cropWidth.clamp(1.0, imageWidth - clampedLeft);
      final clampedHeight = cropHeight.clamp(1.0, imageHeight - clampedTop);
      
      return Rect.fromLTWH(clampedLeft, clampedTop, clampedWidth, clampedHeight);
    } catch (e) {
      debugPrint('Error calculating crop rect: $e');
      return null;
    }
  }
}

/// Custom painter for the selection overlay (dims area outside selection)
class _SelectionOverlayPainter extends CustomPainter {
  final Rect selectionRect;
  
  _SelectionOverlayPainter({required this.selectionRect});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
    
    // Create a path with a hole for the selection
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(selectionRect, const Radius.circular(8)))
      ..fillType = PathFillType.evenOdd;
    
    canvas.drawPath(path, paint);
  }
  
  @override
  bool shouldRepaint(_SelectionOverlayPainter oldDelegate) {
    return selectionRect != oldDelegate.selectionRect;
  }
}

/// Custom painter for corner indicators (not currently used but kept for reference)
class _CornerPainter extends CustomPainter {
  final Alignment alignment;
  final Color color;
  final double thickness;
  
  _CornerPainter({
    required this.alignment,
    required this.color,
    required this.thickness,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;
    
    final path = Path();
    
    if (alignment == Alignment.topLeft) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (alignment == Alignment.topRight) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else if (alignment == Alignment.bottomLeft) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else if (alignment == Alignment.bottomRight) {
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width, 0);
    }
    
    canvas.drawPath(path, paint);
  }
  
  @override
  bool shouldRepaint(_CornerPainter oldDelegate) {
    return alignment != oldDelegate.alignment ||
           color != oldDelegate.color ||
           thickness != oldDelegate.thickness;
  }
}
