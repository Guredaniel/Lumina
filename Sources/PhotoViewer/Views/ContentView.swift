import SwiftUI
import AppKit

enum SidebarSelection: Hashable {
    case allPhotos
    case favorites
    case source(URL)
    case sourceYear(URL, Int)
    case sourceMonth(URL, String)
    case year(Int)
    case month(String)
    case trip(String)
}

struct ContentView: View {
    @ObservedObject var viewModel: PhotoViewModel
    @State private var selection: SidebarSelection? = .allPhotos
    @State private var tripToRename: TripAlbum?
    @State private var renameText = ""
    @State private var tripToEdit: TripAlbum?
    @State private var editStartDate = Date()
    @State private var editEndDate = Date()
    @State private var editLocationName = ""
    @State private var isCreatingAlbum = false
    @State private var newAlbumTitle = ""
    @State private var albumToDelete: TripAlbum?
    @State private var showingBatchDeleteConfirmation = false

    private let tripIconOptions = [
        ("airplane", "Airplane"),
        ("map", "Map"),
        ("camera", "Camera"),
        ("mountain.2", "Mountains"),
        ("beach.umbrella", "Beach"),
        ("building.2", "City"),
        ("figure.hiking", "Hiking"),
        ("fork.knife", "Food")
    ]
    
    private var validatedSelection: SidebarSelection {
        guard let selection = selection else { return .allPhotos }
        switch selection {
        case .year(let year):
            return viewModel.groupedYears[year] != nil ? selection : .allPhotos
        case .month(let id):
            return viewModel.photoMonth(withID: id) != nil ? selection : .allPhotos
        case .source(let directory):
            return viewModel.selectedDirectories.contains(directory) ? selection : .allPhotos
        case .sourceYear(let directory, let year):
            let years = groupedYears(for: directory)
            return years[year] != nil ? selection : .allPhotos
        case .sourceMonth(let directory, let id):
            return sourcePhotoMonth(withID: id, directory: directory) != nil ? selection : .allPhotos
        case .trip(let id):
            return viewModel.tripAlbum(withID: id) != nil ? selection : .allPhotos
        default:
            return selection
        }
    }

    private var activeSource: URL? {
        guard let selection = selection else { return nil }
        switch selection {
        case .source(let directory), .sourceYear(let directory, _), .sourceMonth(let directory, _):
            return directory
        default:
            return nil
        }
    }
    
    var body: some View {
        NavigationSplitView {
            sidebarView
        } detail: {
            detailView
        }
        .frame(minWidth: 800, minHeight: 600)
        .overlay { previewOverlay }
        .overlay(alignment: .bottom) { undoRemovalBanner }
        .onAppear { viewModel.loadDirectories() }
        .onChange(of: viewModel.photoMonths) { _ in syncSelection() }
        .onChange(of: viewModel.selectedDirectories) { _ in syncSelection() }
        .onChange(of: viewModel.tripAlbums) { _ in syncSelection() }
        .sheet(isPresented: $isCreatingAlbum) {
            createAlbumSheet(for: [])
        }
        .sheet(isPresented: Binding(
            get: { viewModel.pendingAlbumPhotos != nil },
            set: { isPresented in
                if !isPresented { viewModel.pendingAlbumPhotos = nil }
            }
        )) {
            createAlbumSheet(for: viewModel.pendingAlbumPhotos ?? [])
        }
        .sheet(item: $tripToEdit) { trip in
            editTripSheet(for: trip)
        }
        .albumAndPhotoDialogs(
            viewModel: viewModel,
            tripToRename: $tripToRename,
            renameText: $renameText,
            albumToDelete: $albumToDelete,
            showingBatchDeleteConfirmation: $showingBatchDeleteConfirmation
        )
    }

    private func syncSelection() {
        if let currentSelection = selection, validatedSelection != currentSelection {
            selection = validatedSelection
        }
    }

