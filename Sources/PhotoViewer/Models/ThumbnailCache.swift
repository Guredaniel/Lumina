import AppKit

/// Legacy backward-compatible wrapper around ThumbnailCacheManager.
/// New code should use ThumbnailCacheManager directly.
/// 
/// This class exists for backward compatibility during the refactoring transition.
class ThumbnailCache {
    /// Retrieves a cached thumbnail for the given URL.
    static func thumbnail(for url: URL) -> NSImage? {
        return ThumbnailCacheManager.shared.thumbnail(for: url)
    }
    
    /// Caches a thumbnail for the given URL.
    static func cacheThumbnail(_ image: NSImage, for url: URL) {
        ThumbnailCacheManager.shared.cacheThumbnail(image, for: url)
    }
    
    /// Clears all cached thumbnails.
    static func clear() {
        ThumbnailCacheManager.shared.clear()
    }
}
