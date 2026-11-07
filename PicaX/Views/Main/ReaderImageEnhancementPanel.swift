import SwiftUI

struct ReaderImageCompareRequest: Identifiable {
    let id = UUID()
    let urlString: String
    let enhancement: ReaderImageEnhancement
}

/// 阅读器内实时调节画质增强的浮层面板。
struct ReaderImageEnhancementPanel: View {
    let targetPixelWidth: Int?
    let canCompare: Bool
    let onCompare: () -> Void
    let onClose: () -> Void

    @AppStorage(ReaderSettingsKey.imageEnhancementMode) private var enhancementMode = ImageEnhancementMode.off.rawValue
    @AppStorage(ReaderSettingsKey.imageEnhancementStrength) private var enhancementStrength = 0.0
    @AppStorage(ReaderSettingsKey.imageEnhancementScale) private var enhancementScale = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("画质增强", systemImage: "wand.and.stars")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .accessibilityLabel("关闭画质增强面板")
            }

            HStack {
                Text("算法")
                Spacer()
                Picker("算法", selection: $enhancementMode) {
                    ForEach(ImageEnhancementMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(.white)
            }

            if selectedMode != .off {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("强度")
                        Spacer()
                        Text("\(Int(enhancementStrength))%")
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Slider(value: $enhancementStrength, in: 0...100, step: 5)
                }

                if selectedMode.usesUpscale {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("目标分辨率")
                            Spacer()
                            Text(outputWidthLabel)
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Picker("目标分辨率", selection: $enhancementScale) {
                            ForEach(ReaderImageEnhancement.scalePresets, id: \.self) { preset in
                                Text(ReaderImageEnhancement.scaleLabel(for: preset))
                                    .tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Button(action: onCompare) {
                    Label("对比原图", systemImage: "rectangle.split.2x1")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCompare)
            } else {
                Text("开启后会把低分辨率漫画图放大到目标分辨率并锐化，切换后当前页立即重新解码。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .foregroundStyle(.white)
        .onChange(of: enhancementMode) { newValue in
            guard newValue != ImageEnhancementMode.off.rawValue,
                  enhancementStrength <= 0 else {
                return
            }
            enhancementStrength = 60
        }
    }

    private var selectedMode: ImageEnhancementMode {
        ImageEnhancementMode(rawValue: enhancementMode) ?? .off
    }

    private var outputWidthLabel: String {
        guard let targetPixelWidth, targetPixelWidth > 0 else {
            return "屏幕物理像素宽 × \(selectedScaleLabel)"
        }
        let width = Int((Double(targetPixelWidth) * enhancementScale).rounded())
        return "约 \(width) px 宽 × \(selectedScaleLabel)"
    }

    private var selectedScaleLabel: String {
        ReaderImageEnhancement.scaleLabel(for: enhancementScale)
    }
}

/// 全屏前后对比：左半部分为原图，右半部分为增强效果，拖动分割线查看差异。
struct ReaderImageCompareView: View {
    let request: ReaderImageCompareRequest
    let targetPixelWidth: Int?
    let onClose: () -> Void

    @State private var originalImage: PicaXPlatformImage?
    @State private var enhancedImage: PicaXPlatformImage?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var splitRatio: CGFloat = 0.5

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Color.black.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if let originalImage, let enhancedImage {
                    compareContent(original: originalImage, enhanced: enhancedImage, size: size)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let width = max(size.width, 1)
                                    splitRatio = min(max(value.location.x / width, 0.03), 0.97)
                                }
                        )
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                        Text(errorMessage ?? "图片加载失败")
                            .font(.footnote)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                }
            }
            .overlay(alignment: .top) {
                header
            }
            .overlay(alignment: .bottom) {
                Text("拖动分割线对比增强前后")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.bottom, 20)
                    .opacity(isLoading ? 0 : 1)
            }
        }
        .task {
            await loadImages()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("原图")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.55), in: Capsule())

            Spacer()

            Text(enhancementSummary)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.55), in: Capsule())

            Text("增强效果")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.55), in: Capsule())

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .accessibilityLabel("关闭对比")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .foregroundStyle(.white)
    }

    private func compareContent(
        original: PicaXPlatformImage,
        enhanced: PicaXPlatformImage,
        size: CGSize
    ) -> some View {
        ZStack {
            Image(picaxImage: enhanced)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)

            Image(picaxImage: original)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: max(size.width * splitRatio, 0))
                }

            Rectangle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 1.5)
                .frame(maxHeight: .infinity)
                .position(x: size.width * splitRatio, y: size.height / 2)
                .allowsHitTesting(false)

            Circle()
                .fill(Color.white)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                }
                .shadow(color: .black.opacity(0.4), radius: 4)
                .position(x: size.width * splitRatio, y: size.height / 2)
                .allowsHitTesting(false)
        }
    }

    private var enhancementSummary: String {
        "\(request.enhancement.mode.title) · 强度 \(Int((request.enhancement.strength * 100).rounded()))% · \(request.enhancement.scaleLabel)"
    }

    @MainActor
    private func loadImages() async {
        guard let imageURL = URL.picaxResolved(from: request.urlString) else {
            errorMessage = "无法解析图片地址"
            isLoading = false
            return
        }

        let pixelWidth = targetPixelWidth
        let enhancement = request.enhancement
        isLoading = true
        do {
            async let original = ReaderImageDecoder.image(
                url: imageURL,
                targetPixelWidth: pixelWidth,
                enhancement: ReaderImageEnhancement.off
            )
            async let enhanced = ReaderImageDecoder.image(
                url: imageURL,
                targetPixelWidth: pixelWidth,
                enhancement: enhancement
            )
            let (originalImage, enhancedImage) = try await (original, enhanced)
            guard !Task.isCancelled else { return }
            self.originalImage = originalImage.image
            self.enhancedImage = enhancedImage.image
            self.isLoading = false
        } catch where error.isTaskCancellation {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "图片加载失败：\(error.localizedDescription)"
            isLoading = false
        }
    }
}

extension View {
    /// iPhone/iPad 用全屏覆盖展示对比页，macOS 用 sheet。
    @ViewBuilder
    func readerImageComparePresentation(
        request: Binding<ReaderImageCompareRequest?>,
        targetPixelWidth: @escaping (CGFloat) -> Int?
    ) -> some View {
        #if os(iOS)
        fullScreenCover(item: request) { item in
            GeometryReader { geometry in
                ReaderImageCompareView(
                    request: item,
                    targetPixelWidth: targetPixelWidth(geometry.size.width),
                    onClose: { request.wrappedValue = nil }
                )
            }
            .background(Color.black.ignoresSafeArea())
        }
        #else
        sheet(item: request) { item in
            GeometryReader { geometry in
                ReaderImageCompareView(
                    request: item,
                    targetPixelWidth: targetPixelWidth(geometry.size.width),
                    onClose: { request.wrappedValue = nil }
                )
            }
            .frame(minWidth: 560, minHeight: 640)
        }
        #endif
    }
}
