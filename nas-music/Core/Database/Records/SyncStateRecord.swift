//
//  SyncStateRecord.swift
//  nas-music
//

import Foundation

struct SyncStateRecord {
    let nasId: String
    let status: String
    let lastFullSyncAt: Date?
    let lastSuccessfulSyncAt: Date?
    let lastFailedSyncAt: Date?
    let lastErrorMessage: String?
    let syncedSongCount: Int
    let totalSongCount: Int?
    let albumCount: Int
    let artistCount: Int
    let playlistCount: Int
    let currentOffset: Int
}
