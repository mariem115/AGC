import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../config/theme.dart';
import '../services/crop_service.dart';

/// Result from the zoom and select screen
class ZoomSelectResult {
  /// Path to the cropped/extracted media file
  final String croppedPath;
  
  /// Whether the source was a video (result is always an image)
  final bool wasVideo;

  ZoomSelectResult({
    required this.croppedPath,
    required this.wasVideo,
  });
}

/// Full-screen zoom and crop selection screen
/// 
/// For photos: Opens native image cropper
/// For videos: Allows frame selection with crop overlay
class ZoomSelectScreen extends StatefulWidget {
  /// Path to the media file
  final String mediaPath;
  
  /// Whether the media is a video
  final bool isVideo;
  
  /// Existing video controller (for videos only)
  final VideoPlayerController? videoController;

  const ZoomSelectScreen({
    super.key,
    required this.mediaPath,
    required this.isVideo,
    this.videoController,
  });

  @override
  State<ZoomSelectScreen> createState() => _ZoomSelectScreenState();
}

class _ZoomSelectScreenState extends State<ZoomSelectScreen> {
  final CropService _cropService = CropService();
  final GlobalKey _videoKey = GlobalKey();
  final TransformationController _transformController = TransformationController();
  
  // Video controller (either passed or created)
  VideoPlayerController? _videoController;
  bool _ownsVideoController = false;
  
  // Crop rectangle state
  Rect _cropRect = Rect.zero;
  Size _mediaSize = Size.zero;
  bool _isInitialized = false;
  bool _isProcessing = false;
  
  // For resizing the crop rect
  _CropHandle? _activeHandle;
  Offset _lastPanPosition = Offset.zero;
  
  // Minimum crop size
  static const double _minCropSize = 50.0;

  @override
  void initState() {
    super.initState();
    _initializeMedia();
  }

