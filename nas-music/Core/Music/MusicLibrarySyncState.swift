//
//  MusicLibrarySyncState.swift
//  nas-music
//

import Foundation

enum MusicLibrarySyncStatus: Equatable {
    case idle
    case preparing
    case syncing(current: Int, total: Int?, progress: Double?)
    case rebuildingAlbums
    case rebuildingArtists
    case completed(date: Date, songCount: Int, albumCount: Int, artistCount: Int)
    case cancelled
    case failed(message: String)
}

enum MusicLibrarySyncError: LocalizedError {
    case nasNotConfigured
    case nasNotConnected
    case audioStationUnavailable
    case sessionExpired
    case networkUnavailable
    case requestFailed
    case decodingFailed
    case databaseWriteFailed
    case databaseReadFailed
    case localIndexEmpty
    case cancelled
    case unknown

    var errorDescription: String? {
        switch self {
        case .nasNotConfigured:
            return "请先添加 NAS 配置。"
        case .nasNotConnected:
            return "请先连接 NAS 后再同步音乐库。"
        case .audioStationUnavailable:
            return "当前 NAS 无法访问 Audio Station，请确认套件已经安装并启用。"
        case .sessionExpired:
            return "NAS 登录状态已经过期，请重新连接。"
        case .networkUnavailable:
            return "无法连接 NAS，请检查网络和 NAS 状态。"
        case .databaseWriteFailed:
            return "本地音乐库写入失败，请稍后重试或重建索引。"
        case .databaseReadFailed:
            return "本地音乐库读取失败，请稍后重试。"
        case .localIndexEmpty:
            return "尚未同步音乐库，请先同步后再浏览。"
        case .requestFailed:
            return "同步请求失败，请稍后重试。"
        case .decodingFailed:
            return "解析音乐库数据失败，请稍后重试。"
        case .cancelled:
            return "同步已取消。"
        case .unknown:
            return "同步失败，请稍后重试。"
        }
    }
}

struct MusicSearchResult {
    let songs: [Song]
    let albums: [Album]
    let artists: [Artist]

    var isEmpty: Bool {
        songs.isEmpty && albums.isEmpty && artists.isEmpty
    }
}

struct MusicLibraryLocalStats: Equatable {
    let nasName: String?
    let songCount: Int
    let albumCount: Int
    let artistCount: Int
    let playlistCount: Int
    let lastSuccessfulSyncAt: Date?
    let databaseSize: Int64
}
