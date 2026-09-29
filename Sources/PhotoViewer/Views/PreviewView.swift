import SwiftUI
import AVKit
import CoreLocation

struct ScrollGestureView: NSViewRepresentable {
    var onScroll: (CGFloat, CGPoint) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ScrollNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class ScrollNSView: NSView {
        var onScroll: ((CGFloat, CGPoint) -> Void)?

        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                setupMonitor()
            } else {
                removeMonitor()
            }
        }

        private func setupMonitor() {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                guard let self = self, let window = self.window else { return event }
                
                let mouseLocation = window.mouseLocationOutsideOfEventStream
                let localPoint = self.convert(mouseLocation, from: nil)
                
                if self.bounds.contains(localPoint) {
                    self.onScroll?(event.scrollingDeltaY, localPoint)
                    return nil // Consume event to prevent double-scrolling if in a list
                }
                return event
            }
        }

        private func removeMonitor() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            removeMonitor()
        }

        override func scrollWheel(with event: NSEvent) {
            let localPoint = self.convert(event.locationInWindow, from: nil)
            onScroll?(event.scrollingDeltaY, localPoint)
        }
    }
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

struct MediaContentView: View {
    let photo: Photo
    @ObservedObject var viewModel: PhotoViewModel
    let enableLivePhotos: Bool
    let livePhotoPlaybackMode: String
    
    @State private var fullImage: NSImage?
    @State private var isLoading = true
    @State private var player: AVPlayer?
    @Binding var extractedMetadata: [String: String]
    @State private var isPlayingLivePhoto = false
    @State private var isVideoReady = false
    @State private var imageLoadTask: Task<Void, Never>? = nil
    
    @State private var currentZoom = 0.0
    @State private var totalZoom = 1.0
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero
    
