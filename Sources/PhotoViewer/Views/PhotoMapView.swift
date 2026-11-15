import AppKit
import MapKit
import SwiftUI

struct PhotoLocationGroup: Identifiable {
    let id: String
    let latitude: Double
    let longitude: Double
    let photos: [Photo]

    static func grouped(photos: [Photo]) -> [PhotoLocationGroup] {
        let coordinateScale = 100_000.0
        var groupedPhotos: [CoordinateBucket: [Photo]] = [:]

        for photo in photos {
            guard let latitude = photo.latitude,
                  let longitude = photo.longitude,
                  latitude.isFinite,
                  longitude.isFinite,
                  (-90...90).contains(latitude),
                  (-180...180).contains(longitude) else {
                continue
            }

            let bucket = CoordinateBucket(
                latitude: Int((latitude * coordinateScale).rounded()),
                longitude: Int((longitude * coordinateScale).rounded())
            )
            groupedPhotos[bucket, default: []].append(photo)
        }

        return groupedPhotos.map { bucket, photos in
            let orderedPhotos = photos.sorted { $0.date > $1.date }
            let latitude = photos.compactMap(\.latitude).reduce(0, +) / Double(photos.count)
            let longitude = photos.compactMap(\.longitude).reduce(0, +) / Double(photos.count)
            return PhotoLocationGroup(
                id: "\(bucket.latitude):\(bucket.longitude)",
                latitude: latitude,
                longitude: longitude,
                photos: orderedPhotos
            )
        }
        .sorted {
            let leftDate = $0.photos.first?.date ?? .distantPast
            let rightDate = $1.photos.first?.date ?? .distantPast
            if leftDate != rightDate { return leftDate > rightDate }
            return $0.id < $1.id
        }
    }

    static func filtering(
        _ locations: [PhotoLocationGroup],
        from startDate: Date,
        through endDate: Date,
        calendar: Calendar = .current
    ) -> [PhotoLocationGroup] {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        guard start <= end,
              let endExclusive = calendar.date(byAdding: .day, value: 1, to: end) else {
            return []
        }

        return locations.compactMap { location in
            let photos = location.photos.filter { $0.date >= start && $0.date < endExclusive }
            guard !photos.isEmpty else { return nil }
            return PhotoLocationGroup(
                id: location.id,
                latitude: location.latitude,
                longitude: location.longitude,
                photos: photos
            )
        }
    }

    private struct CoordinateBucket: Hashable {
        let latitude: Int
        let longitude: Int
    }
}

struct PhotoMapView: View {
    let locations: [PhotoLocationGroup]
    let onSelectPhoto: (Photo) -> Void

    @State private var selectedLocationID: String?
    @State private var selectedPhotos: [Photo] = []
    @State private var selectionTitle = "Location Photos"
    @State private var selectedPhotoURL: URL?
    @State private var dateFilterEnabled = false
    @State private var dateFilterPresented = false
    @State private var dateFilterStart: Date
    @State private var dateFilterEnd: Date

    init(photos: [Photo], onSelectPhoto: @escaping (Photo) -> Void) {
        let locations = PhotoLocationGroup.grouped(photos: photos)
        let dates = locations.flatMap(\.photos).map(\.date)
        self.locations = locations
        self.onSelectPhoto = onSelectPhoto
        self._dateFilterStart = State(initialValue: dates.min() ?? .now)
        self._dateFilterEnd = State(initialValue: dates.max() ?? .now)
    }

