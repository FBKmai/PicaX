import XCTest
@testable import PicaX

final class ReaderPagedViewportTests: XCTestCase {
    func testFirstValidSizeStartsViewportTracking() {
        var viewport = ReaderPagedViewport()
        let size = CGSize(width: 390, height: 844)

        XCTAssertFalse(viewport.matches(.zero))
        XCTAssertTrue(viewport.updateSize(size))
        XCTAssertTrue(viewport.matches(size))
        XCTAssertFalse(viewport.updateSize(size))
    }

    func testFoldingAndRotationRejectOffsetsFromPreviousViewport() {
        var viewport = ReaderPagedViewport()
        let closed = CGSize(width: 390, height: 844)
        let opened = CGSize(width: 760, height: 980)
        let rotated = CGSize(width: 980, height: 760)

        for size in [closed, opened, rotated, closed] {
            let previousSize = viewport.size
            XCTAssertFalse(viewport.matches(size))
            XCTAssertTrue(viewport.updateSize(size))
            XCTAssertTrue(viewport.matches(size))
            XCTAssertFalse(viewport.matches(previousSize))
        }
    }

    func testInvalidTransientSizesKeepLastValidViewport() {
        var viewport = ReaderPagedViewport()
        let size = CGSize(width: 390, height: 844)
        viewport.updateSize(size)

        let invalidSizes = [
            CGSize.zero,
            CGSize(width: 0, height: 844),
            CGSize(width: 390, height: -1),
            CGSize(width: CGFloat.infinity, height: 844),
            CGSize(width: 390, height: CGFloat.nan)
        ]
        for invalidSize in invalidSizes {
            XCTAssertFalse(viewport.updateSize(invalidSize))
            XCTAssertEqual(viewport.size, size)
            XCTAssertFalse(viewport.matches(invalidSize))
        }
    }
}