  Future<void> _initializeMedia() async {
    if (widget.isVideo) {
      // Use passed controller or create new one
      if (widget.videoController != null) {
        _videoController = widget.videoController;
        _ownsVideoController = false;
      } else {
        _videoController = VideoPlayerController.file(File(widget.mediaPath));
        _ownsVideoController = true;
        await _videoController!.initialize();
      }
      
      // Pause video for frame selection
      await _videoController!.pause();
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } else {
      // For images, use the native cropper directly
      _openImageCropper();
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    if (_ownsVideoController) {
      _videoController?.dispose();
    }
    super.dispose();
  }

  /// Open native image cropper for photos
  Future<void> _openImageCropper() async {
    final croppedPath = await _cropService.cropImage(widget.mediaPath);
    
    if (mounted) {
      if (croppedPath != null) {
        Navigator.pop(
          context,
          ZoomSelectResult(croppedPath: croppedPath, wasVideo: false),
        );
      } else {
        // User cancelled or error
        Navigator.pop(context, null);
      }
    }
  }

  /// Initialize crop rect when media dimensions are known
  void _initializeCropRect(Size mediaSize) {
    if (_mediaSize == mediaSize) return;
    
    _mediaSize = mediaSize;
    
    // Default crop rect - centered, 80% of the smaller dimension
    final minDim = mediaSize.width < mediaSize.height 
        ? mediaSize.width 
        : mediaSize.height;
    final cropSize = minDim * 0.8;
    
    _cropRect = Rect.fromCenter(
      center: Offset(mediaSize.width / 2, mediaSize.height / 2),
      width: cropSize,
      height: cropSize,
    );
    
    setState(() {});
  }

  /// Handle crop rectangle pan/resize
  void _onPanStart(DragStartDetails details, _CropHandle handle) {
    _activeHandle = handle;
    _lastPanPosition = details.localPosition;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_activeHandle == null) return;
    
    final delta = details.localPosition - _lastPanPosition;
    _lastPanPosition = details.localPosition;
    
    setState(() {
      switch (_activeHandle!) {
        case _CropHandle.move:
          _moveCropRect(delta);
          break;
        case _CropHandle.topLeft:
          _resizeCropRect(delta, alignRight: true, alignBottom: true);
          break;
        case _CropHandle.topRight:
          _resizeCropRect(delta, alignLeft: true, alignBottom: true);
          break;
        case _CropHandle.bottomLeft:
          _resizeCropRect(delta, alignRight: true, alignTop: true);
          break;
        case _CropHandle.bottomRight:
          _resizeCropRect(delta, alignLeft: true, alignTop: true);
          break;
      }
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _activeHandle = null;
  }

  void _moveCropRect(Offset delta) {
    var newRect = _cropRect.translate(delta.dx, delta.dy);
    
    // Constrain to media bounds
    if (newRect.left < 0) newRect = newRect.translate(-newRect.left, 0);
    if (newRect.top < 0) newRect = newRect.translate(0, -newRect.top);
    if (newRect.right > _mediaSize.width) {
      newRect = newRect.translate(_mediaSize.width - newRect.right, 0);
    }
    if (newRect.bottom > _mediaSize.height) {
      newRect = newRect.translate(0, _mediaSize.height - newRect.bottom);
    }
    
    _cropRect = newRect;
  }

  void _resizeCropRect(
    Offset delta, {
    bool alignLeft = false,
    bool alignRight = false,
    bool alignTop = false,
    bool alignBottom = false,
  }) {
    double left = _cropRect.left;
    double top = _cropRect.top;
    double right = _cropRect.right;
    double bottom = _cropRect.bottom;
    
    if (!alignLeft) left += delta.dx;
    if (!alignRight) right += delta.dx;
    if (!alignTop) top += delta.dy;
    if (!alignBottom) bottom += delta.dy;
    
    // Enforce minimum size
    if (right - left < _minCropSize) {
      if (alignLeft) {
        right = left + _minCropSize;
      } else {
        left = right - _minCropSize;
      }
    }
    if (bottom - top < _minCropSize) {
      if (alignTop) {
        bottom = top + _minCropSize;
      } else {
        top = bottom - _minCropSize;
      }
    }
    
    // Constrain to media bounds
    left = left.clamp(0, _mediaSize.width - _minCropSize);
    top = top.clamp(0, _mediaSize.height - _minCropSize);
    right = right.clamp(_minCropSize, _mediaSize.width);
    bottom = bottom.clamp(_minCropSize, _mediaSize.height);
    
    _cropRect = Rect.fromLTRB(left, top, right, bottom);
  }

  /// Confirm the selection and process the media
  Future<void> _confirmSelection() async {
    if (_isProcessing) return;
    
    setState(() => _isProcessing = true);
    
    try {
      String? resultPath;
      
      if (widget.isVideo) {
        // Extract and crop video frame
        resultPath = await _cropService.extractVideoFrame(
          _videoController!,
          _videoKey,
          cropRect: _cropRect,
        );
      }
      
      if (mounted) {
        if (resultPath != null) {
          Navigator.pop(
            context,
            ZoomSelectResult(croppedPath: resultPath, wasVideo: widget.isVideo),
          );
        } else {
          // Suppressed for demo - error handling logic remains
          setState(() => _isProcessing = false);
        }
      }
    } catch (e) {
      debugPrint('ZoomSelectScreen: Error processing: $e');
      if (mounted) {
        setState(() => _isProcessing = false);
        // Suppressed for demo - error handling logic remains
      }
    }
  }

  /// Cancel and return to preview
  void _cancel() {
    Navigator.pop(context, null);
  }

  /// Toggle video playback for seeking
  void _toggleVideoPlayback() {
    if (_videoController == null) return;
    
    setState(() {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
      } else {
        _videoController!.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // For images, this screen briefly shows loading then opens native cropper
    if (!widget.isVideo) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }
    
    // Video crop UI
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _cancel,
        ),
        title: const Text(
          'Sélectionner une zone',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: _isInitialized
          ? Column(
              children: [
                // Video preview with crop overlay
                Expanded(
                  child: _buildVideoWithCropOverlay(),
                ),
                
                // Playback controls
                _buildPlaybackControls(),
                
                // Action buttons
                _buildActionButtons(),
              ],
            )
          : const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
    );
  }

  Widget _buildVideoWithCropOverlay() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final videoAspectRatio = _videoController!.value.aspectRatio;
        
        // Calculate the size the video will be displayed at
        double displayWidth = constraints.maxWidth;
        double displayHeight = displayWidth / videoAspectRatio;
        
        if (displayHeight > constraints.maxHeight) {
          displayHeight = constraints.maxHeight;
          displayWidth = displayHeight * videoAspectRatio;
        }
        
        final displaySize = Size(displayWidth, displayHeight);
        
        // Initialize crop rect when we know the display size
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _initializeCropRect(displaySize);
        });
        
