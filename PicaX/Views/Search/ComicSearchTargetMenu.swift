import SwiftUI

struct ComicSearchTargetMenu: View, Equatable {
    let selectedTarget: ComicSearchTarget
    let aggregatePlatforms: Set<ComicPlatform>
    let onSelectTarget: (ComicSearchTarget) -> Void
    let onToggleAggregatePlatform: (ComicPlatform) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.selectedTarget == rhs.selectedTarget
            && lhs.aggregatePlatforms == rhs.aggregatePlatforms
    }

    var body: some View {
        Menu {
            Section("聚合搜索") {
                Button {
                    onSelectTarget(aggregateSearchTarget)
                } label: {
                    if selectedTarget.isAggregate {
                        Label(aggregateSearchTarget.title, systemImage: "checkmark")
                    } else {
                        Label(aggregateSearchTarget.title, systemImage: aggregateSearchTarget.systemImage)
                    }
                }

                ForEach(ComicPlatform.onlinePlatforms) { platform in
                    Button {
                        onToggleAggregatePlatform(platform)
                    } label: {
                        Label(
                            platform.title,
                            systemImage: aggregatePlatforms.contains(platform) ? "checkmark.circle.fill" : "circle"
                        )
                    }
                }
            }

            Divider()

            Section("单平台") {
                ForEach(ComicPlatform.onlinePlatforms) { platform in
                    let target = ComicSearchTarget.platform(platform)
                    Button {
                        onSelectTarget(target)
                    } label: {
                        if selectedTarget == target {
                            Label(platform.title, systemImage: "checkmark")
                        } else {
                            Label(platform.title, systemImage: platform.systemImage)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Label(selectedTarget.title, systemImage: selectedTarget.systemImage)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("搜索平台")
        .accessibilityValue(selectedTarget.title)
    }

    private var aggregateSearchTarget: ComicSearchTarget {
        .aggregate(ComicPlatform.onlinePlatforms.filter { aggregatePlatforms.contains($0) })
    }
}
