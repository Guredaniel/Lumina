import Foundation

/// Main view model coordinating the PhotoViewer application state.
/// Acts as a single source of truth for views, delegating specific concerns to focused managers.
@MainActor
class PhotoViewModel: ObservableObject {
    // MARK: - Published Properties (View State)
    @Published var photoMonths: [PhotoMonth] = [] {
        didSet {
            updateDerivedData()
        }
    }
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
    @Published var hiddenTripAlbums: [TripAlbum] = []
    @Published var undoableTripRemoval: TripPhotoRemoval?
    @Published var pendingAlbumPhotos: [Photo]?
    @Published var isSelectingPhotos = false
    @Published var selectedPhotoPaths: Set<String> = []
    
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
    private var userCreatedAlbums: [UserCreatedAlbum]
    private var tripStartDates: [String: Date]
    private var tripEndDates: [String: Date]
    private var tripLocationNames: [String: String]
    private var lockedTripSnapshots: [String: LockedTripSnapshot]
    private var tripRefreshGeneration = 0
    private var selectionAnchorPath: String?

    var hiddenTripCount: Int { hiddenTripAlbums.count }
    
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
        if let data = UserDefaults.standard.data(forKey: AppConstants.UserDefaultsKeys.userCreatedAlbums),
           let albums = try? JSONDecoder().decode([UserCreatedAlbum].self, from: data) {
            userCreatedAlbums = albums
        } else {
            userCreatedAlbums = []
        }
        tripStartDates = Self.loadDateMap(forKey: AppConstants.UserDefaultsKeys.tripStartDates)
        tripEndDates = Self.loadDateMap(forKey: AppConstants.UserDefaultsKeys.tripEndDates)
        tripLocationNames = UserDefaults.standard.dictionary(forKey: AppConstants.UserDefaultsKeys.tripLocationNames) as? [String: String] ?? [:]
        if let data = UserDefaults.standard.data(forKey: AppConstants.UserDefaultsKeys.lockedTripSnapshots),
           let snapshots = try? JSONDecoder().decode([LockedTripSnapshot].self, from: data) {
            lockedTripSnapshots = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        } else {
            lockedTripSnapshots = [:]
        }
        
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

