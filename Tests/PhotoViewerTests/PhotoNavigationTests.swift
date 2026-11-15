import Foundation
import XCTest
@testable import PhotoViewer

@MainActor
final class PhotoNavigationTests: XCTestCase {
    func testNextAndPreviousPhotoFollowLibraryOrderAcrossMonths() {
        let viewModel = PhotoViewModel()
        let newestMonthPhotos = makePhotos(prefix: "newest", count: 2)
        let previousMonthPhotos = makePhotos(prefix: "previous", count: 2)
        viewModel.photoMonths = [
            PhotoMonth(year: 2026, month: 10, photos: newestMonthPhotos),
            PhotoMonth(year: 2026, month: 9, photos: previousMonthPhotos)
        ]

        XCTAssertEqual(viewModel.nextPhoto(after: newestMonthPhotos[1]), previousMonthPhotos[0])
        XCTAssertEqual(viewModel.previousPhoto(before: previousMonthPhotos[0]), newestMonthPhotos[1])
        XCTAssertNil(viewModel.nextPhoto(after: previousMonthPhotos[1]))
        XCTAssertNil(viewModel.previousPhoto(before: newestMonthPhotos[0]))
    }

    func testLoopingNextPhotoReturnsFirstPhotoAfterLast() {
        let viewModel = PhotoViewModel()
        let photos = makePhotos(prefix: "loop", count: 3)
        viewModel.photoMonths = [PhotoMonth(year: 2026, month: 10, photos: photos)]

        XCTAssertEqual(viewModel.nextPhoto(after: photos[0], looping: true), photos[1])
        XCTAssertEqual(viewModel.nextPhoto(after: photos[2], looping: true), photos[0])
        XCTAssertNil(viewModel.nextPhoto(after: photos[2]))
    }

    func testLoopingNextPhotoDoesNotRestartForUnknownPhoto() {
        let viewModel = PhotoViewModel()
        let photos = makePhotos(prefix: "known", count: 2)
        viewModel.photoMonths = [PhotoMonth(year: 2026, month: 10, photos: photos)]
        let unknownPhoto = Photo(
            url: URL(fileURLWithPath: "/tmp/unknown-\(UUID().uuidString).jpg"),
            date: Date()
        )

        XCTAssertNil(viewModel.nextPhoto(after: unknownPhoto, looping: true))
    }

    private func makePhotos(prefix: String, count: Int) -> [Photo] {
        (0..<count).map { index in
            Photo(
                url: URL(fileURLWithPath: "/tmp/\(prefix)-\(index)-\(UUID().uuidString).jpg"),
                date: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
    }
}
