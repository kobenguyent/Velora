import AppKit
import ImageIO
import SwiftUI

/// Bounded in-memory LRU cache (`250` items, `64 MB` pixel budget) for downsampled thumbnails.
final class ThumbnailMemoryCache: @unchecked Sendable {
    static let shared = ThumbnailMemoryCache()

    private let cache: NSCache<NSURL, NSImage>

    init(countLimit: Int = 250, totalCostLimit: Int = 64 * 1024 * 1024) {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
        self.cache = cache
    }

    func image(for url: URL, maxPixelSize: Int) -> NSImage? {
        cache.object(forKey: cacheKey(for: url, maxPixelSize: maxPixelSize))
    }

    func insert(_ image: NSImage, for url: URL, maxPixelSize: Int, cost: Int) {
        cache.setObject(image, forKey: cacheKey(for: url, maxPixelSize: maxPixelSize), cost: max(1, cost))
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    private func cacheKey(for url: URL, maxPixelSize: Int) -> NSURL {
        let keyString = "\(url.absoluteString)#velora_px=\(maxPixelSize)"
        return (URL(string: keyString) ?? url) as NSURL
    }
}

/// Async ImageIO-downsampled thumbnail view with smooth placeholder and error fallback (`CLS = 0`).
struct CachedThumbnailView: View {
    let urlString: String?
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = 10
    var maxPixelSize: Int = 240
    var fallbackSymbol: String = "play.rectangle"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: LoadPhase = .idle

    private enum LoadPhase {
        case idle
        case loading
        case loaded(NSImage)
        case failed
    }

    private struct RequestKey: Equatable {
        let urlString: String?
        let maxPixelSize: Int
    }

    private static let maxRemoteBytes = 15 * 1024 * 1024

    var body: some View {
        ZStack {
            switch phase {
            case .loaded(let image):
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
                    .transition(reduceMotion ? .identity : .opacity)
                    .accessibilityHidden(true)

            case .loading, .idle:
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(VeloraTheme.surfaceSubtle)
                    .overlay {
                        Image(systemName: fallbackSymbol)
                            .font(.system(size: min(width, height) * 0.28, weight: .regular))
                            .foregroundStyle(VeloraTheme.inkSecondary.opacity(0.45))
                    }
                    .accessibilityHidden(true)

            case .failed:
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(VeloraTheme.surfaceSubtle)
                    .overlay {
                        Image(systemName: fallbackSymbol)
                            .font(.system(size: min(width, height) * 0.28, weight: .regular))
                            .foregroundStyle(VeloraTheme.inkSecondary.opacity(0.75))
                    }
                    .accessibilityHidden(true)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(VeloraTheme.hairline, lineWidth: 1)
        )
        .accessibilityHidden(true)
        .task(id: RequestKey(urlString: urlString, maxPixelSize: maxPixelSize)) {
            await loadThumbnail()
        }
    }

    @MainActor
    private func loadThumbnail() async {
        guard let url = validatedHTTPURL(from: urlString) else {
            phase = .failed
            return
        }

        let targetPixels = max(32, maxPixelSize)
        if let cached = ThumbnailMemoryCache.shared.image(for: url, maxPixelSize: targetPixels) {
            phase = .loaded(cached)
            return
        }

        phase = .loading

        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        request.setValue("image/*", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else { return }

            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                phase = .failed
                return
            }

            guard !data.isEmpty, data.count <= Self.maxRemoteBytes else {
                phase = .failed
                return
            }

            let cgImage: CGImage? = await Task.detached(priority: .utility) {
                Self.downsample(data: data, maxPixelSize: targetPixels)
            }.value

            guard !Task.isCancelled else { return }
            guard let cgImage else {
                phase = .failed
                return
            }

            let image = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
            let cost = cgImage.bytesPerRow * cgImage.height
            ThumbnailMemoryCache.shared.insert(image, for: url, maxPixelSize: targetPixels, cost: cost)

            if reduceMotion {
                phase = .loaded(image)
            } else {
                withAnimation(.easeOut(duration: 0.16)) {
                    phase = .loaded(image)
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed
        }
    }

    private func validatedHTTPURL(from raw: String?) -> URL? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }

    private nonisolated static func downsample(data: Data, maxPixelSize: Int) -> CGImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
    }
}
