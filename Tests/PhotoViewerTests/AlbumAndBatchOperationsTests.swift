import Foundation
import XCTest
@testable import PhotoViewer

@MainActor
final class AlbumAndBatchOperationsTests: XCTestCase {

    func testCreateAndDeleteAlbum() {
        let viewModel = PhotoViewModel()
        let albumTitle = "Vacation Test \(UUID().uuidString)"
        
        // 1. Create an album
        guard let createdAlbum = viewModel.createAlbum(title: albumTitle) else {
            XCTFail("Failed to create album")
            return
        }
        
        XCTAssertEqual(createdAlbum.title, albumTitle)
        XCTAssertTrue(createdAlbum.isManual)
        XCTAssertTrue(viewModel.tripAlbums.contains(where: { $0.id == createdAlbum.id }))
        
        // 2. Set an icon and rename
        viewModel.setIcon("camera", forTripWithID: createdAlbum.id)
        viewModel.renameTrip(withID: createdAlbum.id, title: "\(albumTitle) Updated")
        
        let updated = viewModel.tripAlbum(withID: createdAlbum.id)
        XCTAssertEqual(updated?.title, "\(albumTitle) Updated")
        
        // 3. Delete the album
        viewModel.deleteAlbum(withID: createdAlbum.id)
        XCTAssertNil(viewModel.tripAlbum(withID: createdAlbum.id))
        XCTAssertFalse(viewModel.tripAlbums.contains(where: { $0.id == createdAlbum.id }))
    }

    func testToggleFavoritesBatch() {
        let viewModel = PhotoViewModel()
        let date = Date()
        let photo1 = Photo(url: URL(fileURLWithPath: "/tmp/fav-test-1-\(UUID().uuidString).jpg"), date: date, exifMetadata: [:])
        let photo2 = Photo(url: URL(fileURLWithPath: "/tmp/fav-test-2-\(UUID().uuidString).jpg"), date: date, exifMetadata: [:])
        let photos = [photo1, photo2]
        
        // Initially neither is favorite
        XCTAssertFalse(viewModel.isFavorite(photo: photo1))
        XCTAssertFalse(viewModel.isFavorite(photo: photo2))
        
        // Batch favorite both
        viewModel.toggleFavorites(for: photos)
        XCTAssertTrue(viewModel.isFavorite(photo: photo1))
        XCTAssertTrue(viewModel.isFavorite(photo: photo2))
        
        // Batch toggle when all are favorites -> both should become unfavorited
        viewModel.toggleFavorites(for: photos)
        XCTAssertFalse(viewModel.isFavorite(photo: photo1))
        XCTAssertFalse(viewModel.isFavorite(photo: photo2))
    }

    func testResetToDefaultsUsesTenTripMinimumPhotos() {
        let settings = AppSettings.shared
        settings.tripMinimumPhotos = 25
        XCTAssertEqual(settings.tripMinimumPhotos, 25)
        
        settings.resetToDefaults()
        XCTAssertEqual(settings.tripMinimumPhotos, 10)
    }

    func testDiskCacheSizeReturnsNonNegative() {
        let size = ThumbnailCacheManager.shared.diskCacheSize()
        XCTAssertGreaterThanOrEqual(size, 0)
    }

    func testDeletePhotosRemovesFromPhotoMonthsAndSelection() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file1 = tempDir.appendingPathComponent("test1.jpg")
        let file2 = tempDir.appendingPathComponent("test2.jpg")
        try "dummy1".write(to: file1, atomically: true, encoding: .utf8)
        try "dummy2".write(to: file2, atomically: true, encoding: .utf8)

        let viewModel = PhotoViewModel()
        let photo1 = Photo(url: file1, date: Date(), exifMetadata: [:])
        let photo2 = Photo(url: file2, date: Date(), exifMetadata: [:])
        
        let month = PhotoMonth(year: 2026, month: 10, photos: [photo1, photo2])
        viewModel.photoMonths = [month]
        viewModel.beginPhotoSelection()
        viewModel.togglePhotoSelection(photo1, extendSelection: false)
        viewModel.togglePhotoSelection(photo2, extendSelection: false)
        
        XCTAssertEqual(viewModel.selectedPhotos.count, 2)
        
        viewModel.deletePhotos([photo1])
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: file1.path))
        XCTAssertEqual(viewModel.photoMonths.first?.photos.count, 1)
        XCTAssertEqual(viewModel.photoMonths.first?.photos.first?.url, file2)
        XCTAssertFalse(viewModel.selectedPhotoPaths.contains(file1.path))
    }
}
