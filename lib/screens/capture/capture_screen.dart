import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';

/// Camera capture screen for photos and videos
/// Also supports gallery-only mode for importing from device gallery
class CaptureScreen extends StatefulWidget {
  final bool isVideo;
  final bool isGalleryMode; // Skip camera, open picker directly
  
  const CaptureScreen({
    super.key, 
    this.isVideo = false,
    this.isGalleryMode = false,
  });

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isRecording = false;
  bool _isFrontCamera = false;
  bool _hasPermission = false;
  String? _errorMessage;
  double _currentZoom = 1.0;
  double _maxZoom = 1.0;
  double _minZoom = 1.0;
  FlashMode _flashMode = FlashMode.auto;
  
  // Preview state
  bool _showPreview = false;
  String? _capturedFilePath;
  VideoPlayerController? _videoPlayerController;
  
  // Video recording timer
  DateTime? _recordingStartTime;
  Duration _recordingDuration = Duration.zero;
  
  // Gallery mode: dynamically detected media type
  // In camera mode, use widget.isVideo; in gallery mode, use this value
  bool _detectedIsVideo = false;
  
  final ImagePicker _imagePicker = ImagePicker();
  
  /// Returns true if current media is video (either from widget param or detected)
  bool get _isVideoMedia => widget.isGalleryMode ? _detectedIsVideo : widget.isVideo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    if (widget.isGalleryMode) {
      // Gallery mode: open picker directly after first frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pickFromGalleryMixed();
      });
    } else {
      // Camera mode: initialize camera
      _initializeCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _videoPlayerController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Skip camera lifecycle management in gallery mode
    if (widget.isGalleryMode) return;
    if (_controller == null || !_controller!.value.isInitialized) return;
    
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (!_showPreview) {
        _initializeCamera();
      }
    }
  }

  Future<void> _initializeCamera() async {
    // Request permissions
    final cameraStatus = await Permission.camera.request();
    final micStatus = widget.isVideo ? await Permission.microphone.request() : PermissionStatus.granted;
    
    if (!mounted) return; // Check if widget is still mounted after async operation
    
    if (!cameraStatus.isGranted || (widget.isVideo && !micStatus.isGranted)) {
      setState(() {
        _hasPermission = false;
        _errorMessage = 'Permission caméra requise';
      });
      return;
    }
    
    setState(() => _hasPermission = true);
    
    try {
      _cameras = await availableCameras();
      if (!mounted) return; // Check again after async operation
      
      if (_cameras.isEmpty) {
        setState(() => _errorMessage = 'Aucune caméra disponible');
        return;
      }
      
      await _setupCamera(_isFrontCamera ? 1 : 0);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Erreur d\'initialisation: $e');
      }
    }
  }

  Future<void> _setupCamera(int cameraIndex) async {
    if (_cameras.isEmpty) return;
    
    final cameraIdx = cameraIndex.clamp(0, _cameras.length - 1);
    
    _controller?.dispose();
    _controller = CameraController(
      _cameras[cameraIdx],
      ResolutionPreset.high,
      enableAudio: widget.isVideo,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    
    try {
      await _controller!.initialize();
      
      // Try to get zoom levels, but don't fail if not supported
      try {
        _maxZoom = await _controller!.getMaxZoomLevel();
        _minZoom = await _controller!.getMinZoomLevel();
        _currentZoom = _minZoom;
      } catch (_) {
        // Zoom not supported on this camera, use defaults
        _maxZoom = 1.0;
        _minZoom = 1.0;
        _currentZoom = 1.0;
      }
      
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      setState(() => _errorMessage = 'Erreur caméra: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    
    setState(() {
      _isFrontCamera = !_isFrontCamera;
      _isInitialized = false;
    });
    
    await _setupCamera(_isFrontCamera ? 1 : 0);
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    
    FlashMode newMode;
    switch (_flashMode) {
      case FlashMode.auto:
        newMode = FlashMode.always;
        break;
      case FlashMode.always:
        newMode = FlashMode.off;
        break;
      default:
        newMode = FlashMode.auto;
    }
    
    try {
      await _controller!.setFlashMode(newMode);
      setState(() => _flashMode = newMode);
    } catch (_) {}
  }

  void _onZoomChanged(double value) {
    if (_controller == null || _maxZoom <= _minZoom) return;
    
    final zoom = value.clamp(_minZoom, _maxZoom);
    try {
      _controller!.setZoomLevel(zoom);
      setState(() => _currentZoom = zoom);
    } catch (_) {
      // Zoom not supported, ignore
    }
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    
    try {
      final file = await _controller!.takePicture();
      if (mounted) {
        setState(() {
          _capturedFilePath = file.path;
          _showPreview = true;
        });
      }
    } catch (e) {
      _showError('Erreur lors de la capture: $e');
    }
  }

  Future<void> _toggleRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    
    if (_isRecording) {
      try {
        final file = await _controller!.stopVideoRecording();
        setState(() {
          _isRecording = false;
          _recordingStartTime = null;
          _recordingDuration = Duration.zero;
        });
        
        if (mounted) {
          // Initialize video player for preview
          // On web, use networkUrl since dart:io File is not supported
          if (kIsWeb) {
            _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(file.path));
          } else {
            _videoPlayerController = VideoPlayerController.file(File(file.path));
          }
          await _videoPlayerController!.initialize();
          await _videoPlayerController!.setLooping(true);
          await _videoPlayerController!.play();
          
          setState(() {
            _capturedFilePath = file.path;
            _showPreview = true;
          });
        }
      } catch (e) {
        _showError('Erreur: $e');
      }
    } else {
      try {
        await _controller!.startVideoRecording();
        setState(() {
          _isRecording = true;
          _recordingStartTime = DateTime.now();
        });
        // Start timer updates
        _startRecordingTimer();
      } catch (e) {
        _showError('Erreur: $e');
      }
    }
  }
  
  /// Update recording duration timer
  void _startRecordingTimer() {
    Future.doWhile(() async {
      if (!_isRecording || !mounted) return false;
      await Future.delayed(const Duration(seconds: 1));
      if (_isRecording && mounted && _recordingStartTime != null) {
        setState(() {
          _recordingDuration = DateTime.now().difference(_recordingStartTime!);
        });
      }
      return _isRecording && mounted;
    });
  }
  
  /// Format duration as MM:SS
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _pickFromGallery() async {
    try {
      final XFile? file;
      if (_isVideoMedia) {
        file = await _imagePicker.pickVideo(source: ImageSource.gallery);
      } else {
        file = await _imagePicker.pickImage(source: ImageSource.gallery);
      }
      
      if (file != null && mounted) {
        if (_isVideoMedia) {
          // On web, use networkUrl since dart:io File is not supported
          if (kIsWeb) {
            _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(file.path));
          } else {
            _videoPlayerController = VideoPlayerController.file(File(file.path));
          }
          await _videoPlayerController!.initialize();
          await _videoPlayerController!.setLooping(true);
          await _videoPlayerController!.play();
        }
        
        setState(() {
          _capturedFilePath = file!.path;
          _showPreview = true;
        });
      }
    } catch (e) {
      _showError('Erreur: $e');
    }
  }
  
  /// Pick media from gallery - allows both images and videos
  /// Used in gallery mode to let user pick any media type
  Future<void> _pickFromGalleryMixed() async {
    try {
      // Show dialog to choose media type and pick file
      final result = await _showMediaTypeChoice();
      
      if (result == null) {
        // User cancelled - if in gallery mode with no preview, go back
        if (widget.isGalleryMode && !_showPreview && mounted) {
          Navigator.pop(context);
        }
        return;
      }
      
      if (!mounted) return;
      
      // Use user's choice from dialog (not extension detection - fails on web blob URLs)
      final isVideo = result.isVideo;
      setState(() {
        _detectedIsVideo = isVideo;
      });
      
      // Initialize video player if needed
      if (isVideo) {
        if (kIsWeb) {
          _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(result.file.path));
        } else {
          _videoPlayerController = VideoPlayerController.file(File(result.file.path));
        }
        await _videoPlayerController!.initialize();
        await _videoPlayerController!.setLooping(true);
        await _videoPlayerController!.play();
      }
      
      setState(() {
        _capturedFilePath = result.file.path;
        _showPreview = true;
      });
    } catch (e) {
      _showError('Erreur: $e');
      // If in gallery mode and error occurs, go back
      if (widget.isGalleryMode && !_showPreview && mounted) {
        Navigator.pop(context);
      }
    }
  }
  
  /// Show dialog to choose between image or video, then open picker
  /// Returns _MediaPickerResult with both the file and user's media type choice
  Future<_MediaPickerResult?> _showMediaTypeChoice() async {
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Sélectionner un média',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.image_rounded, color: AppColors.primary),
              ),
              title: const Text('Image', style: TextStyle(fontFamily: 'Poppins')),
              subtitle: const Text('Photo depuis la galerie', style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
              onTap: () => Navigator.pop(context, 'image'),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.videocam_rounded, color: AppColors.accent),
              ),
              title: const Text('Vidéo', style: TextStyle(fontFamily: 'Poppins')),
              subtitle: const Text('Vidéo depuis la galerie', style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
              onTap: () => Navigator.pop(context, 'video'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
    
    if (choice == null) return null;
    
    final bool isVideo = choice == 'video';
    final XFile? file;
    
    if (isVideo) {
      file = await _imagePicker.pickVideo(source: ImageSource.gallery);
    } else {
      file = await _imagePicker.pickImage(source: ImageSource.gallery);
    }
    
    if (file == null) return null;
    
    // Return both file and user's choice (not extension-based detection)
    return _MediaPickerResult(file, isVideo);
  }

  void _onConfirm() {
    if (_capturedFilePath == null) return;
    
    _videoPlayerController?.pause();
    
    Navigator.pushReplacementNamed(
      context,
      AppRoutes.photoReview,
      arguments: {
        'imagePath': _capturedFilePath,
        'isVideo': _isVideoMedia, // Use detected type in gallery mode
      },
    );
  }

  void _onRetake() {
    // Delete the captured file (only on mobile, web uses blob URLs)
    if (_capturedFilePath != null && !kIsWeb) {
      try {
        File(_capturedFilePath!).deleteSync();
      } catch (_) {}
    }
    
    _videoPlayerController?.dispose();
    _videoPlayerController = null;
    
    setState(() {
      _capturedFilePath = null;
      _showPreview = false;
      _detectedIsVideo = false; // Reset detected type
    });
    
    // In gallery mode, re-open the picker
    if (widget.isGalleryMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pickFromGalleryMixed();
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera preview or captured preview or gallery loading
            if (_showPreview && _capturedFilePath != null)
              _buildPreviewOverlay()
            else if (widget.isGalleryMode)
              // Gallery mode: show loading while picker is open
              _buildGalleryLoading()
            else if (_isInitialized && _controller != null)
              Positioned.fill(
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: CameraPreview(_controller!),
                ),
              )
            else if (!_hasPermission)
              _buildPermissionDenied()
            else if (_errorMessage != null)
              _buildError()
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            
            // Top controls (only when not in preview mode and not gallery mode)
            if (!_showPreview && !widget.isGalleryMode)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTopControls(),
              ),
            
            // Recording timer indicator (video mode only, not in gallery mode)
            if (!_showPreview && !widget.isGalleryMode && widget.isVideo && _isRecording)
              Positioned(
                top: 70,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDuration(_recordingDuration),
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            
            // Bottom controls (only when not in preview mode and not gallery mode)
            if (!_showPreview && !widget.isGalleryMode)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomControls(),
              ),
            
            // Zoom slider (only when not in preview mode and not gallery mode)
            if (!_showPreview && !widget.isGalleryMode && _isInitialized && _maxZoom > _minZoom)
              Positioned(
                right: 20,
                top: 100,
                bottom: 200,
                child: _buildZoomSlider(),
              ),
          ],
        ),
      ),
    );
  }

  /// Loading screen shown in gallery mode while file picker is open
  Widget _buildGalleryLoading() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.photo_library_rounded,
                color: AppColors.primary,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Sélection depuis la galerie',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choisissez une image ou vidéo',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 32),
            // Back button
            TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
              label: const Text(
                'Retour',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white70,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewOverlay() {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          // Preview content
          Positioned.fill(
            child: _isVideoMedia && _videoPlayerController != null
                ? Center(
                    child: AspectRatio(
                      aspectRatio: _videoPlayerController!.value.aspectRatio,
                      child: VideoPlayer(_videoPlayerController!),
                    ),
                  )
                : kIsWeb
                    ? Image.network(
                        _capturedFilePath!,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
                          );
                        },
                      )
                    : Image.file(
                        File(_capturedFilePath!),
                        fit: BoxFit.contain,
                      ),
          ),
          
          // Close button
          Positioned(
            top: 16,
            left: 16,
            child: _ControlButton(
              icon: Icons.close_rounded,
              onTap: _onRetake,
            ),
          ),
          
          // Video play indicator
          if (_isVideoMedia)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'Vidéo',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          // Bottom action buttons
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.8),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  // Reprendre button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _onRetake,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reprendre'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // Confirmer button
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _onConfirm,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Confirmer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.camera_alt_outlined,
            size: 64,
            color: Colors.white54,
          ),
          const SizedBox(height: 16),
          const Text(
            'Permission caméra requise',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'Poppins',
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => openAppSettings(),
            child: const Text('Ouvrir les paramètres'),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: AppColors.error,
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'Erreur inconnue',
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Poppins',
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _initializeCamera,
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  Widget _buildTopControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.6),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          // Back button
          _ControlButton(
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.pop(context),
          ),
          
          const Spacer(),
          
          // Flash button
          if (_isInitialized)
            _ControlButton(
              icon: _getFlashIcon(),
              onTap: _toggleFlash,
            ),
          
          const SizedBox(width: 12),
          
          // Switch camera button
          if (_cameras.length > 1 && _isInitialized)
            _ControlButton(
              icon: Icons.flip_camera_ios_rounded,
              onTap: _switchCamera,
            ),
        ],
      ),
    );
  }

  IconData _getFlashIcon() {
    switch (_flashMode) {
      case FlashMode.auto:
        return Icons.flash_auto_rounded;
      case FlashMode.always:
        return Icons.flash_on_rounded;
      case FlashMode.off:
        return Icons.flash_off_rounded;
      default:
        return Icons.flash_auto_rounded;
    }
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Gallery button
          _ControlButton(
            icon: Icons.photo_library_rounded,
            onTap: _pickFromGallery,
            size: 48,
          ),
          
          // Capture button
          GestureDetector(
            onTap: widget.isVideo ? _toggleRecording : _takePicture,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 4,
                ),
              ),
              padding: const EdgeInsets.all(4),
              child: Container(
                decoration: BoxDecoration(
                  color: _isRecording ? AppColors.error : Colors.white,
                  shape: _isRecording ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: _isRecording ? BorderRadius.circular(8) : null,
                ),
                margin: _isRecording ? const EdgeInsets.all(12) : null,
              ),
            ),
          ),
          
          // Mode indicator
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              widget.isVideo ? Icons.videocam_rounded : Icons.camera_alt_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomSlider() {
    return RotatedBox(
      quarterTurns: 3,
      child: SliderTheme(
        data: SliderThemeData(
          activeTrackColor: AppColors.primary,
          inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
          thumbColor: Colors.white,
          overlayColor: AppColors.primary.withValues(alpha: 0.3),
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          trackHeight: 3,
        ),
        child: Slider(
          value: _currentZoom,
          min: _minZoom,
          max: _maxZoom,
          onChanged: _onZoomChanged,
        ),
      ),
    );
  }
}

/// Result from media picker dialog - holds file and whether user chose video
class _MediaPickerResult {
  final XFile file;
  final bool isVideo;
  
  _MediaPickerResult(this.file, this.isVideo);
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  
  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(size / 3),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: size * 0.5,
        ),
      ),
    );
  }
}
