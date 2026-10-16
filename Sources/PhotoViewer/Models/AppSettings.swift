import Foundation
import Combine

/// Centralized observable settings model for the PhotoViewer application.
/// Provides a single source of truth for all user preferences and application state.
@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    // MARK: - Grid Display Settings
    @Published var gridColumns: Int {
        didSet {
            UserDefaults.standard.set(gridColumns, forKey: AppConstants.UserDefaultsKeys.gridColumns)
        }
    }
    
    @Published var showFilenames: Bool {
        didSet {
            UserDefaults.standard.set(showFilenames, forKey: AppConstants.UserDefaultsKeys.showFilenames)
        }
    }
    
    // MARK: - Live Photo Settings
    @Published var enableLivePhotos: Bool {
        didSet {
            UserDefaults.standard.set(enableLivePhotos, forKey: AppConstants.UserDefaultsKeys.enableLivePhotos)
        }
    }
    
    @Published var livePhotoPlaybackMode: String {
        didSet {
            UserDefaults.standard.set(livePhotoPlaybackMode, forKey: AppConstants.UserDefaultsKeys.livePhotoPlaybackMode)
        }
    }

    @Published var automaticTripDetection: Bool {
        didSet {
            UserDefaults.standard.set(automaticTripDetection, forKey: AppConstants.UserDefaultsKeys.automaticTripDetection)
        }
    }

    @Published var tripMinimumPhotos: Int {
        didSet {
            UserDefaults.standard.set(tripMinimumPhotos, forKey: AppConstants.UserDefaultsKeys.tripMinimumPhotos)
        }
    }

    @Published var tripLocationRadius: Double {
        didSet {
            UserDefaults.standard.set(tripLocationRadius, forKey: AppConstants.UserDefaultsKeys.tripLocationRadius)
        }
    }

    @Published var tripMaximumTimeGap: Double {
        didSet {
            UserDefaults.standard.set(tripMaximumTimeGap, forKey: AppConstants.UserDefaultsKeys.tripMaximumTimeGap)
        }
    }
    
    // MARK: - Thumbnail Settings
    var thumbnailSize: CGSize {
        return AppConstants.Thumbnail.defaultSize
    }
    
    var thumbnailCompressionQuality: Float {
        return AppConstants.Thumbnail.compressionQuality
    }
    
    // MARK: - Cache Settings
    var thumbnailCachePath: URL {
        return AppConstants.CachePaths.thumbnailCacheDirectory ?? AppConstants.CachePaths.fallbackCacheDirectory
    }
    
    // MARK: - Initialization
    private init() {
        // Load or set default values
        let defaults = UserDefaults.standard
        
        self.gridColumns = defaults.object(forKey: AppConstants.UserDefaultsKeys.gridColumns) as? Int ?? AppConstants.GridDisplay.defaultColumns
        self.showFilenames = defaults.bool(forKey: AppConstants.UserDefaultsKeys.showFilenames)
        self.enableLivePhotos = defaults.object(forKey: AppConstants.UserDefaultsKeys.enableLivePhotos) as? Bool ?? true
        // Default live photo playback to play once for a less intrusive UX
        self.livePhotoPlaybackMode = defaults.string(forKey: AppConstants.UserDefaultsKeys.livePhotoPlaybackMode) ?? "once"
        self.automaticTripDetection = defaults.object(forKey: AppConstants.UserDefaultsKeys.automaticTripDetection) as? Bool ?? true
        self.tripMinimumPhotos = defaults.object(forKey: AppConstants.UserDefaultsKeys.tripMinimumPhotos) as? Int ?? 10
        self.tripLocationRadius = defaults.object(forKey: AppConstants.UserDefaultsKeys.tripLocationRadius) as? Double ?? 75
        self.tripMaximumTimeGap = defaults.object(forKey: AppConstants.UserDefaultsKeys.tripMaximumTimeGap) as? Double ?? 36
    }
    
    // MARK: - Reset to Defaults
    func resetToDefaults() {
        gridColumns = AppConstants.GridDisplay.defaultColumns
        showFilenames = false
        enableLivePhotos = true
        livePhotoPlaybackMode = "once"
        automaticTripDetection = true
        tripMinimumPhotos = 10
        tripLocationRadius = 75
        tripMaximumTimeGap = 36
    }
}