    func toggleFavorites(for photos: [Photo]) {
        guard !photos.isEmpty else { return }
        let allAreFavorites = photos.allSatisfy { isFavorite(photo: $0) }
        for photo in photos {
            if allAreFavorites {
                favoriteManager.removeFavorite(photoPath: photo.url.path)
            } else {
                favoriteManager.addFavorite(photoPath: photo.url.path)
            }
        }
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
        tripRefreshGeneration += 1
        let refreshGeneration = tripRefreshGeneration
        let settings = AppSettings.shared
        let photos = allPhotosFlat
        let detector = TripDetectionService(
            minimumPhotos: max(2, settings.tripMinimumPhotos),
            locationRadiusKilometers: max(1, settings.tripLocationRadius),
            maximumTimeGapHours: max(1, settings.tripMaximumTimeGap),
            enableReverseGeocoding: settings.enableReverseGeocoding
        )

        let lockedPhotoPaths = Set(lockedTripSnapshots.values.flatMap { snapshot in
            snapshot.photoPaths + Array(addedTripPhotoPaths[snapshot.id, default: []])
        })
        let albums = settings.automaticTripDetection
            ? detector.detectTrips(in: photos).filter { album in
                lockedTripSnapshots[album.id] == nil && Set(album.photos.map(\.url.path)).isDisjoint(with: lockedPhotoPaths)
            }
            : []
        updateTripAlbumState(albums, allPhotos: photos)

        guard settings.automaticTripDetection else { return }

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
            guard self.tripRefreshGeneration == refreshGeneration else { return }
            self.updateTripAlbumState(enrichedAlbums, allPhotos: photos)
        }
    }

    func tripAlbum(withID id: String) -> TripAlbum? {
        tripAlbums.first { $0.id == id }
    }

    func iconName(for trip: TripAlbum) -> String {
        tripIcons[trip.id] ?? (trip.isManual ? "folder.fill" : (trip.isCombined ? "rectangle.stack.fill" : "airplane"))
    }

    func isTripLocked(_ id: String) -> Bool {
        lockedTripSnapshots[id] != nil
    }

    func setTripLocked(_ id: String, isLocked: Bool) {
        guard let album = tripAlbums.first(where: { $0.id == id }) else { return }
        if isLocked {
            lockedTripSnapshots[id] = LockedTripSnapshot(
                id: album.id,
                title: album.title,
                startDate: album.startDate,
                endDate: album.endDate,
                locationName: album.locationName,
                photoPaths: album.photos.map(\.url.path),
                isManual: album.isManual
            )
        } else {
            lockedTripSnapshots.removeValue(forKey: id)
        }
        persistLockedTripSnapshots()
        refreshTripAlbums()
    }

    @discardableResult
    func createAlbum(title: String) -> TripAlbum? {
        createAlbum(title: title, photos: [])
    }

    @discardableResult
    func createAlbum(title: String, photos: [Photo]) -> TripAlbum? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }
        let record = UserCreatedAlbum(id: "manual:\(UUID().uuidString)", title: trimmedTitle, createdDate: Date())
        userCreatedAlbums.append(record)
        addedTripPhotoPaths[record.id] = Set(photos.map(\.url.path))
        persistTripMembership()
        persistUserCreatedAlbums()
        refreshTripAlbums()
        return tripAlbum(withID: record.id)
    }

    func deleteAlbum(withID id: String) {
        guard let index = userCreatedAlbums.firstIndex(where: { $0.id == id }) else { return }
        userCreatedAlbums.remove(at: index)
        persistUserCreatedAlbums()

        addedTripPhotoPaths.removeValue(forKey: id)
        removedTripPhotoPaths.removeValue(forKey: id)
        persistTripMembership()

        tripIcons.removeValue(forKey: id)
        UserDefaults.standard.set(tripIcons, forKey: AppConstants.UserDefaultsKeys.tripIcons)

        renamedTripTitles.removeValue(forKey: id)
        UserDefaults.standard.set(renamedTripTitles, forKey: AppConstants.UserDefaultsKeys.tripRenamedTitles)

        tripStartDates.removeValue(forKey: id)
        tripEndDates.removeValue(forKey: id)
        tripLocationNames.removeValue(forKey: id)
        persistTripDetails()

        lockedTripSnapshots.removeValue(forKey: id)
        persistLockedTripSnapshots()

        hiddenTripIDs.remove(id)
        UserDefaults.standard.set(Array(hiddenTripIDs), forKey: AppConstants.UserDefaultsKeys.hiddenTripIDs)

        combinedTripGroups.removeAll { $0.contains(id) }
        UserDefaults.standard.set(combinedTripGroups, forKey: AppConstants.UserDefaultsKeys.combinedTripGroups)

        if undoableTripRemoval?.tripID == id {
            undoableTripRemoval = nil
        }

        refreshTripAlbums()
    }

    func requestNewAlbum(with photos: [Photo]) {
        pendingAlbumPhotos = photos
    }

    var selectedPhotos: [Photo] {
        allPhotosFlat.filter { selectedPhotoPaths.contains($0.url.path) }
    }

    func beginPhotoSelection() {
        isSelectingPhotos = true
    }

    func togglePhotoSelection(_ photo: Photo, extendSelection: Bool) {
        if extendSelection,
              let anchorPath = selectionAnchorPath,
           let startIndex = allPhotosFlat.firstIndex(where: { $0.url.path == anchorPath }),
           let endIndex = allPhotosFlat.firstIndex(where: { $0.url.path == photo.url.path }) {
            let range = startIndex <= endIndex ? startIndex...endIndex : endIndex...startIndex
            for index in range {
                selectedPhotoPaths.insert(allPhotosFlat[index].url.path)
            }
            return
        }

        if selectedPhotoPaths.contains(photo.url.path) {
            selectedPhotoPaths.remove(photo.url.path)
        } else {
            selectedPhotoPaths.insert(photo.url.path)
        }
        selectionAnchorPath = photo.url.path
    }

    func finishPhotoSelection() {
        selectedPhotoPaths.removeAll()
        selectionAnchorPath = nil
        isSelectingPhotos = false
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
        restoreHiddenTrips(withIDs: hiddenTripIDs)
    }

    func restoreHiddenTrips(withIDs ids: Set<String>) {
        hiddenTripIDs.subtract(ids)
        UserDefaults.standard.set(Array(hiddenTripIDs), forKey: AppConstants.UserDefaultsKeys.hiddenTripIDs)
        refreshTripAlbums()
    }

    func addPhoto(_ photo: Photo, toTripWithID tripID: String) {
        guard tripAlbums.contains(where: { $0.id == tripID }) else { return }
        addedTripPhotoPaths[tripID, default: []].insert(photo.url.path)
        removedTripPhotoPaths[tripID, default: []].remove(photo.url.path)
        persistTripMembership()
        undoableTripRemoval = nil
        refreshTripAlbums()
    }

    func addPhotos(_ photos: [Photo], toTripWithID tripID: String) {
        guard tripAlbums.contains(where: { $0.id == tripID }) else { return }
        for photo in photos {
            addedTripPhotoPaths[tripID, default: []].insert(photo.url.path)
            removedTripPhotoPaths[tripID, default: []].remove(photo.url.path)
        }
        persistTripMembership()
        undoableTripRemoval = nil
        refreshTripAlbums()
    }

    func removePhoto(_ photo: Photo, fromTripWithID tripID: String) {
        removePhotos([photo], fromTripWithID: tripID)
    }

    func removePhotos(_ photos: [Photo], fromTripWithID tripID: String) {
        guard let trip = tripAlbum(withID: tripID) else { return }
        let tripPaths = Set(trip.photos.map(\.url.path))
        let removedPhotos = photos.filter { tripPaths.contains($0.url.path) }
        guard !removedPhotos.isEmpty else { return }
        for photo in removedPhotos {
            addedTripPhotoPaths[tripID, default: []].remove(photo.url.path)
            removedTripPhotoPaths[tripID, default: []].insert(photo.url.path)
        }
        persistTripMembership()
        undoableTripRemoval = TripPhotoRemoval(tripID: tripID, tripTitle: trip.title, photos: removedPhotos)
        refreshTripAlbums()
    }

    func undoLastTripPhotoRemoval() {
        guard let removal = undoableTripRemoval else { return }
        for photo in removal.photos {
            removedTripPhotoPaths[removal.tripID, default: []].remove(photo.url.path)
            addedTripPhotoPaths[removal.tripID, default: []].insert(photo.url.path)
        }
        persistTripMembership()
        undoableTripRemoval = nil
        refreshTripAlbums()
    }

    func dismissTripPhotoRemoval(withID id: UUID) {
        guard undoableTripRemoval?.id == id else { return }
        undoableTripRemoval = nil
    }

    func updateTripDetails(withID id: String, startDate: Date, endDate: Date, locationName: String) {
        guard tripAlbums.contains(where: { $0.id == id }), startDate <= endDate else { return }
        tripStartDates[id] = startDate
        tripEndDates[id] = endDate
        let trimmedLocation = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLocation.isEmpty {
            tripLocationNames.removeValue(forKey: id)
        } else {
            tripLocationNames[id] = trimmedLocation
        }
        persistTripDetails()
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

    private func updateTripAlbumState(_ albums: [TripAlbum], allPhotos: [Photo]) {
        let allAlbums = applyTripPreferences(to: albums, allPhotos: allPhotos, includeHidden: true)
        hiddenTripAlbums = allAlbums.filter { hiddenTripIDs.contains($0.id) }
        tripAlbums = allAlbums.filter { !hiddenTripIDs.contains($0.id) }
    }

    private func applyTripPreferences(to albums: [TripAlbum], allPhotos: [Photo], includeHidden: Bool = false) -> [TripAlbum] {
        let detectedAlbums = albums.compactMap { album -> TripAlbum? in
            guard includeHidden || !hiddenTripIDs.contains(album.id) else { return nil }
            let membershipAdjusted = applyMembershipOverrides(to: album, allPhotos: allPhotos)
            return applyTripDetails(to: renamedAlbum(membershipAdjusted))
        }
        let manualAlbums = userCreatedAlbums.compactMap { record -> TripAlbum? in
            guard includeHidden || !hiddenTripIDs.contains(record.id) else { return nil }
            let album = TripAlbum(
                id: record.id,
                title: renamedTripTitles[record.id] ?? record.title,
                startDate: record.createdDate,
                endDate: record.createdDate,
                locationName: nil,
                photos: [],
                isManual: true
            )
            return applyTripDetails(to: applyMembershipOverrides(to: album, allPhotos: allPhotos))
        }
        let lockedAlbums = lockedTripSnapshots.values.compactMap { snapshot -> TripAlbum? in
            guard includeHidden || !hiddenTripIDs.contains(snapshot.id) else { return nil }
            let photosByPath = Dictionary(uniqueKeysWithValues: allPhotos.map { ($0.url.path, $0) })
            let photos = snapshot.photoPaths.compactMap { photosByPath[$0] }
            let lockedAlbum = TripAlbum(
                id: snapshot.id,
                title: snapshot.title,
                startDate: snapshot.startDate,
                endDate: snapshot.endDate,
                locationName: snapshot.locationName,
                photos: photos,
                isManual: snapshot.isManual
            )
            return applyTripDetails(to: renamedAlbum(applyMembershipOverrides(to: lockedAlbum, allPhotos: allPhotos)))
        }
        let availableAlbums = detectedAlbums + manualAlbums.filter { album in
            lockedTripSnapshots[album.id] == nil
        } + lockedAlbums
        let albumsByID = Dictionary(uniqueKeysWithValues: availableAlbums.map { ($0.id, $0) })
        var consumedIDs = Set<String>()
        var combinedAlbums: [TripAlbum] = []

        for group in combinedTripGroups {
            let groupID = combinedTripID(for: group)
            if lockedTripSnapshots[groupID] != nil {
                consumedIDs.formUnion(group)
                continue
            }
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
            combinedAlbums.append(applyTripDetails(to: applyMembershipOverrides(to: combinedAlbum, allPhotos: allPhotos)))
            consumedIDs.formUnion(group)
        }

        return (combinedAlbums + availableAlbums.filter { !consumedIDs.contains($0.id) }).sorted { $0.startDate > $1.startDate }
    }

    private func persistUserCreatedAlbums() {
        guard let data = try? JSONEncoder().encode(userCreatedAlbums) else { return }
        UserDefaults.standard.set(data, forKey: AppConstants.UserDefaultsKeys.userCreatedAlbums)
    }

    private func persistLockedTripSnapshots() {
        let snapshots = lockedTripSnapshots.values.sorted { $0.id < $1.id }
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        UserDefaults.standard.set(data, forKey: AppConstants.UserDefaultsKeys.lockedTripSnapshots)
    }

    private func renamedAlbum(_ album: TripAlbum) -> TripAlbum {
        guard let title = renamedTripTitles[album.id] else { return album }
        return TripAlbum(id: album.id, title: title, startDate: album.startDate, endDate: album.endDate, locationName: album.locationName, photos: album.photos, isManual: album.isManual)
    }

    private func applyTripDetails(to album: TripAlbum) -> TripAlbum {
        TripAlbum(
            id: album.id,
            title: album.title,
            startDate: tripStartDates[album.id] ?? album.startDate,
            endDate: tripEndDates[album.id] ?? album.endDate,
            locationName: tripLocationNames[album.id] ?? album.locationName,
            photos: album.photos,
            isManual: album.isManual
        )
    }

    private func applyMembershipOverrides(to album: TripAlbum, allPhotos: [Photo]) -> TripAlbum {
        let removedPaths = removedTripPhotoPaths[album.id, default: []]
        let addedPaths = addedTripPhotoPaths[album.id, default: []]
        let existingPaths = Set(album.photos.map(\.url.path))
        let addedPhotos = allPhotos.filter { addedPaths.contains($0.url.path) && !existingPaths.contains($0.url.path) }
        let photos = (album.photos.filter { !removedPaths.contains($0.url.path) } + addedPhotos).sorted { $0.date > $1.date }
        return TripAlbum(id: album.id, title: album.title, startDate: photos.last?.date ?? album.startDate, endDate: photos.first?.date ?? album.endDate, locationName: album.locationName, photos: photos, isManual: album.isManual)
    }

    private func persistTripMembership() {
        UserDefaults.standard.set(addedTripPhotoPaths.mapValues(Array.init), forKey: AppConstants.UserDefaultsKeys.addedTripPhotoPaths)
        UserDefaults.standard.set(removedTripPhotoPaths.mapValues(Array.init), forKey: AppConstants.UserDefaultsKeys.removedTripPhotoPaths)
    }

    private func persistTripDetails() {
        UserDefaults.standard.set(tripStartDates.mapValues(\.timeIntervalSince1970), forKey: AppConstants.UserDefaultsKeys.tripStartDates)
        UserDefaults.standard.set(tripEndDates.mapValues(\.timeIntervalSince1970), forKey: AppConstants.UserDefaultsKeys.tripEndDates)
        UserDefaults.standard.set(tripLocationNames, forKey: AppConstants.UserDefaultsKeys.tripLocationNames)
    }

    private static func loadPathSets(forKey key: String) -> [String: Set<String>] {
        let values = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
        return values.mapValues(Set.init)
    }

    private static func loadDateMap(forKey key: String) -> [String: Date] {
        let values = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        return values.mapValues(Date.init(timeIntervalSince1970:))
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
        deletePhotos([photo])
    }

    func deletePhotos(_ photos: [Photo]) {
        guard !photos.isEmpty else { return }
        var deletedPaths = Set<String>()
        var pathsToDeleteFromDB: [String] = []
        var lastError: Error?

        for photo in photos {
            do {
                // Move file to trash
                try FileManager.default.trashItem(at: photo.url, resultingItemURL: nil)
                deletedPaths.insert(photo.url.path)
                pathsToDeleteFromDB.append(photo.url.path)

                // Move associated live photo video to trash if it exists
                if let videoURL = photo.videoURL, FileManager.default.fileExists(atPath: videoURL.path) {
                    try? FileManager.default.trashItem(at: videoURL, resultingItemURL: nil)
                    pathsToDeleteFromDB.append(videoURL.path)
                }
            } catch {
                lastError = error
            }
        }

        if let error = lastError {
            self.errorMessage = "Failed to move one or more photos to trash: \(error.localizedDescription)"
        }

        guard !deletedPaths.isEmpty else { return }

        // Delete from SQLite database
        SQLiteDatabase.shared.deletePhotos(paths: pathsToDeleteFromDB)

        // Remove from the photoMonths array
        var updatedMonths: [PhotoMonth] = []
        for month in photoMonths {
            let remaining = month.photos.filter { !deletedPaths.contains($0.url.path) }
            if !remaining.isEmpty {
                updatedMonths.append(PhotoMonth(year: month.year, month: month.month, photos: remaining))
            }
        }
        photoMonths = updatedMonths

        selectedPhotoPaths.subtract(deletedPaths)
        if let current = selectedPhoto, deletedPaths.contains(current.url.path) {
            selectedPhoto = nil
        }

        updateDerivedData()
        refreshTripAlbums()
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
