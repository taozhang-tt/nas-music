//
//  SongRecord.swift
//  nas-music
//

import Foundation

struct SongRecord {
    let id: String
    let nasId: String
    let sourceId: String
    let title: String
    let normalizedTitle: String?
    let artist: String?
    let normalizedArtist: String?
    let album: String?
    let normalizedAlbum: String?
    let albumArtist: String?
    let duration: TimeInterval?
    let trackNumber: Int?
    let discNumber: Int?
    let year: Int?
    let genre: String?
    let fileExtension: String?
    let bitrate: Int?
    let sampleRate: Int?
    let fileSize: Int64?
    let coverId: String?
    let path: String?
    let createdAt: Date
    let updatedAt: Date
    let lastSeenAt: Date
    let isDeleted: Bool
    let remoteRevision: String?
    let metadataWriteStatus: MetadataWriteStatus
    let metadataLastWrittenAt: Date?
    let metadataIndexStatus: String?
}

extension SongRecord {
    func toDomain() -> Song {
        Song(
            id: sourceId,
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            duration: duration,
            trackNumber: trackNumber,
            discNumber: discNumber,
            year: year,
            genre: genre,
            fileExtension: fileExtension,
            bitrate: bitrate,
            sampleRate: sampleRate,
            fileSize: fileSize,
            coverId: coverId,
            path: path,
            source: .synology(audioStationId: sourceId)
        )
    }
}

extension Song {
    func toRecord(nasId: String, syncTime: Date) -> SongRecord {
        let sourceId: String
        switch source {
        case .synology(let audioStationId):
            sourceId = audioStationId
        case .mock, .local:
            sourceId = id
        }
        return SongRecord(
            id: "\(nasId):\(sourceId)",
            nasId: nasId,
            sourceId: sourceId,
            title: title,
            normalizedTitle: SearchTextNormalizer.normalize(title),
            artist: artist,
            normalizedArtist: artist.map(SearchTextNormalizer.normalize),
            album: album,
            normalizedAlbum: album.map(SearchTextNormalizer.normalize),
            albumArtist: albumArtist,
            duration: duration,
            trackNumber: trackNumber,
            discNumber: discNumber,
            year: year,
            genre: genre,
            fileExtension: fileExtension,
            bitrate: bitrate,
            sampleRate: sampleRate,
            fileSize: fileSize,
            coverId: coverId,
            path: path,
            createdAt: syncTime,
            updatedAt: syncTime,
            lastSeenAt: syncTime,
            isDeleted: false,
            remoteRevision: nil,
            metadataWriteStatus: .idle,
            metadataLastWrittenAt: nil,
            metadataIndexStatus: nil
        )
    }
}
