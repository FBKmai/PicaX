import CoreGraphics

nonisolated struct ReaderPagedViewport {
    private(set) var size: CGSize = .zero

    @discardableResult
    mutating func updateSize(_ newSize: CGSize) -> Bool {
        guard newSize.width.isFinite, newSize.height.isFinite,
              newSize.width > 0, newSize.height > 0,
              newSize != size else {
            return false
        }
        size = newSize
        return true
    }

    func matches(_ candidate: CGSize) -> Bool {
        size.width > 0 && size.height > 0 && size == candidate
    }
}
