import SwiftUI
import AVKit

struct LivePhotoPlayerView: NSViewRepresentable {
    let player: AVPlayer
    let showControls: Bool
    
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = showControls ? .floating : .none
        // Match the image's scaledToFit behavior
        view.videoGravity = .resizeAspect
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
        nsView.controlsStyle = showControls ? .floating : .none
    }
}

struct MediaContentView: View {
    let photo: Photo
    @ObservedObject var viewModel: PhotoViewModel
    let enableLivePhotos: Bool
    let livePhotoPlaybackMode: String
    
    @State private var fullImage: NSImage?
    @State private var isLoading = true
    @State private var player: AVPlayer?
    @Binding var extractedMetadata: [String: Any]
    @State private var playerItemObserver: NSObjectProtocol?
    @State private var isPlayingLivePhoto = false
    @State private var isVideoReady = false
    
    @State private var currentZoom = 0.0
    @State private var totalZoom = 1.0
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero
    
    init(photo: Photo, viewModel: PhotoViewModel, enableLivePhotos: Bool, livePhotoPlaybackMode: String, extractedMetadata: Binding<[String: Any]>) {
        self.photo = photo
        self.viewModel = viewModel
        self.enableLivePhotos = enableLivePhotos
        self.livePhotoPlaybackMode = livePhotoPlaybackMode
        self._extractedMetadata = extractedMetadata
        
        // Pre-load the thumbnail instantly so it feels blazing fast
        if let cachedThumb = ThumbnailCache.shared.thumbnail(for: photo.url) {
            _fullImage = State(initialValue: cachedThumb)
        }
    }
    
    var body: some View {
        ZStack {
            ZStack {
                if let fullImage = fullImage {
                    Image(nsImage: fullImage)
                        .resizable()
                        .scaledToFit()
                }
                
                if let player = player {
                    LivePhotoPlayerView(player: player, showControls: photo.isVideo)
                        .opacity(isVideoReady ? 1 : 0)
                        .onReceive(player.publisher(for: \.timeControlStatus)) { status in
                            if status == .playing && !isVideoReady {
                                withAnimation(.easeIn(duration: 0.3)) {
                                    isVideoReady = true
                                }
                            }
                        }
                }
                
                if fullImage == nil && !isVideoReady {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .scaleEffect(totalZoom + currentZoom)
            .offset(offset)
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
                }
            }
            .highPriorityGesture(
                MagnificationGesture()
                    .onChanged { value in currentZoom = value - 1 }
                    .onEnded { value in
                        totalZoom += currentZoom
                        currentZoom = 0
                        if totalZoom < 1 {
                            withAnimation {
                                totalZoom = 1
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        if totalZoom > 1 {
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                    }
                    .onEnded { value in
                        if totalZoom > 1 {
                            lastOffset = offset
                        } else {
                            withAnimation {
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                    }
            )
            
            // Only show the play/pause button if it's a video or an enabled Live Photo
            if (enableLivePhotos && photo.videoURL != nil) || photo.isVideo {
                Button(action: toggleLivePhoto) {
                    Label(photo.isVideo ? "VIDEO" : "LIVE", systemImage: isPlayingLivePhoto ? "pause.circle.fill" : "play.circle.fill") // Corrected icon logic
                        .font(.caption.bold())
                        .padding(8)
                        .background(Color.black.opacity(0.5))
                        .foregroundColor(isPlayingLivePhoto ? .white : .gray)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(y: AppConstants.UI.previewPlayButtonOffsetY) // Use a named constant for better maintainability
            }
        }
        .onAppear { loadFullImage() }
        .onDisappear { resetPlayerState() }
    }
    
    private func loadFullImage() {
        isLoading = true
        let url = photo.url
        
        // Use a high-priority Task to jump ahead of background scanning tasks
        Task(priority: .userInitiated) {
            let imageTask = Task.detached(priority: .userInitiated) {
                // Using CGImageSource is significantly faster for large files than NSImage(contentsOf:)
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2048 // Optimized for fast retina display
                ]
                
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                    return (NSImage(contentsOf: url), [String: Any]())
                }
                
                let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                let image = cgImage != nil ? NSImage(cgImage: cgImage!, size: .zero) : NSImage(contentsOf: url)
                
                // Extract EXIF metadata here on-demand instead of during the main folder scan
                var metadata: [String: Any] = [:]
                if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
                    if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                        metadata["dateTime"] = exif[kCGImagePropertyExifDateTimeOriginal as String]
                        metadata["cameraMake"] = exif["Make"]
                        metadata["cameraModel"] = exif["Model"]
                    }
                    metadata["width"] = properties[kCGImagePropertyPixelWidth as String]
                    metadata["height"] = properties[kCGImagePropertyPixelHeight as String]
                }
                
                return (image, metadata)
            }
            
            // Timeout after 30 seconds to prevent UI freezing on large files
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                imageTask.cancel()
            }
            
            let result = try? await imageTask.value
            timeoutTask.cancel() // Cancel timeout if task completed
            
            await MainActor.run {
                if let result = result, let image = result.0 {
                    self.fullImage = image
                }
                self.extractedMetadata = result?.1 ?? [:]
                self.isLoading = false
                
                // Handle Video/Live Photo setup
                self.setupPlayer()
            }
        }
    }
    
    private func setupPlayer() {
        // Clean up any existing player first
        resetPlayerState()
        
        if (self.enableLivePhotos && self.photo.videoURL != nil) || self.photo.isVideo {
            let playURL = self.photo.isVideo ? self.photo.url : self.photo.videoURL!
            let newPlayer = AVPlayer(url: playURL)
            newPlayer.isMuted = !self.photo.isVideo
            
            // Capture only the values we need in the closure to avoid keeping the entire view alive
            let livePhotoPlaybackMode = self.livePhotoPlaybackMode
            let isVideo = self.photo.isVideo
            
            self.playerItemObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: newPlayer.currentItem, queue: .main) { _ in
                if livePhotoPlaybackMode == "loop" || isVideo {
                    newPlayer.seek(to: .zero)
                    newPlayer.play()
                }
            }
            self.player = newPlayer
            self.isPlayingLivePhoto = true
            self.player?.play()
        }
    }
    
