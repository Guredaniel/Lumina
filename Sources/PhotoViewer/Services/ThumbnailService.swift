import AppKit
import ImageIO
import AVFoundation

class ThumbnailService {
    static let shared = ThumbnailService()
    
    private let thumbnailQueue = DispatchQueue(label: "com.photoviewer.thumbnails", attributes: .concurrent)
    
    func generateThumbnail(for photo: URL, size: CGSize = CGSize(width: 200, height: 200), completion: @escaping (NSImage?) -> Void) {
        // Check cache first
        if let cachedImage = ThumbnailCache.shared.thumbnail(for: photo) {
            DispatchQueue.main.async {
                completion(cachedImage)
            }
            return
        }
        
        // Generate thumbnail asynchronously
        thumbnailQueue.async {
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            var image: NSImage? = nil
            
            // Check if it's a video based on file extension
            let videoExtensions = ["mp4", "mov", "m4v", "avi"]
            if videoExtensions.contains(photo.pathExtension.lowercased()) {
                image = self.generateVideoThumbnail(for: photo, size: size)
            } else {
                let maxPixelSize = max(size.width, size.height) * scale
                
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
                ]
                
                // Highly optimized native read directly from the file without pulling huge Data into memory
                if let source = CGImageSourceCreateWithURL(photo as CFURL, nil),
                   let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                    // Set point size properly
                    let pointSize = CGSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
                    image = NSImage(cgImage: cgImage, size: pointSize)
                } else {
                    // Fallback for weird formats
                    image = self.loadImageFallback(photo, size: size)
                }
            }
            
            if let generatedImage = image {
                ThumbnailCache.shared.cacheThumbnail(generatedImage, for: photo)
            }
            
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }
    
    private func generateVideoThumbnail(for url: URL, size: CGSize) -> NSImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: size.width * 2, height: size.height * 2)
        
        let time = CMTime(seconds: 1, preferredTimescale: 60)
        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            return NSImage(cgImage: cgImage, size: size)
        } catch {
            print("Error generating video thumbnail: \(error)")
            return nil
        }
    }
    
    private func loadImageFallback(_ url: URL, size: CGSize) -> NSImage? {
        guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else {
            guard let fallback = NSImage(contentsOf: url) else { return nil }
            return resizeImage(fallback, to: size)
        }
        
        return resizeImage(image, to: size)
    }
    
    private func resizeImage(_ image: NSImage, to targetSize: CGSize) -> NSImage {
        // Calculate the aspect ratio preserving dimensions
        let imageSize = image.size
        let widthRatio  = targetSize.width  / imageSize.width
        let heightRatio = targetSize.height / imageSize.height
        
        // We want to fill the target size, so we take the max of the two ratios
        let scaleFactor = max(widthRatio, heightRatio)
        
        let scaledSize = CGSize(width: imageSize.width * scaleFactor, height: imageSize.height * scaleFactor)
        
        let newImage = NSImage(size: scaledSize)
        
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: scaledSize), from: NSRect(origin: .zero, size: imageSize), operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        
        newImage.cacheMode = .never
        return newImage
    }
}
