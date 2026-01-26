import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../../config/theme.dart';
import '../../models/draft_item.dart';
import '../../providers/draft_provider.dart';
import '../../providers/media_provider.dart';
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

class _PhotoReviewScreenState extends State<PhotoReviewScreen> {
  VideoPlayerController? _videoController;
  bool _isVideoPlaying = false;
  DraftItem? _existingDraft;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // Load existing draft if editing
    if (widget.draftId != null) {
      setState(() => _isLoading = true);
      final draft = await context.read<DraftProvider>().getDraftById(widget.draftId!);
      setState(() {
        _existingDraft = draft;
        _isLoading = false;
      });
    }

    // Initialize video player if needed
    if (widget.isVideo) {
      _videoController = VideoPlayerController.file(File(widget.imagePath))
        ..initialize().then((_) {
          setState(() {});
          _videoController!.setLooping(true);
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
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
        final filename = 'AGC_${DateTime.now().millisecondsSinceEpoch}$extension';
        download_helper.downloadFile(widget.imagePath, filename);
      } else {
        // Mobile: save to device gallery with proper extension
        await _saveToGallery();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(kIsWeb 
                ? (widget.isVideo ? 'Vidéo téléchargée' : 'Photo téléchargée')
                : (widget.isVideo ? 'Vidéo téléchargée dans la galerie' : 'Photo téléchargée dans la galerie')),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  void _openCreateDetailsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CreateDetailsModal(
        imagePath: widget.imagePath,
        isVideo: widget.isVideo,
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
      final draftsDir = Directory('${appDir.path}${Platform.pathSeparator}AGC${Platform.pathSeparator}drafts');
      if (!await draftsDir.exists()) {
        await draftsDir.create(recursive: true);
      }

      final ext = _getFileExtension(tempPath);
      final newPath = '${draftsDir.path}${Platform.pathSeparator}draft_${DateTime.now().millisecondsSinceEpoch}$ext';
      await tempFile.copy(newPath);

      return newPath;
    } catch (e) {
      debugPrint('Error copying to persistent storage: $e');
      return null;
    }
  }

  Future<void> _onSaveDraft(DraftItem draft) async {
    Navigator.pop(context); // Close modal
    
    final draftProvider = context.read<DraftProvider>();
    
    try {
      String persistentPath = draft.filePath;
      
      // Copy temp file to persistent location (mobile only)
      // On web, files are blob URLs that persist in browser memory
      if (!kIsWeb && _existingDraft == null) {
        // Only copy for new drafts, not when updating existing ones
        final copied = await _copyToPersistentStorage(draft.filePath);
        if (copied != null) {
          persistentPath = copied;
        } else {
          // File copy failed on mobile - cannot save draft without persistent file
          throw Exception('Impossible de copier le fichier vers le stockage persistant');
        }
      }
      
      if (_existingDraft != null) {
        // Update existing draft (path is already persistent)
        final success = await draftProvider.updateDraft(draft);
        if (!success) {
          throw Exception(draftProvider.error ?? 'Échec de la mise à jour du brouillon');
        }
      } else {
        // Save new draft with persistent path
        final savedDraft = await draftProvider.saveDraft(
          filePath: persistentPath,
          isVideo: draft.isVideo,
          referenceId: draft.referenceId,
          referenceName: draft.referenceName,
          referenceType: draft.referenceType,
          description: draft.description,
          qualityStatus: draft.qualityStatus,
        );
        
        // Check if save was successful
        if (savedDraft == null) {
          throw Exception(draftProvider.error ?? 'Échec de la sauvegarde du brouillon');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Brouillon sauvegardé'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
        Navigator.pop(context); // Go back
      }
    } catch (e) {
      if (mounted) {
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
    Navigator.pop(context); // Close modal
    
    final mediaProvider = context.read<MediaProvider>();
    final draftProvider = context.read<DraftProvider>();
    final mediaService = MediaService();
    
    try {
      String savedPath = draft.filePath;
      
      // === Step 1: Upload to server (if reference is selected) ===
      // Note: Validation in modal ensures referenceId is not null for final save
      if (draft.referenceId != null && draft.referenceType != null) {
        final file = File(draft.filePath);
        if (await file.exists()) {
          // Prepare file name for upload
          final ext = _getFileExtension(draft.filePath);
          final imageName = 'AGC_${DateTime.now().millisecondsSinceEpoch}$ext';
          
          // Upload to server with:
          // - referenceId: selected reference ID
          // - referenceType: selected reference type (1=Component, 2=Semi-final, 3=Final)
          // - mediaType: quality status (4=Bonne/OK, 5=Mauvaise/NOK, 6=Neutre/Neutral)
          final uploadResult = await mediaService.uploadImage(
            file: file,
            referenceId: draft.referenceId!,
            referenceType: draft.referenceType!,
            mediaType: draft.qualityStatus,
            imageName: imageName,
          );
          
          if (!uploadResult.isSuccess) {
            // Server upload failed - show error but continue with local save
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Erreur serveur: ${uploadResult.error ?? "Upload échoué"}\nSauvegarde locale en cours...'),
                  backgroundColor: AppColors.warning,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
      // Copy to persistent storage if not already there (mobile only)
      if (!kIsWeb) {
        final file = File(draft.filePath);
        if (await file.exists()) {
          final saved = await mediaProvider.saveImageLocally(
            file,
            draft.referenceName ?? 'AGC_Photo',
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
          isVideo: draft.isVideo,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Média sauvegardé avec succès'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
        Navigator.pop(context); // Go back
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la sauvegarde: $e'),
            backgroundColor: AppColors.error,
          ),
        );
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
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMedia() async {
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
            content: Text(widget.isVideo ? 'Vidéo supprimée' : 'Photo supprimée'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
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
            onPressed: _downloadMedia,
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
                Expanded(
                  child: _buildMediaPreview(),
                ),
                
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
        child: widget.isVideo ? _buildVideoPreview() : _buildImagePreview(),
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
      return const Center(
        child: CircularProgressIndicator(),
      );
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
                onPressed: _openCreateDetailsModal,
                icon: const Icon(Icons.edit_note_rounded),
                label: Text(_existingDraft != null ? 'Modifier Détails' : 'Crée Détails'),
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
              onPressed: _showDeleteConfirmation,
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
