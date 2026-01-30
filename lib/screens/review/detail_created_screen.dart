import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../services/crop_service.dart';

/// Screen displaying the composite image after successful save, with arrow linking original to detail
class DetailCreatedScreen extends StatefulWidget {
  final String compositeImagePath;
  final int qualityStatus;
  final Rect? cropRect;
  final String originalImagePath;
  final bool isUsingCroppedMedia;

  const DetailCreatedScreen({
    super.key,
    required this.compositeImagePath,
    required this.qualityStatus,
    this.cropRect,
    required this.originalImagePath,
    required this.isUsingCroppedMedia,
  });

  @override
  State<DetailCreatedScreen> createState() => _DetailCreatedScreenState();
}

class _DetailCreatedScreenState extends State<DetailCreatedScreen> {
  ui.Image? _compositeImage;
  ui.Image? _originalImage;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    try {
      // Load composite image
      final compositeFile = File(widget.compositeImagePath);
      if (!await compositeFile.exists()) {
        setState(() {
          _error = 'Image composite introuvable';
          _isLoading = false;
        });
        return;
      }

      final compositeBytes = await compositeFile.readAsBytes();
      final compositeCodec = await ui.instantiateImageCodec(compositeBytes);
      final compositeFrame = await compositeCodec.getNextFrame();
      
      // Load original image for dimensions (if crop rect is provided)
      ui.Image? originalImage;
      if (widget.cropRect != null && widget.isUsingCroppedMedia) {
        try {
          final originalFile = File(widget.originalImagePath);
          if (await originalFile.exists()) {
            final originalBytes = await originalFile.readAsBytes();
            final originalCodec = await ui.instantiateImageCodec(originalBytes);
            final originalFrame = await originalCodec.getNextFrame();
            originalImage = originalFrame.image;
          }
        } catch (e) {
          debugPrint('Error loading original image: $e');
          // Continue without original image - arrow won't be drawn
        }
      }

      if (mounted) {
        setState(() {
          _compositeImage = compositeFrame.image;
          _originalImage = originalImage;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading images: $e');
      if (mounted) {
        setState(() {
          _error = 'Erreur lors du chargement de l\'image';
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _compositeImage?.dispose();
    _originalImage?.dispose();
    
    // Clean up temporary composite file when leaving the screen
    final cropService = CropService();
    cropService.cleanupTempFile(widget.compositeImagePath);
    
    super.dispose();
  }

  Color _getQualityColor() {
    switch (widget.qualityStatus) {
      case 4: // Bonne
        return AppColors.statusOK;
      case 5: // Mauvaise
        return AppColors.statusNOK;
      case 6: // Neutre
      default:
        return AppColors.statusNeutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Détail créé',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _error != null
              ? Center(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              : _compositeImage == null
                  ? const Center(
                      child: Text(
                        'Image non disponible',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        // Image with arrow overlay
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              if (_compositeImage == null) {
                                return const Center(
                                  child: Text(
                                    'Image non disponible',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                );
                              }

                              final imageWidth = _compositeImage!.width.toDouble();
                              final imageHeight = _compositeImage!.height.toDouble();

                              return Center(
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: SizedBox(
                                    width: imageWidth,
                                    height: imageHeight,
                                    child: Stack(
                                      children: [
                                        // Composite image
                                        Image.file(
                                          File(widget.compositeImagePath),
                                          fit: BoxFit.contain,
                                        ),
                                        // Arrow overlay
                                        if (widget.cropRect != null &&
                                            widget.isUsingCroppedMedia &&
                                            _originalImage != null)
                                          CustomPaint(
                                            painter: _ArrowPainter(
                                              cropRect: widget.cropRect!,
                                              originalImage: _originalImage!,
                                              compositeImage: _compositeImage!,
                                              arrowColor: _getQualityColor(),
                                            ),
                                            child: SizedBox(
                                              width: imageWidth,
                                              height: imageHeight,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        // Retour accueil button
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, -2),
                              ),
                            ],
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pushNamedAndRemoveUntil(
                                  context,
                                  AppRoutes.home,
                                  (route) => false,
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Retour accueil',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }
}

/// Custom painter for drawing arrow from crop area to detail
class _ArrowPainter extends CustomPainter {
  final Rect cropRect;
  final ui.Image originalImage;
  final ui.Image compositeImage;
  final Color arrowColor;

  _ArrowPainter({
    required this.cropRect,
    required this.originalImage,
    required this.compositeImage,
    required this.arrowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Composite layout constants (from crop_service.dart)
    const int padding = 20;
    const int borderWidth = 8;
    const int headerHeight = 50;
    const int footerHeight = 40;
    const int spacing = 16;
    const double originalRatio = 0.4;
    const double croppedRatio = 0.6;
    const int contentHeight = 400;

    // Calculate scaled dimensions (same logic as crop_service.dart)
    final int availableOriginalWidth =
        ((contentHeight * 2 - spacing) * originalRatio).toInt() - padding;
    
    // Calculate original image scale
    final originalScale = _calculateScale(
      originalImage.width,
      originalImage.height,
      availableOriginalWidth,
      contentHeight - padding * 2,
    );
    
    final int scaledOriginalWidth = (originalImage.width * originalScale).toInt();
    final int scaledOriginalHeight = (originalImage.height * originalScale).toInt();

    // Calculate total composite dimensions
    final int totalWidth = padding +
        scaledOriginalWidth +
        spacing +
        borderWidth * 2 +
        ((contentHeight * 2 - spacing) * croppedRatio).toInt() -
        padding -
        borderWidth * 2 +
        padding;
    final int totalHeight = headerHeight +
        padding +
        (scaledOriginalHeight > contentHeight ? scaledOriginalHeight : contentHeight) +
        padding +
        footerHeight;

    // Original photo position in composite
    final int originalX = padding;
    final int originalY = headerHeight +
        padding +
        ((totalHeight - headerHeight - footerHeight - padding * 2 - scaledOriginalHeight) ~/ 2);

    // Calculate crop area center in composite coordinates
    final cropCenterX = originalX + (cropRect.left + cropRect.width / 2) * originalScale;
    final cropCenterY = originalY + (cropRect.top + cropRect.height / 2) * originalScale;

    // Calculate cropped detail center position
    final int croppedAreaX = padding + scaledOriginalWidth + spacing;
    final int croppedAreaY = headerHeight +
        padding +
        ((totalHeight - headerHeight - footerHeight - padding * 2 - contentHeight - borderWidth * 2) ~/ 2);
    
    // Estimate cropped detail dimensions (we don't have exact dimensions, use reasonable estimate)
    final int estimatedCroppedWidth = ((contentHeight * 2 - spacing) * croppedRatio).toInt() - padding - borderWidth * 2;
    final int estimatedCroppedHeight = contentHeight - padding * 2;
    
    final detailCenterX = croppedAreaX + borderWidth + estimatedCroppedWidth / 2;
    final detailCenterY = croppedAreaY + borderWidth + estimatedCroppedHeight / 2;

    // Calculate border rectangle bounds (outer edges)
    final borderLeft = croppedAreaX.toDouble();
    final borderRight = (croppedAreaX + estimatedCroppedWidth + borderWidth * 2).toDouble();
    final borderTop = croppedAreaY.toDouble();
    final borderBottom = (croppedAreaY + estimatedCroppedHeight + borderWidth * 2).toDouble();

    // Calculate line direction from crop center to detail center
    final dx = detailCenterX - cropCenterX;
    final dy = detailCenterY - cropCenterY;

    // Find intersection with left edge of border (arrow comes from left)
    double arrowEndX = borderLeft;
    double arrowEndY;
    if (dx != 0) {
      final slope = dy / dx;
      arrowEndY = cropCenterY + slope * (borderLeft - cropCenterX);
      // Clamp to border rectangle bounds
      arrowEndY = arrowEndY.clamp(borderTop, borderBottom);
    } else {
      // Vertical line - use crop center Y clamped to border
      arrowEndY = cropCenterY.clamp(borderTop, borderBottom);
    }

    // Draw arrow
    final paint = Paint()
      ..color = arrowColor
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Draw arrow line (from crop center to border edge)
    canvas.drawLine(
      Offset(cropCenterX, cropCenterY),
      Offset(arrowEndX, arrowEndY),
      paint,
    );

    // Draw arrowhead (pointing to border edge)
    final arrowLength = 12.0;
    final arrowAngle = 0.5; // radians
    
    final arrowDx = arrowEndX - cropCenterX;
    final arrowDy = arrowEndY - cropCenterY;
    final angle = (arrowDx == 0 && arrowDy == 0) ? 0.0 : (arrowDx == 0) ? (arrowDy > 0 ? math.pi / 2 : -math.pi / 2) : math.atan2(arrowDy, arrowDx);
    
    final arrowPath = Path();
    arrowPath.moveTo(arrowEndX, arrowEndY);
    arrowPath.lineTo(
      arrowEndX - arrowLength * math.cos(angle - arrowAngle),
      arrowEndY - arrowLength * math.sin(angle - arrowAngle),
    );
    arrowPath.lineTo(
      arrowEndX - arrowLength * math.cos(angle + arrowAngle),
      arrowEndY - arrowLength * math.sin(angle + arrowAngle),
    );
    arrowPath.close();

    final arrowPaint = Paint()
      ..color = arrowColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(arrowPath, arrowPaint);
  }

  double _calculateScale(int imageWidth, int imageHeight, int maxWidth, int maxHeight) {
    final scaleX = maxWidth / imageWidth;
    final scaleY = maxHeight / imageHeight;
    return scaleX < scaleY ? scaleX : scaleY;
  }

  @override
  bool shouldRepaint(_ArrowPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect ||
        oldDelegate.originalImage != originalImage ||
        oldDelegate.compositeImage != compositeImage ||
        oldDelegate.arrowColor != arrowColor;
  }
}