    var body: some View {
        Group {
            if locations.isEmpty {
                ContentUnavailableView(
                    "No Photos with Locations",
                    systemImage: "map",
                    description: Text("Photos appear here when they include GPS location metadata.")
                )
            } else if displayedLocations.isEmpty {
                ContentUnavailableView {
                    Label("No Photos in This Date Range", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text("Choose a wider date range or show all dates.")
                } actions: {
                    Button("Show All Dates") {
                        dateFilterEnabled = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                HStack(spacing: 0) {
                    ClusteredPhotoMap(
                        locations: displayedLocations,
                        selectedLocationID: $selectedLocationID,
                        onSelectLocation: selectLocation,
                        onSelectCluster: selectCluster,
                        onClearSelection: clearSelection
                    )
                    .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)

                    Divider()

                    locationInspector
                        .frame(width: 320)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if !locations.isEmpty {
                dateFilterControl
                    .padding(12)
            }
        }
        .onChange(of: dateFilterEnabled) { _ in clearSelection() }
        .onChange(of: dateFilterStart) { _ in clearSelection() }
        .onChange(of: dateFilterEnd) { _ in clearSelection() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var displayedLocations: [PhotoLocationGroup] {
        guard dateFilterEnabled else { return locations }
        return PhotoLocationGroup.filtering(
            locations,
            from: dateFilterStart,
            through: dateFilterEnd
        )
    }

    private var dateFilterControl: some View {
        Button {
            dateFilterPresented.toggle()
        } label: {
            Label(dateFilterEnabled ? "Date Filter" : "All Dates", systemImage: "calendar")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .popover(isPresented: $dateFilterPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Filter Photos by Date")
                    .font(.headline)

                Toggle("Limit to date range", isOn: $dateFilterEnabled)

                DatePicker(
                    "From",
                    selection: $dateFilterStart,
                    in: ...dateFilterEnd,
                    displayedComponents: .date
                )
                .disabled(!dateFilterEnabled)

                DatePicker(
                    "Through",
                    selection: $dateFilterEnd,
                    in: dateFilterStart...,
                    displayedComponents: .date
                )
                .disabled(!dateFilterEnabled)

                Text("\(visiblePhotoCount) of \(totalPhotoCount) photos")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("Show All Dates") {
                        dateFilterEnabled = false
                        dateFilterPresented = false
                    }
                    .disabled(!dateFilterEnabled)
                }
            }
            .padding(16)
            .frame(width: 300)
        }
    }

    private var totalPhotoCount: Int {
        locations.reduce(0) { $0 + $1.photos.count }
    }

    private var visiblePhotoCount: Int {
        displayedLocations.reduce(0) { $0 + $1.photos.count }
    }

    private var locationInspector: some View {
        Group {
            if !selectedPhotos.isEmpty, let focusedPhoto {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectionTitle)
                                .font(.headline)
                            Text(photoCountLabel(selectedPhotos.count))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            clearSelection()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .help("Clear selected location")
                        .accessibilityLabel("Clear selected location")
                    }
                    .padding(16)

                    Button {
                        onSelectPhoto(focusedPhoto)
                    } label: {
                        PhotoMapImage(
                            photo: focusedPhoto,
                            pixelSize: CGSize(width: 600, height: 440),
                            displayHeight: 220
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help("Open \(focusedPhoto.filename)")
                    .accessibilityLabel("Open \(focusedPhoto.filename)")
                    .padding(.horizontal, 14)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(focusedPhoto.filename)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text(focusedPhoto.date, format: .dateTime.month(.abbreviated).day().year())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 14)

                    Divider()
                    Text("All Photos")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 10
                        ) {
                            ForEach(selectedPhotos) { photo in
                                locationPhotoTile(photo)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Select a Photo Cluster",
                    systemImage: "mappin.and.ellipse",
                    description: Text("Select a marker or numbered cluster to preview its photos.")
                )
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var focusedPhoto: Photo? {
        selectedPhotos.first(where: { $0.url == selectedPhotoURL }) ?? selectedPhotos.first
    }

    private func selectLocation(_ location: PhotoLocationGroup) {
        selectedLocationID = location.id
        selectedPhotos = location.photos
        selectionTitle = "Location Photos"
        selectedPhotoURL = nil
    }

    private func selectCluster(_ locations: [PhotoLocationGroup]) {
        selectedLocationID = nil
        selectedPhotos = locations.flatMap(\.photos).sorted { $0.date > $1.date }
        selectionTitle = "Photos in This Area"
        selectedPhotoURL = nil
    }

    private func clearSelection() {
        selectedLocationID = nil
        selectedPhotos = []
        selectedPhotoURL = nil
    }

    private func locationPhotoTile(_ photo: Photo) -> some View {
        let isFocused = focusedPhoto?.url == photo.url
        return Button {
            selectedPhotoURL = photo.url
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                PhotoMapImage(
                    photo: photo,
                    pixelSize: CGSize(width: 300, height: 200),
                    displayHeight: 92
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(photo.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(5)
            .background(
                isFocused ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(isFocused ? Color.accentColor : Color.clear, lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help(photo.filename)
        .accessibilityLabel("Preview \(photo.filename)")
    }

    private func photoCountLabel(_ count: Int) -> String {
        "\(count) photo\(count == 1 ? "" : "s")"
    }
}

private struct ClusteredPhotoMap: NSViewRepresentable {
    let locations: [PhotoLocationGroup]
    @Binding var selectedLocationID: String?
    let onSelectLocation: (PhotoLocationGroup) -> Void
    let onSelectCluster: ([PhotoLocationGroup]) -> Void
    let onClearSelection: () -> Void

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.showsScale = true
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateAnnotations(on: mapView, locations: locations)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ClusteredPhotoMap
        private var hasSetInitialRegion = false

        init(parent: ClusteredPhotoMap) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            let isCluster = annotation is MKClusterAnnotation
            guard isCluster || annotation is PhotoMapAnnotation else { return nil }

            let reuseIdentifier = isCluster ? "PhotoLocationCluster" : "PhotoLocation"
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: reuseIdentifier)

            annotationView.annotation = annotation
            annotationView.markerTintColor = .systemBlue
            annotationView.canShowCallout = false
            annotationView.glyphText = nil
            annotationView.glyphImage = nil

            if let cluster = annotation as? MKClusterAnnotation {
                let photoCount = cluster.memberAnnotations.reduce(into: 0) { count, member in
                    count += (member as? PhotoMapAnnotation)?.location.photos.count ?? 0
                }
                annotationView.glyphText = photoCount.formatted()
                annotationView.clusteringIdentifier = nil
            } else if let photoAnnotation = annotation as? PhotoMapAnnotation {
                let count = photoAnnotation.location.photos.count
                annotationView.glyphText = count > 1 ? count.formatted() : nil
                annotationView.glyphImage = count == 1
                    ? NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
                    : nil
                annotationView.clusteringIdentifier = "PhotoLocations"
                annotationView.displayPriority = .defaultHigh
            }
            return annotationView
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation {
                let locations = cluster.memberAnnotations
                    .compactMap { ($0 as? PhotoMapAnnotation)?.location }
                parent.onSelectCluster(locations)
                mapView.deselectAnnotation(cluster, animated: false)
            } else if let annotation = view.annotation as? PhotoMapAnnotation {
                parent.onSelectLocation(annotation.location)
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            guard let annotation = view.annotation as? PhotoMapAnnotation,
                  parent.selectedLocationID == annotation.location.id else {
                return
            }
            parent.selectedLocationID = nil
            parent.onClearSelection()
        }

        func mapView(
            _ mapView: MKMapView,
            clusterAnnotationForMemberAnnotations memberAnnotations: [any MKAnnotation]
        ) -> MKClusterAnnotation {
            let cluster = MKClusterAnnotation(memberAnnotations: memberAnnotations)
            let count = memberAnnotations.reduce(into: 0) { total, member in
                total += (member as? PhotoMapAnnotation)?.location.photos.count ?? 0
            }
            cluster.title = "\(count) photos"
            return cluster
        }

        func updateAnnotations(on mapView: MKMapView, locations: [PhotoLocationGroup]) {
            let locationsByID = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
            let existingAnnotations = mapView.annotations.compactMap { $0 as? PhotoMapAnnotation }
            var existingIDs = Set<String>()

            for annotation in existingAnnotations {
                if let location = locationsByID[annotation.location.id] {
                    annotation.update(location: location)
                    existingIDs.insert(location.id)
                } else {
                    mapView.removeAnnotation(annotation)
                }
            }

            let newAnnotations = locations
                .filter { !existingIDs.contains($0.id) }
                .map(PhotoMapAnnotation.init(location:))
            if !newAnnotations.isEmpty {
                mapView.addAnnotations(newAnnotations)
            }

            if !hasSetInitialRegion, !newAnnotations.isEmpty {
                mapView.showAnnotations(
                    mapView.annotations.filter { $0 is PhotoMapAnnotation },
                    animated: false
                )
                hasSetInitialRegion = true
            }

            synchronizeSelection(on: mapView)
        }

        private func synchronizeSelection(on mapView: MKMapView) {
            let annotations = mapView.annotations.compactMap { $0 as? PhotoMapAnnotation }
            guard let selectedLocationID = parent.selectedLocationID else {
                for selected in mapView.selectedAnnotations {
                    mapView.deselectAnnotation(selected, animated: false)
                }
                return
            }

            guard let annotation = annotations.first(where: { $0.location.id == selectedLocationID }) else {
                parent.selectedLocationID = nil
                return
            }

            let alreadySelected = mapView.selectedAnnotations.contains {
                ($0 as? PhotoMapAnnotation)?.location.id == selectedLocationID
            }
            if !alreadySelected {
                mapView.selectAnnotation(annotation, animated: false)
            }
        }
    }
}

private final class PhotoMapAnnotation: NSObject, MKAnnotation {
    var location: PhotoLocationGroup
    @objc dynamic var coordinate: CLLocationCoordinate2D
    @objc dynamic var title: String?

    init(location: PhotoLocationGroup) {
        self.location = location
        self.coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        self.title = "\(location.photos.count) photos"
    }

    func update(location: PhotoLocationGroup) {
        self.location = location
        coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        title = "\(location.photos.count) photos"
    }
}

private struct PhotoMapImage: View {
    let photo: Photo
    let pixelSize: CGSize
    let displayHeight: CGFloat

    @State private var thumbnail: NSImage?
    @State private var thumbnailURL: URL?
    @State private var failedURL: URL?

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.1)
            if let thumbnail, thumbnailURL == photo.url {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .padding(5)
            } else if failedURL == photo.url {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .help("Could not load this photo thumbnail")
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: displayHeight)
        .task(id: photo.id) {
            thumbnail = nil
            thumbnailURL = nil
            failedURL = nil
            do {
                let loadedThumbnail = try await ThumbnailService.shared.generateThumbnail(
                    for: photo.url,
                    size: pixelSize
                )
                guard !Task.isCancelled else { return }
                if let loadedThumbnail {
                    thumbnail = loadedThumbnail
                    thumbnailURL = photo.url
                } else {
                    failedURL = photo.url
                }
            } catch {
                guard !Task.isCancelled else { return }
                failedURL = photo.url
            }
        }
    }
}
