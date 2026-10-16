import SwiftUI

struct ReaderWholeBookChapterSection: Identifiable {
    let chapterIndex: Int
    let chapter: ComicChapter
    let images: [ComicChapterImage]

    var id: String {
        "\(chapterIndex)-\(chapter.id)"
    }
}

struct ReaderWholeBookContinuousView: View {
    let listContext: ComicReaderListContext?
    let service: ComicContentService
    let imageSpacing: CGFloat
    let firstImageTopPadding: CGFloat
    let lastImageBottomPadding: CGFloat
    let preloadImageCount: Int
    let chapterLoadThreshold: Int
    let retryCount: Int
    let retryInterval: Double
    let targetPixelWidth: Int?
    let displaySize: CGSize
    let zoomConfiguration: ReaderZoomConfiguration
    let dimsImages: Bool
    let showsChapterComments: Bool
    let uiToggleMode: ReaderUIToggleMode
    let tapPagingEnabled: Bool
    let tapPagingEdgePercent: Int
    let tapPagingInverted: Bool
    let tapPagingDistancePercent: Int
    let doubleTapZoomEnabled: Bool
    let isAutoPaging: Bool
    let isAutoPagingSuspended: Bool
    let autoPagingInterval: Double
    let autoPagingDistancePercent: Int
    let smoothContinuousAutoPaging: Bool
    let automaticallyContinuesToNextBook: Bool
    @Binding var progressJumpRequest: ReaderProgressJumpRequest?
    let onToggleUI: () -> Void
    let onPositionChange: (ReaderContinuousChapterSection, Int, ReaderContinuousChapterSection?) -> Void
    let onReachedBookEnd: () -> Void

    @StateObject private var sequence: ReaderContinuousSequence
    @State private var loadableImageIDs = Set<String>()
    @State private var currentVisiblePage: ReaderWholeBookPageID
    @State private var appendTask: Task<Void, Never>?
    @State private var scrollBridge = ReaderContinuousScrollBridge()
    @State private var scrollTracker = ReaderContinuousScrollTracker()
    @State private var isAutoPagingTurnInFlight = false
    @State private var visiblePageIDs = Set<ReaderWholeBookPageID>()
    @State private var hasReportedBookEnd = false
    @State private var scrollPosition = ReaderWholeBookScrollPosition()

