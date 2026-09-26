import SwiftUI

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
    @State private var isCreatingAlbum = false
    @State private var newAlbumTitle = ""

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
            List(selection: $selection) {
                Section {
                    Label("All Photos", systemImage: "photo.on.rectangle")
                        .tag(SidebarSelection.allPhotos)
                    
                    Label("Favorites", systemImage: "heart.fill")
                        .tag(SidebarSelection.favorites)
                        .foregroundColor(selection == .favorites ? .white : .brown)
                }
                
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
                        }
                        .tag(SidebarSelection.trip(trip.id))
                        .contextMenu {
                            Button("Rename Trip", systemImage: "pencil") {
                                renameText = trip.title
                                tripToRename = trip
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
                            Button("Hide Trip", systemImage: "eye.slash") {
                                viewModel.hideTrip(withID: trip.id)
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
                            // Optionally let user select the whole year
                            Label("All \(String(year))", systemImage: "photo.stack")
                                .tag(SidebarSelection.year(year))
                            
                            // Let user select specific month in that year
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
            .navigationTitle("Photo Viewer")
            .toolbar {
                ToolbarItemGroup {
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
        } detail: {
            detailView
        }
        .overlay {
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
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            viewModel.loadDirectories()
        }
        .onChange(of: viewModel.photoMonths) { _ in
            if let currentSelection = selection, validatedSelection != currentSelection {
                selection = validatedSelection
            }
        }
        .onChange(of: viewModel.selectedDirectories) { _ in
            if let currentSelection = selection, validatedSelection != currentSelection {
                selection = validatedSelection
            }
        }
        .alert("Rename Trip", isPresented: Binding(
            get: { tripToRename != nil },
            set: { isPresented in
                if !isPresented { tripToRename = nil }
            }
        )) {
            TextField("Trip name", text: $renameText)
            Button("Cancel", role: .cancel) { tripToRename = nil }
            Button("Rename") {
                if let tripToRename {
                    viewModel.renameTrip(withID: tripToRename.id, title: renameText)
                }
                tripToRename = nil
            }
        }
        .sheet(isPresented: $isCreatingAlbum) {
            createAlbumSheet
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
            .navigationTitle(detailTitle)
        }
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

    private var createAlbumSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Album")
                .font(.title2.weight(.semibold))
            TextField("Album name", text: $newAlbumTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(createAlbum)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    isCreatingAlbum = false
                }
                Button("Create", action: createAlbum)
                    .keyboardShortcut(.defaultAction)
                    .disabled(newAlbumTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func createAlbum() {
        guard let album = viewModel.createAlbum(title: newAlbumTitle) else { return }
        selection = .trip(album.id)
        isCreatingAlbum = false
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
