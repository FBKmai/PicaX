import SwiftUI
#if os(iOS)
import UIKit

struct ReaderContinuousZoomHost<Content: View>: UIViewRepresentable {
    let configuration: ReaderZoomConfiguration
    let resetID: String
    let content: Content

    init(
        configuration: ReaderZoomConfiguration,
        resetID: String,
        @ViewBuilder content: () -> Content
    ) {
        self.configuration = configuration
        self.resetID = resetID
        self.content = content()
    }

    func makeUIView(context: Context) -> ReaderContinuousZoomUIView {
        ReaderContinuousZoomUIView(rootView: AnyView(content))
    }

    func updateUIView(_ uiView: ReaderContinuousZoomUIView, context: Context) {
        uiView.update(rootView: AnyView(content), configuration: configuration, resetID: resetID)
    }

    static func dismantleUIView(_ uiView: ReaderContinuousZoomUIView, coordinator: ()) {
        uiView.prepareForReuse()
    }
}

// Keep this bridge type-erased: a generic UIHostingController subclass crashes
// the Swift compiler during the CI Release whole-module optimization build.
final class ReaderContinuousZoomUIView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let scrollView = UIScrollView()
    private lazy var horizontalPanRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handleHorizontalPan(_:)))
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        recognizer.isEnabled = false
        return recognizer
    }()
    private let hostingController: UIHostingController<AnyView>
    private var resetID = ""
    private var lastBoundsSize: CGSize = .zero
    private var configuration = ReaderZoomConfiguration(
        pinchEnabled: true,
        doubleTapEnabled: true,
        doubleTapScale: 1.75,
        longPressEnabled: true,
        longPressScale: 1.75,
        longPressTriggerDuration: ReaderZoomConfiguration.defaultLongPressTriggerDuration
    )
    private var longPressStartedZoom = false

    init(rootView: AnyView) {
        hostingController = UIHostingController(rootView: rootView)
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(rootView: AnyView, configuration: ReaderZoomConfiguration, resetID: String) {
        hostingController.rootView = rootView
        let wasZoomEnabled = self.configuration.isZoomEnabled
        if self.configuration != configuration {
            self.configuration = configuration
            configureGestures()
            configureZoomLimits()
        }
        let shouldReset = self.resetID != resetID
        self.resetID = resetID
        if shouldReset || (wasZoomEnabled && !configuration.isZoomEnabled) {
            resetZoom(animated: false)
        }
    }

    func prepareForReuse() {
        resetZoom(animated: false)
        resetID = ""
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        // The hosting view fills the viewport; reading progress does not change its size.
        guard lastBoundsSize != bounds.size else { return }
        let previousSize = lastBoundsSize
        let normalizedCenterX = previousSize.width > 0
            ? (scrollView.contentOffset.x + previousSize.width * 0.5)
                / (previousSize.width * scrollView.zoomScale)
            : 0.5
        lastBoundsSize = bounds.size
        scrollView.frame = bounds
        if previousSize == .zero {
            resetZoom(animated: false)
        } else {
            layoutHostedViewForCurrentZoomScale(adjustsReadingOffset: false)
            scrollView.contentOffset = clampedContentOffset(CGPoint(
                x: normalizedCenterX * scrollView.contentSize.width - bounds.width * 0.5,
                y: 0
            ))
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        hostingController.view
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateContentInsets()
        updateInteractionState()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        layoutHostedViewForCurrentZoomScale()
        updateInteractionState()
    }

    private func setup() {
        backgroundColor = .black
        clipsToBounds = true

        scrollView.delegate = self
        scrollView.backgroundColor = .black
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.bounces = true
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        // UIScrollView owns its built-in pan delegate. Use our explicitly
        // delegated recognizer to cooperate with the SwiftUI reading scroll view.
        scrollView.panGestureRecognizer.isEnabled = false
        scrollView.addGestureRecognizer(horizontalPanRecognizer)

        hostingController.view.backgroundColor = .clear
        hostingController.view.frame = bounds

        addSubview(scrollView)
        scrollView.addSubview(hostingController.view)
        configureGestures()
        configureZoomLimits()
    }

    private func configureGestures() {
        scrollView.pinchGestureRecognizer?.isEnabled = configuration.pinchEnabled
        if scrollView.gestureRecognizers?.contains(where: { $0.name == "reader.continuousDoubleTapZoom" }) != true {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            recognizer.numberOfTapsRequired = 2
            recognizer.name = "reader.continuousDoubleTapZoom"
            recognizer.cancelsTouchesInView = true
            recognizer.delegate = self
            scrollView.addGestureRecognizer(recognizer)
        }
        if scrollView.gestureRecognizers?.contains(where: { $0.name == "reader.continuousLongPressZoom" }) != true {
            let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            recognizer.minimumPressDuration = configuration.normalizedLongPressTriggerDuration
            recognizer.allowableMovement = 12
            recognizer.name = "reader.continuousLongPressZoom"
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            scrollView.addGestureRecognizer(recognizer)
        }
        scrollView.gestureRecognizers?.forEach { recognizer in
            if recognizer.name == "reader.continuousDoubleTapZoom" {
                recognizer.isEnabled = configuration.doubleTapEnabled
            } else if recognizer.name == "reader.continuousLongPressZoom" {
                recognizer.isEnabled = configuration.longPressEnabled
                (recognizer as? UILongPressGestureRecognizer)?.minimumPressDuration = configuration.normalizedLongPressTriggerDuration
            }
        }
    }

    private func configureZoomLimits() {
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = max(2.5, configuration.normalizedDoubleTapScale, configuration.normalizedLongPressScale)
        if scrollView.zoomScale < scrollView.minimumZoomScale {
            scrollView.zoomScale = scrollView.minimumZoomScale
        } else if scrollView.zoomScale > scrollView.maximumZoomScale {
            scrollView.zoomScale = scrollView.maximumZoomScale
        }
        updateInteractionState()
    }

    private func resetZoom(animated: Bool) {
        longPressStartedZoom = false
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: animated)
        scrollView.contentOffset = .zero
        if !animated {
            scrollView.contentSize = bounds.size
            hostingController.view.transform = .identity
            hostingController.view.frame = CGRect(origin: .zero, size: bounds.size)
        }
        updateContentInsets()
        updateInteractionState()
    }

    private func layoutHostedViewForCurrentZoomScale(adjustsReadingOffset: Bool = true) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let readingScrollView = findReadingScrollView(in: hostingController.view)
        let scale = scrollView.zoomScale
        let oldOffset = scrollView.contentOffset
        let readingOffset = adjustsReadingOffset ? readingScrollView?.contentOffset : nil

        // Keep the scaled reading viewport exactly as tall as the screen. The
        // inner scroll view owns vertical scrolling; this scroll view owns zoom
        // and horizontal panning, so every page remains reachable at any scale.
        hostingController.view.bounds = CGRect(
            origin: .zero,
            size: CGSize(width: bounds.width, height: bounds.height / scale)
        )
        scrollView.contentSize = CGSize(width: bounds.width * scale, height: bounds.height)
        hostingController.view.center = CGPoint(
            x: scrollView.contentSize.width * 0.5,
            y: bounds.height * 0.5
        )
        hostingController.view.layoutIfNeeded()
        updateContentInsets()
        scrollView.contentOffset = clampedContentOffset(CGPoint(x: oldOffset.x, y: 0))

        // Transfer the vertical displacement introduced by the zoom into the
        // reading position, preserving the content under the zoom anchor.
        if let readingScrollView, let readingOffset {
            let minY = -readingScrollView.adjustedContentInset.top
            let maxY = max(
                readingScrollView.contentSize.height - readingScrollView.bounds.height
                    + readingScrollView.adjustedContentInset.bottom,
                minY
            )
            readingScrollView.contentOffset = CGPoint(
                x: readingOffset.x,
                y: min(max(readingOffset.y + oldOffset.y / scale, minY), maxY)
            )
        }
    }

    private func findReadingScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = findReadingScrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }

    private func clampedContentOffset(_ offset: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(offset.x, 0), max(scrollView.contentSize.width - bounds.width, 0)),
            y: min(max(offset.y, 0), max(scrollView.contentSize.height - bounds.height, 0))
        )
    }

    private func updateContentInsets() {
        let contentSize = scrollView.contentSize
        let insetX = max((bounds.width - contentSize.width) * 0.5, 0)
        let insetY = max((bounds.height - contentSize.height) * 0.5, 0)
        let insets = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
        if scrollView.contentInset != insets {
            scrollView.contentInset = insets
        }
    }

    private func updateInteractionState() {
        let isZoomed = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
        if horizontalPanRecognizer.isEnabled != isZoomed {
            horizontalPanRecognizer.isEnabled = isZoomed
        }
    }

    @objc private func handleHorizontalPan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        recognizer.setTranslation(.zero, in: self)
        guard !scrollView.isZooming, !scrollView.isZoomBouncing else { return }

        switch recognizer.state {
        case .began, .changed, .ended:
            ReaderZoomTapSuppressor.suppressTap()
            // Measure in the unscaled viewport so the image follows the finger
            // one-to-one. Vertical movement remains with the reading scroll view.
            scrollView.contentOffset = clampedContentOffset(CGPoint(
                x: scrollView.contentOffset.x - translation.x,
                y: scrollView.contentOffset.y
            ))
        default:
            break
        }
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard configuration.doubleTapEnabled, recognizer.state == .ended else { return }
        ReaderZoomTapSuppressor.suppressTap()
        if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
            resetZoom(animated: true)
            return
        }

        zoom(to: configuration.normalizedDoubleTapScale, at: recognizer.location(in: hostingController.view), animated: true)
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard configuration.longPressEnabled else { return }
        switch recognizer.state {
        case .began:
            ReaderZoomTapSuppressor.suppressTap(for: 0.5)
            guard scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 else {
                longPressStartedZoom = false
                return
            }
            longPressStartedZoom = true
            zoom(to: configuration.normalizedLongPressScale, at: recognizer.location(in: hostingController.view), animated: true)
        case .changed:
            if longPressStartedZoom {
                ReaderZoomTapSuppressor.suppressTap(for: 0.5)
            }
        case .ended, .cancelled, .failed:
            if longPressStartedZoom {
                ReaderZoomTapSuppressor.suppressTap()
                resetZoom(animated: true)
            }
            longPressStartedZoom = false
        default:
            break
        }
    }

    private func zoom(to multiplier: CGFloat, at location: CGPoint, animated: Bool) {
        let targetScale = min(max(scrollView.minimumZoomScale * multiplier, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
        let size = CGSize(width: bounds.width / targetScale, height: bounds.height / targetScale)
        let zoomRect = CGRect(
            x: location.x - size.width * 0.5,
            y: location.y - size.height * 0.5,
            width: size.width,
            height: size.height
        )
        scrollView.zoom(to: zoomRect, animated: animated)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === horizontalPanRecognizer {
            return otherGestureRecognizer === scrollView.pinchGestureRecognizer
                || otherGestureRecognizer.view?.isDescendant(of: hostingController.view) == true
        }
        return true
    }
}

#endif
