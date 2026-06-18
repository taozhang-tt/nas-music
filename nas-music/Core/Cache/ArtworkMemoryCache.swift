//
//  ArtworkMemoryCache.swift
//  nas-music
//
//  封面内存缓存：NSCache 本身已经会在系统内存紧张时自动清理，这里额外监听
//  didReceiveMemoryWarningNotification 主动清空一次，覆盖 NSCache 不一定立即响应的情况。
//

import UIKit

final class ArtworkMemoryCache {
    private let cache = NSCache<NSString, UIImage>()
    private var memoryWarningObserver: NSObjectProtocol?

    init(countLimit: Int = 300) {
        cache.countLimit = countLimit
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.removeAll()
        }
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
