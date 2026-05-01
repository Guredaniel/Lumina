import Foundation
import ImageIO
import AppKit

class PhotoScanner {
    static let shared = PhotoScanner()
    
    private let fileManager = FileManager.default
    
    func selectDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = AppConstants.Messages.selectFolderPrompt
        panel.prompt = AppConstants.Messages.selectFolderButton
        
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        let response = panel.runModal()
        if response == .OK {
            return panel.url
        }
        return nil
    }
    
    // MARK: - Main Scanning Operations
    
    func scanDirectories(_ directories: [URL]) async throws -> [PhotoMonth] {
        return try await withThrowingTaskGroup(of: [Photo].self) { group in
            for directory in directories {
                group.addTask {
                    return try await self.scanDirectory(directory)
                        .flatMap { $0.photos }
                }
            }
            
            var allPhotos: [Photo] = []
            for try await photos in group {
                allPhotos.append(contentsOf: photos)
            }
            
            let groupedPhotos = self.groupPhotosByMonth(allPhotos)
            return groupedPhotos.sorted()
        }
    }
    
    func scanDirectory(_ directory: URL) async throws -> [PhotoMonth] {
        guard fileManager.fileExists(atPath: directory.path) else {
            throw PhotoViewerError.invalidDirectory(path: directory.path)
        }
        
        let photos = try await enumerateAndProcessPhotos(in: directory)
        let groupedPhotos = self.groupPhotosByMonth(photos)
        return groupedPhotos.sorted()
    }
    
    // MARK: - Core Scanning Logic (Separated)
    
    /// Enumerates all files in a directory and processes them into Photo objects.
    private func enumerateAndProcessPhotos(in directory: URL) async throws -> [Photo] {
        let fileURLs = try enumerateFiles(in: directory)
        
        let mediaItems = try await fileURLs.concurrentMap { url in
            try self.processFileURL(url)
        }
        
        // Filter out videos that are paired with images (Live Photo videos)
        let livePhotoVideoPaths = Set(mediaItems.compactMap { $0.videoURL?.path.lowercased() })
        return mediaItems.filter { item in
            if item.isVideo {
                return !livePhotoVideoPaths.contains(item.url.path.lowercased())
            }
            return true
        }
    }
    
    /// Enumerates all supported image and video files in a directory recursively.
    private func enumerateFiles(in directory: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .typeIdentifierKey, .contentModificationDateKey, .creationDateKey]
        
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            throw PhotoViewerError.permissionDenied(path: directory.path)
        }
        
        var supportedFiles: [URL] = []
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(keys))
                guard resourceValues.isDirectory != true,
                      let typeIdentifier = resourceValues.typeIdentifier,
                      isImageType(typeIdentifier) || isVideoType(typeIdentifier) else {
                    continue
                }
                supportedFiles.append(fileURL)
            } catch {
                // Skip files we can't read metadata for
                continue
            }
        }
        
        return supportedFiles
    }
    
    /// Processes a single file URL into a Photo object.
    private func processFileURL(_ fileURL: URL) throws -> Photo {
        let keys: [URLResourceKey] = [.typeIdentifierKey, .contentModificationDateKey, .creationDateKey]
        
        let resourceValues = try fileURL.resourceValues(forKeys: Set(keys))
        guard let typeIdentifier = resourceValues.typeIdentifier else {
            throw PhotoViewerError.corruptedMetadata(path: fileURL.path)
        }
        
        let isVideo = isVideoType(typeIdentifier)
        let date = resourceValues.contentModificationDate ?? resourceValues.creationDate ?? Date.distantPast
        
        var videoURL: URL? = nil
        if !isVideo {
            // Check for paired Live Photo video
            videoURL = detectLivePhoto(for: fileURL)
        }
        
        return Photo(
            url: fileURL.standardized,
            date: date,
            exifMetadata: [:],
            videoURL: videoURL,
            isVideo: isVideo
        )
    }
    
    /// Detects if an image file has an associated Live Photo video.
    private func detectLivePhoto(for imageURL: URL) -> URL? {
        let baseName = imageURL.deletingPathExtension().lastPathComponent
        let dir = imageURL.deletingLastPathComponent()
        let possibleVideoExtensions = ["mov", "MOV", "mp4", "MP4"]
        
        for ext in possibleVideoExtensions {
            let possibleURL = dir.appendingPathComponent("\(baseName).\(ext)")
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: possibleURL.path, isDirectory: &isDir), !isDir.boolValue {
                return possibleURL.standardized
            }
        }
        
        return nil
    }
    
    // MARK: - File Type Detection
    
    private func isImageType(_ typeIdentifier: String) -> Bool {
        let imageTypes = [
            "public.heic", "public.heif", "public.jpeg", "public.png",
            "public.tiff", "public.gif", "public.webp",
            "com.apple.jpeg", "com.apple.heic", "com.compuserve.gif"
        ]
        return imageTypes.contains(typeIdentifier) || typeIdentifier.contains("image")
    }
    
    private func isVideoType(_ typeIdentifier: String) -> Bool {
        let videoTypes = [
            "public.mpeg-4", "com.apple.quicktime-movie", "public.avi",
            "public.mpeg", "public.movie"
        ]
        return videoTypes.contains(typeIdentifier) || typeIdentifier.contains("video")
    }
    
    // MARK: - Photo Grouping
    
    func groupPhotosByMonth(_ photos: [Photo]) -> [PhotoMonth] {
        struct MonthKey: Hashable {
            let year: Int
            let month: Int
        }
        
        let grouped = Dictionary(grouping: photos) { photo -> MonthKey in
            let components = Calendar.current.dateComponents([.year, .month], from: photo.date)
            let year = components.year ?? 2000
            let month = components.month ?? 1
            return MonthKey(year: year, month: month)
        }
        
        return grouped.map { key, photos in
            let sortedPhotos = photos.sorted { $0.date > $1.date }
            return PhotoMonth(year: key.year, month: key.month, photos: sortedPhotos)
        }
    }
}

// Helper for concurrent mapping using Swift Concurrency TaskGroups
extension Array {
    func concurrentMap<T>(_ transform: @escaping (Element) async throws -> T) async throws -> [T] {
        // Limit concurrency to avoid saturating the thread pool and starving the UI/Image loading
        let maxConcurrency = 8
        return try await withThrowingTaskGroup(of: (Int, T).self) { group in
            var results = ContiguousArray<T?>(repeating: nil, count: self.count)
            var currentIndex = 0
            
            // Feed initial batch
            while currentIndex < Swift.min(maxConcurrency, self.count) {
                let element = self[currentIndex]
                let index = currentIndex
                group.addTask { (index, try await transform(element)) }
                currentIndex += 1
            }
            
            // As tasks finish, add new ones until done
            for try await (finishedIndex, result) in group {
                results[finishedIndex] = result
                
                if currentIndex < self.count {
                    let nextElement = self[currentIndex]
                    let nextIndex = currentIndex
                    group.addTask { (nextIndex, try await transform(nextElement)) }
                    currentIndex += 1
                }
            }
            
            return results.map { $0! }
        }
    }
}
