import AppKit
import ImageIO
import AVFoundation
import os

class ThumbnailService: @unchecked Sendable {
    static let shared = ThumbnailService()
    
    private let logger = Logger(subsystem: "com.photoviewer", category: "ThumbnailService")
    
    // MARK: - Thumbnail Generation
    
    /// Generates and caches a thumbnail for the given photo.
    /// Uses optimized native decoding and async/await for non-blocking operations.
    func generateThumbnail(for photo: URL, size: CGSize = CGSize(width: 200, height: 200)) async throws -> NSImage? {
        // Check cache first
        if let cachedImage = ThumbnailCacheManager.shared.thumbnail(for: photo) {
            return cachedImage
        }
        
        // Generate thumbnail on a background thread
        return try await Task.detached(priority: .userInitiated) { [self] () -> NSImage? in
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            var image: NSImage? = nil
            
            // Determine if it's a video
            let isVideo = AppConstants.SupportedFormats.videoExtensions.contains(photo.pathExtension.lowercased())
            
            if isVideo {
                image = self.generateVideoThumbnail(for: photo, size: size, scale: scale)
            } else {
                image = self.generateImageThumbnail(for: photo, size: size, scale: scale)
            }
            
            // Cache the generated image
            if let generatedImage = image {
                ThumbnailCacheManager.shared.cacheThumbnail(generatedImage, for: photo)
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
    
    /// Generates a thumbnail from a video file using AVAssetImageGenerator with robust error handling.
    /// Tries multiple seek times and includes validation and logging for edge cases.
    private func generateVideoThumbnail(for url: URL, size: CGSize, scale: CGFloat) -> NSImage? {
        let asset = AVAsset(url: url)
        
        // Validate the asset is readable and has video tracks
        guard asset.tracks(withMediaType: .video).count > 0 else {
            logger.warning("Video has no video tracks: \(url.lastPathComponent)")
            return nil
        }
        
        // Get video duration to intelligently pick a seek time
        let duration = asset.duration.seconds
        guard duration.isFinite && duration > 0 else {
            logger.warning("Video has invalid duration: \(url.lastPathComponent), duration: \(duration)")
            return nil
        }
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: size.width * scale * 2, height: size.height * scale * 2)
        
        // Try multiple seek times: 10% in, 25% in, 1 second, or 3 seconds (intelligent for short/long videos)
        let seekTimes: [CMTime] = [
            CMTime(seconds: min(duration * 0.1, 3.0), preferredTimescale: 1),
            CMTime(seconds: min(duration * 0.25, 5.0), preferredTimescale: 1),
            CMTime(seconds: min(1.0, duration * 0.5), preferredTimescale: 1),
            CMTime(seconds: min(3.0, duration * 0.8), preferredTimescale: 1)
        ]
        
        for seekTime in seekTimes {
            do {
                let cgImage = try generator.copyCGImage(at: seekTime, actualTime: nil)
                let pointSize = CGSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
                let thumbnail = NSImage(cgImage: cgImage, size: pointSize)
                logger.debug("Generated video thumbnail at \(seekTime.seconds)s for \(url.lastPathComponent)")
                return thumbnail
            } catch {
                // Log but continue to next seek time
                logger.debug("Seek time \(seekTime.seconds)s failed for \(url.lastPathComponent): \(error.localizedDescription)")
                continue
            }
        }
        
        // All seek times failed
        logger.error("Failed to generate video thumbnail for \(url.lastPathComponent) after trying \(seekTimes.count) seek times")
        return nil
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
