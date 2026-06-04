import SwiftUI

enum SidebarSelection: Hashable {
    case allPhotos
    case favorites
    case source(URL)
    case sourceYear(URL, Int)
    case sourceMonth(URL, String)
    case year(Int)
    case month(String)
}

struct ContentView: View {
    @ObservedObject var viewModel: PhotoViewModel
    @State private var selection: SidebarSelection? = .allPhotos
    
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
                            ProgressView()
                                .controlSize(.small)
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
        }
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
