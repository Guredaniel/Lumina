import Foundation

struct Photo: Identifiable {
    let id = UUID()
    let url: URL
    let date: Date
    let filename: String
    var exifMetadata: [String: Any] = [:]
    var videoURL: URL? = nil
    var isVideo: Bool = false
    
    init(url: URL, date: Date, exifMetadata: [String: Any] = [:], videoURL: URL? = nil, isVideo: Bool = false) {
        self.url = url
        self.date = date
        self.filename = url.lastPathComponent
        self.exifMetadata = exifMetadata
        self.videoURL = videoURL
        self.isVideo = isVideo
    }
}

extension Photo: Equatable {
    static func == (lhs: Photo, rhs: Photo) -> Bool {
        lhs.id == rhs.id
    }
}
