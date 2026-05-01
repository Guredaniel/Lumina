import SwiftUI

enum SidebarSelection: Hashable {
    case allPhotos
    case favorites
    case year(Int)
    case month(UUID)
}

struct ContentView: View {
    @ObservedObject var viewModel: PhotoViewModel
    @State private var selection: SidebarSelection? = .allPhotos
    
    // Group months by year
    private var years: [Int: [PhotoMonth]] {
        Dictionary(grouping: viewModel.photoMonths, by: { $0.year })
    }
    
    // Sorted list of years
    private var sortedYears: [Int] {
        years.keys.sorted(by: >)
    }
    
    private var favoritePhotos: [Photo] {
        viewModel.allPhotosFlat.filter { viewModel.isFavorite(photo: $0) }
    }
    
    var body: some View {
        ZStack {
            NavigationSplitView {
                List(selection: $selection) {
                    Section {
                        Label("All Photos", systemImage: "photo.on.rectangle")
                            .tag(SidebarSelection.allPhotos)
                        
                        Label("Favorites", systemImage: "heart.fill")
                            .tag(SidebarSelection.favorites)
                            .foregroundColor(selection == .favorites ? .white : .brown)
                    }
                    
                    if !viewModel.photoMonths.isEmpty {
                        ForEach(sortedYears, id: \.self) { year in
                            Section(header: Text(String(year))) {
                                // Optionally let user select the whole year
                                Label("All \(String(year))", systemImage: "photo.stack")
                                    .tag(SidebarSelection.year(year))
                                
                                // Let user select specific month in that year
                                if let monthsInYear = years[year] {
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
                            // Only show a small spinner in the toolbar if we're already showing content.
                            // If the main view is currently showing its own large loading indicator, 
                            // we hide this one to avoid redundant icons.
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
            
            if let photo = viewModel.selectedPhoto {
                ZStack {
                    // Move background dimming here so it fades independently of the scale transition
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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch selection {
                    case .allPhotos, .none:
                        ForEach(viewModel.photoMonths) { month in
                            PhotoGridView(month: month, viewModel: viewModel)
                        }
                    case .favorites:
                        if favoritePhotos.isEmpty {
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
                            PhotoGridView(title: "Favorites", photos: favoritePhotos, viewModel: viewModel)
                        }
                    case .year(let selectedYear):
                        if let monthsInYear = years[selectedYear] {
                            ForEach(monthsInYear) { month in
                                PhotoGridView(month: month, viewModel: viewModel)
                            }
                        }
                    case .month(let id):
                        if let month = viewModel.photoMonths.first(where: { $0.id == id }) {
                            PhotoGridView(month: month, viewModel: viewModel)
                        }
                    }
                }
                .id("PhotoDetailScrollView") // Assign a stable ID to preserve scroll position
            }
            .navigationTitle(detailTitle)
        }
    }
    
    private var detailTitle: String {
        switch selection {
        case .allPhotos, .none:
            return "All Photos"
        case .favorites:
            return "Favorites"
        case .year(let year):
            return String(year)
        case .month(let id):
            return viewModel.photoMonths.first(where: { $0.id == id })?.monthYearString ?? "Photos"
        }
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
