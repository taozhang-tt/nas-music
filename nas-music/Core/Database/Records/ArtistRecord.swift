//
//  ArtistRecord.swift
//  nas-music
//

import Foundation

struct ArtistRecord {
    let id: String
    let nasId: String
    let normalizedName: String
    let name: String
    let songCount: Int
    let albumCount: Int
    let createdAt: Date
    let updatedAt: Date
    let lastSeenAt: Date
    let isDeleted: Bool

    func toDomain() -> Artist {
        Artist(id: normalizedName, name: name, songCount: songCount)
    }
}
