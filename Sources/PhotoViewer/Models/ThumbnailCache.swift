import AppKit

class ThumbnailCache {
    static let shared = ThumbnailCache()
    
    private let memoryCache = NSCache<NSString, NSImage>()
    private let cacheDirectory: URL
    private let maxCacheSize: Int = 100 * 1024 * 1024 // 100MB
    
    private init() {
        // Set up cache directory
        if let cachePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            cacheDirectory = cachePath.appendingPathComponent("com.photoviewer/thumbnails")
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } else {
            cacheDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PhotoViewerCache")
        }
        
        // Configure memory cache
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB in memory
        memoryCache.countLimit = 500
    }
    
    func thumbnail(for url: URL) -> NSImage? {
        let cacheKey = url.lastPathComponent as NSString
        
        // Check memory cache first
        if let cachedImage = memoryCache.object(forKey: cacheKey) {
            return cachedImage
        }
        
        // Check disk cache
        if let diskImage = loadFromDiskCache(for: url) {
            memoryCache.setObject(diskImage, forKey: cacheKey, cost: estimateImageSize(diskImage))
            return diskImage
        }
        
        return nil
    }
    
    func cacheThumbnail(_ image: NSImage, for url: URL) {
        let cacheKey = url.lastPathComponent as NSString
        let cost = estimateImageSize(image)
        
        memoryCache.setObject(image, forKey: cacheKey, cost: cost)
        saveToDiskCache(image, for: url)
    }
    
    private func loadFromDiskCache(for url: URL) -> NSImage? {
        let diskCachePath = cacheFilePath(for: url)
        return NSImage(contentsOf: diskCachePath)
    }
    
    private func saveToDiskCache(_ image: NSImage, for url: URL) {
        let diskCachePath = cacheFilePath(for: url)
        
        DispatchQueue.global(qos: .background).async {
            if let tiffData = image.tiffRepresentation,
               let bitmapImage = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                try? jpegData.write(to: diskCachePath)
            }
            
            // Manage cache size
            self.purgeCacheIfNeeded()
        }
    }
    
    private func cacheFilePath(for url: URL) -> URL {
        let filename = url.lastPathComponent + ".jpg"
        return cacheDirectory.appendingPathComponent(filename)
    }
    
    private func estimateImageSize(_ image: NSImage) -> Int {
        guard let tiffData = image.tiffRepresentation else { return 100 * 1024 }
        return tiffData.count
    }
    
    private func purgeCacheIfNeeded() {
        do {
            let resources = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
            
            var totalSize: Int = 0
            var fileInfos: [(url: URL, size: Int, date: Date)] = []
            
            for resource in resources {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: resource.path),
                   let size = attributes[.size] as? Int,
                   let date = attributes[.modificationDate] as? Date {
                    totalSize += size
                    fileInfos.append((resource, size, date))
                }
            }
            
            if totalSize > maxCacheSize {
                // Sort by modification date (oldest first) and remove oldest files
                fileInfos.sort { $0.date < $1.date }
                
                var currentSize = totalSize
                for fileInfo in fileInfos {
                    if currentSize <= maxCacheSize * 8 / 10 { // Keep it at 80% of limit
                        break
                    }
                    try? FileManager.default.removeItem(at: fileInfo.url)
                    currentSize -= fileInfo.size
                }
            }
        } catch {
            print("Error purging cache: \(error)")
        }
    }
    
    func clear() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}
