import AppKit
import XCTest
@testable import PhotoViewer

final class ThumbnailServiceTests: XCTestCase {
    func testCachedThumbnailMustMeetRequestedPixelSize() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 400,
            pixelsHigh: 300,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let image = NSImage(size: NSSize(width: 200, height: 150))
        image.addRepresentation(bitmap)

        XCTAssertTrue(
            ThumbnailService.hasSufficientResolution(
                image,
                for: CGSize(width: 180, height: 120),
                backingScaleFactor: 2
            )
        )
        XCTAssertFalse(
            ThumbnailService.hasSufficientResolution(
                image,
                for: CGSize(width: 220, height: 180),
                backingScaleFactor: 2
            )
        )
    }
}
