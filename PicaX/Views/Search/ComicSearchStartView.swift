import SwiftUI

struct ComicSearchStartView: View {
    @AppStorage(SearchHistorySettingsKey.isEnabled) private var savesSearchHistory = true
    let records: [SearchHistoryRecord]
    let onSelect: (SearchHistoryRecord) -> Void
    let onDelete: (SearchHistoryRecord) -> Void
    let onShowSavedSearches: () -> Void

    var body: some View {
        List {
            Section {
                Button(action: onShowSavedSearches) {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("常用搜索")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("快速使用保存的关键词与筛选条件")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "star")
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                NavigationLink {
                    SearchSettingsView()
                } label: {
                    Label("搜索设置", systemImage: "gearshape")
                }
            } footer: {
                Text("输入漫画、作者或标签，也可以切换平台缩小搜索范围。")
            }

            Section {
                if savesSearchHistory, !records.isEmpty {
                    ForEach(records) { record in
                        Button {
                            onSelect(record)
                        } label: {
                            historyRow(record)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                onDelete(record)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } else {
                    Label {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(savesSearchHistory ? "还没有搜索记录" : "搜索历史已关闭")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(savesSearchHistory
                                 ? "搜索过的关键词会显示在这里，方便下次继续。"
                                 : "可在搜索设置中开启，保存关键词与浏览进度。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                }
            } header: {
                Text("最近搜索")
            } footer: {
                if savesSearchHistory, !records.isEmpty {
                    Text("轻点记录重新搜索或从断点继续，向左轻扫可删除。")
                }
            }
        }
        .picaxInsetGroupedListStyle()
    }

    private func historyRow(_ record: SearchHistoryRecord) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 6) {
                Text(record.keyword)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text("\(record.target.title) · \(record.searchedAtText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if record.resumableBreakpoint != nil {
                    Label("可从上次进度继续", systemImage: "arrow.forward.circle")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
        } icon: {
            Image(systemName: record.target.systemImage)
                .foregroundStyle(record.target.searchTarget.accentColor)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview("搜索首页") {
    PicaxNavigationContainer {
        ComicSearchStartView(
            records: [
                SearchHistoryRecord(keyword: "画集", target: .platform(.picacg), searchedAt: Date()),
                SearchHistoryRecord(
                    keyword: "冒险", target: .aggregate([.picacg, .jmComic]),
                    breakpoint: ComicSearchBreakpoint(requests: [
                        .init(keyword: "冒险", platform: .picacg, nextPage: 2)
                    ]),
                    searchedAt: Date().addingTimeInterval(-3600)
                )
            ],
            onSelect: { _ in }, onDelete: { _ in }, onShowSavedSearches: {}
        )
        .navigationTitle("搜索")
    }
}
