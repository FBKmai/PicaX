import XCTest
@testable import PicaX

@MainActor
final class ReaderContinuousSequenceTests: XCTestCase {
    func testChaptersThenBooksAppendWithDistinctPageIdentities() async throws {
        let first = book("first", chapterCount: 2)
        let second = book("second")
        let sequence = ReaderContinuousSequence(book: first, chapterIndex: 0, images: images("first-0"))
        sequence.configure(entries: entries(first, second), loadBook: { _ in second }, currentBookID: first.id)

        await sequence.appendNext()
        XCTAssertEqual(sequence.sections.map(\.book.id), [first.id, first.id])
        XCTAssertEqual(sequence.sections.map(\.chapterIndex), [0, 1])
        await sequence.appendNext()
        XCTAssertEqual(sequence.sections.map(\.book.id), [first.id, first.id, second.id])
        XCTAssertNotEqual(sequence.sections[0].pageID(0), sequence.sections[2].pageID(0))
        XCTAssertFalse(sequence.canAppend)

        let firstPage = sequence.sections[0].pageID(0)
        let nextBookPage = sequence.sections[2].pageID(0)
        let completed = try XCTUnwrap(sequence.completedBook(movingFrom: firstPage, to: nextBookPage))
        XCTAssertEqual(completed.chapterIndex, 1)
        XCTAssertNil(sequence.completedBook(movingFrom: nextBookPage, to: firstPage))
    }

    func testFailedNextBookStaysAtBoundaryAndCanRetry() async {
        let first = book("first")
        var attempts = 0
        let second = book("second", loadImages: { _ in
            attempts += 1
            return attempts == 1 ? [] : self.images("second")
        })
        let sequence = ReaderContinuousSequence(book: first, chapterIndex: 0, images: images("first"))
        sequence.configure(entries: entries(first, second), loadBook: { _ in second }, currentBookID: first.id)

        await sequence.appendNext()
        XCTAssertEqual(sequence.sections.count, 1)
        XCTAssertNotNil(sequence.errorMessage)
        XCTAssertEqual(sequence.nextBookEntry?.id, second.id)
        XCTAssertFalse(sequence.isLoading)

        await sequence.appendNext()
        XCTAssertEqual(sequence.sections.last?.book.id, second.id)
        XCTAssertNil(sequence.errorMessage)
        XCTAssertEqual(attempts, 2)
    }

    func testReorderingDiscardsInFlightBookAndLoadsNewSuccessor() async {
        let first = book("first")
        var discardedBookImageRequests = 0
        let second = book("second", loadImages: { _ in
            discardedBookImageRequests += 1
            return self.images("second")
        })
        let third = book("third")
        let sequence = ReaderContinuousSequence(book: first, chapterIndex: 0, images: images("first"))
        let started = expectation(description: "next book request started")
        var finishLoading: CheckedContinuation<ReaderContinuousBook, Never>?
        sequence.configure(entries: entries(first, second, third), loadBook: { _ in
            await withCheckedContinuation { continuation in
                finishLoading = continuation
                started.fulfill()
            }
        }, currentBookID: first.id)

        let loading = Task { await sequence.appendNext() }
        await fulfillment(of: [started], timeout: 2)
        sequence.configure(entries: entries(first, third, second), loadBook: { _ in third }, currentBookID: first.id)
        finishLoading?.resume(returning: second)
        await loading.value
        XCTAssertEqual(sequence.sections.map(\.book.id), [first.id])
        XCTAssertEqual(discardedBookImageRequests, 0)
        await sequence.appendNext()
        XCTAssertEqual(sequence.sections.map(\.book.id), [first.id, third.id])
    }

