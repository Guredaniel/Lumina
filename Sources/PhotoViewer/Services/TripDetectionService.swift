import CoreLocation
import Foundation

struct TripDetectionService: Sendable {
    let minimumPhotos: Int
    let locationRadiusKilometers: Double
    let maximumTimeGapHours: Double

    func detectTrips(in photos: [Photo]) -> [TripAlbum] {
        let locatedPhotos = photos.compactMap { photo -> (Photo, CLLocation)? in
            guard let latitude = Double(photo.exifMetadata["gpsLatitude"] ?? ""),
                  let longitude = Double(photo.exifMetadata["gpsLongitude"] ?? ""),
                  (-90...90).contains(latitude),
                  (-180...180).contains(longitude) else { return nil }
            return (photo, CLLocation(latitude: latitude, longitude: longitude))
        }.sorted { $0.0.date < $1.0.date }

        guard !locatedPhotos.isEmpty else { return [] }

        var groups: [[(Photo, CLLocation)]] = [[]]
        for item in locatedPhotos {
            guard let previous = groups.last?.last else {
                groups[0].append(item)
                continue
            }

            let timeGap = item.0.date.timeIntervalSince(previous.0.date) / 3600
            let distance = item.1.distance(from: previous.1) / 1000
            if timeGap > maximumTimeGapHours || distance > locationRadiusKilometers {
                groups.append([item])
            } else {
                groups[groups.count - 1].append(item)
            }
        }

        var albums: [TripAlbum] = []
        for group in groups where group.count >= minimumPhotos {
            guard let first = group.first, let last = group.last else { continue }
            let title = "Trip, \(Self.yearFormatter.string(from: first.0.date))"
            let idData = group.map { $0.0.url.path }.joined(separator: "|").data(using: .utf8)!
            let id = idData.base64EncodedString()
            albums.append(TripAlbum(id: id, title: title, startDate: first.0.date, endDate: last.0.date, locationName: nil, photos: group.map(\.0).reversed()))
        }

        return albums.sorted { $0.startDate > $1.startDate }
    }

    func locationName(for photos: [Photo]) async -> String? {
        let coordinates = photos.compactMap { photo -> CLLocation? in
            guard let latitude = Double(photo.exifMetadata["gpsLatitude"] ?? ""),
                  let longitude = Double(photo.exifMetadata["gpsLongitude"] ?? ""),
                  (-90...90).contains(latitude),
                  (-180...180).contains(longitude) else { return nil }
            return CLLocation(latitude: latitude, longitude: longitude)
        }
        guard !coordinates.isEmpty else { return nil }
        let center = coordinates[coordinates.count / 2]
        if let cachedName = SQLiteDatabase.shared.cachedLocationName(latitude: center.coordinate.latitude, longitude: center.coordinate.longitude) {
            return cachedName
        }

        guard let placeName = await reverseGeocode(center) else { return nil }
        SQLiteDatabase.shared.cacheLocationName(placeName, latitude: center.coordinate.latitude, longitude: center.coordinate.longitude)
        return placeName
    }

    private func reverseGeocode(_ location: CLLocation) async -> String? {
        await withCheckedContinuation { continuation in
            CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
                guard let placemark = placemarks?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                let parts = [placemark.locality, placemark.administrativeArea, placemark.country].compactMap { $0 }
                continuation.resume(returning: parts.isEmpty ? nil : parts.joined(separator: ", "))
            }
        }
    }

    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter
    }()
}