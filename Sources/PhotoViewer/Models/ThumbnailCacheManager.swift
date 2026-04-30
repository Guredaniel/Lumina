import AppKit

/// Unified thumbnail cache manager coordinating memory and disk cache layers.
/// Provides a simple interface for thumbnail caching with automatic fallback from memory to disk.
/// 
/// Cache key strategy:
/// - Uses URL.path hash for stable, collision-free keys (fixes duplicate filename issue)
/// - Prevents cache misses when identical filenames exist in different directories
class ThumbnailCacheManager {
    static let shared = ThumbnailCacheManager()
    
    private let memoryLayer: MemoryCacheLayer
    private let diskLayer: DiskCacheLayer
    
    private init() {
        memoryLayer = MemoryCacheLayer()
        diskLayer = DiskCacheLayer()
    }
    
    // MARK: - Public Interface
    
    /// Retrieves a cached thumbnail for the given URL.
    /// Checks memory cache first, then disk cache, promoting disk hits to memory cache.
    func thumbnail(for url: URL) -> NSImage? {
        let key = cacheKey(for: url)
        
        // Check memory cache first (fastest)
        if let image = memoryLayer.thumbnail(forKey: key) {
            return image
        }
        
        // Check disk cache and promote to memory
        if let image = diskLayer.thumbnail(forKey: key) {
            memoryLayer.cacheThumbnail(image, forKey: key)
            return image
        }
        
        return nil
    }
    
    /// Caches a thumbnail in both memory and disk layers.
    func cacheThumbnail(_ image: NSImage, for url: URL) {
        let key = cacheKey(for: url)
        memoryLayer.cacheThumbnail(image, forKey: key)
        diskLayer.cacheThumbnail(image, forKey: key)
    }
    
    /// Clears all cached thumbnails from both memory and disk.
    func clear() {
        memoryLayer.clear()
        diskLayer.clear()
    }
    
    // MARK: - Private Helpers
    
    /// Generates a stable cache key from a URL.
    /// Uses hash of full path to prevent collisions between identically-named files.
    private func cacheKey(for url: URL) -> String {
        return diskLayer.cacheKey(for: url)
    }
}
