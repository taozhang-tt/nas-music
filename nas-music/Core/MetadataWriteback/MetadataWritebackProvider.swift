//
//  MetadataWritebackProvider.swift
//  nas-music
//

import Foundation

protocol MetadataWritebackProvider {
    func health() async throws -> MetadataAgentHealth
    func libraryIndexStatus() async throws -> MetadataLibraryIndexStatus
    func updateLibraryIndex(songs: [MetadataLibraryIndexSong]) async throws -> MetadataLibraryIndexUpdateResult
    func readRemoteMetadata(for song: Song) async throws -> RemoteAudioMetadataEnvelope
    func previewUpdate(song: Song, patch: AudioMetadataPatch) async throws -> MetadataUpdatePreview
    func previewUpdate(song: Song, patch: AudioMetadataPatch, convertToSimplified: Bool, fields: [String]) async throws -> MetadataUpdatePreview
    func writeMetadata(song: Song, patch: AudioMetadataPatch, expectedRevision: String) async throws -> MetadataWriteResult
    func rollback(operationId: String) async throws
}

extension MetadataWritebackProvider {
    func previewUpdate(song: Song, patch: AudioMetadataPatch) async throws -> MetadataUpdatePreview {
        try await previewUpdate(song: song, patch: patch, convertToSimplified: false, fields: [])
    }
}
