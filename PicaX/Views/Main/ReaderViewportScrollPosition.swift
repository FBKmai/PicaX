import CoreGraphics
import Foundation

enum ReaderViewportScrollAdjustment<PageID: Hashable> {
    case revealPage(PageID)
    case scrollTo(CGFloat)
}

// Only materialized pages participate, so a resize does not scan the whole book.
@MainActor
final class ReaderViewportScrollPosition<PageID: Hashable> {
    private struct Anchor {
        let page: PageID
        let fraction: CGFloat
        let topSpacing: CGFloat
    }

    private var viewportWidth: CGFloat = 0
    private var pageFrames: [PageID: CGRect] = [:]
    private var pendingAnchor: Anchor?
    private var lastAdjustedFrame: CGRect?
    private var hasRequestedPage = false

    var isRestoring: Bool { pendingAnchor != nil }

    func cancelRestoration() {
        pendingAnchor = nil
        lastAdjustedFrame = nil
        hasRequestedPage = false
    }

    func reset() {
        viewportWidth = 0
        pageFrames.removeAll(keepingCapacity: true)
        cancelRestoration()
    }

    func preservePosition(of page: PageID) {
        guard pendingAnchor?.page != page,
              let frame = pageFrames[page], frame.height > 0 else { return }
        pendingAnchor = Anchor(
            page: page,
            fraction: min(max(-frame.minY / frame.height, 0), 1),
            topSpacing: max(frame.minY, 0)
        )
        lastAdjustedFrame = nil
        hasRequestedPage = false
    }

    func updateViewportWidth(_ width: CGFloat, isUserInteracting: Bool) {
        guard width.isFinite, width > 0, abs(width - viewportWidth) > 0.5 else { return }
        if isUserInteracting {
            pendingAnchor = nil
        } else if viewportWidth > 0, pendingAnchor == nil {
            let firstVisiblePage = pageFrames
                .filter { $0.value.height > 0 && $0.value.maxY > 0 }
                .min { lhs, rhs in
                    max(lhs.value.minY, 0) < max(rhs.value.minY, 0)
                }
            if let page = firstVisiblePage?.key {
                preservePosition(of: page)
            }
        }
        viewportWidth = width
        lastAdjustedFrame = nil
        hasRequestedPage = false
    }

    func updateFrames(
        _ frames: [PageID: CGRect],
        viewportWidth: CGFloat,
        scrollY: CGFloat,
        isUserInteracting: Bool
    ) -> ReaderViewportScrollAdjustment<PageID>? {
        updateViewportWidth(viewportWidth, isUserInteracting: isUserInteracting)
        pageFrames = frames
        if isUserInteracting {
            pendingAnchor = nil
        }
        guard let anchor = pendingAnchor else { return nil }
        guard let frame = frames[anchor.page] else {
            guard !hasRequestedPage else { return nil }
            hasRequestedPage = true
            return .revealPage(anchor.page)
        }
        guard abs(frame.width - viewportWidth) <= 1 else { return nil }

        let desiredMinY = anchor.topSpacing - anchor.fraction * frame.height
        let adjustment = frame.minY - desiredMinY
        if abs(adjustment) <= 0.5 {
            pendingAnchor = nil
            lastAdjustedFrame = nil
            return nil
        }
        guard frame != lastAdjustedFrame else { return nil }
        lastAdjustedFrame = frame
        return .scrollTo(max(scrollY + adjustment, 0))
    }
}

