import SwiftUI
import AVKit

struct AirPlayView: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        return picker
    }
    
    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}

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

struct PreviewView: View {
    let initialPhoto: Photo
    @ObservedObject var viewModel: PhotoViewModel
    
    @State private var currentPhoto: Photo
    @State private var fullImage: NSImage?
    @State private var isLoading = true
    @State private var showMetadata = false
    
    @State private var player: AVPlayer?
    @State private var playerItemObserver: NSObjectProtocol?
    @State private var isPlayingLivePhoto = false
    @State private var isVideoReady = false
    
    @State private var currentZoom = 0.0
    @State private var totalZoom = 1.0
    
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero
    
    @AppStorage("enableLivePhotos") private var enableLivePhotos: Bool = true
    @AppStorage("livePhotoPlaybackMode") private var livePhotoPlaybackMode: String = "loop"
    
    init(photo: Photo, viewModel: PhotoViewModel) {
        self.initialPhoto = photo
        self.viewModel = viewModel
        self._currentPhoto = State(initialValue: photo)
        
        // Pre-load the thumbnail instantly so it feels blazing fast
        if let cachedThumb = ThumbnailCache.shared.thumbnail(for: photo.url) {
            self._fullImage = State(initialValue: cachedThumb)
        }
    }
    
    var body: some View {
        ZStack {
            // Background dimming - This now takes up the FULL program window
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation {
                        viewModel.selectedPhoto = nil
                    }
                }
            
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    Button(action: { 
                        withAnimation {
                            viewModel.selectedPhoto = nil 
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                    
                    Spacer()
                    
                    Text(currentPhoto.filename)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                    
                    Spacer()
                    
                    // Favorite button
                    Button(action: { viewModel.toggleFavorite(photo: currentPhoto) }) {
                        Image(systemName: viewModel.isFavorite(photo: currentPhoto) ? "heart.fill" : "heart")
                            .font(.system(size: 16))
                            .foregroundColor(viewModel.isFavorite(photo: currentPhoto) ? .red : .white)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                    
                    // Delete button
                    Button(action: deleteCurrentPhoto) {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                    
                    // Metadata button
                    Button(action: {
                        withAnimation {
                            showMetadata.toggle()
                        }
                    }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 16))
                            .foregroundColor(showMetadata ? .accentColor : .white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color(white: 0.12))
                
                // Image and Navigation display
                ZStack {
                    ZStack {
                        if let fullImage = fullImage {
                            Image(nsImage: fullImage)
                                .resizable()
                                .scaledToFit()
                        }
                        
                        if let player = player {
                            LivePhotoPlayerView(player: player, showControls: currentPhoto.isVideo)
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
                        Button(action: { viewModel.toggleFavorite(photo: currentPhoto) }) {
                            Label(viewModel.isFavorite(photo: currentPhoto) ? "Remove from Favorites" : "Add to Favorites", systemImage: viewModel.isFavorite(photo: currentPhoto) ? "heart.slash" : "heart")
                        }
                        
                        Divider()
                        
                        Button(action: copyPhotoToPasteboard) {
                            Label(currentPhoto.isVideo ? "Copy Video" : "Copy Image", systemImage: "doc.on.doc")
                        }
                        Button(action: showInFinder) {
                            Label("Show in Finder", systemImage: "folder")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive, action: deleteCurrentPhoto) {
                            Label("Move to Trash", systemImage: "trash")
                        }
                    }
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                currentZoom = value - 1
                            }
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
                    
                    // Live Photo or Video Toggle Button
                    if player != nil {
                        Button(action: toggleLivePhoto) {
                            Label(currentPhoto.isVideo ? "VIDEO" : "LIVE", systemImage: isPlayingLivePhoto ? "play.circle.fill" : "pause.circle.fill")
                                .font(.caption.bold())
                                .padding(8)
                                .background(Color.black.opacity(0.5))
                                .foregroundColor(isPlayingLivePhoto ? .white : .gray)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    
                    // Navigation Buttons
                    HStack {
                        if viewModel.previousPhoto(before: currentPhoto) != nil {
                            Button(action: goToPreviousPhoto) {
                                Image(systemName: "chevron.left.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundColor(.white.opacity(0.5))
                                    .shadow(radius: 4)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 16)
                            // Keyboard shortcuts
                            .keyboardShortcut(.leftArrow, modifiers: [])
                        }
                        
                        Spacer()
                        
                        if viewModel.nextPhoto(after: currentPhoto) != nil {
                            Button(action: goToNextPhoto) {
                                Image(systemName: "chevron.right.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundColor(.white.opacity(0.5))
                                    .shadow(radius: 4)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 16)
                            .keyboardShortcut(.rightArrow, modifiers: [])
                        }
                    }
                    
                    // Hidden button just for handling the delete keyboard shortcut globally in the view
                    Button(action: deleteCurrentPhoto) { EmptyView() }
                        .keyboardShortcut(.delete, modifiers: [.command])
                        .opacity(0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .clipped() // Strictly contain the image within this central area
                
                // Metadata section
                if showMetadata {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Image Details")
                            .font(.headline)
                        
                        Divider()
                        
                        if let dateTime = currentPhoto.exifMetadata["dateTime"] {
                            HStack {
                                Text("Date:")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("\(dateTime)")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let cameraMake = currentPhoto.exifMetadata["cameraMake"] {
                            HStack {
                                Text("Camera:")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("\(cameraMake)")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let width = currentPhoto.exifMetadata["width"],
                           let height = currentPhoto.exifMetadata["height"] {
                            HStack {
                                Text("Dimensions:")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("\(width) × \(height)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .transition(.move(edge: .bottom))
                }
            }
            .frame(maxWidth: 1000, maxHeight: 850) // ONLY the window content is constrained
            .background(Color(white: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 25, y: 15) // Deep, smooth native shadow
            .padding(40) // Spacing from the main window edges
        }
        .colorScheme(.dark)
        .onAppear {
            loadFullImage()
        }
        .onDisappear {
            resetPlayerState()
        }
        .onChange(of: currentPhoto) { _ in
            loadFullImage()
        }
    }
    
    private func goToPreviousPhoto() {
        if let previous = viewModel.previousPhoto(before: currentPhoto) {
            withAnimation {
                currentPhoto = previous
                totalZoom = 1.0
                currentZoom = 0.0
                fullImage = ThumbnailCache.shared.thumbnail(for: previous.url)
                resetPlayerState()
            }
        }
    }
    
    private func goToNextPhoto() {
        if let next = viewModel.nextPhoto(after: currentPhoto) {
            withAnimation {
                currentPhoto = next
                totalZoom = 1.0
                currentZoom = 0.0
                fullImage = ThumbnailCache.shared.thumbnail(for: next.url)
                resetPlayerState()
            }
        }
    }
    
    private func resetPlayerState() {
        player?.pause()
        player = nil
        isVideoReady = false
        isPlayingLivePhoto = false
        if let observer = playerItemObserver {
            NotificationCenter.default.removeObserver(observer)
            playerItemObserver = nil
        }
    }
    
    private func toggleLivePhoto() {
        isPlayingLivePhoto.toggle()
        if isPlayingLivePhoto {
            if let item = player?.currentItem {
                let duration = item.duration.seconds
                let current = item.currentTime().seconds
                if duration > 0 && current >= duration - 0.1 {
                    player?.seek(to: .zero)
                }
            }
            player?.play()
        } else {
            player?.pause()
        }
    }
    
    private func loadFullImage() {
        isLoading = true
        resetPlayerState()
        
        let url = currentPhoto.url
        DispatchQueue.global(qos: .userInitiated).async {
            var image: NSImage? = nil
            
            // Try loading via Data first (often more robust and handles orientation metadata natively)
            if let data = try? Data(contentsOf: url) {
                image = NSImage(data: data)
            }
            // Fallback
            if image == nil {
                image = NSImage(contentsOf: url)
            }
            // Video fallback: use cached thumbnail
            if image == nil {
                image = ThumbnailCache.shared.thumbnail(for: url)
            }
            
            DispatchQueue.main.async {
                // Ensure we're setting the image for the currently viewed photo
                if self.currentPhoto.url == url {
                    self.fullImage = image
                    self.isLoading = false
                    
                    if (self.enableLivePhotos && self.currentPhoto.videoURL != nil) || self.currentPhoto.isVideo {
                        let playURL = self.currentPhoto.isVideo ? self.currentPhoto.url : self.currentPhoto.videoURL!
                        let newPlayer = AVPlayer(url: playURL)
                        newPlayer.isMuted = self.currentPhoto.isVideo ? false : true
                        
                        self.playerItemObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: newPlayer.currentItem, queue: .main) { _ in
                            if self.livePhotoPlaybackMode == "loop" || self.currentPhoto.isVideo {
                                newPlayer.seek(to: .zero)
                                newPlayer.play()
                            } else {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    self.isVideoReady = false
                                    self.isPlayingLivePhoto = false
                                }
                                newPlayer.seek(to: .zero)
                            }
                        }
                        
                        self.player = newPlayer
                        self.isPlayingLivePhoto = true
                        self.player?.play()
                    }
                }
            }
        }
    }
    
    private func copyPhotoToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        if currentPhoto.isVideo {
            // Copy video file to pasteboard
            let types = [NSPasteboard.PasteboardType.fileURL]
            pasteboard.declareTypes(types, owner: nil)
            pasteboard.writeObjects([currentPhoto.url as NSURL])
        } else {
            // Copy image to pasteboard
            if let image = fullImage ?? NSImage(contentsOf: currentPhoto.url) {
                pasteboard.writeObjects([image])
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
            withAnimation {
                viewModel.selectedPhoto = nil
            }
        }
    }
}
