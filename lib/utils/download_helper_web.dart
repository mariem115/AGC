// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Download a file from URL with specified filename (Web implementation)
void downloadFile(String url, String filename) {
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..style.display = 'none';
  
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}

/// Check if web download is available
bool get isWebDownloadAvailable => true;