    init(
        initialBook: ReaderContinuousBook,
        listContext: ComicReaderListContext?,
        initialChapterIndex: Int,
        initialPageIndex: Int,
        initialImages: [ComicChapterImage],
        service: ComicContentService,
        imageSpacing: CGFloat,
        firstImageTopPadding: CGFloat,
        lastImageBottomPadding: CGFloat,
        preloadImageCount: Int,
        chapterLoadThreshold: Int,
        retryCount: Int,
        retryInterval: Double,
        targetPixelWidth: Int?,
        displaySize: CGSize,
        zoomConfiguration: ReaderZoomConfiguration,
        dimsImages: Bool,
        showsChapterComments: Bool,
        uiToggleMode: ReaderUIToggleMode,
        tapPagingEnabled: Bool,
        tapPagingEdgePercent: Int,
        tapPagingInverted: Bool,
        tapPagingDistancePercent: Int,
        doubleTapZoomEnabled: Bool,
        isAutoPaging: Bool,
        isAutoPagingSuspended: Bool,
        autoPagingInterval: Double,
        autoPagingDistancePercent: Int,
        smoothContinuousAutoPaging: Bool,
        automaticallyContinuesToNextBook: Bool,
        progressJumpRequest: Binding<ReaderProgressJumpRequest?>,
        onToggleUI: @escaping () -> Void,
        onPositionChange: @escaping (ReaderContinuousChapterSection, Int, ReaderContinuousChapterSection?) -> Void,
        onReachedBookEnd: @escaping () -> Void
    ) {
        self.listContext = listContext
        self.service = service
        self.imageSpacing = imageSpacing
        self.firstImageTopPadding = firstImageTopPadding
        self.lastImageBottomPadding = lastImageBottomPadding
        self.preloadImageCount = preloadImageCount
        self.chapterLoadThreshold = chapterLoadThreshold
        self.retryCount = retryCount
        self.retryInterval = retryInterval
        self.targetPixelWidth = targetPixelWidth
        self.displaySize = displaySize
        self.zoomConfiguration = zoomConfiguration
        self.dimsImages = dimsImages
        self.showsChapterComments = showsChapterComments
        self.uiToggleMode = uiToggleMode
        self.tapPagingEnabled = tapPagingEnabled
        self.tapPagingEdgePercent = tapPagingEdgePercent
        self.tapPagingInverted = tapPagingInverted
        self.tapPagingDistancePercent = tapPagingDistancePercent
        self.doubleTapZoomEnabled = doubleTapZoomEnabled
        self.isAutoPaging = isAutoPaging
        self.isAutoPagingSuspended = isAutoPagingSuspended
        self.autoPagingInterval = autoPagingInterval
        self.autoPagingDistancePercent = autoPagingDistancePercent
        self.smoothContinuousAutoPaging = smoothContinuousAutoPaging
        self.automaticallyContinuesToNextBook = automaticallyContinuesToNextBook
        _progressJumpRequest = progressJumpRequest
        self.onToggleUI = onToggleUI
        self.onPositionChange = onPositionChange
        self.onReachedBookEnd = onReachedBookEnd

        let boundedChapterIndex = min(max(initialChapterIndex, 0), max(initialBook.detail.chapters.count - 1, 0))
        let boundedPageIndex = min(max(initialPageIndex, 0), max(initialImages.count - 1, 0))
        _sequence = StateObject(wrappedValue: ReaderContinuousSequence(
            book: initialBook, chapterIndex: boundedChapterIndex, images: initialImages
        ))
        _currentVisiblePage = State(initialValue: ReaderWholeBookPageID(
            bookID: initialBook.id, chapterIndex: boundedChapterIndex, pageIndex: boundedPageIndex
        ))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: imageSpacing) {
                    ForEach(Array(sequence.sections.enumerated()), id: \.element.id) { sectionOffset, section in
                        Section {
                            ForEach(section.images.indices, id: \.self) { pageIndex in
                                let pageID = section.pageID(pageIndex)
                                ReaderImageView(
                                    image: section.images[pageIndex],
                                    retryCount: retryCount,
                                    retryInterval: retryInterval,
                                    targetPixelWidth: targetPixelWidth,
                                    displayWidth: displaySize.width,
                                    containerSize: nil,
                                    isLoadAllowed: loadableImageIDs.contains(section.images[pageIndex].urlString),
                                    zoomConfiguration: zoomConfiguration,
                                    dimsImage: dimsImages
                                )
                                .padding(.top, sectionOffset == 0 && pageIndex == 0 ? firstImageTopPadding : 0)
                                .padding(.bottom, pageIndex == section.images.index(before: section.images.endIndex) ? lastImageBottomPadding : 0)
                                .id(pageID)
                                .background {
                                    GeometryReader { pageGeometry in
                                        Color.clear.preference(
                                            key: ReaderWholeBookVisiblePageFramesPreferenceKey.self,
                                            value: [
                                                pageID: pageGeometry.frame(in: .named(coordinateSpaceName))
                                            ]
                                        )
                                    }
                                }
                            }

                            if showsChapterComments && service.supportsChapterComments(platform: section.book.detail.item.platform) {
                                ReaderChapterCommentsView(
                                    item: section.book.detail.item,
                                    chapter: section.chapter,
                                    chapterIndex: section.chapterIndex,
                                    service: service,
                                    account: section.book.account,
                                    localCommentsProvider: section.book.localCommentsProvider
                                )
                                .id("whole-book-comments-\(section.id)")
                                .padding(.horizontal, 10)
                            }
                        } header: {
                            if sectionOffset > 0 {
                                chapterHeader(section, startsBook: sequence.sections[sectionOffset - 1].book.id != section.book.id)
                            }
                        }
                    }

                    chapterAppendFooter
                }
                .padding(.vertical, 10)
                .readerContinuousScrollBridge(scrollBridge) { metrics in
                    handleScrollMetrics(metrics)
                }
            }
            .coordinateSpace(name: coordinateSpaceName)
            .background(Color.black)
            .ignoresSafeArea(.container)
            .readerInteractionGesture(
                size: displaySize,
                mode: uiToggleMode,
                tapPagingEnabled: tapPagingEnabled,
                tapPagingEdgePercent: tapPagingEdgePercent,
                tapPagingInverted: tapPagingInverted,
                doubleTapZoomEnabled: doubleTapZoomEnabled,
                readingMode: .topToBottomContinuous,
                toggleUI: onToggleUI,
                turnPage: { direction in
                    handleTapPage(direction)
                }
            )
            .readerAutoPaging(
                isEnabled: isAutoPaging && !isAutoPagingSuspended && !smoothContinuousAutoPaging,
                interval: autoPagingInterval
            ) {
                handleAutoPageTick()
            }
            .readerSmoothAutoPaging(
                isEnabled: isAutoPaging && !isAutoPagingSuspended && smoothContinuousAutoPaging,
                pointsPerSecond: smoothAutoPagingPointsPerSecond
            ) { distance in
                handleSmoothAutoPageStep(distance: distance)
            }
            .onPreferenceChange(ReaderWholeBookVisiblePageFramesPreferenceKey.self) { pageFrames in
                syncVisiblePage(pageFrames)
            }
            .task {
                let initialPage = currentVisiblePage
                scrollTracker.reset()
                focusLoadableImages(around: initialPage)
                configureReadingList()
                if let section = sequence.sections.first {
                    onPositionChange(section, initialPage.pageIndex, nil)
                }
                requestNextChapterIfNeeded(visiblePage: initialPage)
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled, !scrollTracker.isReady else { return }
                scrollTracker.setReady()
                guard !scrollTracker.hasUserScrolled,
                      !scrollBridge.isUserInteracting else { return }
                proxy.scrollTo(initialPage, anchor: .top)
            }
            .onDisappear {
                appendTask?.cancel()
                appendTask = nil
                sequence.cancelLoading()
            }
            .onChange(of: progressJumpRequest) { request in
                guard let request else { return }
                defer {
                    if progressJumpRequest?.id == request.id {
                        progressJumpRequest = nil
                    }
                }
                guard let section = sequence.sections.first(where: {
                    $0.book.id == currentVisiblePage.bookID && $0.chapterIndex == request.chapterIndex
                }),
                      !section.images.isEmpty else {
                    return
                }
                let pageIndex = min(max(request.pageIndex, 0), section.images.count - 1)
                let pageID = section.pageID(pageIndex)
                scrollTracker.setReady()
                focusLoadableImages(around: pageID)
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(pageID, anchor: .top)
                }
                currentVisiblePage = pageID
                onPositionChange(section, pageIndex, nil)
            }
            .onChange(of: listContext?.entries.map(\.id)) { _ in
                configureReadingList()
                requestNextChapterIfNeeded(visiblePage: currentVisiblePage)
            }
            .onChange(of: sequence.sections.count) { _ in
                focusLoadableImages(around: currentVisiblePage, visiblePageIDs: visiblePageIDs)
            }
            .onChange(of: automaticallyContinuesToNextBook) { isEnabled in
                if isEnabled {
                    continueToNextBookIfNeeded()
                }
            }
            .readerContinuousZoom(
                configuration: zoomConfiguration,
                resetID: coordinateSpaceName,
                allowsInteraction: true
            )
        }
    }

    private var coordinateSpaceName: String {
        "reader-whole-book-\(sequence.id)"
    }

    private var lastSection: ReaderContinuousChapterSection? {
        sequence.sections.last
    }

    private var hasReachedBookEnd: Bool {
        !sequence.canAppend
    }

    private var smoothAutoPagingPointsPerSecond: CGFloat {
        guard displaySize.height.isFinite,
              displaySize.height > 0,
              autoPagingInterval.isFinite,
              autoPagingInterval > 0 else {
            return 0
        }
        let distance = displaySize.height * CGFloat(autoPagingDistancePercent) / 100
        return distance / CGFloat(autoPagingInterval)
    }

    private var flattenedPages: [(id: ReaderWholeBookPageID, image: ComicChapterImage)] {
        sequence.sections.flatMap { section in
            section.images.indices.map { pageIndex in
                (
                    id: section.pageID(pageIndex),
                    image: section.images[pageIndex]
                )
            }
        }
    }

    @ViewBuilder
    private func chapterHeader(_ section: ReaderContinuousChapterSection, startsBook: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down")
                .font(.caption.weight(.bold))
            if startsBook {
                Text(section.book.detail.item.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            Text(section.chapter.title.isEmpty ? "第 \(section.chapterIndex + 1) 章" : section.chapter.title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .foregroundStyle(.white.opacity(0.82))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.black)
    }

    @ViewBuilder
    private var chapterAppendFooter: some View {
        if sequence.isLoading {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(.white)
                Text(sequence.isAtBookBoundary ? "正在加载下一本…" : "正在加载下一章…")
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.78))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else if let nextChapterError = sequence.errorMessage {
            VStack(spacing: 12) {
                Text(nextChapterError)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                Button(sequence.isAtBookBoundary ? "重试加载下一本" : "重试加载下一章") {
                    requestNextChapter(retry: true)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        } else if hasReachedBookEnd {
            Label(listContext == nil ? "已读完全书" : "已读完阅读列表", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.82))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
        }
    }

    private func syncVisiblePage(_ pageFrames: [ReaderWholeBookPageID: CGRect]) {
        scrollPosition.pageFrames = pageFrames
        if let anchor = scrollPosition.pendingAnchor, let frame = pageFrames[anchor.page] {
            scrollPosition.pendingAnchor = nil
            let targetY = max(scrollTracker.scrollY + frame.minY - anchor.minY, 0)
            if scrollBridge.scroll(toY: targetY, animated: false) {
                scrollTracker.updateScrollY(targetY)
            }
            return
        }
        guard displaySize.height.isFinite, displaySize.height > 0 else { return }
        let viewportHeight = scrollTracker.visibleHeight > 0 ? scrollTracker.visibleHeight : displaySize.height
        let viewport = CGRect(x: 0, y: 0, width: .greatestFiniteMagnitude, height: viewportHeight)
        let viewportCenterY = viewportHeight / 2
        let visiblePages = pageFrames.compactMap { id, frame -> (ReaderWholeBookPageID, CGFloat, CGFloat)? in
            guard frame.minY.isFinite, frame.maxY.isFinite else { return nil }
            let visibleHeight = frame.intersection(viewport).height
            guard visibleHeight > 1 else { return nil }
            return (id, visibleHeight, abs(frame.midY - viewportCenterY))
        }
        guard let visiblePage = visiblePages.max(by: { lhs, rhs in
            if abs(lhs.1 - rhs.1) > 1 {
                return lhs.1 < rhs.1
            }
            return lhs.2 > rhs.2
        })?.0,
              let section = sequence.sections.first(where: { $0.book.id == visiblePage.bookID && $0.chapterIndex == visiblePage.chapterIndex }) else {
            return
        }

        if visiblePage == sequence.sections.first?.pageID(0),
           visiblePage != currentVisiblePage,
           !scrollTracker.isUserInteracting,
           !scrollTracker.wasLastUserScrollNearTop(
               maximumOffset: (pageFrames[visiblePage]?.height ?? displaySize.height) + imageSpacing
           ) {
            return
        }

        let newVisiblePageIDs = Set(visiblePages.map(\.0))
        if newVisiblePageIDs != visiblePageIDs {
            visiblePageIDs = newVisiblePageIDs
            focusLoadableImages(around: visiblePage, visiblePageIDs: newVisiblePageIDs)
        }
        guard visiblePage != currentVisiblePage else { return }
        let completedBook = sequence.completedBook(movingFrom: currentVisiblePage, to: visiblePage)
        currentVisiblePage = visiblePage
        onPositionChange(section, visiblePage.pageIndex, completedBook)
        requestNextChapterIfNeeded(visiblePage: visiblePage)
    }

    private func focusLoadableImages(
        around pageID: ReaderWholeBookPageID,
        visiblePageIDs: Set<ReaderWholeBookPageID> = []
    ) {
        let pages = flattenedPages
        guard !pages.isEmpty else {
            loadableImageIDs.removeAll(keepingCapacity: true)
            return
        }
        var centers = pages.indices.filter { visiblePageIDs.contains(pages[$0].id) }
        if centers.isEmpty, let index = pages.firstIndex(where: { $0.id == pageID }) {
            centers = [index]
        }
        guard !centers.isEmpty else { return }

        let radius = min(max(preloadImageCount, 0), 15)
        var indices = Set<Int>()
        for center in centers {
            let start = max(center - radius, 0)
            let end = min(center + radius, pages.count - 1)
            indices.formUnion(start...end)
        }
        let imageIDs = Set(indices.map { pages[$0].image.urlString })
        guard imageIDs != loadableImageIDs else { return }
        loadableImageIDs = imageIDs
    }

    private func requestNextChapterIfNeeded(visiblePage: ReaderWholeBookPageID) {
        guard let lastSection,
              visiblePage.bookID == lastSection.book.id,
              visiblePage.chapterIndex == lastSection.chapterIndex,
              sequence.errorMessage == nil,
              visiblePage.pageIndex >= max(lastSection.images.count - chapterLoadThreshold, 0) else {
            return
        }
        requestNextChapter()
    }

    private func configureReadingList() {
        let previousIDs = sequence.sections.map(\.id)
        let anchorY = scrollPosition.pageFrames[currentVisiblePage]?.minY
        sequence.configure(
            entries: listContext?.entries ?? [],
            loadBook: listContext?.loadContinuousBook,
            currentBookID: currentVisiblePage.bookID
        )
        if previousIDs != sequence.sections.map(\.id), let anchorY {
            scrollPosition.pendingAnchor = (currentVisiblePage, anchorY)
        }
    }

    private func requestNextChapter(retry: Bool = false) {
        guard !sequence.isLoading, sequence.canAppend,
              retry || sequence.errorMessage == nil else { return }
        appendTask?.cancel()
        appendTask = Task { @MainActor in
            await sequence.appendNext()
        }
    }

    private func handleTapPage(_ direction: ReaderPageTurnDirection) {
        guard displaySize.height.isFinite, displaySize.height > 0 else { return }
        let currentY = scrollTracker.effectiveScrollY(fallback: nil)
        let maxY = scrollTracker.maxScrollY(fallbackViewportHeight: displaySize.height)
        let distance = max(displaySize.height * CGFloat(tapPagingDistancePercent) / 100, 1)
        let targetY = direction == .previous
            ? max(currentY - distance, 0)
            : min(currentY + distance, maxY)
        if scrollBridge.scroll(toY: targetY, animated: true) {
            scrollTracker.updateScrollY(targetY)
        }
        if direction == .next, targetY >= maxY - 4 {
            if hasReachedBookEnd {
                reportBookEndIfNeeded()
            } else {
                requestNextChapter()
            }
        }
    }

    private func handleScrollMetrics(_ metrics: ReaderScrollMetrics) {
        scrollTracker.updateMetrics(metrics)
        let maxY = max(metrics.contentHeight - metrics.visibleHeight, 0)
        guard metrics.offsetY >= maxY - 4 else {
            hasReportedBookEnd = false
            return
        }
        guard metrics.isUserInteracting else { return }
        continueToNextBookIfNeeded()
    }

    private func continueToNextBookIfNeeded() {
        guard automaticallyContinuesToNextBook,
              hasReachedBookEnd,
              scrollTracker.hasContentMetrics,
              scrollTracker.scrollY >= scrollTracker.maxScrollY(fallbackViewportHeight: displaySize.height) - 4 else {
            return
        }
        reportBookEndIfNeeded()
    }

    private func reportBookEndIfNeeded() {
        guard !hasReportedBookEnd else { return }
        hasReportedBookEnd = true
        onReachedBookEnd()
    }

    private func handleAutoPageTick() {
        guard isAutoPaging,
              !isAutoPagingSuspended,
              !smoothContinuousAutoPaging,
              !isAutoPagingTurnInFlight,
              displaySize.height.isFinite, displaySize.height > 0 else {
            return
        }
        isAutoPagingTurnInFlight = true
        let currentY = scrollTracker.effectiveScrollY(fallback: nil)
        let maxY = scrollTracker.maxScrollY(fallbackViewportHeight: displaySize.height)
        let distance = max(displaySize.height * CGFloat(autoPagingDistancePercent) / 100, 1)
        let targetY = min(currentY + distance, maxY)
        if scrollBridge.scroll(toY: targetY, animated: true) {
            scrollTracker.updateScrollY(targetY)
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            isAutoPagingTurnInFlight = false
            guard isAutoPaging, targetY >= maxY - 4 else { return }
            if hasReachedBookEnd {
                reportBookEndIfNeeded()
            } else {
                requestNextChapter()
            }
        }
    }

    private func handleSmoothAutoPageStep(distance: CGFloat) {
        guard isAutoPaging,
              !isAutoPagingSuspended,
              smoothContinuousAutoPaging,
              !isAutoPagingTurnInFlight,
              !scrollBridge.isUserInteracting,
              !sequence.isLoading,
              sequence.errorMessage == nil,
              scrollTracker.hasContentMetrics,
              displaySize.height.isFinite,
              displaySize.height > 0,
              distance.isFinite,
              distance > 0 else {
            return
        }

        let currentY = scrollTracker.effectiveScrollY(fallback: nil)
        let maxY = scrollTracker.maxScrollY(fallbackViewportHeight: displaySize.height)
        let targetY = min(currentY + distance, maxY)
        if scrollBridge.scroll(toY: targetY, animated: false) {
            scrollTracker.updateScrollY(targetY)
        }

        guard targetY >= maxY - 0.5 else { return }
        if hasReachedBookEnd {
            reportBookEndIfNeeded()
        } else {
            requestNextChapter()
        }
    }
}

// Geometry changes on every scroll tick; keep it outside observable view state.
@MainActor
private final class ReaderWholeBookScrollPosition {
    var pageFrames: [ReaderWholeBookPageID: CGRect] = [:]
    var pendingAnchor: (page: ReaderWholeBookPageID, minY: CGFloat)?
}
