//
//  ArtworkDiskCache.swift
//  nas-music
//
//  封面磁盘缓存：文件名只用 hash key（SHA256），不包含 NAS 地址/用户名/sid/synotoken。
//  写成 actor 让所有文件 IO 天然跑在后台 executor 上，调用方不需要自己再切线程。
//  超出 500MB 配额后按文件最后访问时间（mtime）做 LRU 清理。
//

import Foundation

actor ArtworkDiskCache {
    private let directory: URL
    private let maxBytes: Int64

    init(maxBytes: Int64 = 500 * 1024 * 1024) {
        self.maxBytes = maxBytes
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("NASMusic/ArtworkCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func data(forKey key: String) -> Data? {
        let url = fileURL(forKey: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        touch(url)
        return data
    }

    func store(_ data: Data, forKey key: String) throws {
        let url = fileURL(forKey: key)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ArtworkError.diskWriteFailed
        }
        enforceQuotaIfNeeded()
    }

    func removeAll() throws {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func currentStats() -> (totalBytes: Int64, fileCount: Int) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return (0, 0) }
        var totalBytes: Int64 = 0
        for url in contents {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            totalBytes += Int64(size)
        }
        return (totalBytes, contents.count)
    }

    private func fileURL(forKey key: String) -> URL {
        directory.appendingPathComponent(key)
    }

    private func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private func enforceQuotaIfNeeded() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        var entries = contents.map { url -> (url: URL, size: Int64, modifiedAt: Date) in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return (url, Int64(values?.fileSize ?? 0), values?.contentModificationDate ?? .distantPast)
        }

        var totalBytes = entries.reduce(0) { $0 + $1.size }
        guard totalBytes > maxBytes else { return }

        entries.sort { $0.modifiedAt < $1.modifiedAt }
        for entry in entries {
            guard totalBytes > maxBytes else { break }
            try? FileManager.default.removeItem(at: entry.url)
            totalBytes -= entry.size
        }
    }
}
