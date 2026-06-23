//
//  MetadataWritebackModels.swift
//  nas-music
//

import Foundation

struct RemoteAudioMetadata: Codable, Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var genre: String?
    var year: Int?
    var trackNumber: Int?
    var trackTotal: Int?
    var discNumber: Int?
    var discTotal: Int?
    var comment: String?
    var composer: String?
}

struct RemoteAudioMetadataEnvelope: Codable, Equatable {
    let sourceId: String
    let revision: String
    let format: String
    let fileSize: Int64
    let modifiedAt: Date
    let metadata: RemoteAudioMetadata
    let writeSupported: Bool?
}

struct AudioMetadataPatch: Codable, Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var genre: String?
    var year: Int?
    var trackNumber: Int?
    var trackTotal: Int?
    var discNumber: Int?
    var discTotal: Int?
    var comment: String?
    var composer: String?

    var isEmpty: Bool {
        title == nil && artist == nil && album == nil && albumArtist == nil && genre == nil &&
        year == nil && trackNumber == nil && trackTotal == nil && discNumber == nil &&
        discTotal == nil && comment == nil && composer == nil
    }
}

struct MetadataUpdatePreview: Codable, Equatable {
    let before: RemoteAudioMetadata
    let after: RemoteAudioMetadata
    let warnings: [String]

    private enum CodingKeys: String, CodingKey {
        case before
        case after
        case warnings
    }

    init(before: RemoteAudioMetadata, after: RemoteAudioMetadata, warnings: [String]) {
        self.before = before
        self.after = after
        self.warnings = warnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        before = try container.decode(RemoteAudioMetadata.self, forKey: .before)
        after = try container.decode(RemoteAudioMetadata.self, forKey: .after)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}

struct MetadataWriteResult: Codable, Equatable {
    let operationId: String
    let newRevision: String
    let backupCreated: Bool
    let indexStatus: String
    let metadata: RemoteAudioMetadata
}

struct MetadataAgentHealth: Codable, Equatable {
    let status: String
    let version: String
    let tagWriterAvailable: Bool
    let openCCAvailable: Bool
    let musicDirectoryWritable: Bool?
    let backupDirectoryWritable: Bool?
}

struct MetadataLibraryIndexSong: Codable, Equatable {
    let sourceId: String
    let path: String
    let title: String?
    let artist: String?
    let album: String?
}

struct MetadataLibraryIndexUpdateResult: Codable, Equatable {
    let acceptedCount: Int
    let rejectedCount: Int
    let rejected: [MetadataLibraryIndexRejectedSong]?
    let songCount: Int
}

struct MetadataLibraryIndexRejectedSong: Codable, Equatable {
    let sourceId: String
    let reason: String
}

struct MetadataLibraryIndexStatus: Codable, Equatable {
    let songCount: Int
    let updatedAt: Date?
}

enum MetadataWriteStatus: String, Codable, Equatable {
    case idle
    case previewing
    case writing
    case written
    case waitingForIndex
    case indexed
    case conflict
    case failed
}

struct MetadataWriteOperationRecord: Equatable {
    let id: String
    let nasId: String
    let songId: String
    let sourceId: String
    let status: MetadataWriteStatus
    let oldRevision: String?
    let newRevision: String?
    let beforeMetadataJSON: String?
    let afterMetadataJSON: String?
    let backupAvailable: Bool
    let errorMessage: String?
    let createdAt: Date
    let completedAt: Date?
}
