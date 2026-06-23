//
//  NASMetadataEditorViewModel.swift
//  nas-music
//

import Foundation
import Combine

@MainActor
final class NASMetadataEditorViewModel: ObservableObject {
    @Published private(set) var remote: RemoteAudioMetadataEnvelope?
    @Published private(set) var preview: MetadataUpdatePreview?
    @Published private(set) var isLoading = false
    @Published private(set) var isWriting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var successMessage: String?

    @Published var title = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var albumArtist = ""
    @Published var genre = ""
    @Published var year = ""
    @Published var trackNumber = ""
    @Published var discNumber = ""
    @Published var createBackup = true
    @Published var convertToSimplified = true

    private let song: Song
    private let service: MetadataWritebackService
    private let songRepository: SongRepositoryProtocol
    private let sessionManager: NASSessionManager

    init(
        song: Song,
        service: MetadataWritebackService,
        sessionManager: NASSessionManager,
        songRepository: SongRepositoryProtocol = SongRepository()
    ) {
        self.song = song
        self.service = service
        self.sessionManager = sessionManager
        self.songRepository = songRepository
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await service.provider().readRemoteMetadata(for: song)
            remote = loaded
            apply(loaded.metadata)
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func generatePreview() async {
        do {
            preview = try await service.provider().previewUpdate(
                song: song,
                patch: patch(),
                convertToSimplified: convertToSimplified,
                fields: simplifiedFields
            )
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func write() async {
        guard let remote else {
            errorMessage = "请先加载 NAS 原始标签。"
            return
        }
        guard let nasId = sessionManager.config?.id.uuidString,
              let sourceId = song.audioStationId else {
            errorMessage = MetadataWritebackError.invalidSongSource.localizedDescription
            return
        }
        isWriting = true
        defer { isWriting = false }
        do {
            let patch = patch()
            let result = try await service.provider().writeMetadata(song: song, patch: patch, expectedRevision: remote.revision)
            await service.recordWrite(song: song, oldRevision: remote.revision, result: result, before: remote.metadata)
            try await songRepository.updateMetadata(
                nasId: nasId,
                sourceId: sourceId,
                metadata: result.metadata,
                revision: result.newRevision,
                indexStatus: result.indexStatus
            )
            successMessage = result.indexStatus == "indexed" ? "标签已写入 NAS 文件。" : "文件已修改，等待群晖更新音乐索引。"
            errorMessage = nil
        } catch MetadataWritebackError.fileChanged {
            errorMessage = MetadataWritebackError.fileChanged.localizedDescription
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func apply(_ metadata: RemoteAudioMetadata) {
        title = metadata.title ?? song.title
        artist = metadata.artist ?? song.artist ?? ""
        album = metadata.album ?? song.album ?? ""
        albumArtist = metadata.albumArtist ?? song.albumArtist ?? ""
        genre = metadata.genre ?? song.genre ?? ""
        year = metadata.year.map(String.init) ?? ""
        trackNumber = metadata.trackNumber.map(String.init) ?? ""
        discNumber = metadata.discNumber.map(String.init) ?? ""
    }

    private func patch() -> AudioMetadataPatch {
        AudioMetadataPatch(
            title: emptyToNil(title),
            artist: emptyToNil(artist),
            album: emptyToNil(album),
            albumArtist: emptyToNil(albumArtist),
            genre: emptyToNil(genre),
            year: Int(year),
            trackNumber: Int(trackNumber),
            discNumber: Int(discNumber)
        )
    }

    private func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var simplifiedFields: [String] {
        ["title", "artist", "album", "albumArtist", "genre", "composer"]
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "标签写回失败，请稍后重试。"
    }
}
