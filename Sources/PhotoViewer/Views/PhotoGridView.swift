import SwiftUI
import AppKit

struct PhotoGridView: View {
    let title: String
    let photos: [Photo]
    @ObservedObject var viewModel: PhotoViewModel
    let tripID: String?
    @ObservedObject private var appSettings = AppSettings.shared
    
    init(month: PhotoMonth, viewModel: PhotoViewModel) {
        self.title = month.monthYearString
        self.photos = month.photos
        self.viewModel = viewModel
        self.tripID = nil
    }
    
    init(title: String, photos: [Photo], viewModel: PhotoViewModel, tripID: String? = nil) {
        self.title = title
        self.photos = photos
        self.viewModel = viewModel
        self.tripID = tripID
    }
    
    private var columns: [GridItem] {
        if appSettings.gridColumns == 0 {
            return [GridItem(.adaptive(minimum: AppConstants.GridDisplay.minColumnWidth), spacing: AppConstants.GridDisplay.gridSpacing)]
        } else {
            return Array(repeating: GridItem(.flexible(), spacing: AppConstants.GridDisplay.gridSpacing), count: appSettings.gridColumns)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            .padding(.horizontal, AppConstants.GridDisplay.gridPadding)
            .padding(.top, AppConstants.GridDisplay.gridPadding)
            
            LazyVGrid(columns: columns, spacing: AppConstants.GridDisplay.gridSpacing) {
                ForEach(photos, id: \.url) { photo in
                    PhotoThumbnailView(
                        photo: photo,
                        viewModel: viewModel,
                        tripID: tripID,
                        isSelectionMode: viewModel.isSelectingPhotos,
                        isSelected: viewModel.selectedPhotoPaths.contains(photo.url.path),
                        onEnterSelection: { viewModel.beginPhotoSelection() },
                        onToggleSelection: { extendSelection in
                            viewModel.togglePhotoSelection(photo, extendSelection: extendSelection)
                        }
                    )
                }
            }
            .padding(.horizontal, AppConstants.GridDisplay.gridPadding)
            .padding(.bottom, AppConstants.GridDisplay.gridPadding)
        }
    }

}

struct PhotoThumbnailView: View {
    let photo: Photo
    @ObservedObject var viewModel: PhotoViewModel
    let tripID: String?
    let isSelectionMode: Bool
    let isSelected: Bool
    let onEnterSelection: () -> Void
    let onToggleSelection: (Bool) -> Void
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var thumbnail: NSImage?
    @State private var isHovered = false
    @State private var loadError: Bool = false
    @State private var loadingTask: Task<Void, Never>?
    
    init(
        photo: Photo,
        viewModel: PhotoViewModel,
        tripID: String? = nil,
        isSelectionMode: Bool = false,
        isSelected: Bool = false,
        onEnterSelection: @escaping () -> Void = {},
        onToggleSelection: @escaping (Bool) -> Void = { _ in }
    ) {
        self.photo = photo
        self.viewModel = viewModel
        self.tripID = tripID
        self.isSelectionMode = isSelectionMode
        self.isSelected = isSelected
        self.onEnterSelection = onEnterSelection
        self.onToggleSelection = onToggleSelection
        
        // Synchronous cache check: If the image is already cached, 
        // show it IMMEDIATELY to prevent the loading flicker.
        _thumbnail = State(initialValue: ThumbnailCacheManager.shared.thumbnail(for: photo.url))
    }
    
    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack {
                    Color.gray.opacity(0.2)
                    
                    if let thumbnail = thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    } else if loadError {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                            .scaleEffect(0.8)
                    } else {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    
                    if appSettings.enableLivePhotos && photo.videoURL != nil {
                        Image(systemName: "livephoto")
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                            .padding(6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                    
                    if photo.isVideo {
                        Image(systemName: "play.fill")
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                    
                    if viewModel.isFavorite(photo: photo) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .padding(4)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                            .padding(6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }

                            if isSelectionMode {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(isSelected ? Color.accentColor : .white)
                                .background(Circle().fill(.black.opacity(0.45)))
                                .padding(8)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: isHovered ? 3 : 0)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                if isSelectionMode {
                    onToggleSelection(NSEvent.modifierFlags.contains(.shift))
                } else if NSEvent.modifierFlags.contains(.shift) {
                    onEnterSelection()
                    onToggleSelection(false)
                } else {
                    viewModel.selectedPhoto = photo
                }
            }
            .onAppear {
                if thumbnail == nil {
                    loadingTask = Task {
                        do {
                            let generatedThumbnail = try await ThumbnailService.shared.generateThumbnail(
                                for: photo.url,
                                size: CGSize(width: 200, height: 200)
                            )
                            DispatchQueue.main.async {
                                self.thumbnail = generatedThumbnail
                            }
                        } catch {
                            DispatchQueue.main.async {
                                self.loadError = true
                            }
                        }
                    }
                }
            }
            .onDisappear {
                loadingTask?.cancel()
            }
            .draggable(photo.url)
            .contextMenu {
                Button(action: { viewModel.toggleFavorite(photo: photo) }) {
                    Label(viewModel.isFavorite(photo: photo) ? "Remove from Favorites" : "Add to Favorites", systemImage: viewModel.isFavorite(photo: photo) ? "heart.slash" : "heart")
                }
                
                Divider()
                
                Button(action: copyPhotoToPasteboard) {
                    Label(photo.isVideo ? "Copy Video" : "Copy Image", systemImage: "doc.on.doc")
                }
                
                Button(action: showInFinder) {
                    Label("Show in Finder", systemImage: "folder")
                }

                Menu("Add to Trip...", systemImage: "plus.rectangle.on.rectangle") {
                    ForEach(viewModel.tripAlbums.filter { $0.id != tripID }) { trip in
                        Button(trip.title) {
                            viewModel.addPhoto(photo, toTripWithID: trip.id)
                        }
                    }
                    Divider()
                    Button("New Trip…", systemImage: "plus") {
                        viewModel.requestNewAlbum(with: [photo])
                    }
                }

                if let tripID {
                    Button("Remove from Trip", systemImage: "minus.rectangle") {
                        viewModel.removePhoto(photo, fromTripWithID: tripID)
                    }
                }
                
                Divider()
                
                Button(role: .destructive, action: { viewModel.deletePhoto(photo) }) {
                    Label("Move to Trash", systemImage: "trash")
                        .foregroundColor(.red)
                }
            }
            
            if appSettings.showFilenames {
                Text(photo.url.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 4)
            }
        }
    }
    
    private func copyPhotoToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        if photo.isVideo {
            // Copy video file to pasteboard
            let types = [NSPasteboard.PasteboardType.fileURL]
            pasteboard.declareTypes(types, owner: nil)
            pasteboard.writeObjects([photo.url as NSURL])
        } else {
            // Copy image to pasteboard
            if let image = NSImage(contentsOf: photo.url) {
                pasteboard.writeObjects([image])
            }
        }
    }
    
    private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([photo.url])
    }
}
