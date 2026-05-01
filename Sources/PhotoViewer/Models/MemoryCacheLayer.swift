import AppKit

/// In-memory cache layer for thumbnails using NSCache.
/// Provides fast O(1) access to recently-used thumbnails.
class MemoryCacheLayer {
    private let cache = NSCache<NSString, NSImage>()
    
    init() {
        cache.totalCostLimit = AppConstants.Thumbnail.memoryCacheSizeLimit
        cache.countLimit = AppConstants.Thumbnail.memoryCacheCountLimit
    }
    
    /// Retrieves a thumbnail from memory cache.
    func thumbnail(forKey key: String) -> NSImage? {
        return cache.object(forKey: key as NSString)
    }
    
    /// Stores a thumbnail in memory cache with estimated cost.
    func cacheThumbnail(_ image: NSImage, forKey key: String) {
        let cost = estimateImageSize(image)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
    
    /// Clears all cached thumbnails from memory.
    func clear() {
        cache.removeAllObjects()
    }
    
    /// Clears a specific cached thumbnail from memory.
    func clearCache(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }
    
    /// Estimates the memory cost of an image for cache accounting.
    private func estimateImageSize(_ image: NSImage) -> Int {
        let size = image.size
        // Estimate 4 bytes per pixel (RGBA) for a standard uncompressed representation
        return Int(size.width * size.height * 4)
    }
}
