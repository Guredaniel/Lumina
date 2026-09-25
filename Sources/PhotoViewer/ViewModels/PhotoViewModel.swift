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
    @Published var tripAlbums: [TripAlbum] = []
    
    // MARK: - Private Managers
    private let scanCoordinator: ScanCoordinator
    private let directoryManager: DirectoryManager
    private let favoriteManager: FavoriteManager
    private var preCachingTask: Task<Void, Never>? = nil
    private var renamedTripTitles: [String: String]
    private var hiddenTripIDs: Set<String>
    private var combinedTripGroups: [[String]]
    private var addedTripPhotoPaths: [String: Set<String>]
    private var removedTripPhotoPaths: [String: Set<String>]
    private var tripIcons: [String: String]

    var hiddenTripCount: Int { hiddenTripIDs.count }
    
    // MARK: - Initialization
    init() {
        scanCoordinator = ScanCoordinator()
        directoryManager = DirectoryManager()
        favoriteManager = FavoriteManager()
        renamedTripTitles = UserDefaults.standard.dictionary(forKey: AppConstants.UserDefaultsKeys.tripRenamedTitles) as? [String: String] ?? [:]
        hiddenTripIDs = Set(UserDefaults.standard.stringArray(forKey: AppConstants.UserDefaultsKeys.hiddenTripIDs) ?? [])
        combinedTripGroups = UserDefaults.standard.array(forKey: AppConstants.UserDefaultsKeys.combinedTripGroups) as? [[String]] ?? []
        addedTripPhotoPaths = Self.loadPathSets(forKey: AppConstants.UserDefaultsKeys.addedTripPhotoPaths)
        removedTripPhotoPaths = Self.loadPathSets(forKey: AppConstants.UserDefaultsKeys.removedTripPhotoPaths)
        tripIcons = UserDefaults.standard.dictionary(forKey: AppConstants.UserDefaultsKeys.tripIcons) as? [String: String] ?? [:]
        
        // Load persisted state
        directoryManager.loadDirectories()
        favoriteManager.loadFavorites()
        
        // Sync directory state
        selectedDirectories = directoryManager.selectedDirectories
        favoritePaths = favoriteManager.favoritePaths
        loadPhotosFromDatabase()
        updateDerivedData()
        refreshTripAlbums()
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
        refreshTripAlbums()
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
                    self.refreshTripAlbums()
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

    func refreshTripAlbums() {
        let settings = AppSettings.shared
        guard settings.automaticTripDetection else {
            tripAlbums = []
            return
        }

        let photos = allPhotosFlat
        let detector = TripDetectionService(
            minimumPhotos: max(2, settings.tripMinimumPhotos),
            locationRadiusKilometers: max(1, settings.tripLocationRadius),
            maximumTimeGapHours: max(1, settings.tripMaximumTimeGap)
        )

        let albums = detector.detectTrips(in: photos)
        tripAlbums = applyTripPreferences(to: albums, allPhotos: photos)

        Task { [weak self] in
            var enrichedAlbums: [TripAlbum] = []
            for album in albums {
                guard let locationName = await detector.locationName(for: album.photos) else {
                    enrichedAlbums.append(album)
                    continue
                }
                enrichedAlbums.append(TripAlbum(
                    id: album.id,
                    title: "Trip to \(locationName)",
                    startDate: album.startDate,
                    endDate: album.endDate,
                    locationName: locationName,
                    photos: album.photos
                ))
            }
            guard let self else { return }
            self.tripAlbums = self.applyTripPreferences(to: enrichedAlbums, allPhotos: photos)
        }
    }

    func tripAlbum(withID id: String) -> TripAlbum? {
        tripAlbums.first { $0.id == id }
    }

    func iconName(for trip: TripAlbum) -> String {
        tripIcons[trip.id] ?? (trip.isCombined ? "rectangle.stack.fill" : "airplane")
    }

    func setIcon(_ iconName: String, forTripWithID tripID: String) {
        guard tripAlbums.contains(where: { $0.id == tripID }) else { return }
        tripIcons[tripID] = iconName
        UserDefaults.standard.set(tripIcons, forKey: AppConstants.UserDefaultsKeys.tripIcons)
        objectWillChange.send()
    }

    func renameTrip(withID id: String, title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, tripAlbums.contains(where: { $0.id == id }) else { return }
        renamedTripTitles[id] = trimmedTitle
        UserDefaults.standard.set(renamedTripTitles, forKey: AppConstants.UserDefaultsKeys.tripRenamedTitles)
        refreshTripAlbums()
    }

    func hideTrip(withID id: String) {
        guard tripAlbums.contains(where: { $0.id == id }) else { return }
        hiddenTripIDs.insert(id)
        UserDefaults.standard.set(Array(hiddenTripIDs), forKey: AppConstants.UserDefaultsKeys.hiddenTripIDs)
        tripAlbums.removeAll { $0.id == id }
    }

    func restoreHiddenTrips() {
        hiddenTripIDs.removeAll()
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.hiddenTripIDs)
        refreshTripAlbums()
    }

    func addPhoto(_ photo: Photo, toTripWithID tripID: String) {
        guard tripAlbums.contains(where: { $0.id == tripID }) else { return }
        addedTripPhotoPaths[tripID, default: []].insert(photo.url.path)
        removedTripPhotoPaths[tripID, default: []].remove(photo.url.path)
        persistTripMembership()
        refreshTripAlbums()
    }

    func removePhoto(_ photo: Photo, fromTripWithID tripID: String) {
        guard let trip = tripAlbum(withID: tripID), trip.photos.contains(where: { $0.url == photo.url }) else { return }
        addedTripPhotoPaths[tripID, default: []].remove(photo.url.path)
        removedTripPhotoPaths[tripID, default: []].insert(photo.url.path)
        persistTripMembership()
        refreshTripAlbums()
    }

    func combineTrips(withID firstID: String, and secondID: String) {
        guard firstID != secondID,
              tripAlbums.contains(where: { $0.id == firstID }),
              tripAlbums.contains(where: { $0.id == secondID }) else { return }

        let firstMembers = memberIDs(for: firstID)
        let secondMembers = memberIDs(for: secondID)
        let mergedMembers = Array(Set(firstMembers + secondMembers)).sorted()
        combinedTripGroups.removeAll { group in
            !Set(group).isDisjoint(with: mergedMembers)
        }
        combinedTripGroups.append(mergedMembers)
        let combinedID = combinedTripID(for: mergedMembers)
        let memberTitles = [firstID, secondID].compactMap { id in
            tripAlbums.first(where: { $0.id == id })?.title
        }.reduce(into: [String]()) { result, title in
            if !result.contains(title) { result.append(title) }
        }
        if renamedTripTitles[combinedID] == nil, !memberTitles.isEmpty {
            renamedTripTitles[combinedID] = memberTitles.joined(separator: " + ")
            UserDefaults.standard.set(renamedTripTitles, forKey: AppConstants.UserDefaultsKeys.tripRenamedTitles)
        }
        UserDefaults.standard.set(combinedTripGroups, forKey: AppConstants.UserDefaultsKeys.combinedTripGroups)
        refreshTripAlbums()
    }

    func separateTrip(withID id: String) {
        guard let index = combinedTripGroups.firstIndex(where: { combinedTripID(for: $0) == id }) else { return }
        combinedTripGroups.remove(at: index)
        UserDefaults.standard.set(combinedTripGroups, forKey: AppConstants.UserDefaultsKeys.combinedTripGroups)
        refreshTripAlbums()
    }

    private func applyTripPreferences(to albums: [TripAlbum], allPhotos: [Photo]) -> [TripAlbum] {
        let availableAlbums = albums.compactMap { album -> TripAlbum? in
            guard !hiddenTripIDs.contains(album.id) else { return nil }
            let membershipAdjusted = applyMembershipOverrides(to: album, allPhotos: allPhotos)
            return renamedAlbum(membershipAdjusted)
        }
        let albumsByID = Dictionary(uniqueKeysWithValues: availableAlbums.map { ($0.id, $0) })
        var consumedIDs = Set<String>()
        var combinedAlbums: [TripAlbum] = []

        for group in combinedTripGroups {
            let members = group.compactMap { albumsByID[$0] }
            guard members.count >= 2 else { continue }

            let uniquePhotos = Dictionary(uniqueKeysWithValues: members.flatMap(\.photos).map { ($0.url, $0) })
            let photos = uniquePhotos.values.sorted { $0.date > $1.date }
            guard let firstPhoto = photos.last, let lastPhoto = photos.first else { continue }
            let id = combinedTripID(for: group)
            let memberTitles = members.map(\.title).reduce(into: [String]()) { result, title in
                if !result.contains(title) { result.append(title) }
            }
            let defaultTitle = memberTitles.isEmpty ? "Combined Trip" : memberTitles.joined(separator: " + ")
            let title = renamedTripTitles[id] ?? defaultTitle
            let locations = members.compactMap(\.locationName).reduce(into: [String]()) { result, location in
                if !result.contains(location) { result.append(location) }
            }
            let combinedAlbum = TripAlbum(id: id, title: title, startDate: firstPhoto.date, endDate: lastPhoto.date, locationName: locations.isEmpty ? nil : locations.joined(separator: ", "), photos: photos)
            combinedAlbums.append(applyMembershipOverrides(to: combinedAlbum, allPhotos: allPhotos))
            consumedIDs.formUnion(group)
        }

        return (combinedAlbums + availableAlbums.filter { !consumedIDs.contains($0.id) }).sorted { $0.startDate > $1.startDate }
    }

    private func renamedAlbum(_ album: TripAlbum) -> TripAlbum {
        guard let title = renamedTripTitles[album.id] else { return album }
        return TripAlbum(id: album.id, title: title, startDate: album.startDate, endDate: album.endDate, locationName: album.locationName, photos: album.photos)
    }

    private func applyMembershipOverrides(to album: TripAlbum, allPhotos: [Photo]) -> TripAlbum {
        let removedPaths = removedTripPhotoPaths[album.id, default: []]
        let addedPaths = addedTripPhotoPaths[album.id, default: []]
        let existingPaths = Set(album.photos.map(\.url.path))
        let addedPhotos = allPhotos.filter { addedPaths.contains($0.url.path) && !existingPaths.contains($0.url.path) }
        let photos = (album.photos.filter { !removedPaths.contains($0.url.path) } + addedPhotos).sorted { $0.date > $1.date }
        return TripAlbum(id: album.id, title: album.title, startDate: photos.last?.date ?? album.startDate, endDate: photos.first?.date ?? album.endDate, locationName: album.locationName, photos: photos)
    }

    private func persistTripMembership() {
        UserDefaults.standard.set(addedTripPhotoPaths.mapValues(Array.init), forKey: AppConstants.UserDefaultsKeys.addedTripPhotoPaths)
        UserDefaults.standard.set(removedTripPhotoPaths.mapValues(Array.init), forKey: AppConstants.UserDefaultsKeys.removedTripPhotoPaths)
    }

    private static func loadPathSets(forKey key: String) -> [String: Set<String>] {
        let values = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
        return values.mapValues(Set.init)
    }

    private func memberIDs(for id: String) -> [String] {
        combinedTripGroups.first(where: { combinedTripID(for: $0) == id }) ?? [id]
    }

    private func combinedTripID(for members: [String]) -> String {
        "combined:" + members.sorted().joined(separator: "|")
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
            refreshTripAlbums()
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
        tripAlbums = []
        updateDerivedData()
        selectedPhoto = nil
        errorMessage = nil
    }
}
