//
//  DownloadsViewModel.swift
//  nas-music
//

import Foundation
import Combine

@MainActor
final class DownloadsViewModel: ObservableObject {
    private let downloadManager: DownloadManager
    private var cancellable: AnyCancellable?

    init(downloadManager: DownloadManager) {
        self.downloadManager = downloadManager
        cancellable = downloadManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var items: [DownloadItem] { downloadManager.items }

    func pause(_ item: DownloadItem) { downloadManager.pause(item) }
    func resume(_ item: DownloadItem) { downloadManager.resume(item) }
    func retry(_ item: DownloadItem) { downloadManager.retry(item) }
    func remove(_ item: DownloadItem) { downloadManager.remove(item) }
}
