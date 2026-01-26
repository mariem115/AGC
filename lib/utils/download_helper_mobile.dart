/// Mobile implementation of download helper
/// On mobile, we use Gal package instead, so this is a no-op stub

/// Download a file - not used on mobile (uses gallery saver instead)
void downloadFile(String url, String filename) {
  // Not implemented for mobile - use Gal package instead
  throw UnsupportedError('Use Gal package on mobile platforms');
}

/// Check if web download is available
bool get isWebDownloadAvailable => false;
