import Foundation

struct Photo: Identifiable, Sendable, Codable {
    var id: URL { url }
    let url: URL
    let date: Date
    let filename: String
    var exifMetadata: [String: String] = [:]
    let latitude: Double?
    let longitude: Double?
    var videoURL: URL? = nil
    var isVideo: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case url, date, filename, exifMetadata, latitude, longitude, videoURL, isVideo
    }
    
    init(url: URL, date: Date, exifMetadata: [String: String] = [:], latitude: Double? = nil, longitude: Double? = nil, videoURL: URL? = nil, isVideo: Bool = false) {
        self.url = url
        self.date = date
        self.filename = url.lastPathComponent
        self.exifMetadata = exifMetadata
        self.latitude = latitude ?? Double(exifMetadata["gpsLatitude"] ?? "")
        self.longitude = longitude ?? Double(exifMetadata["gpsLongitude"] ?? "")
        self.videoURL = videoURL
        self.isVideo = isVideo
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try container.decode(URL.self, forKey: .url)
        self.date = try container.decode(Date.self, forKey: .date)
        self.filename = try container.decode(String.self, forKey: .filename)
        self.exifMetadata = try container.decodeIfPresent([String: String].self, forKey: .exifMetadata) ?? [:]
        self.latitude = try container.decodeIfPresent(Double.self, forKey: .latitude) ?? Double(self.exifMetadata["gpsLatitude"] ?? "")
        self.longitude = try container.decodeIfPresent(Double.self, forKey: .longitude) ?? Double(self.exifMetadata["gpsLongitude"] ?? "")
        self.videoURL = try container.decodeIfPresent(URL.self, forKey: .videoURL)
        self.isVideo = try container.decode(Bool.self, forKey: .isVideo)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(date, forKey: .date)
        try container.encode(filename, forKey: .filename)
        try container.encode(exifMetadata, forKey: .exifMetadata)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(videoURL, forKey: .videoURL)
        try container.encode(isVideo, forKey: .isVideo)
    }
}

extension Photo: Equatable {
    static func == (lhs: Photo, rhs: Photo) -> Bool {
        lhs.id == rhs.id
    }
}
