//
//  DownloadItem.swift
//  nas-music
//

import Foundation

enum DownloadStatus: Equatable {
    case queued
    case downloading
    case paused
    case completed
    case failed
}

struct DownloadItem: Identifiable, Hashable {
    let id: String
    let song: Song
    var status: DownloadStatus
    var progress: Double

    static func == (lhs: DownloadItem, rhs: DownloadItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
