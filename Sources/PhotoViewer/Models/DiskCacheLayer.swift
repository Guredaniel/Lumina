import AppKit
import CommonCrypto // Required for MD5 hashing

/// Persistent disk cache layer for thumbnails.
/// Manages storage, retrieval, and size-based eviction of cached thumbnails.
class DiskCacheLayer {
    private let cacheDirectory: URL
    private let maxCacheSizeBytes: Int = AppConstants.Thumbnail.diskCacheSizeLimit
    private let fileManager = FileManager.default
    private var writeCounter = 0
    
    init() {
        // Initialize cache directory
        self.cacheDirectory = DiskCacheLayer.getCacheDirectory()
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    /// Retrieves a cached thumbnail from disk if it exists.
    func thumbnail(forKey key: String) -> NSImage? {
        let cachePath = cacheFilePath(forKey: key)
        guard fileManager.fileExists(atPath: cachePath.path) else {
            return nil
        }
        return NSImage(contentsOf: cachePath)
    }
    
    /// Stores a thumbnail to disk cache asynchronously.
    func cacheThumbnail(_ image: NSImage, forKey key: String) {
        // Save to disk on background thread to avoid blocking UI
        Task.detached(priority: .background) { [weak self] in
            self?.saveThumbnailToDisk(image, forKey: key)
        }
    }
    
    /// Saves a thumbnail to disk and manages cache size.
    private func saveThumbnailToDisk(_ image: NSImage, forKey key: String) {
        let cachePath = cacheFilePath(forKey: key)
        
        // Convert image to JPEG and write to disk
        if let tiffData = image.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: AppConstants.Thumbnail.compressionQuality]) {
            // Use .atomic to ensure the file is fully written before replacing old data
            try? jpegData.write(to: cachePath, options: .atomic)
        }
        
        // Only perform the expensive disk scan every 50 writes to improve performance
        writeCounter += 1
        if writeCounter % 50 == 0 {
            purgeCacheIfNeeded()
        }
    }
    
    /// Calculates a stable cache key hash for a given URL.
    /// Uses full path to avoid collisions between files with the same name in different directories.
    func cacheKey(for url: URL) -> String {
        // Use standardizedFileURL to get a consistent path, then MD5 hash for stability
        let canonicalPath = url.standardizedFileURL.path
        // Use .cache extension for internal cache files, as the content is JPEG data, not necessarily a .jpg file
        return canonicalPath.md5() + ".cache" 
    }
    
    /// Gets the file path for a cache entry.
    private func cacheFilePath(forKey key: String) -> URL {
        return cacheDirectory.appendingPathComponent(key)
    }
    
    /// Removes old cache entries if total size exceeds limit.
    /// Purges oldest files first until cache is at 80% of limit.
    private func purgeCacheIfNeeded() {
        do {
            let resources = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
            
            var totalSize = 0
            var fileInfos: [(url: URL, size: Int, date: Date)] = []
            
            for resource in resources {
                if let attributes = try? fileManager.attributesOfItem(atPath: resource.path),
                   let size = attributes[.size] as? Int,
                   let date = attributes[.modificationDate] as? Date {
                    totalSize += size
                    fileInfos.append((resource, size, date))
                }
            }
            
            // If total size exceeds limit, remove oldest files
            if totalSize > maxCacheSizeBytes {
                fileInfos.sort { $0.date < $1.date }
                
                let targetSize = Int(Double(maxCacheSizeBytes) * 0.8) // Target 80% of max
                var currentSize = totalSize
                
                for fileInfo in fileInfos {
                    if currentSize <= targetSize {
                        break
                    }
                    try? fileManager.removeItem(at: fileInfo.url)
                    currentSize -= fileInfo.size
                }
            }
        } catch {
            // Silently continue on cache purge errors
        }
    }
    
    /// Clears all cached thumbnails from disk.
    func clear() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    /// Gets or creates the cache directory URL.
    private static func getCacheDirectory() -> URL {
        if let cachePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            return cachePath.appendingPathComponent("com.photoviewer/thumbnails")
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PhotoViewerCache")
    }
}

// MARK: - String+MD5
extension String {
    func md5() -> String {
        let data = Data(self.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_MD5(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }
}
