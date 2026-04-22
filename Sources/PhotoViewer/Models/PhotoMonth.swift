import Foundation

struct PhotoMonth: Identifiable {
    let year: Int
    let month: Int
    let photos: [Photo]
    
    var id: UUID {
        // Create a deterministic UUID based on year and month
        // This ensures the same month always has the same ID across scans
        let seed = "\(year)-\(String(format: "%02d", month))"
        var digest = [UInt8](repeating: 0, count: 16)
        
        // Simple hash function to create consistent UUID bytes
        let bytes = Array(seed.utf8)
        for (index, byte) in bytes.enumerated() {
            digest[index % 16] = digest[index % 16] &+ byte
        }
        
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }
    
    var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let components = DateComponents(year: year, month: month, day: 1)
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }
    
    var monthString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        let components = DateComponents(year: year, month: month, day: 1)
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }
    
    var sortedPhotos: [Photo] {
        photos.sorted { $0.date > $1.date }
    }
}

extension PhotoMonth: Comparable {
    static func < (lhs: PhotoMonth, rhs: PhotoMonth) -> Bool {
        if lhs.year != rhs.year {
            return lhs.year > rhs.year
        }
        return lhs.month > rhs.month
    }
    
    static func == (lhs: PhotoMonth, rhs: PhotoMonth) -> Bool {
        lhs.year == rhs.year && lhs.month == rhs.month
    }
}
