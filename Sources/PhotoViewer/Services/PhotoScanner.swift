import Foundation
import ImageIO
import AppKit

class PhotoScanner {
    static let shared = PhotoScanner()
    
    private let supportedUTTypes = ["com.apple.jpeg", "public.png", "public.heic", "com.compuserve.gif", "public.tiff", "public.webp"]
    
    func selectDirectory() -> URL? {
        // Ensure the panel is created and displayed on the main thread
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to scan for photos"
        panel.prompt = "Select"
        
        // Make the app active and present the dialog
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        let response = panel.runModal()
        
        if response == .OK {
            print("DEBUG: Selected directory: \(panel.url?.path ?? "nil")")
            return panel.url
        } else {
            print("DEBUG: No directory selected (response: \(response.rawValue))")
            return nil
        }
    }
    
    func scanDirectories(_ directories: [URL]) async throws -> [PhotoMonth] {
        return try await withThrowingTaskGroup(of: [Photo].self) { group in
            for directory in directories {
                group.addTask {
                    print("DEBUG: Starting recursive image search in: \(directory.path)")
                    return try await self.recursiveImageSearch(in: directory)
                }
            }
            
            var allPhotos: [Photo] = []
            for try await photos in group {
                allPhotos.append(contentsOf: photos)
            }
            
            print("DEBUG: Found \(allPhotos.count) total photos across directories")
            let groupedPhotos = self.groupPhotosByMonth(allPhotos)
            let sortedMonths = groupedPhotos.sorted()
            return sortedMonths
        }
    }
    
    func scanDirectory(_ directory: URL) async throws -> [PhotoMonth] {
        let photos = try await self.recursiveImageSearch(in: directory)
        let groupedPhotos = self.groupPhotosByMonth(photos)
        return groupedPhotos.sorted()
    }
    
    private func recursiveImageSearch(in directory: URL) async throws -> [Photo] {
        let fileManager = FileManager.default
        // Pre-fetch all needed keys here to avoid re-hitting the disk in the loop
        let keys: [URLResourceKey] = [.isDirectoryKey, .typeIdentifierKey, .contentModificationDateKey, .creationDateKey]
        
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            throw NSError(domain: "PhotoScanner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot access directory"])
        }
        
        // Store URL and pre-fetched metadata together
        var itemsToProcess: [(url: URL, type: String, date: Date)] = []
        
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: Set(keys)),
               resourceValues.isDirectory != true,
               let typeIdentifier = resourceValues.typeIdentifier,
               (isImageType(typeIdentifier) || isVideoType(typeIdentifier)) {
                
                // Swapping priority: Modification date is often more reliable than creation date 
                // on macOS for moved files. Defaulting to distantPast to avoid current month (April 2026).
                let date = resourceValues.contentModificationDate ?? resourceValues.creationDate ?? Date.distantPast
                itemsToProcess.append((fileURL, typeIdentifier, date))
            }
        }
        
        // Process media in parallel batches to avoid overloading the system
        let mediaItems = try await itemsToProcess.concurrentMap { item in
            let isVideo = self.isVideoType(item.type)
            let url = item.url
            var videoURL: URL? = nil
            
            if !isVideo {
                // Check for paired video (Live Photo)
                let baseName = url.deletingPathExtension().lastPathComponent
                let dir = url.deletingLastPathComponent()
                let possibleVideoExtensions = ["mov", "MOV", "mp4", "MP4"]
                
                for ext in possibleVideoExtensions {
                    let possibleURL = dir.appendingPathComponent("\(baseName).\(ext)")
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: possibleURL.path, isDirectory: &isDir), !isDir.boolValue {
                        // Standardize the URL to ensure matching works correctly later
                        videoURL = possibleURL.standardized
                        break
                    }
                }
            }
            
            return Photo(url: url.standardized, date: item.date, exifMetadata: [:], videoURL: videoURL, isVideo: isVideo)
        }
        
        // Filter out videos that are actually part of a Live Photo
        // Use standardized paths to ensure the filter correctly identifies the video files
        let livePhotoVideoPaths = Set(mediaItems.compactMap { $0.videoURL?.path.lowercased() })
        return mediaItems.filter { item in
            if item.isVideo {
                return !livePhotoVideoPaths.contains(item.url.path.lowercased())
            }
            return true
        }
    }
    
    private func extractMetadata(from url: URL) -> (Date?, [String: Any]) {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
            return (nil, [:])
        }
        
        var metadata: [String: Any] = [:]
        var date: Date? = nil
        
        if let exifDict = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            if let dateString = exifDict[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                date = parseEXIFDate(dateString)
                metadata["dateTime"] = dateString
            }
            if let make = exifDict["Make"] { metadata["cameraMake"] = make }
            if let model = exifDict["Model"] { metadata["cameraModel"] = model }
            if let iso = exifDict[kCGImagePropertyExifISOSpeedRatings as String] { metadata["iso"] = iso }
        }
        
        if let pixelWidth = properties[kCGImagePropertyPixelWidth as String] { metadata["width"] = pixelWidth }
        if let pixelHeight = properties[kCGImagePropertyPixelHeight as String] { metadata["height"] = pixelHeight }
        if let orientation = properties[kCGImagePropertyOrientation as String] { metadata["Orientation"] = orientation }
        
        return (date, metadata)
    }
    
    private func isImageType(_ typeIdentifier: String) -> Bool {
        let imageTypes = [
            "public.heic",
            "public.heif",
            "public.jpeg",
            "public.png",
            "public.tiff",
            "public.gif",
            "public.webp",
            "com.apple.jpeg",
            "com.apple.heic",
            "com.compuserve.gif"
        ]
        return imageTypes.contains(typeIdentifier) || typeIdentifier.contains("image")
    }
    
    private func isVideoType(_ typeIdentifier: String) -> Bool {
        let videoTypes = [
            "public.mpeg-4",
            "com.apple.quicktime-movie",
            "public.avi",
            "public.mpeg",
            "public.movie"
        ]
        return videoTypes.contains(typeIdentifier) || typeIdentifier.contains("video")
    }
    
    private func parseEXIFDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: dateString)
    }
    
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
            PhotoMonth(year: key.year, month: key.month, photos: photos)
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
