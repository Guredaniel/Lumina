import Foundation
import SQLite3
import XCTest
@testable import PhotoViewer

final class PhotoScannerTests: XCTestCase {
    func testCaptureDateUsesOriginalExifWallTimeInsteadOfTimezoneOffset() throws {
        let fallback = Date(timeIntervalSince1970: 0)
        let date = PhotoScanner.captureDate(
            from: [
                "dateTime": "2024:02:29 23:30:00",
                "dateTimeOffset": "-08:00",
                "dateTimeDigitized": "2020:01:01 00:00:00"
            ],
            fallback: fallback
        )

        XCTAssertEqual(date, try localDate(year: 2024, month: 2, day: 29, hour: 23, minute: 30))
    }

    func testCaptureDateFallsBackToDigitizedDateWhenOriginalIsInvalid() throws {
        let fallback = Date(timeIntervalSince1970: 0)
        let date = PhotoScanner.captureDate(
            from: [
                "dateTime": "not a date",
                "dateTimeDigitized": "2021:06:15 12:00:00",
                "dateTimeDigitizedOffset": "+00:00"
            ],
            fallback: fallback
        )

        XCTAssertEqual(date, try localDate(year: 2021, month: 6, day: 15, hour: 12))
    }

    func testCaptureDateUsesFileDateWhenMetadataIsUnavailable() {
        let fallback = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertEqual(PhotoScanner.captureDate(from: [:], fallback: fallback), fallback)
    }

    func testCaptureDateUsesTIFFDateWhenExifDatesAreMissing() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let expected = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2020,
            month: 12,
            day: 31,
            hour: 23,
            minute: 59,
            second: 58
        )))

        let date = PhotoScanner.captureDate(
            from: ["tiffDateTime": "2020:12:31 23:59:58"],
            fallback: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(date, expected)
    }

    func testCaptureDateParsesFractionalISO8601Values() throws {
        let date = PhotoScanner.captureDate(
            from: ["dateTime": "2024-02-29T23:30:00.123-08:00"],
            fallback: Date(timeIntervalSince1970: 0)
        )
        let expected = try localDate(year: 2024, month: 2, day: 29, hour: 23, minute: 30, nanosecond: 123_000_000)

        XCTAssertEqual(date.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)
    }

    func testInvalidCaptureDatesUseFileDateFallback() {
        let fallback = Date(timeIntervalSince1970: 1_700_000_000)
        let date = PhotoScanner.captureDate(
            from: [
                "dateTime": "2024:02:30 23:30:00",
                "dateTimeDigitized": "not a date",
                "tiffDateTime": "also not a date"
            ],
            fallback: fallback
        )

        XCTAssertEqual(date, fallback)
    }

    func testCaptureDateMigrationRescansOldRowsOnceAndPreservesFavorites() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoViewerTests-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: databaseURL)
            try? FileManager.default.removeItem(at: databaseURL.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: databaseURL.appendingPathExtension("shm"))
        }

        var legacyDB: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &legacyDB) == SQLITE_OK, let legacyDB else {
            XCTFail("Could not create the legacy test database")
            return
        }

        let createLegacyPhoto = """
        CREATE TABLE photos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url_path TEXT UNIQUE NOT NULL,
            filename TEXT NOT NULL,
            date_taken REAL NOT NULL,
            file_modified_date REAL NOT NULL,
            file_size INTEGER NOT NULL,
            is_video INTEGER NOT NULL DEFAULT 0,
            video_path TEXT,
            exif_json TEXT,
            latitude REAL,
            longitude REAL,
            is_favorite INTEGER NOT NULL DEFAULT 0
        );
        INSERT INTO photos (url_path, filename, date_taken, file_modified_date, file_size, is_favorite)
        VALUES ('/tmp/legacy-photo.jpg', 'legacy-photo.jpg', 0, 0, 123, 1);
        PRAGMA user_version = 1;
        """
        let setupResult = sqlite3_exec(legacyDB, createLegacyPhoto, nil, nil, nil)
        let closeResult = sqlite3_close_v2(legacyDB)
        XCTAssertEqual(setupResult, SQLITE_OK)
        XCTAssertEqual(closeResult, SQLITE_OK)

        do {
            let database = SQLiteDatabase(databaseURL: databaseURL)
            let knownFile = database.getKnownFiles(forDirectoryPrefix: "/tmp/legacy-photo.jpg")
            XCTAssertEqual(knownFile["/tmp/legacy-photo.jpg"]?.fileSize, -1)
            XCTAssertTrue(database.fetchFavoritePaths().contains("/tmp/legacy-photo.jpg"))

            let photo = Photo(
                url: URL(fileURLWithPath: "/tmp/legacy-photo.jpg"),
                date: Date(timeIntervalSince1970: 1_700_000_000)
            )
            database.batchUpsertPhotos([(photo: photo, fileModifiedDate: photo.date, fileSize: 456)])
        }

        do {
            let reopenedDatabase = SQLiteDatabase(databaseURL: databaseURL)
            let knownFileAfterReopen = reopenedDatabase.getKnownFiles(forDirectoryPrefix: "/tmp/legacy-photo.jpg")
            XCTAssertEqual(knownFileAfterReopen["/tmp/legacy-photo.jpg"]?.fileSize, 456)
        }
    }

    private func localDate(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0, nanosecond: Int = 0) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.nanosecond = nanosecond
        return try XCTUnwrap(Calendar.current.date(from: components))
    }
}
