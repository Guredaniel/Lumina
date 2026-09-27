import Foundation

struct TripAlbum: Identifiable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let locationName: String?
    let photos: [Photo]
    var isManual = false

    var coverPhoto: Photo? { photos.first }
    var isCombined: Bool { id.hasPrefix("combined:") }
    var photoCountLabel: String { "\(photos.count) photo\(photos.count == 1 ? "" : "s")" }

    var dateRange: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
            return formatter.string(from: startDate)
        }
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }
}

struct UserCreatedAlbum: Codable, Identifiable {
    let id: String
    let title: String
    let createdDate: Date
}

struct TripPhotoRemoval: Identifiable, Sendable {
    let id = UUID()
    let tripID: String
    let tripTitle: String
    let photos: [Photo]
}