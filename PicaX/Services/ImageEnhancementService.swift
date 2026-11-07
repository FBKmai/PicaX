import CoreGraphics
import CoreImage
import Foundation

enum ImageEnhancementMode: String, CaseIterable, Identifiable, Sendable {
    case off
    case sharpen
    case upscaleSharpen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            "关闭"
        case .sharpen:
            "锐化"
        case .upscaleSharpen:
            "放大 + 锐化"
        }
    }
}

struct ReaderImageEnhancement: Equatable, Sendable {
    let mode: ImageEnhancementMode
    /// 0...1，0 表示不锐化。
    let strength: Double

    static let off = ReaderImageEnhancement(mode: .off, strength: 0)

    var isEnabled: Bool {
        mode != .off
    }

    var cacheKeyFragment: String {
        "\(mode.rawValue)-\(Int((strength * 100).rounded()))"
    }
}

enum ImageEnhancementService {
    /// 放大倍率上限，避免低分辨率源图被放大到超大内存占用。
    private nonisolated static let maxUpscaleScale: CGFloat = 2

    nonisolated(unsafe) private static let ciContext: CIContext = {
        CIContext(options: [.cacheIntermediates: false])
    }()

    nonisolated static func current(defaults: UserDefaults = .standard) -> ReaderImageEnhancement {
        let mode = ImageEnhancementMode(rawValue: defaults.string(forKey: ReaderSettingsKey.imageEnhancementMode) ?? "") ?? .off
        let storedStrength = defaults.object(forKey: ReaderSettingsKey.imageEnhancementStrength) as? Double ?? 0
        let strength = min(max(storedStrength, 0), 100) / 100
        return ReaderImageEnhancement(mode: mode, strength: strength)
    }

    /// 返回增强后的图片；返回 `nil` 表示无需或无法增强，调用方应继续使用原图。
    nonisolated static func enhancedImage(
        cgImage: CGImage,
        targetPixelWidth: Int?,
        enhancement: ReaderImageEnhancement
    ) -> CGImage? {
        guard enhancement.isEnabled, cgImage.width > 0, cgImage.height > 0 else {
            return nil
        }

        var result = cgImage
        var didChange = false

        if enhancement.mode == .upscaleSharpen,
           let targetPixelWidth,
           targetPixelWidth > cgImage.width,
           let upscaled = upscaledImage(cgImage: cgImage, targetPixelWidth: targetPixelWidth) {
            result = upscaled
            didChange = true
        }

        if enhancement.strength > 0,
           let sharpened = sharpenedImage(cgImage: result, strength: enhancement.strength) {
            result = sharpened
            didChange = true
        }

        return didChange ? result : nil
    }

    private nonisolated static func upscaledImage(cgImage: CGImage, targetPixelWidth: Int) -> CGImage? {
        guard cgImage.width > 0, cgImage.height > 0 else {
            return nil
        }

        let boundedTarget = min(targetPixelWidth, Int((CGFloat(cgImage.width) * maxUpscaleScale).rounded()))
        guard boundedTarget > cgImage.width else {
            return nil
        }

        let scale = CGFloat(boundedTarget) / CGFloat(cgImage.width)
        let targetHeight = max(Int((CGFloat(cgImage.height) * scale).rounded()), 1)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: boundedTarget,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: boundedTarget * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(boundedTarget), height: CGFloat(targetHeight)))
        return context.makeImage()
    }

    private nonisolated static func sharpenedImage(cgImage: CGImage, strength: Double) -> CGImage? {
        guard strength > 0 else {
            return nil
        }

        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CISharpenLuminance") else {
            return nil
        }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(strength * 1.2, forKey: kCIInputSharpnessKey)
        guard let output = filter.outputImage else {
            return nil
        }

        let extent = output.extent
        guard !extent.isEmpty, !extent.isInfinite else {
            return nil
        }
        return ciContext.createCGImage(output, from: extent)
    }
}
