//
//  AlbumRecord.swift
//  nas-music
//

import Foundation

struct AlbumRecord {
    let id: String
    let nasId: String
    let sourceKey: String
    let title: String
    let normalizedTitle: String?
    let artist: String?
    let normalizedArtist: String?
    let albumArtist: String?
    let year: Int?
    let songCount: Int
    let totalDuration: TimeInterval?
    let coverId: String?
    let createdAt: Date
    let updatedAt: Date
    let lastSeenAt: Date
    let isDeleted: Bool

    func toDomain() -> Album {
        Album(
            id: sourceKey,
            title: title,
            artistName: artist ?? albumArtist ?? "未知歌手",
            year: year,
            trackCount: songCount,
            coverId: coverId,
            source: .synology(audioStationId: sourceKey)
        )
    }
}

extension Album {
    static func sourceKey(title: String, albumArtist: String?) -> String {
        "\(SearchTextNormalizer.normalize(title))|\(SearchTextNormalizer.normalize(albumArtist ?? ""))"
    }
}