    private var sidebarView: some View {
        List(selection: $selection) {
            librarySection
            sourcesSection
            tripsSection
            timelineSection
        }
        .navigationTitle("Photo Viewer")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if viewModel.isScanning {
                    if !viewModel.photoMonths.isEmpty {
                        Button(action: {}) {
                            ProgressView()
                                .controlSize(.small)
                        }
                        .disabled(true)
                        .help("Scanning…")
                    }
                } else {
                    Button(action: { viewModel.scanAllDirectories(showLoading: false) }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Scan folders for new photos")
                }
            }
        }
    }

    private var librarySection: some View {
        Section {
            Label("All Photos", systemImage: "photo.on.rectangle")
                .tag(SidebarSelection.allPhotos)
            
            Label("Favorites", systemImage: "heart.fill")
                .tag(SidebarSelection.favorites)
                .foregroundColor(selection == .favorites ? .white : .brown)
        }
    }

    @ViewBuilder
    private var sourcesSection: some View {
        if !viewModel.selectedDirectories.isEmpty {
            Section(header: Text("Sources")) {
                Label("All Sources", systemImage: "tray.full")
                    .tag(SidebarSelection.allPhotos)
                ForEach(viewModel.selectedDirectories, id: \.self) { directory in
                    Label(directory.lastPathComponent, systemImage: "folder")
                        .tag(SidebarSelection.source(directory))
                }
            }
        }
    }

    private var tripsSection: some View {
        Section {
            ForEach(viewModel.tripAlbums) { trip in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trip.title)
                        Text(trip.photos.isEmpty ? "Empty album" : trip.dateRange)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } icon: {
                    Image(systemName: viewModel.iconName(for: trip))
                        .foregroundStyle(.secondary)
                        .overlay(alignment: .bottomTrailing) {
                            if viewModel.isTripLocked(trip.id) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(2)
                                    .background(.background, in: Circle())
                                    .offset(x: 4, y: 3)
                            }
                        }
                }
                .tag(SidebarSelection.trip(trip.id))
                .contextMenu {
                    Button(trip.isManual ? "Rename Album" : "Rename Trip", systemImage: "pencil") {
                        renameText = trip.title
                        tripToRename = trip
                    }
                    if !trip.isManual {
                        Button("Edit Trip Details…", systemImage: "calendar.badge.gearshape") {
                            editStartDate = trip.startDate
                            editEndDate = trip.endDate
                            editLocationName = trip.locationName ?? ""
                            tripToEdit = trip
                        }
                    }
                    Button(
                        viewModel.isTripLocked(trip.id)
                            ? (trip.isManual ? "Unlock Album" : "Unlock Trip")
                            : (trip.isManual ? "Lock Album" : "Lock Trip"),
                        systemImage: viewModel.isTripLocked(trip.id) ? "lock.open" : "lock"
                    ) {
                        viewModel.setTripLocked(trip.id, isLocked: !viewModel.isTripLocked(trip.id))
                    }
                    Menu("Change Icon...", systemImage: "paintpalette") {
                        ForEach(tripIconOptions, id: \.0) { iconName, label in
                            Button {
                                viewModel.setIcon(iconName, forTripWithID: trip.id)
                            } label: {
                                Label(label, systemImage: iconName)
                            }
                        }
                    }
                    if viewModel.tripAlbums.count > 1 {
                        Menu("Combine with...", systemImage: "rectangle.2.swap") {
                            ForEach(viewModel.tripAlbums.filter { $0.id != trip.id }) { otherTrip in
                                Button(otherTrip.title) {
                                    viewModel.combineTrips(withID: trip.id, and: otherTrip.id)
                                }
                            }
                        }
                    }
                    if trip.isCombined {
                        Button("Separate into Trips", systemImage: "rectangle.2.arrowtriangle.2.outward") {
                            viewModel.separateTrip(withID: trip.id)
                        }
                    }
                    if trip.isManual {
                        Divider()
                        Button(role: .destructive) {
                            albumToDelete = trip
                        } label: {
                            Label("Delete Album", systemImage: "trash")
                        }
                    } else {
                        Button("Hide Trip", systemImage: "eye.slash") {
                            viewModel.hideTrip(withID: trip.id)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Trips & Albums")
                Spacer()
                Button {
                    newAlbumTitle = ""
                    isCreatingAlbum = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Create Album")
                .accessibilityLabel("Create Album")
            }
        }
    }

    @ViewBuilder
    private var timelineSection: some View {
        if let source = activeSource {
            let years = groupedYears(for: source)
            let yearKeys = years.keys.sorted(by: >)
            if !yearKeys.isEmpty {
                ForEach(yearKeys, id: \.self) { year in
                    Section(header: Text(String(year))) {
                        Label("All \(String(year))", systemImage: "photo.stack")
                            .tag(SidebarSelection.sourceYear(source, year))
                        if let monthsInYear = years[year] {
                            ForEach(monthsInYear) { month in
                                Label(month.monthString, systemImage: "calendar")
                                    .tag(SidebarSelection.sourceMonth(source, month.id))
                            }
                        }
                    }
                }
            }
        } else if !viewModel.sortedYears.isEmpty {
            ForEach(viewModel.sortedYears, id: \.self) { year in
                Section(header: Text(String(year))) {
                    Label("All \(String(year))", systemImage: "photo.stack")
                        .tag(SidebarSelection.year(year))
                    
                    if let monthsInYear = viewModel.groupedYears[year] {
                        ForEach(monthsInYear) { month in
                            Label(month.monthString, systemImage: "calendar")
                                .tag(SidebarSelection.month(month.id))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var previewOverlay: some View {
        if let photo = viewModel.selectedPhoto {
            ZStack {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.18, dampingFraction: 0.85)) {
                            viewModel.selectedPhoto = nil
                        }
                    }
                    .transition(.opacity)
                
                PreviewView(photo: photo, viewModel: viewModel)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
            .zIndex(1)
        }
    }

    @ViewBuilder
    private var undoRemovalBanner: some View {
        if let removal = viewModel.undoableTripRemoval {
            HStack(spacing: 14) {
                Text("Removed \(removal.photos.count) photo\(removal.photos.count == 1 ? "" : "s") from \(removal.tripTitle)")
                    .lineLimit(1)
                Button("Undo") {
                    viewModel.undoLastTripPhotoRemoval()
                }
                .buttonStyle(.borderedProminent)
                Button {
                    viewModel.dismissTripPhotoRemoval(withID: removal.id)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Dismiss")
                .accessibilityLabel("Dismiss undo message")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 16)
            .shadow(radius: 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: removal.id) {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    return
                }
                viewModel.dismissTripPhotoRemoval(withID: removal.id)
            }
        }
    }
    
    @ViewBuilder
    private var detailView: some View {
        if viewModel.selectedDirectories.isEmpty {
            emptyStateView
        } else if let errorMessage = viewModel.errorMessage {
            errorView(message: errorMessage)
        } else if viewModel.isLoading || (viewModel.photoMonths.isEmpty && viewModel.isScanning) {
            loadingView
        } else {
            ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        switch validatedSelection {
                    case .allPhotos:
                        ForEach(viewModel.photoMonths) { month in
                            PhotoGridView(month: month, viewModel: viewModel)
                        }
                    case .favorites:
                        if viewModel.favoritePhotos.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "heart.slash")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray)
                                Text("No Favorites Yet")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 400)
                        } else {
                            PhotoGridView(title: "Favorites", photos: viewModel.favoritePhotos, viewModel: viewModel)
                        }
                    case .year(let selectedYear):
                        if let monthsInYear = viewModel.groupedYears[selectedYear], !monthsInYear.isEmpty {
                            ForEach(monthsInYear) { month in
                                PhotoGridView(month: month, viewModel: viewModel)
                            }
                        } else {
                            noContentView(message: "No photos were found for the selected year.")
                        }
                    case .month(let id):
                        if let month = viewModel.photoMonth(withID: id) {
                            PhotoGridView(month: month, viewModel: viewModel)
                        } else {
                            noContentView(message: "No photos were found for the selected month.")
                        }
                    case .source(let directory):
                        let months = photoMonths(for: directory)
                        if months.isEmpty {
                            noContentView(message: "No photos were found in \(directory.lastPathComponent).")
                        } else {
                            ForEach(months) { month in
                                PhotoGridView(month: month, viewModel: viewModel)
                            }
                        }
                    case .sourceYear(let directory, let selectedYear):
                        let years = groupedYears(for: directory)
                        if let monthsInYear = years[selectedYear], !monthsInYear.isEmpty {
                            ForEach(monthsInYear) { month in
                                PhotoGridView(month: month, viewModel: viewModel)
                            }
                        } else {
                            noContentView(message: "No photos were found for \(directory.lastPathComponent) in \(selectedYear).")
                        }
                    case .sourceMonth(let directory, let id):
                        if let month = sourcePhotoMonth(withID: id, directory: directory) {
                            PhotoGridView(month: month, viewModel: viewModel)
                        } else {
                            noContentView(message: "No photos were found in \(directory.lastPathComponent) for the selected month.")
                        }
                    case .trip(let id):
                        if let trip = viewModel.tripAlbum(withID: id) {
                            if trip.photos.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 32))
                                        .foregroundStyle(.secondary)
                                    Text("This album is empty")
                                        .font(.headline)
                                    Button("Browse All Photos") {
                                        selection = .allPhotos
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 300)
                            } else {
                                PhotoGridView(title: "\(trip.title) · \(trip.dateRange)", photos: trip.photos, viewModel: viewModel, tripID: trip.id)
                            }
                        } else {
                            noContentView(message: "This trip is no longer available.")
                        }
                        }
                    }
            }
            .overlay(alignment: .bottomTrailing) {
                selectionBubble
                    .padding(20)
            }
            .navigationTitle(detailTitle)
            .navigationSubtitle(detailSubtitle)
        }
    }

    private var detailSubtitle: Text {
        guard case .trip(let id) = validatedSelection,
              let locationName = viewModel.tripAlbum(withID: id)?.locationName,
              !locationName.isEmpty else { return Text("") }
        return Text(locationName)
    }

    @ViewBuilder
    private var selectionBubble: some View {
        if viewModel.isSelectingPhotos {
            HStack(spacing: 12) {
                Text("\(viewModel.selectedPhotoPaths.count) selected")
                    .font(.callout.monospacedDigit())
                    .fixedSize()
                    .accessibilityLabel("\(viewModel.selectedPhotoPaths.count) photos selected")

                Divider()
                    .frame(height: 18)

                Button {
                    copySelectedPhotos()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy selected photos and videos")
                .accessibilityLabel("Copy selected photos and videos")
                .keyboardShortcut("c", modifiers: .command)
                .disabled(viewModel.selectedPhotos.isEmpty)

                Button {
                    viewModel.toggleFavorites(for: viewModel.selectedPhotos)
                } label: {
                    let allFav = !viewModel.selectedPhotos.isEmpty && viewModel.selectedPhotos.allSatisfy { viewModel.isFavorite(photo: $0) }
                    Image(systemName: allFav ? "heart.slash" : "heart.fill")
                }
                .help("Toggle favorite for selected photos")
                .accessibilityLabel("Toggle favorite for selected photos")
                .disabled(viewModel.selectedPhotos.isEmpty)

                Menu {
                    ForEach(viewModel.tripAlbums) { trip in
                        Button(trip.title) {
                            viewModel.addPhotos(viewModel.selectedPhotos, toTripWithID: trip.id)
                            viewModel.finishPhotoSelection()
                        }
                    }
                    Divider()
                    Button("New Album…", systemImage: "plus") {
                        viewModel.requestNewAlbum(with: viewModel.selectedPhotos)
                        viewModel.finishPhotoSelection()
                    }
                } label: {
                    Image(systemName: "plus.rectangle.on.rectangle")
                }
                .help("Add selected photos to an album")
                .accessibilityLabel("Add selected photos to an album")
                .disabled(viewModel.selectedPhotoPaths.isEmpty)

                if case .trip(let tripID) = validatedSelection {
                    let isManual = viewModel.tripAlbum(withID: tripID)?.isManual == true
                    Button(role: .destructive) {
                        viewModel.removePhotos(viewModel.selectedPhotos, fromTripWithID: tripID)
                        viewModel.finishPhotoSelection()
                    } label: {
                        Image(systemName: "minus.rectangle")
                    }
                    .help(isManual ? "Remove selected photos from this album" : "Remove selected photos from this trip")
                    .accessibilityLabel(isManual ? "Remove selected photos from this album" : "Remove selected photos from this trip")
                    .disabled(viewModel.selectedPhotoPaths.isEmpty)
                }

                Button(role: .destructive) {
                    showingBatchDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .help("Move selected photos to Trash")
                .accessibilityLabel("Move selected photos to Trash")
                .disabled(viewModel.selectedPhotos.isEmpty)

                Divider()
                    .frame(height: 18)

                Button(role: .cancel) {
                    viewModel.finishPhotoSelection()
                } label: {
                    Image(systemName: "xmark")
                }
                .help("Cancel photo selection")
                .accessibilityLabel("Cancel photo selection")
                .keyboardShortcut(.cancelAction)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: Capsule())
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if !viewModel.allPhotosFlat.isEmpty {
            Button("Select Photos", systemImage: "checkmark.circle") {
                viewModel.beginPhotoSelection()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: Capsule())
            .help("Select photos across the library")
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func copySelectedPhotos() {
        let fileURLs = viewModel.selectedPhotos.map { $0.url as NSURL }
        guard !fileURLs.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(fileURLs)
    }
    
    private var detailTitle: String {
        switch validatedSelection {
        case .allPhotos:
            return "All Photos"
        case .favorites:
            return "Favorites"
        case .source(let directory):
            return "Source: \(directory.lastPathComponent)"
        case .sourceYear(let directory, let year):
            return "\(directory.lastPathComponent): \(year)"
        case .sourceMonth(let directory, let id):
            return sourcePhotoMonth(withID: id, directory: directory)?.monthYearString ?? "Source Photos"
        case .year(let year):
            return "Photos from \(year)"
        case .month(let id):
            return viewModel.photoMonth(withID: id)?.monthYearString ?? "Photos"
        case .trip(let id):
            return viewModel.tripAlbum(withID: id)?.title ?? "Trip"
        }
    }

    private func createAlbumSheet(for photos: [Photo]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Album")
                .font(.title2.weight(.semibold))
            if !photos.isEmpty {
                Text("\(photos.count) photo\(photos.count == 1 ? "" : "s") will be added")
                    .foregroundStyle(.secondary)
            }
            TextField("Album name", text: $newAlbumTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit { createAlbum(with: photos) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    isCreatingAlbum = false
                }
                Button("Create") { createAlbum(with: photos) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newAlbumTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func editTripSheet(for trip: TripAlbum) -> some View {
        NavigationStack {
            Form {
                Section("Trip dates") {
                    DatePicker("Starts", selection: $editStartDate, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Ends", selection: $editEndDate, in: editStartDate..., displayedComponents: [.date, .hourAndMinute])
                }

                Section("Location") {
                    TextField("Location label", text: $editLocationName)
                    Text("This label is shown beneath the album name.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Trip Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        tripToEdit = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.updateTripDetails(withID: trip.id, startDate: editStartDate, endDate: editEndDate, locationName: editLocationName)
                        tripToEdit = nil
                    }
                    .disabled(editEndDate < editStartDate)
                }
            }
            .frame(minWidth: 420, minHeight: 280)
        }
    }

    private func createAlbum(with photos: [Photo]) {
        guard let album = viewModel.createAlbum(title: newAlbumTitle, photos: photos) else { return }
        selection = .trip(album.id)
        isCreatingAlbum = false
        viewModel.pendingAlbumPhotos = nil
        newAlbumTitle = ""
    }

    private func photoMonths(for directory: URL) -> [PhotoMonth] {
        viewModel.photoMonths.compactMap { month in
            let filteredPhotos = month.photos.filter { photo in
                photo.url.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path)
            }
            guard !filteredPhotos.isEmpty else { return nil }
            return PhotoMonth(year: month.year, month: month.month, photos: filteredPhotos)
        }
    }

    private func groupedYears(for directory: URL) -> [Int: [PhotoMonth]] {
        Dictionary(grouping: photoMonths(for: directory), by: { $0.year })
    }

    private func sourcePhotoMonth(withID id: String, directory: URL) -> PhotoMonth? {
        photoMonths(for: directory).first(where: { $0.id == id })
    }
    
    private func noContentView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
        .padding(32)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 64))
                .foregroundColor(.gray)
            
            VStack(spacing: 8) {
                Text("No Photos Selected")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Select a folder to view your photos organized by month")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { 
                viewModel.addDirectory()
            }) {
                Label("Add Folder...", systemImage: "folder.badge.plus")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
        }
    }
    
    private var loadingView: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.2)
            Text("Scanning for photos...")
                .foregroundColor(.secondary)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Button(action: { viewModel.scanAllDirectories() }) {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(32)
    }
}

// MARK: - Dialog Modifiers Extension
private extension View {
    func albumAndPhotoDialogs(
        viewModel: PhotoViewModel,
        tripToRename: Binding<TripAlbum?>,
        renameText: Binding<String>,
        albumToDelete: Binding<TripAlbum?>,
        showingBatchDeleteConfirmation: Binding<Bool>
    ) -> some View {
        self
            .alert(tripToRename.wrappedValue?.isManual == true ? "Rename Album" : "Rename Trip", isPresented: Binding(
                get: { tripToRename.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented { tripToRename.wrappedValue = nil }
                }
            )) {
                TextField(tripToRename.wrappedValue?.isManual == true ? "Album name" : "Trip name", text: renameText)
                Button("Cancel", role: .cancel) { tripToRename.wrappedValue = nil }
                Button("Rename") {
                    if let trip = tripToRename.wrappedValue {
                        viewModel.renameTrip(withID: trip.id, title: renameText.wrappedValue)
                    }
                    tripToRename.wrappedValue = nil
                }
            }
            .alert(
                "Delete Album",
                isPresented: Binding(
                    get: { albumToDelete.wrappedValue != nil },
                    set: { isPresented in
                        if !isPresented { albumToDelete.wrappedValue = nil }
                    }
                ),
                presenting: albumToDelete.wrappedValue
            ) { album in
                Button("Cancel", role: .cancel) { albumToDelete.wrappedValue = nil }
                Button("Delete Album", role: .destructive) {
                    viewModel.deleteAlbum(withID: album.id)
                    albumToDelete.wrappedValue = nil
                }
            } message: { album in
                Text("Are you sure you want to delete \"\(album.title)\"? The photos in this album will remain in your library.")
            }
            .alert(
                "Delete Photos",
                isPresented: showingBatchDeleteConfirmation
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Move to Trash", role: .destructive) {
                    viewModel.deletePhotos(viewModel.selectedPhotos)
                    viewModel.finishPhotoSelection()
                }
            } message: {
                let count = viewModel.selectedPhotos.count
                Text("Are you sure you want to move \(count) selected photo\(count == 1 ? "" : "s") to the Trash?")
            }
    }
}
