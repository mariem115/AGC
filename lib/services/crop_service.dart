import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../config/theme.dart';

/// Service for cropping images and extracting video frames
class CropService {
  static final CropService _instance = CropService._internal();
  factory CropService() => _instance;
  CropService._internal();

  /// Crop an image using the native image_cropper UI
  /// 
  /// Returns the path to the cropped image, or null if cancelled
  Future<String?> cropImage(String sourcePath) async {
    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: sourcePath,
        compressFormat: ImageCompressFormat.png,
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Recadrer',
            toolbarColor: AppColors.primary,
            toolbarWidgetColor: Colors.white,
            statusBarColor: AppColors.primaryDark,
            backgroundColor: Colors.black,
            activeControlsWidgetColor: AppColors.primary,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: 'Recadrer',
            doneButtonTitle: 'Confirmer',
            cancelButtonTitle: 'Annuler',
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
            aspectRatioPickerButtonHidden: false,
            rotateButtonsHidden: false,
            rotateClockwiseButtonHidden: true,
          ),
        ],
      );

      return croppedFile?.path;
    } catch (e) {
      debugPrint('CropService: Error cropping image: $e');
      return null;
    }
  }

  /// Crop an image programmatically using the image package
  /// 
  /// [sourcePath] - Path to the source image file
  /// [cropRect] - The crop rectangle in image coordinates
  /// 
  /// Returns the path to the cropped image, or null on error
  Future<String?> cropImageManual(String sourcePath, Rect cropRect) async {
    try {
      final file = File(sourcePath);
      if (!await file.exists()) {
        debugPrint('CropService: Source file not found: $sourcePath');
        return null;
      }

      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      
      if (image == null) {
        debugPrint('CropService: Failed to decode image');
        return null;
      }

      // Ensure crop rect is within image bounds
      final x = cropRect.left.toInt().clamp(0, image.width - 1);
      final y = cropRect.top.toInt().clamp(0, image.height - 1);
      final width = cropRect.width.toInt().clamp(1, image.width - x);
      final height = cropRect.height.toInt().clamp(1, image.height - y);

      // Crop the image
      final cropped = img.copyCrop(image, x: x, y: y, width: width, height: height);

      // Save to temp file
      final tempDir = await getTemporaryDirectory();
      final outputPath = '${tempDir.path}${Platform.pathSeparator}crop_${DateTime.now().millisecondsSinceEpoch}.png';
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(img.encodePng(cropped));

      return outputPath;
    } catch (e) {
      debugPrint('CropService: Error in manual crop: $e');
      return null;
    }
  }

  /// Extract a frame from a video at the current position
  /// 
  /// [controller] - The video player controller
  /// [repaintBoundaryKey] - GlobalKey attached to the RepaintBoundary wrapping the video
  /// [cropRect] - Optional crop rectangle (if null, captures full frame)
  /// 
  /// Returns the path to the captured/cropped frame image, or null on error
  Future<String?> extractVideoFrame(
    VideoPlayerController controller,
    GlobalKey repaintBoundaryKey, {
    Rect? cropRect,
  }) async {
    try {
      // Pause video to get stable frame
      final wasPlaying = controller.value.isPlaying;
      if (wasPlaying) {
        await controller.pause();
      }

      // Wait a bit for the pause to take effect
      await Future.delayed(const Duration(milliseconds: 100));

      // Capture the video frame using RepaintBoundary
      final boundary = repaintBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('CropService: Could not find RepaintBoundary');
        return null;
      }

      // Capture at higher resolution for quality
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData == null) {
        debugPrint('CropService: Failed to convert frame to bytes');
        return null;
      }

      final frameBytes = byteData.buffer.asUint8List();

      // If no crop rect, save the full frame
      if (cropRect == null) {
        final tempDir = await getTemporaryDirectory();
        final outputPath = '${tempDir.path}${Platform.pathSeparator}frame_${DateTime.now().millisecondsSinceEpoch}.png';
        final outputFile = File(outputPath);
        await outputFile.writeAsBytes(frameBytes);
        return outputPath;
      }

      // Crop the frame
      final decodedImage = img.decodeImage(frameBytes);
      if (decodedImage == null) {
        debugPrint('CropService: Failed to decode frame for cropping');
        return null;
      }

      // Scale crop rect to actual image dimensions (account for pixel ratio)
      final scaleX = decodedImage.width / (boundary.size.width);
      final scaleY = decodedImage.height / (boundary.size.height);

      final x = (cropRect.left * scaleX).toInt().clamp(0, decodedImage.width - 1);
      final y = (cropRect.top * scaleY).toInt().clamp(0, decodedImage.height - 1);
      final width = (cropRect.width * scaleX).toInt().clamp(1, decodedImage.width - x);
      final height = (cropRect.height * scaleY).toInt().clamp(1, decodedImage.height - y);

      final croppedFrame = img.copyCrop(decodedImage, x: x, y: y, width: width, height: height);

      // Save cropped frame
      final tempDir = await getTemporaryDirectory();
      final outputPath = '${tempDir.path}${Platform.pathSeparator}frame_crop_${DateTime.now().millisecondsSinceEpoch}.png';
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(img.encodePng(croppedFrame));

      return outputPath;
    } catch (e) {
      debugPrint('CropService: Error extracting video frame: $e');
      return null;
    }
  }

  /// Extract video frame without cropping - simpler method
  /// Uses RepaintBoundary to capture the video display
  Future<String?> captureVideoFrame(GlobalKey repaintBoundaryKey) async {
    try {
      final boundary = repaintBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('CropService: Could not find RepaintBoundary');
        return null;
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData == null) {
        debugPrint('CropService: Failed to convert frame to bytes');
        return null;
      }

      final tempDir = await getTemporaryDirectory();
      final outputPath = '${tempDir.path}${Platform.pathSeparator}frame_${DateTime.now().millisecondsSinceEpoch}.png';
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(byteData.buffer.asUint8List());

      return outputPath;
    } catch (e) {
      debugPrint('CropService: Error capturing video frame: $e');
      return null;
    }
  }

  /// Clean up a temporary file
  Future<void> cleanupTempFile(String? path) async {
    if (path == null) return;
    
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('CropService: Error cleaning up temp file: $e');
    }
  }

  /// Check if a path is a temporary crop file
  bool isTempCropFile(String path) {
    final fileName = path.split(Platform.pathSeparator).last;
    return fileName.startsWith('crop_') || fileName.startsWith('frame_') || fileName.startsWith('composite_');
  }

  /// Generate a composite image containing the original photo, zoomed detail with colored border,
  /// and metadata (description, reference, date).
  /// 
  /// Layout:
  /// +------------------------------------------+
  /// |              [Description]                |
  /// +------------------------------------------+
  /// |                    |                      |
  /// |   Original Photo   |   Cropped Detail     |
  /// |     (smaller)      |    (larger)          |
  /// |                    |   [COLORED BORDER]   |
  /// |                    |                      |
  /// +------------------------------------------+
  /// | Réf: [Reference]        Créée: [Date]     |
  /// +------------------------------------------+
  /// 
  /// Returns the path to the generated composite image, or null on error.
  Future<String?> generateCompositeImage({
    required String originalPath,
    required String croppedPath,
    required int qualityStatus,
    String? description,
    String? referenceName,
    DateTime? createdAt,
  }) async {
    try {
      // Load images
      final originalFile = File(originalPath);
      final croppedFile = File(croppedPath);
      
      if (!await originalFile.exists() || !await croppedFile.exists()) {
        debugPrint('CropService: Source files not found');
        return null;
      }
      
      final originalBytes = await originalFile.readAsBytes();
      final croppedBytes = await croppedFile.readAsBytes();
      
      final originalImage = img.decodeImage(originalBytes);
      final croppedImage = img.decodeImage(croppedBytes);
      
      if (originalImage == null || croppedImage == null) {
        debugPrint('CropService: Failed to decode images');
        return null;
      }
      
      // Layout constants
      const int padding = 20;
      const int borderWidth = 8;
      const int headerHeight = 50;
      const int footerHeight = 40;
      const int spacing = 16;
      
      // Calculate content area dimensions
      // Original takes ~40% of width, cropped takes ~60%
      const double originalRatio = 0.4;
      const double croppedRatio = 0.6;
      
      // Target content height (images area)
      final int contentHeight = 400;
      
      // Calculate scaled dimensions maintaining aspect ratio
      final int availableOriginalWidth = ((contentHeight * 2 - spacing) * originalRatio).toInt() - padding;
      final int availableCroppedWidth = ((contentHeight * 2 - spacing) * croppedRatio).toInt() - padding - borderWidth * 2;
      
      // Scale original image to fit
      final originalScale = _calculateScale(originalImage.width, originalImage.height, availableOriginalWidth, contentHeight - padding * 2);
      final int scaledOriginalWidth = (originalImage.width * originalScale).toInt();
      final int scaledOriginalHeight = (originalImage.height * originalScale).toInt();
      
      // Scale cropped image to fit (larger)
      final croppedScale = _calculateScale(croppedImage.width, croppedImage.height, availableCroppedWidth, contentHeight - padding * 2);
      final int scaledCroppedWidth = (croppedImage.width * croppedScale).toInt();
      final int scaledCroppedHeight = (croppedImage.height * croppedScale).toInt();
      
      // Calculate total canvas size
      final int totalWidth = padding + scaledOriginalWidth + spacing + borderWidth * 2 + scaledCroppedWidth + padding;
      final int totalHeight = headerHeight + padding + 
          (scaledOriginalHeight > scaledCroppedHeight + borderWidth * 2 ? scaledOriginalHeight : scaledCroppedHeight + borderWidth * 2) + 
          padding + footerHeight;
      
      // Create white canvas
      final composite = img.Image(width: totalWidth, height: totalHeight);
      img.fill(composite, color: img.ColorRgb8(255, 255, 255));
      
      // Get quality color for border
      final borderColor = _getQualityColor(qualityStatus);
      
      // Draw header background (light gray)
      img.fillRect(composite, 
        x1: 0, y1: 0, x2: totalWidth, y2: headerHeight,
        color: img.ColorRgb8(245, 245, 245),
      );
      
      // Draw description text at top center
      final descText = description ?? '';
      if (descText.isNotEmpty) {
        _drawTextCentered(composite, descText, totalWidth, headerHeight ~/ 2 - 8, img.ColorRgb8(50, 50, 50));
      }
      
      // Draw footer background (light gray)
      img.fillRect(composite,
        x1: 0, y1: totalHeight - footerHeight, x2: totalWidth, y2: totalHeight,
        color: img.ColorRgb8(245, 245, 245),
      );
      
      // Draw reference text at bottom left
      final refText = 'Réf: ${referenceName ?? 'N/A'}';
      _drawText(composite, refText, padding, totalHeight - footerHeight + 12, img.ColorRgb8(80, 80, 80));
      
      // Draw date text at bottom right
      final date = createdAt ?? DateTime.now();
      final dateText = 'Créée: ${_formatDate(date)}';
      _drawTextRight(composite, dateText, totalWidth - padding, totalHeight - footerHeight + 12, img.ColorRgb8(80, 80, 80));
      
      // Calculate image positions
      final int originalX = padding;
      final int originalY = headerHeight + padding + 
          ((totalHeight - headerHeight - footerHeight - padding * 2 - scaledOriginalHeight) ~/ 2);
      
      final int croppedAreaX = padding + scaledOriginalWidth + spacing;
      final int croppedAreaY = headerHeight + padding +
          ((totalHeight - headerHeight - footerHeight - padding * 2 - scaledCroppedHeight - borderWidth * 2) ~/ 2);
      
      // Draw colored border rectangle for cropped image
      img.fillRect(composite,
        x1: croppedAreaX, 
        y1: croppedAreaY, 
        x2: croppedAreaX + scaledCroppedWidth + borderWidth * 2, 
        y2: croppedAreaY + scaledCroppedHeight + borderWidth * 2,
        color: borderColor,
      );
      
      // Scale and composite original image
      final scaledOriginal = img.copyResize(originalImage, 
        width: scaledOriginalWidth, 
        height: scaledOriginalHeight,
        interpolation: img.Interpolation.linear,
      );
      img.compositeImage(composite, scaledOriginal, dstX: originalX, dstY: originalY);
      
      // Scale and composite cropped image (inside the border)
      final scaledCropped = img.copyResize(croppedImage,
        width: scaledCroppedWidth,
        height: scaledCroppedHeight,
        interpolation: img.Interpolation.linear,
      );
      img.compositeImage(composite, scaledCropped, 
        dstX: croppedAreaX + borderWidth, 
        dstY: croppedAreaY + borderWidth,
      );
      
      // Draw a thin border around the original image
      _drawRectOutline(composite, originalX, originalY, 
        originalX + scaledOriginalWidth, originalY + scaledOriginalHeight, 
        img.ColorRgb8(200, 200, 200), 2);
      
      // Save composite image
      final tempDir = await getTemporaryDirectory();
      final outputPath = '${tempDir.path}${Platform.pathSeparator}composite_${DateTime.now().millisecondsSinceEpoch}.png';
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(img.encodePng(composite));
      
      debugPrint('CropService: Generated composite image at $outputPath');
      return outputPath;
    } catch (e) {
      debugPrint('CropService: Error generating composite image: $e');
      return null;
    }
  }
  
  /// Calculate scale factor to fit image within bounds while maintaining aspect ratio
  double _calculateScale(int imageWidth, int imageHeight, int maxWidth, int maxHeight) {
    final scaleX = maxWidth / imageWidth;
    final scaleY = maxHeight / imageHeight;
    return scaleX < scaleY ? scaleX : scaleY;
  }
  
  /// Get the border color based on quality status
  img.ColorRgb8 _getQualityColor(int qualityStatus) {
    switch (qualityStatus) {
      case 4: // Bonne (OK) - Green
        return img.ColorRgb8(0x22, 0xC5, 0x5E);
      case 5: // Mauvaise (NOK) - Red
        return img.ColorRgb8(0xEF, 0x44, 0x44);
      case 6: // Neutre - Blue
      default:
        return img.ColorRgb8(0x3B, 0x82, 0xF6);
    }
  }
  
  /// Format date as DD/MM/YYYY
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
  
  /// Draw text at position using bitmap font
  void _drawText(img.Image image, String text, int x, int y, img.ColorRgb8 color) {
    img.drawString(image, text, font: img.arial24, x: x, y: y, color: color);
  }
  
  /// Draw text centered horizontally
  void _drawTextCentered(img.Image image, String text, int totalWidth, int y, img.ColorRgb8 color) {
    // Approximate character width for arial24
    final textWidth = text.length * 12;
    final x = (totalWidth - textWidth) ~/ 2;
    img.drawString(image, text, font: img.arial24, x: x, y: y, color: color);
  }
  
  /// Draw text right-aligned
  void _drawTextRight(img.Image image, String text, int rightX, int y, img.ColorRgb8 color) {
    // Approximate character width for arial24
    final textWidth = text.length * 12;
    final x = rightX - textWidth;
    img.drawString(image, text, font: img.arial24, x: x, y: y, color: color);
  }
  
  /// Draw a rectangle outline
  void _drawRectOutline(img.Image image, int x1, int y1, int x2, int y2, img.ColorRgb8 color, int thickness) {
    for (int t = 0; t < thickness; t++) {
      // Top edge
      img.drawLine(image, x1: x1 + t, y1: y1 + t, x2: x2 - t, y2: y1 + t, color: color);
      // Bottom edge
      img.drawLine(image, x1: x1 + t, y1: y2 - t, x2: x2 - t, y2: y2 - t, color: color);
      // Left edge
      img.drawLine(image, x1: x1 + t, y1: y1 + t, x2: x1 + t, y2: y2 - t, color: color);
      // Right edge
      img.drawLine(image, x1: x2 - t, y1: y1 + t, x2: x2 - t, y2: y2 - t, color: color);
    }
  }
}
