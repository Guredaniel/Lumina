import Foundation

/// Main view model coordinating the PhotoViewer application state.
/// Acts as a single source of truth for views, delegating specific concerns to focused managers.
@MainActor
class PhotoViewModel: ObservableObject {
    // MARK: - Published Properties (View State)
    @Published var photoMonths: [PhotoMonth] = []
    @Published var isLoading = false
    @Published var selectedPhoto: Photo? = nil
    @Published var isScanning = false
    @Published var errorMessage: String? = nil
    @Published var selectedDirectories: [URL] = []
    @Published var favoritePaths: Set<String> = []
    
    // Optimized Derived Data
    @Published var groupedYears: [Int: [PhotoMonth]] = [:]
    @Published var sortedYears: [Int] = []
    @Published var favoritePhotos: [Photo] = []
    @Published var allPhotosFlat: [Photo] = []
    
    // MARK: - Private Managers
    private let scanCoordinator: ScanCoordinator
    private let directoryManager: DirectoryManager
    private let favoriteManager: FavoriteManager
    private var preCachingTask: Task<Void, Never>? = nil
    
    // MARK: - Initialization
    init() {
        scanCoordinator = ScanCoordinator()
        directoryManager = DirectoryManager()
        favoriteManager = FavoriteManager()
        
        // Load persisted state
        directoryManager.loadDirectories()
        favoriteManager.loadFavorites()
        
        // Sync directory state
        selectedDirectories = directoryManager.selectedDirectories
        favoritePaths = favoriteManager.favoritePaths
        loadPhotosFromDatabase()
        updateDerivedData()
    }
    
    // MARK: - Directory Management (delegates to DirectoryManager)
    
    func addDirectory() {
        guard let directory = directoryManager.selectAndAddDirectory() else {
            return
        }
        selectedDirectories = directoryManager.selectedDirectories
        scanAllDirectories()
    }
    
    func removeDirectory(_ url: URL) {
        directoryManager.removeDirectory(url)
        selectedDirectories = directoryManager.selectedDirectories
        self.photoMonths = SQLiteDatabase.shared.fetchPhotoMonths(forDirectories: selectedDirectories)
        updateDerivedData()
    }
    
    func loadDirectories() {
        directoryManager.loadDirectories()
        selectedDirectories = directoryManager.selectedDirectories
        scanAllDirectories(showLoading: false)
    }
    
    // MARK: - Favorite Management (delegates to FavoriteManager)
    
    func toggleFavorite(photo: Photo) {
        favoriteManager.toggleFavorite(photoPath: photo.url.path)
        favoritePaths = favoriteManager.favoritePaths
        updateDerivedData()
    }
    
    func isFavorite(photo: Photo) -> Bool {
        favoriteManager.isFavorite(photoPath: photo.url.path)
    }
    
    // MARK: - Scan Operations (delegates to ScanCoordinator)
    
    func scanAllDirectories(showLoading: Bool = true) {
        // Prevent concurrent scans
        guard !isScanning else { return }
        
        isScanning = true
        if showLoading {
            isLoading = true
            photoMonths = []
        }
        errorMessage = nil
        
        // Early exit if no directories selected
        if selectedDirectories.isEmpty {
            isLoading = false
            isScanning = false
            return
        }
        
        Task {
            do {
                let months = try await PhotoScanner.shared.scanDirectories(selectedDirectories)
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.photoMonths = months
                    self.updateDerivedData()
                    self.startBackgroundThumbnailCaching()
                    self.isLoading = false
                    self.isScanning = false
                    
                    if months.isEmpty {
                        self.errorMessage = AppConstants.Messages.noPhotosFound
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.isLoading = false
                    self.isScanning = false
                    let photoError = error as? PhotoViewerError ?? .scanFailed(reason: error.localizedDescription)
                    self.errorMessage = photoError.errorDescription
                }
            }
        }
    }
    
