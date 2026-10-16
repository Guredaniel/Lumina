import Foundation
import XCTest
@testable import PhotoViewer

final class TripDetectionServiceTests: XCTestCase {
    func testDetectsSeparateTripsWhenTimeGapExceedsLimit() {
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let firstTrip = makePhotos(count: 3, startDate: startDate, latitude: 56.95, longitude: 24.10)
        let secondTrip = makePhotos(count: 3, startDate: startDate.addingTimeInterval(48 * 3600), latitude: 31.77, longitude: 35.21)
        let service = TripDetectionService(minimumPhotos: 2, locationRadiusKilometers: 100, maximumTimeGapHours: 36)

        let albums = service.detectTrips(in: firstTrip + secondTrip)

        XCTAssertEqual(albums.count, 2)
        XCTAssertEqual(albums.map(\.photos.count).sorted(), [3, 3])
    }

    func testIgnoresPhotosWithoutValidGPS() {
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let validPhotos = makePhotos(count: 2, startDate: startDate, latitude: 56.95, longitude: 24.10)
        let missingLocation = Photo(url: URL(fileURLWithPath: "/tmp/no-gps.jpg"), date: startDate, exifMetadata: [:])
        let invalidLocation = Photo(
            url: URL(fileURLWithPath: "/tmp/invalid-gps.jpg"),
            date: startDate.addingTimeInterval(60),
            exifMetadata: ["gpsLatitude": "not-a-coordinate", "gpsLongitude": "24.10"]
        )
        let service = TripDetectionService(minimumPhotos: 2, locationRadiusKilometers: 100, maximumTimeGapHours: 36)

        let albums = service.detectTrips(in: validPhotos + [missingLocation, invalidLocation])

        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(albums[0].photos.count, 2)
    }

    func testDetectsSeparateTripsWhenDistanceExceedsLimit() {
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let firstTrip = makePhotos(count: 2, startDate: startDate, latitude: 56.95, longitude: 24.10)
        let secondTrip = makePhotos(count: 2, startDate: startDate.addingTimeInterval(60), latitude: 31.77, longitude: 35.21)
        let service = TripDetectionService(minimumPhotos: 2, locationRadiusKilometers: 100, maximumTimeGapHours: 36)

        let albums = service.detectTrips(in: firstTrip + secondTrip)

        XCTAssertEqual(albums.count, 2)
        XCTAssertEqual(albums.map(\.photos.count).sorted(), [2, 2])
    }

    func testIncludesPhotosAtExactTimeGapAndSortsPhotosByDate() {
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let earlierPhoto = Photo(
            url: URL(fileURLWithPath: "/tmp/earlier.jpg"),
            date: startDate,
            latitude: 56.95,
            longitude: 24.10
        )
        let laterPhoto = Photo(
            url: URL(fileURLWithPath: "/tmp/later.jpg"),
            date: startDate.addingTimeInterval(36 * 3600),
            latitude: 56.95,
            longitude: 24.10
        )
        let service = TripDetectionService(minimumPhotos: 2, locationRadiusKilometers: 100, maximumTimeGapHours: 36)

        let albums = service.detectTrips(in: [laterPhoto, earlierPhoto])

        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(albums[0].startDate, earlierPhoto.date)
        XCTAssertEqual(albums[0].endDate, laterPhoto.date)
        XCTAssertEqual(albums[0].photos.map(\.url), [laterPhoto.url, earlierPhoto.url])
    }

    func testDiscardsGroupsSmallerThanMinimumPhotoCount() {
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let photos = makePhotos(count: 2, startDate: startDate, latitude: 56.95, longitude: 24.10)
        let service = TripDetectionService(minimumPhotos: 3, locationRadiusKilometers: 100, maximumTimeGapHours: 36)

        let albums = service.detectTrips(in: photos)

        XCTAssertTrue(albums.isEmpty)
    }

    func testIgnoresCoordinatesOutsideValidRanges() {
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let photos = [
            Photo(
                url: URL(fileURLWithPath: "/tmp/invalid-latitude.jpg"),
                date: startDate,
                latitude: 90.01,
                longitude: 24.10
            ),
            Photo(
                url: URL(fileURLWithPath: "/tmp/invalid-longitude.jpg"),
                date: startDate.addingTimeInterval(60),
                latitude: 56.95,
                longitude: -180.01
            )
        ]
        let service = TripDetectionService(minimumPhotos: 1, locationRadiusKilometers: 100, maximumTimeGapHours: 36)

        let albums = service.detectTrips(in: photos)

        XCTAssertTrue(albums.isEmpty)
    }

    func testPersistsParsedGPSCoordinatesInSQLite() {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoViewerTests-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: databaseURL)
            try? FileManager.default.removeItem(at: databaseURL.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: databaseURL.appendingPathExtension("shm"))
        }

        let database = SQLiteDatabase(databaseURL: databaseURL)
        let photo = Photo(
            url: URL(fileURLWithPath: "/tmp/cached-gps.jpg"),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            exifMetadata: ["gpsLatitude": "56.95", "gpsLongitude": "24.10"]
        )
        database.batchUpsertPhotos([(photo: photo, fileModifiedDate: photo.date, fileSize: 100)])

        let loadedPhoto = database.fetchPhotos(forDirectories: []).first

        XCTAssertEqual(loadedPhoto?.latitude, 56.95)
        XCTAssertEqual(loadedPhoto?.longitude, 24.10)
    }

    private func makePhotos(count: Int, startDate: Date, latitude: Double, longitude: Double) -> [Photo] {
        (0..<count).map { index in
            Photo(
                url: URL(fileURLWithPath: "/tmp/photo-\(UUID().uuidString).jpg"),
                date: startDate.addingTimeInterval(TimeInterval(index * 60)),
                exifMetadata: [
                    "gpsLatitude": String(latitude),
                    "gpsLongitude": String(longitude)
                ]
            )
        }
    }
}