        return Center(
          child: SizedBox(
            width: displayWidth,
            height: displayHeight,
            child: Stack(
              children: [
                // Video
                RepaintBoundary(
                  key: _videoKey,
                  child: VideoPlayer(_videoController!),
                ),
                
                // Dimmed overlay outside crop area
                if (_cropRect != Rect.zero)
                  CustomPaint(
                    size: displaySize,
                    painter: _CropOverlayPainter(cropRect: _cropRect),
                  ),
                
                // Crop rectangle handles
                if (_cropRect != Rect.zero)
                  _buildCropHandles(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCropHandles() {
    const handleSize = 24.0;
    const handlePadding = 4.0;
    
    return Stack(
      children: [
        // Move handle (entire crop area)
        Positioned(
          left: _cropRect.left,
          top: _cropRect.top,
          width: _cropRect.width,
          height: _cropRect.height,
          child: GestureDetector(
            onPanStart: (d) => _onPanStart(d, _CropHandle.move),
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: Container(color: Colors.transparent),
          ),
        ),
        
        // Top-left handle
        Positioned(
          left: _cropRect.left - handlePadding,
          top: _cropRect.top - handlePadding,
          child: _buildHandle(_CropHandle.topLeft, handleSize),
        ),
        
        // Top-right handle
        Positioned(
          left: _cropRect.right - handleSize + handlePadding,
          top: _cropRect.top - handlePadding,
          child: _buildHandle(_CropHandle.topRight, handleSize),
        ),
        
        // Bottom-left handle
        Positioned(
          left: _cropRect.left - handlePadding,
          top: _cropRect.bottom - handleSize + handlePadding,
          child: _buildHandle(_CropHandle.bottomLeft, handleSize),
        ),
        
        // Bottom-right handle
        Positioned(
          left: _cropRect.right - handleSize + handlePadding,
          top: _cropRect.bottom - handleSize + handlePadding,
          child: _buildHandle(_CropHandle.bottomRight, handleSize),
        ),
      ],
    );
  }

  Widget _buildHandle(_CropHandle handle, double size) {
    return GestureDetector(
      onPanStart: (d) => _onPanStart(d, handle),
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.primary, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaybackControls() {
    if (_videoController == null) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black,
      child: Row(
        children: [
          // Play/Pause button
          IconButton(
            onPressed: _toggleVideoPlayback,
            icon: Icon(
              _videoController!.value.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              color: Colors.white,
            ),
          ),
          
          // Seek bar
          Expanded(
            child: VideoProgressIndicator(
              _videoController!,
              allowScrubbing: true,
              colors: VideoProgressColors(
                playedColor: AppColors.primary,
                bufferedColor: AppColors.primary.withValues(alpha: 0.3),
                backgroundColor: Colors.white24,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
          
          // Time indicator
          Text(
            _formatDuration(_videoController!.value.position),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontFamily: 'Poppins',
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Cancel button
            Expanded(
              child: OutlinedButton(
                onPressed: _isProcessing ? null : _cancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Annuler',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            
            const SizedBox(width: 12),
            
            // Confirm button
            Expanded(
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _confirmSelection,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Text(
                        'Confirmer',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Enum for crop handle positions
enum _CropHandle {
  move,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

/// Custom painter for the crop overlay (dims area outside crop rect)
class _CropOverlayPainter extends CustomPainter {
  final Rect cropRect;
  
  _CropOverlayPainter({required this.cropRect});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    
    // Draw dimmed overlay
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(cropRect)
      ..fillType = PathFillType.evenOdd;
    
    canvas.drawPath(path, paint);
    
    // Draw crop rectangle border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    canvas.drawRect(cropRect, borderPaint);
    
    // Draw grid lines (rule of thirds)
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    
    final thirdWidth = cropRect.width / 3;
    final thirdHeight = cropRect.height / 3;
    
    // Vertical grid lines
    canvas.drawLine(
      Offset(cropRect.left + thirdWidth, cropRect.top),
      Offset(cropRect.left + thirdWidth, cropRect.bottom),
      gridPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left + thirdWidth * 2, cropRect.top),
      Offset(cropRect.left + thirdWidth * 2, cropRect.bottom),
      gridPaint,
    );
    
    // Horizontal grid lines
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top + thirdHeight),
      Offset(cropRect.right, cropRect.top + thirdHeight),
      gridPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top + thirdHeight * 2),
      Offset(cropRect.right, cropRect.top + thirdHeight * 2),
      gridPaint,
    );
  }
  
  @override
  bool shouldRepaint(_CropOverlayPainter oldDelegate) {
    return cropRect != oldDelegate.cropRect;
  }
}
