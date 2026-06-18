//
//  ArtworkCacheManager.swift
//  nas-music
//
//  封面缓存的统一入口：先查内存，再查磁盘，命中磁盘后回填内存。写入时同时落盘和落内存。
//  key 用 SHA256(nasId + coverId + size) 生成，保证缓存文件名和内存 key 都不包含 NAS 地址/
//  用户名/sid/synotoken 等敏感信息。
//

import UIKit
import CryptoKit

@MainActor
final class ArtworkCacheManager {
    static let shared = ArtworkCacheManager()

    private let memoryCache: ArtworkMemoryCache
    private let diskCache: ArtworkDiskCache

    init(memoryCache: ArtworkMemoryCache = ArtworkMemoryCache(), diskCache: ArtworkDiskCache = ArtworkDiskCache()) {
        self.memoryCache = memoryCache
        self.diskCache = diskCache
    }

    func image(nasId: String, coverId: String, size: ArtworkSize) async -> UIImage? {
        let key = Self.cacheKey(nasId: nasId, coverId: coverId, size: size)
        if let cached = memoryCache.image(forKey: key) { return cached }

        guard let diskData = await diskCache.data(forKey: key), let image = UIImage(data: diskData) else {
            return nil
        }
        memoryCache.setImage(image, forKey: key)
        return image
    }

    func store(_ image: UIImage, data: Data, nasId: String, coverId: String, size: ArtworkSize) async {
        let key = Self.cacheKey(nasId: nasId, coverId: coverId, size: size)
        memoryCache.setImage(image, forKey: key)
        try? await diskCache.store(data, forKey: key)
    }

    func clearArtworkCache() async throws {
        try await diskCache.removeAll()
        memoryCache.removeAll()
    }

    func cacheStats() async -> (totalBytes: Int64, fileCount: Int) {
        await diskCache.currentStats()
    }

    static func cacheKey(nasId: String, coverId: String, size: ArtworkSize) -> String {
        let raw = "\(nasId)|\(coverId)|\(size.rawValue)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
