import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

/// Image utility functions
class ImageUtils {
  /// Capture widget as image
  static Future<Uint8List?> captureWidget(GlobalKey key) async {
    try {
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
  
  /// Save bytes to file
  static Future<File?> saveToFile(Uint8List bytes, String fileName) async {
    try {
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/$fileName';
      final file = File(path);
      await file.writeAsBytes(bytes);
      return file;
    } catch (_) {
      return null;
    }
  }
  
  /// Get formatted current date string
  static String getFormattedDate() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
  }
  
  /// Get formatted timestamp for file names
  static String getTimestamp() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}${now.year}_'
           '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  }
  
  /// Calculate aspect ratio preserving size
  static Size calculateFitSize(Size imageSize, Size containerSize) {
    final aspectRatio = imageSize.width / imageSize.height;
    
    double width = containerSize.width;
    double height = width / aspectRatio;
    
    if (height > containerSize.height) {
      height = containerSize.height;
      width = height * aspectRatio;
    }
    
    return Size(width, height);
  }
}
