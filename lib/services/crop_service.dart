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
    return fileName.startsWith('crop_') || fileName.startsWith('frame_');
  }
}
