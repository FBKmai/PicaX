import Combine
import Foundation

@MainActor
final class ReaderContinuousSequence: ObservableObject {
    let id = UUID()
    @Published private(set) var sections: [ReaderContinuousChapterSection]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var entries: [ReadingListEntry] = []
    private var loadBook: ((ReadingListEntry) async throws -> ReaderContinuousBook)?
    private var generation = UUID()

    init(book: ReaderContinuousBook, chapterIndex: Int, images: [ComicChapterImage]) {
        sections = [.init(book: book, chapterIndex: chapterIndex, images: images)]
    }

    var nextBookEntry: ReadingListEntry? {
        guard let last = sections.last,
              let index = entries.firstIndex(where: { $0.id == last.book.id }),
              entries.indices.contains(index + 1) else { return nil }
        return entries[index + 1]
    }

    var isAtBookBoundary: Bool {
        guard let last = sections.last else { return false }
        return last.chapterIndex == last.book.detail.chapters.count - 1
    }

    var canAppend: Bool {
        !isAtBookBoundary || nextBookEntry != nil
    }

    func configure(
        entries: [ReadingListEntry],
        loadBook: ((ReadingListEntry) async throws -> ReaderContinuousBook)?,
        currentBookID: String
    ) {
        let changed = self.entries.map(\.id) != entries.map(\.id)
        self.entries = entries
        self.loadBook = loadBook
        guard changed else { return }
        cancelLoading()

        // Rebuild the unread tail in the new order. Keep the current book and readable past books.
        guard let currentEnd = sections.lastIndex(where: { $0.book.id == currentBookID }) else { return }
        let currentIndex = entries.firstIndex { $0.id == currentBookID } ?? 0
        let earlierIDs = Set(entries.prefix(currentIndex).map(\.id))
        sections = Array(sections[...currentEnd]).filter {
            $0.book.id == currentBookID || earlierIDs.contains($0.book.id)
        }
    }

    func completedBook(movingFrom previous: ReaderWholeBookPageID, to next: ReaderWholeBookPageID) -> ReaderContinuousChapterSection? {
        guard previous.bookID != next.bookID,
              let previousEnd = sections.lastIndex(where: { $0.book.id == previous.bookID }),
              let nextStart = sections.firstIndex(where: { $0.book.id == next.bookID }),
              previousEnd < nextStart else { return nil }
        return sections[previousEnd]
    }

    func appendNext() async {
        guard !isLoading, canAppend, let last = sections.last else { return }
        let token = generation
        let nextEntry = isAtBookBoundary ? nextBookEntry : nil
        isLoading = true
        errorMessage = nil
        defer {
            if generation == token { isLoading = false }
        }
        do {
            let book: ReaderContinuousBook
            let chapterIndex: Int
            if let nextEntry, let loadBook {
                book = try await loadBook(nextEntry)
                chapterIndex = 0
            } else {
                book = last.book
                chapterIndex = last.chapterIndex + 1
            }
            guard !Task.isCancelled, generation == token else { return }
            guard book.detail.chapters.indices.contains(chapterIndex) else {
                throw ReaderContinuousLoadError.noChapters
            }
            let images = try await book.loadImages(chapterIndex)
            guard !Task.isCancelled, generation == token else { return }
            guard !images.isEmpty else { throw ReaderContinuousLoadError.emptyChapter }
            sections.append(.init(book: book, chapterIndex: chapterIndex, images: images))
        } catch {
            guard !Task.isCancelled, generation == token else { return }
            let destination = nextEntry == nil ? "下一章" : "下一本"
            errorMessage = "\(destination)加载失败：\(error.localizedDescription)"
        }
    }

    func cancelLoading() {
        generation = UUID()
        isLoading = false
        errorMessage = nil
    }
}

private enum ReaderContinuousLoadError: LocalizedError {
    case noChapters
    case emptyChapter

    var errorDescription: String? {
        switch self {
        case .noChapters: "当前漫画没有可阅读章节。"
        case .emptyChapter: "章节没有返回可阅读图片。"
        }
    }
}
