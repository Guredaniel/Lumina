import Foundation
import ImageIO
import AppKit
import UniformTypeIdentifiers

class PhotoScanner: @unchecked Sendable {
    static let shared = PhotoScanner()
    
    private let fileManager = FileManager.default
    
    func selectDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = AppConstants.Messages.selectFolderPrompt
        panel.prompt = AppConstants.Messages.selectFolderButton
        
        NSApplication.shared.activate()
        
        let response = panel.runModal()
        if response == .OK {
            return panel.url
        }
        return nil
    }
    
    // MARK: - Helper Structures
    
    struct DiscoveredFile {
        let url: URL
        let modificationDate: Date
        let fileSize: Int
        let isImage: Bool
        let isVideo: Bool
    }
    
    // MARK: - Main Scanning Operations
    
    func scanDirectories(_ directories: [URL]) async throws -> [PhotoMonth] {
        for directory in directories {
            _ = try await scanDirectory(directory)
        }
        return SQLiteDatabase.shared.fetchPhotoMonths(forDirectories: directories)
    }
    
    func scanDirectory(_ directory: URL) async throws -> [PhotoMonth] {
        guard fileManager.fileExists(atPath: directory.path) else {
            throw PhotoViewerError.invalidDirectory(path: directory.path)
        }
        
        let dirPath = directory.standardizedFileURL.path
        let knownFiles = SQLiteDatabase.shared.getKnownFiles(forDirectoryPrefix: dirPath)
        let discoveredFiles = try enumerateFiles(in: directory)
        
        let discoveredPaths = Set(discoveredFiles.map { $0.url.path })
        
        // 1. Identify and remove deleted files (in DB for this directory prefix, but no longer on disk)
        let deletedPaths = knownFiles.keys.filter { !discoveredPaths.contains($0) }
        if !deletedPaths.isEmpty {
            SQLiteDatabase.shared.deletePhotos(paths: Array(deletedPaths))
        }
        
        // 2. Identify paired Live Photo videos
        // Index all discovered video files by lowercase directory + lowercase base name
        var videoMap: [String: URL] = [:]
        for file in discoveredFiles where file.isVideo {
            let key = file.url.deletingLastPathComponent().path.lowercased() + "/" + file.url.deletingPathExtension().lastPathComponent.lowercased()
            videoMap[key] = file.url
        }
        
        var livePhotoVideoPathsLower = Set<String>()
        var imagePairedVideos: [String: URL] = [:] // image path -> matched video URL
        
        for file in discoveredFiles where file.isImage {
            let key = file.url.deletingLastPathComponent().path.lowercased() + "/" + file.url.deletingPathExtension().lastPathComponent.lowercased()
            if let matchedVideoURL = videoMap[key] {
                livePhotoVideoPathsLower.insert(matchedVideoURL.path.lowercased())
                imagePairedVideos[file.url.path] = matchedVideoURL
            } else if let pairedVideo = detectLivePhoto(for: file.url) {
                livePhotoVideoPathsLower.insert(pairedVideo.path.lowercased())
                imagePairedVideos[file.url.path] = pairedVideo
            }
        }
        
        // Remove any paired videos that were stored as standalone photos (case-insensitive check)
        let strayVideos = knownFiles.keys.filter { livePhotoVideoPathsLower.contains($0.lowercased()) }
        if !strayVideos.isEmpty {
            SQLiteDatabase.shared.deletePhotos(paths: Array(strayVideos))
        }
        
        // 3. Find files that need processing (new or changed)
        let filesToProcess = discoveredFiles.filter { file in
            // Do not process paired Live Photo videos as standalone photos
            if livePhotoVideoPathsLower.contains(file.url.path.lowercased()) {
                return false
            }
            guard let known = knownFiles[file.url.path] else {
                return true // New file
            }
            let dateDiff = abs(known.modifiedDate.timeIntervalSince(file.modificationDate))
            return dateDiff > 1.0 || known.fileSize != file.fileSize // Modified file
        }
        
        // 4. Concurrently process only the new / modified files
        if !filesToProcess.isEmpty {
            let pairedVideosSnapshot = imagePairedVideos  // Immutable capture for concurrent use
            let processedItems = try await filesToProcess.concurrentMap { file -> (photo: Photo, fileModifiedDate: Date, fileSize: Int)? in
                do {
                    let pairedVideo = pairedVideosSnapshot[file.url.path]
                    let photo = try self.processFileURL(file.url, pairedVideoURL: pairedVideo)
                    return (photo, file.modificationDate, file.fileSize)
                } catch {
                    print("Warning: Skipping file due to error at \(file.url.path): \(error.localizedDescription)")
                    return nil
                }
            }
            let validItems = processedItems.compactMap { $0 }
            SQLiteDatabase.shared.batchUpsertPhotos(validItems)
        }
        
        // Trigger duplicate cleanup in database as extra safeguard
        SQLiteDatabase.shared.cleanupDuplicateLivePhotoVideos()
        
        // 5. Fetch updated months from SQLite
        return SQLiteDatabase.shared.fetchPhotoMonths(forDirectories: [directory])
    }
    
    // MARK: - Core File Enumeration
    
    /// Enumerates all supported image and video files in a directory recursively.
    private func enumerateFiles(in directory: URL) throws -> [DiscoveredFile] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .typeIdentifierKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey]
        
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            throw PhotoViewerError.permissionDenied(path: directory.path)
        }
        
        var supportedFiles: [DiscoveredFile] = []
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(keys))
                guard resourceValues.isDirectory != true else {
                    continue
                }

                let typeIdentifier = resourceValues.typeIdentifier
                let fileExtension = fileURL.pathExtension.lowercased()
                let isImg = isImageType(typeIdentifier: typeIdentifier, fileExtension: fileExtension)
                let isVid = isVideoType(typeIdentifier: typeIdentifier, fileExtension: fileExtension)
                guard isImg || isVid else {
                    continue
                }
                
                let modDate = resourceValues.contentModificationDate ?? resourceValues.creationDate ?? Date.distantPast
                let fileSize = resourceValues.fileSize ?? 0
                
                supportedFiles.append(DiscoveredFile(
                    url: fileURL.standardizedFileURL,
                    modificationDate: modDate,
                    fileSize: fileSize,
                    isImage: isImg,
                    isVideo: isVid
                ))
            } catch {
                // Skip files we can't read metadata for
                continue
            }
        }
        
        return supportedFiles
    }
    
    /// Processes a single file URL into a Photo object.
    private func processFileURL(_ fileURL: URL, pairedVideoURL: URL? = nil) throws -> Photo {
        let keys: [URLResourceKey] = [.typeIdentifierKey, .contentModificationDateKey, .creationDateKey]
        
        let resourceValues = try fileURL.resourceValues(forKeys: Set(keys))
        let typeIdentifier = resourceValues.typeIdentifier
        let fileExtension = fileURL.pathExtension.lowercased()
        let isVideo = isVideoType(typeIdentifier: typeIdentifier, fileExtension: fileExtension)
        let date = resourceValues.contentModificationDate ?? resourceValues.creationDate ?? Date.distantPast
        
        var videoURL: URL? = nil
        if !isVideo {
            // Check for paired Live Photo video
            videoURL = pairedVideoURL ?? detectLivePhoto(for: fileURL)
        }
        
        // Extract metadata during scan for better performance
        let metadata = isVideo ? [:] : extractMetadata(for: fileURL)
        
        return Photo(
            url: fileURL.standardized,
            date: date,
            exifMetadata: metadata,
            videoURL: videoURL,
            isVideo: isVideo
        )
    }
    
    /// Detects if an image file has an associated Live Photo video.
    private func detectLivePhoto(for imageURL: URL) -> URL? {
        let baseName = imageURL.deletingPathExtension().lastPathComponent
        let dir = imageURL.deletingLastPathComponent()
        
        // Check directory contents first to get exact disk casing and avoid APFS case folding issues
        if let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            let possibleExtensions = Set(["mov", "mp4"])
            for url in contents {
                if url.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(baseName) == .orderedSame,
                   possibleExtensions.contains(url.pathExtension.lowercased()) {
                    return url.standardized
                }
            }
        }
        
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
    
    /// Extracts basic EXIF metadata from an image file.
    private func extractMetadata(for imageURL: URL) -> [String: String] {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return [:]
        }
        
        var metadata: [String: String] = [:]
        
        // Extract basic properties
        if let width = properties[kCGImagePropertyPixelWidth as String] as? NSNumber {
            metadata["width"] = String(describing: width)
        }
        if let height = properties[kCGImagePropertyPixelHeight as String] as? NSNumber {
            metadata["height"] = String(describing: height)
        }
        
        // Extract EXIF data
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            if let dateTime = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                metadata["dateTime"] = dateTime
            }
            if let make = exif["Make"] as? String {
                metadata["cameraMake"] = make
            }
            if let model = exif["Model"] as? String {
                metadata["cameraModel"] = model
            }
        }
        
        // Extract GPS data
        if let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            if let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
               let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String,
               let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double,
               let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String {
                let signedLat = latRef == "S" ? -lat : lat
                let signedLon = lonRef == "W" ? -lon : lon
                metadata["gpsLatitude"] = String(signedLat)
                metadata["gpsLongitude"] = String(signedLon)
            }
        }
        
        return metadata
    }
    
    // MARK: - File Type Detection
    
    private func isImageType(typeIdentifier: String?, fileExtension: String) -> Bool {
        let supportedExtensions = Set(AppConstants.SupportedFormats.imageExtensions)
        let supportedTypes = Set(AppConstants.SupportedFormats.imageUTTypes.map { $0.lowercased() })

        if supportedExtensions.contains(fileExtension) {
            return true
        }

        if let typeIdentifier = typeIdentifier?.lowercased() {
            if supportedTypes.contains(typeIdentifier) {
                return true
            }
            return typeIdentifier.contains("image")
        }

        return false
    }
    
    private func isVideoType(typeIdentifier: String?, fileExtension: String) -> Bool {
        let supportedExtensions = Set(AppConstants.SupportedFormats.videoExtensions)
        let supportedTypes = [
            "public.mpeg-4", "com.apple.quicktime-movie", "public.avi",
            "public.mpeg", "public.movie"
        ]

        if supportedExtensions.contains(fileExtension) {
            return true
        }

        if let typeIdentifier = typeIdentifier?.lowercased() {
            if supportedTypes.contains(typeIdentifier) {
                return true
            }
            return typeIdentifier.contains("video")
        }

        return false
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
extension Array where Element: Sendable {
    func concurrentMap<T: Sendable>(_ transform: @escaping @Sendable (Element) async throws -> T) async throws -> [T] {
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
