import Foundation
import XCTest
@testable import PhotoViewer

final class PhotoLocationGroupTests: XCTestCase {
    func testGroupsMatchingCoordinatesAndKeepsNearbyPlacesSeparate() {
        let older = makePhoto(
            name: "older.jpg",
            date: Date(timeIntervalSince1970: 100),
            latitude: 37.77491,
            longitude: -122.41941
        )
        let newer = makePhoto(
            name: "newer.jpg",
            date: Date(timeIntervalSince1970: 200),
            latitude: 37.77491,
            longitude: -122.41941
        )
        let nearby = makePhoto(
            name: "nearby.jpg",
            date: Date(timeIntervalSince1970: 250),
            latitude: 37.77492,
            longitude: -122.41942
        )
        let otherLocation = makePhoto(
            name: "other.jpg",
            date: Date(timeIntervalSince1970: 300),
            latitude: 47.6062,
            longitude: -122.3321
        )

        let locations = PhotoLocationGroup.grouped(photos: [older, newer, nearby, otherLocation])

        XCTAssertEqual(locations.count, 3)
        XCTAssertEqual(locations.first?.photos.map(\.filename), ["other.jpg"])
        XCTAssertEqual(locations.first(where: { $0.photos.count == 2 })?.photos.map(\.filename), ["newer.jpg", "older.jpg"])
    }

    func testIgnoresPhotosWithoutValidCoordinates() {
        let noCoordinates = makePhoto(name: "missing.jpg", latitude: nil, longitude: nil)
        let invalidLatitude = makePhoto(name: "invalid.jpg", latitude: 91, longitude: 0)
        let invalidLongitude = makePhoto(name: "invalid-longitude.jpg", latitude: 0, longitude: .infinity)

        XCTAssertTrue(PhotoLocationGroup.grouped(photos: [noCoordinates, invalidLatitude, invalidLongitude]).isEmpty)
    }

    func testDateFilterIncludesWholeSelectedDaysAndRemovesEmptyLocations() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10)))
        let secondDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))
        let thirdDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12)))
        let includedFirstDay = makePhoto(
            name: "first-day.jpg",
            date: firstDay.addingTimeInterval(60 * 60 * 23),
            latitude: 37.7749,
            longitude: -122.4194
        )
        let includedSecondDay = makePhoto(
            name: "second-day.jpg",
            date: secondDay.addingTimeInterval(60 * 60 * 2),
            latitude: 37.7749,
            longitude: -122.4194
        )
        let excluded = makePhoto(
            name: "outside-range.jpg",
            date: thirdDay,
            latitude: 47.6062,
            longitude: -122.3321
        )
        let locations = PhotoLocationGroup.grouped(photos: [includedFirstDay, includedSecondDay, excluded])

        let filtered = PhotoLocationGroup.filtering(
            locations,
            from: firstDay.addingTimeInterval(60 * 60 * 12),
            through: secondDay,
            calendar: calendar
        )

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.photos.map(\.filename), ["second-day.jpg", "first-day.jpg"])
    }

    private func makePhoto(
        name: String,
        date: Date = Date(),
        latitude: Double?,
        longitude: Double?
    ) -> Photo {
        Photo(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            date: date,
            latitude: latitude,
            longitude: longitude
        )
    }
}
