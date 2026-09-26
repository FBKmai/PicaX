import Foundation

/// A book keeps its own account and local chapter mapping while other books are visible.
struct ReaderContinuousBook {
    let id: String
    let detail: ComicDetailInfo
    let account: PlatformAccount?
    let localCommentsProvider: ((ComicChapter, Int) async -> [ComicComment])?
    let historyChapterIndex: (Int) -> Int
    let loadImages: (Int) async throws -> [ComicChapterImage]

    static func make(
        id: String,
        detail: ComicDetailInfo,
        service: ComicContentService,
        account: PlatformAccount?,
        localImages: ((ComicChapter, Int) async -> [ComicChapterImage])?,
        localComments: ((ComicChapter, Int) async -> [ComicComment])?,
        historyChapterIndex: @escaping (Int) -> Int
    ) -> Self {
        Self(
            id: id,
            detail: detail,
            account: account,
            localCommentsProvider: localComments,
            historyChapterIndex: historyChapterIndex,
            loadImages: { index in
                let chapter = detail.chapters[index]
                if let localImages {
                    return await localImages(chapter, index)
                }
                return try await service.loadChapterImages(item: detail.item, chapter: chapter, account: account)
            }
        )
    }
}

struct ReaderContinuousChapterSection: Identifiable {
    let book: ReaderContinuousBook
    let chapterIndex: Int
    let images: [ComicChapterImage]

    var chapter: ComicChapter { book.detail.chapters[chapterIndex] }
    var id: String { "\(book.id)-\(chapterIndex)-\(chapter.id)" }

    func pageID(_ pageIndex: Int) -> ReaderWholeBookPageID {
        ReaderWholeBookPageID(bookID: book.id, chapterIndex: chapterIndex, pageIndex: pageIndex)
    }
}
