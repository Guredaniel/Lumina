import Foundation

struct PhotoMonth: Identifiable, Sendable, Codable {
    let year: Int
    let month: Int
    let photos: [Photo]
    
    var id: String {
        "\(year)-\(month)"
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