    private func resetPlayerState() {
        player?.pause()
        player = nil
        if let observer = playerItemObserver {
            NotificationCenter.default.removeObserver(observer)
            playerItemObserver = nil
        }
    }
    
    private func toggleLivePhoto() {
        isPlayingLivePhoto.toggle()
        isPlayingLivePhoto ? player?.play() : player?.pause()
    }
    
    private func copyPhotoToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if photo.isVideo {
            pasteboard.writeObjects([photo.url as NSURL])
        } else if let image = fullImage ?? NSImage(contentsOf: photo.url) {
            pasteboard.writeObjects([image])
        }
    }
    
    private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([photo.url])
    }
}

struct PreviewView: View {
    let initialPhoto: Photo
    @ObservedObject var viewModel: PhotoViewModel
    @ObservedObject private var appSettings = AppSettings.shared
    
    @State private var currentPhoto: Photo
    @State private var showMetadata = false
    @State private var slideDirection: CGFloat = 0
    @State private var isFullscreen = false
    @State private var extractedMetadata: [String: Any] = [:]
    
    // Hover states for buttons
    @State private var isCloseButtonHovered = false
    @State private var isFullscreenButtonHovered = false
    @State private var isFavoriteButtonHovered = false
    @State private var isDeleteButtonHovered = false
    @State private var isMetadataButtonHovered = false
    @State private var isLeftNavButtonHovered = false
    @State private var isRightNavButtonHovered = false
    
    init(photo: Photo, viewModel: PhotoViewModel) {
        self.initialPhoto = photo
        self.viewModel = viewModel
        self._currentPhoto = State(initialValue: photo)
    }
    
