//
//  PlaylistRecord.swift
//  nas-music
//

import Foundation

struct PlaylistRecord {
    let id: String
    let nasId: String
    let sourceId: String
    let name: String
    let normalizedName: String?
    let songCount: Int
    let coverId: String?
    let createdAt: Date
    let updatedAt: Date
    let lastSeenAt: Date
    let isDeleted: Bool

    func toDomain() -> Playlist {
        Playlist(id: sourceId, name: name, songCount: songCount)
    }
}

extension Playlist {
    func toRecord(nasId: String, syncTime: Date) -> PlaylistRecord {
        PlaylistRecord(
            id: "\(nasId):\(id)",
            nasId: nasId,
            sourceId: id,
            name: name,
            normalizedName: SearchTextNormalizer.normalize(name),
            songCount: songCount,
            coverId: nil,
            createdAt: syncTime,
            updatedAt: syncTime,
            lastSeenAt: syncTime,
            isDeleted: false
        )
    }
}
