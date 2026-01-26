// Script to create a padded version of the logo for app icons
// Run with: dart run scripts/create_padded_icon.dart

import 'dart:io';
import 'package:image/image.dart' as img;

void main() async {
  print('Creating padded icon from Qualifour logo...');
  
  // Load the original logo
  final logoFile = File('assets/images/qualifour_logo.png');
  if (!logoFile.existsSync()) {
    print('Error: Logo file not found at assets/images/qualifour_logo.png');
    exit(1);
  }
  
  final logoBytes = await logoFile.readAsBytes();
  final logo = img.decodeImage(logoBytes);
  
  if (logo == null) {
    print('Error: Could not decode logo image');
    exit(1);
  }
  
  print('Original logo size: ${logo.width}x${logo.height}');
  
  // Create a square canvas (1024x1024 for high quality icons)
  final canvasSize = 1024;
  
  // Scale logo to ~70% of canvas size while maintaining aspect ratio
  final targetSize = (canvasSize * 0.70).toInt();
  
  // Calculate scaled dimensions maintaining aspect ratio
  int scaledWidth, scaledHeight;
  if (logo.width > logo.height) {
    scaledWidth = targetSize;
    scaledHeight = (logo.height * targetSize / logo.width).toInt();
  } else {
    scaledHeight = targetSize;
    scaledWidth = (logo.width * targetSize / logo.height).toInt();
  }
  
  print('Scaled logo size: ${scaledWidth}x${scaledHeight}');
  
  // Resize the logo
  final scaledLogo = img.copyResize(
    logo,
    width: scaledWidth,
    height: scaledHeight,
    interpolation: img.Interpolation.cubic,
  );
  
  // Create a new transparent canvas with white background for icons
  final canvas = img.Image(
    width: canvasSize,
    height: canvasSize,
    numChannels: 4,
  );
  
  // Fill with white background (required for iOS icons)
  img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 255));
  
  // Calculate position to center the logo
  final x = (canvasSize - scaledWidth) ~/ 2;
  final y = (canvasSize - scaledHeight) ~/ 2;
  
  print('Logo position: ($x, $y)');
  
  // Composite the logo onto the canvas
  img.compositeImage(canvas, scaledLogo, dstX: x, dstY: y);
  
  // Save the padded icon
  final outputFile = File('assets/images/app_icon.png');
  await outputFile.writeAsBytes(img.encodePng(canvas));
  
  print('Padded icon saved to: assets/images/app_icon.png');
  print('Icon size: ${canvasSize}x${canvasSize}');
  print('Logo scaled to ${(targetSize / canvasSize * 100).toStringAsFixed(0)}% of icon size');
  print('\nNow update pubspec.yaml to use app_icon.png and run:');
  print('dart run flutter_launcher_icons');
}