    var body: some View {
        ZStack {
            // Background Color
            (isFullscreen ? Color.black : Color(white: 0.12))
                .ignoresSafeArea()
            
            // Main Image Content
            MediaContentView(photo: currentPhoto, viewModel: viewModel, enableLivePhotos: appSettings.enableLivePhotos, livePhotoPlaybackMode: appSettings.livePhotoPlaybackMode, extractedMetadata: $extractedMetadata)
                .id(currentPhoto.url)
                .transition(.asymmetric(
                    insertion: .move(edge: slideDirection > 0 ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: slideDirection > 0 ? .leading : .trailing).combined(with: .opacity)
                ))
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                        isFullscreen.toggle()
                    }
                }
        }
        .overlay(alignment: .center) {
            // Navigation Buttons (Floating)
            HStack {
                if viewModel.previousPhoto(before: currentPhoto) != nil {
                    Button(action: goToPreviousPhoto) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white.opacity(isLeftNavButtonHovered ? 0.5 : 0.3))
                            .shadow(radius: 4)
                            .scaleEffect(isLeftNavButtonHovered ? 1.05 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .padding(.leading, 16)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .onHover { hovering in
                        isLeftNavButtonHovered = hovering
                    }
                }
                
                Spacer()
                
                if viewModel.nextPhoto(after: currentPhoto) != nil {
                    Button(action: goToNextPhoto) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white.opacity(isRightNavButtonHovered ? 0.5 : 0.3))
                            .shadow(radius: 4)
                            .scaleEffect(isRightNavButtonHovered ? 1.05 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .padding(.trailing, 16)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .onHover { hovering in
                        isRightNavButtonHovered = hovering
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            // Custom Toolbar Overlay
            HStack {
                Button(action: {
                    withAnimation(.easeIn(duration: 0.15)) {
                        viewModel.selectedPhoto = nil
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(isCloseButtonHovered ? 9 : 8)
                        .background(Color.white.opacity(isCloseButtonHovered ? 0.25 : 0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .padding(.leading, isFullscreen ? 70 : 0)
                .onHover { hovering in
                    isCloseButtonHovered = hovering
                }
                
                Spacer()
                
                Text(currentPhoto.filename)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .shadow(radius: 2)
                
                Spacer()
                
                HStack(spacing: 16) {
                    Button(action: {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                            isFullscreen.toggle()
                        }
                    }) {
                        Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .scaleEffect(isFullscreenButtonHovered ? 1.1 : 1.0)
                    }
                    .help(isFullscreen ? "Exit Full Screen" : "Enter Full Screen")
                    .keyboardShortcut("f", modifiers: [.command])
                    .onHover { hovering in
                        isFullscreenButtonHovered = hovering
                    }
                    
                    Button(action: { viewModel.toggleFavorite(photo: currentPhoto) }) {
                        Image(systemName: viewModel.isFavorite(photo: currentPhoto) ? "heart.fill" : "heart")
                            .foregroundColor(viewModel.isFavorite(photo: currentPhoto) ? .red : .white)
                            .scaleEffect(isFavoriteButtonHovered ? 1.1 : 1.0)
                    }
                    .onHover { hovering in
                        isFavoriteButtonHovered = hovering
                    }
                    
                    Button(action: deleteCurrentPhoto) {
                        Image(systemName: "trash")
                            .scaleEffect(isDeleteButtonHovered ? 1.1 : 1.0)
                    }
                    .onHover { hovering in
                        isDeleteButtonHovered = hovering
                    }
                    
                    Button(action: { withAnimation { showMetadata.toggle() } }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(showMetadata ? .accentColor : .white)
                            .scaleEffect(isMetadataButtonHovered ? 1.1 : 1.0)
                    }
                    .onHover { hovering in
                        isMetadataButtonHovered = hovering
                    }
                }
                .font(.system(size: 16))
                .foregroundColor(.white)
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: isFullscreenButtonHovered)
                .animation(.easeInOut(duration: 0.15), value: isFavoriteButtonHovered)
                .animation(.easeInOut(duration: 0.15), value: isDeleteButtonHovered)
                .animation(.easeInOut(duration: 0.15), value: isMetadataButtonHovered)
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(
                LinearGradient(gradient: Gradient(colors: [.black.opacity(0.5), .clear]), startPoint: .top, endPoint: .bottom)
            )
        }
        .overlay(alignment: .bottom) {
            // Metadata section
            if showMetadata {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Image Details").font(.headline)
                    Divider()
                    Group {
                        let meta = extractedMetadata.isEmpty ? currentPhoto.exifMetadata : extractedMetadata
                        metadataRow(label: "Date:", value: meta["dateTime"] as? String)
                        metadataRow(label: "Camera:", value: meta["cameraMake"] as? String)
                        if let w = meta["width"], let h = meta["height"] {
                            metadataRow(label: "Dimensions:", value: "\(w) \u{00D7} \(h)")
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 400, alignment: .leading)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .padding(20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            Button(action: deleteCurrentPhoto) { EmptyView() }
                .keyboardShortcut(.delete, modifiers: [.command])
                .opacity(0)
        }
        .frame(maxWidth: isFullscreen ? .infinity : 1000, maxHeight: isFullscreen ? .infinity : 850)
        .clipShape(RoundedRectangle(cornerRadius: isFullscreen ? 0 : 12))
        .overlay(
            RoundedRectangle(cornerRadius: isFullscreen ? 0 : 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(isFullscreen ? 0 : 0.4), radius: isFullscreen ? 0 : 20, y: 10)
        .padding(isFullscreen ? 0 : 40)
        .colorScheme(.dark)
        .animation(.easeInOut(duration: 0.15), value: isLeftNavButtonHovered)
        .animation(.easeInOut(duration: 0.15), value: isRightNavButtonHovered)
        .ignoresSafeArea(edges: isFullscreen ? [.bottom, .horizontal] : [])
    }
    
    @ViewBuilder
    private func metadataRow(label: String, value: String?) -> some View {
        if let value = value {
            HStack {
                Text(label).fontWeight(.semibold)
                Spacer()
                Text(value).foregroundColor(.secondary)
            }
        }
    }
    
    private func goToPreviousPhoto() {
        if let previous = viewModel.previousPhoto(before: currentPhoto) {
            slideDirection = -1
            // Tightened response from 0.22 to 0.18 for snappier feel
            withAnimation(.spring(response: 0.18, dampingFraction: 0.85)) {
                currentPhoto = previous
            }
        }
    }
    
    private func goToNextPhoto() {
        if let next = viewModel.nextPhoto(after: currentPhoto) {
            slideDirection = 1
            withAnimation(.spring(response: 0.18, dampingFraction: 0.85)) {
                currentPhoto = next
            }
        }
    }
    
    private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([currentPhoto.url])
    }
    
    private func deleteCurrentPhoto() {
        let photoToDelete = currentPhoto
        
        // Decide where to go next before deleting
        if let next = viewModel.nextPhoto(after: photoToDelete) {
            goToNextPhoto()
            viewModel.deletePhoto(photoToDelete)
        } else if let prev = viewModel.previousPhoto(before: photoToDelete) {
            goToPreviousPhoto()
            viewModel.deletePhoto(photoToDelete)
        } else {
            // It was the very last photo
            viewModel.deletePhoto(photoToDelete)
            withAnimation(.spring(response: 0.18, dampingFraction: 0.85)) {
                viewModel.selectedPhoto = nil
            }
        }
    }
}
