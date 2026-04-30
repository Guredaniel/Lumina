import AppKit
import ImageIO
import AVFoundation

class ThumbnailService {
    static let shared = ThumbnailService()
    
    // MARK: - Thumbnail Generation
    
    /// Generates and caches a thumbnail for the given photo.
    /// Uses optimized native decoding and async/await for non-blocking operations.
    func generateThumbnail(for photo: URL, size: CGSize = CGSize(width: 200, height: 200)) async throws -> NSImage? {
        // Check cache first
        if let cachedImage = ThumbnailCache.shared.thumbnail(for: photo) {
            return cachedImage
        }
        
        // Generate thumbnail on a background thread
        return try await Task.detached(priority: .userInitiated) { [weak self] () -> NSImage? in
            guard let self = self else { return nil }
            
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            var image: NSImage? = nil
            
            // Determine if it's a video
            let isVideo = AppConstants.SupportedFormats.videoExtensions.contains(photo.pathExtension.lowercased())
            
            if isVideo {
                image = self.generateVideoThumbnail(for: photo, size: size)
            } else {
                image = self.generateImageThumbnail(for: photo, size: size, scale: scale)
            }
            
            // Cache the generated image
            if let generatedImage = image {
                ThumbnailCache.shared.cacheThumbnail(generatedImage, for: photo)
            }
            
            return image
        }.value
    }
    
    /// Generates a thumbnail for an image file using optimized CGImageSource decoding.
    private func generateImageThumbnail(for photo: URL, size: CGSize, scale: CGFloat) -> NSImage? {
        let maxPixelSize = max(size.width, size.height) * scale
        
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        
        // Optimized native decoding directly from file
        if let source = CGImageSourceCreateWithURL(photo as CFURL, nil),
           let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            let pointSize = CGSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
            return NSImage(cgImage: cgImage, size: pointSize)
        }
        
        // Fallback for unsupported formats
        return loadImageFallback(photo, size: size)
    }
    
    /// Generates a thumbnail from a video file using AVAssetImageGenerator.
    private func generateVideoThumbnail(for url: URL, size: CGSize) -> NSImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: size.width * 2, height: size.height * 2)
        
        do {
            let cgImage = try generator.copyCGImage(at: AppConstants.VideoThumbnail.seekTime, actualTime: nil)
            return NSImage(cgImage: cgImage, size: size)
        } catch {
            // Video thumbnail generation failed
            return nil
        }
    }
    
    /// Fallback method for loading images that don't decode with CGImageSource.
    private func loadImageFallback(_ url: URL, size: CGSize) -> NSImage? {
        if let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
            return resizeImage(image, to: size)
        }
        
        if let image = NSImage(contentsOf: url) {
            return resizeImage(image, to: size)
        }
        
        return nil
    }
    
    /// Resizes an image to fit the target size while maintaining aspect ratio.
    private func resizeImage(_ image: NSImage, to targetSize: CGSize) -> NSImage {
        let imageSize = image.size
        let widthRatio = targetSize.width / imageSize.width
        let heightRatio = targetSize.height / imageSize.height
        let scaleFactor = max(widthRatio, heightRatio)
        
        let scaledSize = CGSize(width: imageSize.width * scaleFactor, height: imageSize.height * scaleFactor)
        let newImage = NSImage(size: scaledSize)
        
        // Simple and reliable image resizing using lockFocus
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: scaledSize),
                  from: NSRect(origin: .zero, size: imageSize),
                  operation: .copy,
                  fraction: 1.0)
        newImage.unlockFocus()
        
        newImage.cacheMode = .never
        return newImage
    }
}
