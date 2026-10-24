import SwiftUI

struct ReaderControlsToolbar: ToolbarContent {
    let isAutoPaging: Bool
    let showsReadingList: Bool
    let canMovePreviousBook: Bool
    let canLoadPreviousChapter: Bool
    let canLoadNextChapter: Bool
    let canMoveNextBook: Bool
    let onToggleAutoPaging: () -> Void
    let onShowChapters: () -> Void
    let onShowReadingList: () -> Void
    let onMovePreviousBook: () -> Void
    let onLoadPreviousChapter: () -> Void
    let onLoadNextChapter: () -> Void
    let onMoveNextBook: () -> Void

    var body: some ToolbarContent {
        readingControls
        #if os(iOS)
        if #available(iOS 27.0, *) {
            chapterControls.visibilityPriority(.high)
        } else {
            chapterControls
        }
        #else
        chapterControls
        #endif
    }

    private var readingControls: some ToolbarContent {
        ToolbarItemGroup(placement: controlsPlacement) {
            Button(action: onToggleAutoPaging) {
                Label(
                    isAutoPaging ? "停止自动翻页" : "自动翻页",
                    systemImage: isAutoPaging ? "timer.circle.fill" : "timer"
                )
            }

            Button(action: onShowChapters) {
                Label("章节", systemImage: "list.bullet")
            }

            if showsReadingList {
                Button(action: onShowReadingList) {
                    Label("阅读列表", systemImage: "list.bullet.rectangle")
                }
            }
        }
    }

    private var chapterControls: some ToolbarContent {
        ToolbarItemGroup(placement: controlsPlacement) {
            if showsReadingList {
                Button(action: onMovePreviousBook) {
                    Label("上一本", systemImage: "backward.end")
                }
                .disabled(!canMovePreviousBook)
            }

            Button(action: onLoadPreviousChapter) {
                Label("上一章", systemImage: "chevron.up")
            }
            .disabled(!canLoadPreviousChapter)

            Button(action: onLoadNextChapter) {
                Label("下一章", systemImage: "chevron.down")
            }
            .disabled(!canLoadNextChapter)

            if showsReadingList {
                Button(action: onMoveNextBook) {
                    Label("下一本", systemImage: "forward.end")
                }
                .disabled(!canMoveNextBook)
            }
        }
    }

    private var controlsPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        .bottomBar
        #endif
    }
}