    init(photo: Photo, viewModel: PhotoViewModel, enableLivePhotos: Bool, livePhotoPlaybackMode: String, extractedMetadata: Binding<[String: String]>) {
        self.photo = photo
        self.viewModel = viewModel
        self.enableLivePhotos = enableLivePhotos
        self.livePhotoPlaybackMode = livePhotoPlaybackMode
        self._extractedMetadata = extractedMetadata
        
        // Pre-load the thumbnail instantly so it feels blazing fast
        if let cachedThumb = ThumbnailCacheManager.shared.thumbnail(for: photo.url) {
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
                            if status == .playing {
                                withAnimation(.easeInOut(duration: 0.4)) {
                                    isVideoReady = true
                                }
                            } else if (status == .paused || status == .waitingToPlayAtSpecifiedRate) {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    isVideoReady = photo.isVideo
                                }
                            }
                        }
                }
                
                if fullImage == nil && !isVideoReady {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .background(GeometryReader { geo in
                ScrollGestureView { delta, location in
                    handleScrollZoom(delta: delta, location: location, size: geo.size)
                }
            })
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
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard let item = notification.object as? AVPlayerItem,
                  item == player?.currentItem else { return }
            
            if livePhotoPlaybackMode == "loop" || photo.isVideo {
                player?.seek(to: .zero)
                player?.play()
            } else if livePhotoPlaybackMode == "once" && !photo.isVideo {
                // Transition back to the static photo smoothly without jumping frames
                withAnimation(.easeOut(duration: 0.6)) {
                    isPlayingLivePhoto = false
                    isVideoReady = false
                }
                player?.pause()
            }
        }
        .onAppear {
            loadFullImage()
        }
        .onDisappear {
            imageLoadTask?.cancel()
            imageLoadTask = nil
            resetPlayerState()
        }
        .onChange(of: photo) { newPhoto in
            // Reset zoom and metadata when photo changes
            totalZoom = 1.0
            currentZoom = 0
            offset = .zero
            lastOffset = .zero
        }
    }
    
    private func loadFullImage() {
        isLoading = true
        imageLoadTask?.cancel()
        imageLoadTask = Task(priority: .userInitiated) { [photo] in
            let url = photo.url
            let imageTask = Task.detached(priority: .userInitiated) {
                // Using CGImageSource is significantly faster for large files than NSImage(contentsOf:)
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2048 // Optimized for fast retina display
                ]
                
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                    return (NSImage(contentsOf: url), [String: String]())
                }
                
                let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                let image = cgImage != nil ? NSImage(cgImage: cgImage!, size: .zero) : NSImage(contentsOf: url)
                
                // Extract EXIF metadata here on-demand instead of during the main folder scan
                var metadata: [String: String] = [:]
                if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
                    if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                        if let dateTime = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                            metadata["dateTime"] = dateTime
                        }
                        if let cameraMake = exif["Make"] as? String {
                            metadata["cameraMake"] = cameraMake
                        }
                        if let cameraModel = exif["Model"] as? String {
                            metadata["cameraModel"] = cameraModel
                        }
                    }
                    if let width = properties[kCGImagePropertyPixelWidth as String] as? NSNumber {
                        metadata["width"] = String(describing: width)
                    }
                    if let height = properties[kCGImagePropertyPixelHeight as String] as? NSNumber {
                        metadata["height"] = String(describing: height)
                    }
                    // Extract GPS data
                    if let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
                        if let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
                           let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String,
                           let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double,
                           let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String {
                            let signedLat = latRef == "S" ? -lat : lat
                            let signedLon = lonRef == "W" ? -lon : lon
                            metadata["gpsLatitude"] = String(signedLat)
                            metadata["gpsLongitude"] = String(signedLon)
                        }
                    }
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
            
            guard !Task.isCancelled else { return }
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
    
    private func handleScrollZoom(delta: CGFloat, location: CGPoint, size: CGSize) {
        let sensitivity: CGFloat = 0.01
        let oldZoom = totalZoom
        let newZoom = max(1.0, min(totalZoom + (delta * sensitivity), 10.0))
        
        if newZoom == oldZoom { return }

        // Mouse location in SwiftUI-style center-relative coordinates
        // AppKit Y is measured from bottom, SwiftUI offset Y is measured from center (positive is down)
        let mouseFromCenter = CGSize(
            width: location.x - size.width / 2,
            height: (size.height - location.y) - size.height / 2
        )
        
        let ratio = newZoom / oldZoom
        
        // Update the zoom level
        totalZoom = newZoom
        
        if totalZoom == 1.0 && oldZoom > 1.0 {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                offset = .zero
                lastOffset = .zero
            }
        } else {
            // Adjust offset to keep the point under the mouse stable
            // This math shifts the image so the "focal point" doesn't move on screen
            offset = CGSize(
                width: mouseFromCenter.width * (1 - ratio) + offset.width * ratio,
                height: mouseFromCenter.height * (1 - ratio) + offset.height * ratio
            )
            lastOffset = offset
        }
    }
    
    private func setupPlayer() {
        // Clean up any existing player first
        resetPlayerState()
        
        if (self.enableLivePhotos && self.photo.videoURL != nil) || self.photo.isVideo {
            let playURL = self.photo.isVideo ? self.photo.url : self.photo.videoURL!
            let newPlayer = AVPlayer(url: playURL)
            newPlayer.isMuted = !self.photo.isVideo
            self.player = newPlayer
            self.isPlayingLivePhoto = true
            self.player?.play()
        }
    }
    
    private func resetPlayerState() {
        player?.pause()
        player = nil
    }
    
    private func toggleLivePhoto() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isPlayingLivePhoto.toggle()
        }
        
        if isPlayingLivePhoto {
            // If the player is at the end of the item, seek back to zero before playing
            if let player = player,
               let item = player.currentItem,
               player.currentTime() >= item.duration {
                player.seek(to: .zero) { _ in
                    player.play()
                }
            } else {
                player?.play()
            }
        } else {
            player?.pause()
        }
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
    @State private var extractedMetadata: [String: String] = [:]
    @State private var preloadedImages: [URL: NSImage] = [:]
    @State private var navigationQueue: [Photo] = []
    @State private var isNavigating = false
    @State private var geoPlaceName: String? = nil
    @State private var isGeocoding = false
    
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
                        Text("Media Details").font(.headline)
                    Divider()
                    Group {
                        let meta = extractedMetadata.isEmpty ? currentPhoto.exifMetadata : extractedMetadata
                            metadataRow(label: "Name:", value: currentPhoto.filename)
                            metadataRow(label: "Type:", value: currentPhoto.isVideo ? "Video" : "Photo")
                            metadataRow(label: "Date:", value: meta["dateTime"] as? String ?? Self.detailsDateFormatter.string(from: currentPhoto.date))
                            metadataRow(label: "File Size:", value: fileSizeDescription)
                        metadataRow(label: "Camera:", value: meta["cameraMake"] as? String)
                        if let w = meta["width"], let h = meta["height"] {
                            metadataRow(label: "Dimensions:", value: "\(w) \u{00D7} \(h)")
                        }
                        // Geo / Location row
                        if let latStr = meta["gpsLatitude"], let lonStr = meta["gpsLongitude"],
                           let lat = Double(latStr), let lon = Double(lonStr) {
                            let coordStr = String(format: "%.4f° %@, %.4f° %@",
                                abs(lat), lat >= 0 ? "N" : "S",
                                abs(lon), lon >= 0 ? "E" : "W")
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Location:").fontWeight(.semibold)
                                    Spacer()
                                    if isGeocoding {
                                        ProgressView().scaleEffect(0.6)
                                    } else if let place = geoPlaceName {
                                        Text(place).foregroundColor(.secondary)
                                    }
                                }
                                HStack {
                                    Text(coordStr)
                                        .font(.caption)
                                        .foregroundColor(.secondary.opacity(0.8))
                                    Spacer()
                                    Button {
                                        let encoded = "\(lat),\(lon)"
                                        if let url = URL(string: "maps://?q=\(encoded)&ll=\(encoded)") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    } label: {
                                        Label("Open in Maps", systemImage: "map")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
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
        .onChange(of: extractedMetadata) { _ in geocodeIfNeeded() }
        .onChange(of: currentPhoto.url) { _ in
            geoPlaceName = nil
            isGeocoding = false
        }
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

    private var fileSizeDescription: String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: currentPhoto.url.path),
              let fileSize = attributes[.size] as? NSNumber else { return nil }
        return ByteCountFormatter.string(fromByteCount: fileSize.int64Value, countStyle: .file)
    }

    private static let detailsDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    /// Reverse-geocodes GPS coordinates from the current photo's metadata using CLGeocoder.
    private func geocodeIfNeeded() {
        let meta = extractedMetadata.isEmpty ? currentPhoto.exifMetadata : extractedMetadata
        guard geoPlaceName == nil,
              !isGeocoding,
              let latStr = meta["gpsLatitude"],
              let lonStr = meta["gpsLongitude"],
              let lat = Double(latStr),
              let lon = Double(lonStr) else { return }
        
        isGeocoding = true
        let location = CLLocation(latitude: lat, longitude: lon)
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            DispatchQueue.main.async {
                isGeocoding = false
                if let pm = placemarks?.first {
                    var parts: [String] = []
                    if let locality = pm.locality { parts.append(locality) }
                    if let adminArea = pm.administrativeArea { parts.append(adminArea) }
                    if let country = pm.country { parts.append(country) }
                    geoPlaceName = parts.isEmpty ? nil : parts.joined(separator: ", ")
                }
            }
        }
    }
    
    private func goToPreviousPhoto() {
        if let previous = viewModel.previousPhoto(before: currentPhoto) {
            navigateToPhoto(previous, direction: -1)
        }
    }
    
    private func goToNextPhoto() {
        if let next = viewModel.nextPhoto(after: currentPhoto) {
            navigateToPhoto(next, direction: 1)
        }
    }
    
    private func navigateToPhoto(_ photo: Photo, direction: CGFloat) {
        guard !isNavigating else { return }
        isNavigating = true
        slideDirection = direction
        
        // Ultra-snappy animation: 0.12s response, 0.95 damping for instant feel
        withAnimation(.spring(response: 0.12, dampingFraction: 0.95)) {
            currentPhoto = photo
        }
        
        // Preload adjacent photos immediately after navigation
        Task {
            preloadAdjacentPhotos()
            // Minimal delay before allowing next navigation
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            isNavigating = false
        }
    }
    
    private func preloadAdjacentPhotos() {
        // Preload next and previous photos in background for instant display
        if let next = viewModel.nextPhoto(after: currentPhoto) {
            Task(priority: .userInitiated) {
                let image = await preloadImage(next.url)
                if let image = image {
                    preloadedImages[next.url] = image
                }
            }
        }
        
        if let previous = viewModel.previousPhoto(before: currentPhoto) {
            Task(priority: .userInitiated) {
                let image = await preloadImage(previous.url)
                if let image = image {
                    preloadedImages[previous.url] = image
                }
            }
        }
    }
    
    private func preloadImage(_ url: URL) async -> NSImage? {
        // Return cached image if available
        if let cached = preloadedImages[url] {
            return cached
        }
        
        // Quick load: try cached thumbnail first, then full image with timeout
        if let thumb = ThumbnailCacheManager.shared.thumbnail(for: url) {
            return thumb
        }
        
        let imageTask = Task.detached(priority: .userInitiated) { () -> NSImage? in
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
            ]
            
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return NSImage(contentsOf: url)
            }
            
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return NSImage(cgImage: cgImage, size: .zero)
            }
            
            return NSImage(contentsOf: url)
        }
        
        // 5 second timeout for preload
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            imageTask.cancel()
        }
        
        let result = try? await imageTask.value
        timeoutTask.cancel()
        return result
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
