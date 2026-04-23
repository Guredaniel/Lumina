import SwiftUI

struct PhotoGridView: View {
    let title: String
    let photos: [Photo]
    @ObservedObject var viewModel: PhotoViewModel
    
    @AppStorage("gridColumns") private var gridColumns: Int = 4
    
    init(month: PhotoMonth, viewModel: PhotoViewModel) {
        self.title = month.monthYearString
        self.photos = month.sortedPhotos
        self.viewModel = viewModel
    }
    
    init(title: String, photos: [Photo], viewModel: PhotoViewModel) {
        self.title = title
        self.photos = photos
        self.viewModel = viewModel
    }
    
    private var columns: [GridItem] {
        if gridColumns == 0 {
            return [GridItem(.adaptive(minimum: 150), spacing: 12)]
        } else {
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: gridColumns)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, 16)
                .padding(.top, 16)
            
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(photos, id: \.url) { photo in
                    PhotoThumbnailView(photo: photo, viewModel: viewModel)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }
}

struct PhotoThumbnailView: View {
    let photo: Photo
    @ObservedObject var viewModel: PhotoViewModel
    @State private var thumbnail: NSImage?
    
    @AppStorage("showFilenames") private var showFilenames: Bool = false
    @AppStorage("enableLivePhotos") private var enableLivePhotos: Bool = true
    @State private var isHovered = false
    
    init(photo: Photo, viewModel: PhotoViewModel) {
        self.photo = photo
        self.viewModel = viewModel
        
        // Synchronous cache check: If the image is already cached, 
        // show it IMMEDIATELY to prevent the loading flicker.
        _thumbnail = State(initialValue: ThumbnailCache.shared.thumbnail(for: photo.url))
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
                    } else {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    
                    if enableLivePhotos && photo.videoURL != nil {
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
                viewModel.selectedPhoto = photo
            }
            .onAppear {
                if thumbnail == nil {
                    ThumbnailService.shared.generateThumbnail(for: photo.url, size: CGSize(width: 200, height: 200)) { image in
                        self.thumbnail = image
                    }
                }
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
                
                Divider()
                
                Button(role: .destructive, action: { viewModel.deletePhoto(photo) }) {
                    Label("Move to Trash", systemImage: "trash")
                        .foregroundColor(.red)
                }
            }
            
            if showFilenames {
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
