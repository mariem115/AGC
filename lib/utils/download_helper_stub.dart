/// Stub for download helper - provides interface for conditional imports

/// Download a file from URL with specified filename
/// This is a stub that will be replaced by platform-specific implementations
void downloadFile(String url, String filename) {
  throw UnsupportedError('downloadFile is not supported on this platform');
}

/// Check if web download is available
bool get isWebDownloadAvailable => false;
