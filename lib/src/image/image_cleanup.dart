/// Available image display protocols.
enum ImageProtocol {
  /// Unicode half-block characters (universal fallback).
  unicodeBlocks,

  /// iTerm2 inline images protocol.
  iterm2,

  /// Sixel graphics protocol.
  sixel,

  /// Kitty graphics protocol.
  kitty,
}

/// Manages cleanup of sixel and iTerm2 images when they move or unmount.
///
/// Those protocols have no delete command, so a vacated region is
/// overwritten with spaces on the next frame. Kitty images need none of
/// this: the binding's KittyPlacer deletes a placement when it leaves the
/// frame. Unicode blocks are plain cells, overwritten naturally.
///
/// Usage:
/// ```dart
/// // When rendering an image, register it:
/// final registration = ImageCleanupManager.instance.registerImage(
///   x: 0, y: 0, width: 10, height: 5,
///   protocol: ImageProtocol.sixel,
/// );
///
/// // When disposing the image render object:
/// registration.dispose();
/// ```
class ImageCleanupManager {
  ImageCleanupManager._();

  static final ImageCleanupManager instance = ImageCleanupManager._();

  /// Pending regions that need to be cleared with spaces.
  /// These are processed during the next frame.
  final List<ImageRegion> _pendingCleanups = [];

  /// Register an image for cleanup tracking.
  ///
  /// Returns an [ImageRegistration] that should be disposed when the
  /// image component is unmounted.
  ImageRegistration registerImage({
    required int x,
    required int y,
    required int width,
    required int height,
    required ImageProtocol protocol,
  }) {
    return ImageRegistration._(
      manager: this,
      region: ImageRegion(x: x, y: y, width: width, height: height),
      protocol: protocol,
    );
  }

  /// Get pending cleanup regions and clear the list.
  ///
  /// Called by the terminal binding during rendering to get regions
  /// that need to be overwritten with spaces.
  List<ImageRegion> consumePendingCleanups() {
    final regions = List<ImageRegion>.from(_pendingCleanups);
    _pendingCleanups.clear();
    return regions;
  }

  /// Check if there are pending cleanups.
  bool get hasPendingCleanups => _pendingCleanups.isNotEmpty;

  void _scheduleSpaceCleanup(ImageRegion region) {
    _pendingCleanups.add(region);
  }

  /// Drop pending cleanups at shutdown: leaving the alternate screen
  /// takes the regions with it. (Kitty images are freed by the binding's
  /// KittyPlacer.)
  void clearAllImages() {
    _pendingCleanups.clear();
  }
}

/// Represents a registered image that will be cleaned up on dispose.
class ImageRegistration {
  ImageRegistration._({
    required ImageCleanupManager manager,
    required this.region,
    required this.protocol,
  }) : _manager = manager;

  final ImageCleanupManager _manager;
  final ImageRegion region;
  final ImageProtocol protocol;

  bool _disposed = false;

  /// Update the image region (e.g., if it moved or resized).
  ImageRegistration updateRegion({
    required int x,
    required int y,
    required int width,
    required int height,
  }) {
    return ImageRegistration._(
      manager: _manager,
      region: ImageRegion(x: x, y: y, width: width, height: height),
      protocol: protocol,
    );
  }

  /// Dispose this registration, triggering cleanup.
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    switch (protocol) {
      case ImageProtocol.sixel:
      case ImageProtocol.iterm2:
        // Schedule space overwrite for next frame
        _manager._scheduleSpaceCleanup(region);
        break;

      case ImageProtocol.kitty:
        // The binding's KittyPlacer deletes placements that leave the frame.
      case ImageProtocol.unicodeBlocks:
        // Unicode blocks are just text cells, they get overwritten naturally
        break;
    }
  }
}

/// Represents a rectangular region on the terminal.
class ImageRegion {
  final int x;
  final int y;
  final int width;
  final int height;

  const ImageRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  @override
  String toString() => 'ImageRegion($x, $y, ${width}x$height)';
}
