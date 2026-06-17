//
//  DownloadManager.swift
//  nas-music
//
//  模拟离线下载任务的进度推进，没有接入真实文件传输。
//

import Foundation
import Combine

@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var items: [DownloadItem]

    private var timerCancellable: AnyCancellable?

    init(items: [DownloadItem]) {
        self.items = items
        startTimerIfNeeded()
    }

    func pause(_ item: DownloadItem) {
        setStatus(itemId: item.id, to: .paused)
    }

    func resume(_ item: DownloadItem) {
        setStatus(itemId: item.id, to: .downloading)
        startTimerIfNeeded()
    }

    func retry(_ item: DownloadItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].status = .downloading
        items[index].progress = 0
        startTimerIfNeeded()
    }

    func remove(_ item: DownloadItem) {
        items.removeAll { $0.id == item.id }
    }

    private func setStatus(itemId: String, to status: DownloadStatus) {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[index].status = status
    }

    private func startTimerIfNeeded() {
        guard timerCancellable == nil else { return }
        timerCancellable = Timer.publish(every: 0.6, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        var anyStillDownloading = false
        for index in items.indices where items[index].status == .downloading {
            anyStillDownloading = true
            items[index].progress = min(1, items[index].progress + 0.05)
            if items[index].progress >= 1 {
                items[index].status = .completed
            }
        }
        if !anyStillDownloading {
            timerCancellable?.cancel()
            timerCancellable = nil
        }
    }
}
