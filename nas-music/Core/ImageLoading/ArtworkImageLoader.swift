//
//  ArtworkImageLoader.swift
//  nas-music
//
//  封面加载的统一入口：内存/磁盘缓存命中直接返回；未命中时去网络拿数据，downsample 后
//  写回缓存。同一个 nasId+coverId+size 同时被多处请求时，只发一次真正的网络请求——
//  后来的调用者复用同一个 in-flight Task，常见于列表快速滚动时同一封面被多行同时请求。
//  provider 随 NAS 连接状态切换（见 MusicLibraryProviderStore），调用方不需要关心当前是
//  Mock 还是 Synology。
//

import Combine
import ImageIO
import UIKit

@MainActor
final class ArtworkImageLoader {
    static let shared = ArtworkImageLoader()

    private let cacheManager: ArtworkCacheManager
    private var provider: ArtworkProvider
    private var nasIdentifier: String
    private var inFlightTasks: [String: Task<UIImage, Error>] = [:]

    init(
        cacheManager: ArtworkCacheManager = .shared,
        provider: ArtworkProvider = MockArtworkProvider(),
        nasIdentifier: String = "mock"
    ) {
        self.cacheManager = cacheManager
        self.provider = provider
        self.nasIdentifier = nasIdentifier
    }

    /// NAS 连接状态变化时，切换封面该用哪个 Provider/缓存命名空间。
    func updateProvider(_ provider: ArtworkProvider, nasIdentifier: String) {
        self.provider = provider
        self.nasIdentifier = nasIdentifier
    }

    func loadImage(coverId: String?, size: ArtworkSize) async throws -> UIImage {
        guard let coverId, !coverId.isEmpty else { throw ArtworkError.missingCoverId }

        let key = ArtworkCacheManager.cacheKey(nasId: nasIdentifier, coverId: coverId, size: size)

        if let cached = await cacheManager.image(nasId: nasIdentifier, coverId: coverId, size: size) {
            return cached
        }

        if let existing = inFlightTasks[key] {
            return try await existing.value
        }

        let provider = self.provider
        let nasIdentifier = self.nasIdentifier
        let cacheManager = self.cacheManager
        let maxPixelSize = size.maxPixelSize
        let task = Task<UIImage, Error> {
            let data = try await provider.fetchArtworkData(coverId: coverId, size: size)
            let downsampled = try await Task.detached(priority: .utility) {
                try Self.downsample(data: data, maxPixelSize: maxPixelSize)
            }.value
            if let jpegData = downsampled.jpegData(compressionQuality: 0.85) {
                await cacheManager.store(downsampled, data: jpegData, nasId: nasIdentifier, coverId: coverId, size: size)
            }
            return downsampled
        }
        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        return try await task.value
    }

    /// 用 ImageIO 直接从原始 Data 生成缩略图，避免先把整张原图解码进内存再缩放。
    private nonisolated static func downsample(data: Data, maxPixelSize: CGFloat) throws -> UIImage {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            throw ArtworkError.invalidImageData
        }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions as CFDictionary) else {
            throw ArtworkError.invalidImageData
        }
        return UIImage(cgImage: cgImage)
    }
}

/// ArtworkView 背后的加载状态：每次 load() 用 coverId+size 生成请求标识，异步结果回来时
/// 校验标识仍然匹配才落地，避免旧歌曲/旧封面的请求晚到后覆盖新内容（比如快速切歌或者
/// 列表行被复用到不同歌曲上）。
@MainActor
final class ArtworkImageViewModel: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?
    private var currentRequestKey: String?

    deinit {
        task?.cancel()
    }

    func load(coverId: String?, size: ArtworkSize) {
        let requestKey = "\(coverId ?? "")|\(size.rawValue)"
        guard requestKey != currentRequestKey || image == nil else { return }
        currentRequestKey = requestKey
        task?.cancel()

        guard let coverId, !coverId.isEmpty else {
            image = nil
            isLoading = false
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil
        task = Task { [weak self] in
            do {
                let result = try await ArtworkImageLoader.shared.loadImage(coverId: coverId, size: size)
                guard !Task.isCancelled, self?.currentRequestKey == requestKey else { return }
                self?.image = result
                self?.isLoading = false
            } catch {
                guard !Task.isCancelled, self?.currentRequestKey == requestKey else { return }
                self?.isLoading = false
                self?.errorMessage = (error as? LocalizedError)?.errorDescription
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