    /// Starts a background task to pre-generate thumbnails for all discovered photos.
    /// This populates the cache so images appear instantly when scrolling.
    private func startBackgroundThumbnailCaching() {
        preCachingTask?.cancel()
        let photos = allPhotosFlat
        
        preCachingTask = Task(priority: .background) { [weak self] in
            for photo in photos {
                guard let self = self, !Task.isCancelled else { break }
                
                // generateThumbnail internally checks if it's already cached
                _ = try? await ThumbnailService.shared.generateThumbnail(for: photo.url)
                await Task.yield() // Ensure we don't starve the UI thread
            }
        }
    }
    
    /// Updates grouped data once to prevent UI "jumping" during selection changes
    private func updateDerivedData() {
        let months = self.photoMonths
        let paths = self.favoritePaths
        
        self.allPhotosFlat = months.flatMap { $0.photos }
        self.groupedYears = Dictionary(grouping: months, by: { $0.year })
        self.sortedYears = groupedYears.keys.sorted(by: >)
        self.favoritePhotos = allPhotosFlat.filter { paths.contains($0.url.path) }
    }
    
    private func loadPhotosFromDatabase() {
        SQLiteDatabase.shared.cleanupDuplicateLivePhotoVideos()
        guard !selectedDirectories.isEmpty else {
            self.photoMonths = []
            return
        }
        self.photoMonths = SQLiteDatabase.shared.fetchPhotoMonths(forDirectories: selectedDirectories)
    }
    
    // MARK: - Photo Navigation
    
    func getPhotosInMonth(_ month: PhotoMonth) -> [Photo] {
        return month.photos
    }
    
    func photoMonth(withID id: String) -> PhotoMonth? {
        return photoMonths.first(where: { $0.id == id })
            ?? groupedYears.values.flatMap { $0 }.first(where: { $0.id == id })
    }
    
    func nextPhoto(after photo: Photo) -> Photo? {
        let all = allPhotosFlat
        guard let index = all.firstIndex(where: { $0.url == photo.url }) else { return nil }
        return index < all.count - 1 ? all[index + 1] : nil
    }
    
    func previousPhoto(before photo: Photo) -> Photo? {
        let all = allPhotosFlat
        guard let index = all.firstIndex(where: { $0.url == photo.url }) else { return nil }
        return index > 0 ? all[index - 1] : nil
    }
    
    // MARK: - Photo Management
    
    func deletePhoto(_ photo: Photo) {
        do {
            // Move file to trash
            try FileManager.default.trashItem(at: photo.url, resultingItemURL: nil)
            
            // Move associated live photo video to trash if it exists
            if let videoURL = photo.videoURL, FileManager.default.fileExists(atPath: videoURL.path) {
                try? FileManager.default.trashItem(at: videoURL, resultingItemURL: nil)
            }
            
            // Delete from SQLite database
            var pathsToDelete = [photo.url.path]
            if let videoURL = photo.videoURL {
                pathsToDelete.append(videoURL.path)
            }
            SQLiteDatabase.shared.deletePhotos(paths: pathsToDelete)
            
            // Remove from the photoMonths array
            for i in 0..<photoMonths.count {
                if let photoIndex = photoMonths[i].photos.firstIndex(where: { $0.url == photo.url }) {
                    var updatedPhotos = photoMonths[i].photos
                    updatedPhotos.remove(at: photoIndex)
                    
                    if updatedPhotos.isEmpty {
                        photoMonths.remove(at: i)
                    } else {
                        photoMonths[i] = PhotoMonth(year: photoMonths[i].year, month: photoMonths[i].month, photos: updatedPhotos)
                    }
                    break
                }
            }
            
            updateDerivedData()
            if selectedPhoto == photo {
                selectedPhoto = nil
            }
        } catch {
            self.errorMessage = "Failed to move photo to trash: \(error.localizedDescription)"
        }
    }
    
    func clearPhotos() {
        preCachingTask?.cancel()
        photoMonths = []
        updateDerivedData()
        selectedPhoto = nil
        errorMessage = nil
    }
}
