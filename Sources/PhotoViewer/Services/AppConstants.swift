import Foundation
import AVFoundation

/// Centralized configuration and magic numbers for the PhotoViewer application.
enum AppConstants {
    // MARK: - UserDefaults Keys
    enum UserDefaultsKeys {
        static let favoritePhotoPaths = "favoritePhotoPaths"
        static let photoDirectories = "photoDirectories"
        static let lastPhotoDirectory = "lastPhotoDirectory" // Legacy key for migration
        static let gridColumns = "gridColumns"
        static let showFilenames = "showFilenames"
        static let enableLivePhotos = "enableLivePhotos"
        static let livePhotoPlaybackMode = "livePhotoPlaybackMode"
        static let automaticTripDetection = "automaticTripDetection"
        static let tripMinimumPhotos = "tripMinimumPhotos"
        static let tripLocationRadius = "tripLocationRadius"
        static let tripMaximumTimeGap = "tripMaximumTimeGap"
        static let tripRenamedTitles = "tripRenamedTitles"
        static let hiddenTripIDs = "hiddenTripIDs"
        static let combinedTripGroups = "combinedTripGroups"
        static let addedTripPhotoPaths = "addedTripPhotoPaths"
        static let removedTripPhotoPaths = "removedTripPhotoPaths"
        static let tripIcons = "tripIcons"
        static let userCreatedAlbums = "userCreatedAlbums"
        static let tripStartDates = "tripStartDates"
        static let tripEndDates = "tripEndDates"
        static let tripLocationNames = "tripLocationNames"
        static let lockedTripSnapshots = "lockedTripSnapshots"
    }
    
    // MARK: - Image Format Support
    enum SupportedFormats {
        static let imageUTTypes = ["com.apple.jpeg", "public.png", "public.heic", "com.compuserve.gif", "public.tiff", "public.webp"]
        static let imageExtensions = ["jpg", "jpeg", "png", "heic", "gif", "tiff", "tif", "webp"]
        static let videoExtensions = ["mp4", "mov", "m4v", "avi", "mkv", "flv", "wmv"]
    }
    
    // MARK: - Thumbnail Configuration
    enum Thumbnail {
        static let defaultSize = CGSize(width: 200, height: 200)
        static let compressionQuality: Float = 0.7
        static let memoryCacheSizeLimit = 50 * 1024 * 1024 // 50MB
        static let memoryCacheCountLimit = 500
        static let diskCacheSizeLimit = 100 * 1024 * 1024 // 100MB
    }
    
    // MARK: - Video Thumbnail Configuration
    enum VideoThumbnail {
        static let seekTime: CMTime = CMTime(seconds: 1.0, preferredTimescale: 1)
    }
    
    // MARK: - Grid Display Configuration
    enum GridDisplay {
        // 0 means adaptive/auto columns (use .adaptive GridItem)
        static let defaultColumns = 0
        static let minColumnWidth: CGFloat = 150
        static let gridSpacing: CGFloat = 12
        static let gridPadding: CGFloat = 16
    }
    
    // MARK: - Cache Directory Paths
    enum CachePaths {
        static var thumbnailCacheDirectory: URL? {
            guard let cachePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                return nil
            }
            let directory = cachePath.appendingPathComponent("com.photoviewer/thumbnails")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
        
        static var fallbackCacheDirectory: URL {
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PhotoViewerCache")
        }
    }
    
    // MARK: - UI Configuration
    enum UI {
        static let settingsWindowWidth: CGFloat = 400
        static let settingsWindowHeight: CGFloat = 210
        static let photoThumbnailSize = CGSize(width: 150, height: 150)
        static let previewPlayButtonOffsetY: CGFloat = 20
    }
    
    // MARK: - Messages
    enum Messages {
        static let noPhotosFound = "No photos found in the selected directories"
        static let errorScanningDirectories = "Error scanning directories"
        static let selectFolderPrompt = "Select a folder to scan for photos"
        static let selectFolderButton = "Select"
        static let noDirectoriesSelected = "No Directories"
        static let addDirectoryPrompt = "Add a directory to scan for photos."
    }
}