    func testRemovingReadBookPreservesCurrentBookAndDisablingStopsAtItsEnd() async {
        let first = book("first")
        let second = book("second")
        let third = book("third")
        let sequence = ReaderContinuousSequence(book: first, chapterIndex: 0, images: images("first"))
        sequence.configure(entries: entries(first, second, third), loadBook: { entry in
            entry.id == second.id ? second : third
        }, currentBookID: first.id)
        await sequence.appendNext()
        await sequence.appendNext()

        sequence.configure(entries: entries(second, third), loadBook: { _ in third }, currentBookID: second.id)
        XCTAssertEqual(sequence.sections.map(\.book.id), [second.id])
        XCTAssertEqual(sequence.nextBookEntry?.id, third.id)
        sequence.configure(entries: [], loadBook: nil, currentBookID: second.id)
        await sequence.appendNext()
        XCTAssertEqual(sequence.sections.map(\.book.id), [second.id])
        XCTAssertFalse(sequence.canAppend)
    }

    func testActiveBookControlsProgressBookmarksAndLocalChapterSource() async throws {
        let first = book("first", chapterCount: 2)
        let second = book("second", chapterCount: 2, historyChapterIndex: { $0 + 4 })
        let viewModel = ComicReaderViewModel(
            detail: first.detail, initialChapterIndex: 0, initialPageIndex: 0,
            service: ComicContentService(), localChapterImageProvider: nil, initialContinuousBook: first
        )
        let section = ReaderContinuousChapterSection(book: second, chapterIndex: 0, images: images("second-0"))
        XCTAssertTrue(viewModel.adoptContinuousPosition(section: section, pageIndex: 1))
        XCTAssertEqual(viewModel.detail.item.id, "second")
        XCTAssertEqual(viewModel.currentPageIndex, 1)
        XCTAssertEqual(viewModel.continuousBook?.historyChapterIndex(0), 4)
        XCTAssertEqual(viewModel.bookmarkImageURL(chapterIndex: 0, pageIndex: 1), "file:///tmp/second-0-1.jpg")

        await viewModel.loadChapter(index: 1, pageIndex: 0, account: nil)
        guard case .loaded(let loadedImages) = viewModel.state else {
            return XCTFail("The next chapter must use the active book's source")
        }
        XCTAssertEqual(loadedImages, images("second-1"))

        let previousSection = ReaderContinuousChapterSection(book: first, chapterIndex: 0, images: images("first-0"))
        XCTAssertTrue(viewModel.adoptContinuousPosition(section: previousSection, pageIndex: 0))
        XCTAssertEqual(viewModel.detail.item.id, "first")
        XCTAssertEqual(viewModel.loadedChapterIndex, 0)
        XCTAssertNil(viewModel.bookmarkImageURL(chapterIndex: 1, pageIndex: 0))
    }

    private func entries(_ books: ReaderContinuousBook...) -> [ReadingListEntry] {
        books.map { .online($0.detail.item) }
    }

    private func images(_ prefix: String) -> [ComicChapterImage] {
        (0..<2).map { .init(id: "page-\($0)", urlString: "file:///tmp/\(prefix)-\($0).jpg") }
    }

    private func book(
        _ id: String,
        chapterCount: Int = 1,
        historyChapterIndex: @escaping (Int) -> Int = { $0 },
        loadImages: ((Int) async throws -> [ComicChapterImage])? = nil
    ) -> ReaderContinuousBook {
        let item = ComicListItem(
            id: id, platform: .local, title: id, subtitle: "", coverURLString: "", tags: [],
            pageCount: nil, likesCount: nil, favoriteDate: nil
        )
        let detail = ComicDetailInfo(
            item: item, description: "", tagGroups: [],
            chapters: (0..<chapterCount).map { .init(id: "chapter-\($0)", title: "Chapter \($0)", subtitle: nil) },
            related: [], updatedText: nil
        )
        return ReaderContinuousBook(
            id: item.readingHistoryID, detail: detail, account: nil, localCommentsProvider: nil,
            historyChapterIndex: historyChapterIndex,
            loadImages: loadImages ?? { self.images("\(id)-\($0)") }
        )
    }
}
