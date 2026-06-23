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
    @Published private(set) var informationalMessage: String?

    @Published var title = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var albumArtist = ""
    @Published var genre = ""
    @Published var year = ""
    @Published var trackNumber = ""
    @Published var discNumber = ""
    @Published var convertToSimplified = true

    private let song: Song
    private let service: MetadataWritebackService
    private let songRepository: SongRepositoryProtocol
    private let sessionManager: NASSessionManager

    var canWrite: Bool {
        guard !isWriting,
              let remote,
              remote.writeSupported ?? true,
              song.audioStationId != nil else { return false }
        return hasPendingChanges
    }

    var canGeneratePreview: Bool {
        remote != nil && !isWriting
    }

    var isEditable: Bool {
        guard let remote else { return false }
        return remote.writeSupported ?? true
    }

    var hasPendingChanges: Bool {
        guard let remote else { return false }
        let formChanged = Self.hasChanges(before: remote.metadata, after: currentMetadata)
        let previewChanged = preview.map { Self.hasChanges(before: $0.before, after: $0.after) } ?? false
        return formChanged || previewChanged
    }

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
            preview = nil
            apply(loaded.metadata)
            informationalMessage = (loaded.writeSupported ?? true) ? nil : "当前格式暂不支持安全修改标签。"
            successMessage = nil
            errorMessage = nil
        } catch MetadataWritebackError.unsupportedFormat {
            remote = nil
            preview = nil
            informationalMessage = "当前格式暂不支持安全修改标签。"
            successMessage = nil
            errorMessage = MetadataWritebackError.unsupportedFormat.localizedDescription
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
            informationalMessage = Self.hasChanges(before: preview?.before, after: preview?.after) ? nil : "没有检测到标签变化。"
            successMessage = nil
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
        guard remote.writeSupported ?? true else {
            errorMessage = MetadataWritebackError.unsupportedFormat.localizedDescription
            return
        }
        guard hasPendingChanges else {
            informationalMessage = "没有检测到标签变化。"
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
            let patch = patchForWrite()
            let result = try await service.provider().writeMetadata(song: song, patch: patch, expectedRevision: remote.revision)
            await service.recordWrite(song: song, oldRevision: remote.revision, result: result, before: remote.metadata)
            try await songRepository.updateMetadata(
                nasId: nasId,
                sourceId: sourceId,
                metadata: result.metadata,
                revision: result.newRevision,
                indexStatus: result.indexStatus
            )
            successMessage = "文件已写入 NAS，App 已更新本地标签，等待群晖音乐索引刷新。"
            preview = nil
            await reloadAfterWrite()
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
        patch(from: currentMetadata)
    }

    private func patchForWrite() -> AudioMetadataPatch {
        guard let remote,
              let preview,
              Self.hasChanges(before: preview.before, after: preview.after) else {
            return patch()
        }
        let current = currentMetadata
        if current == remote.metadata || current == preview.after {
            return patch(from: preview.after)
        }
        return patch()
    }

    private func patch(from metadata: RemoteAudioMetadata) -> AudioMetadataPatch {
        AudioMetadataPatch(
            title: metadata.title,
            artist: metadata.artist,
            album: metadata.album,
            albumArtist: metadata.albumArtist,
            genre: metadata.genre,
            year: metadata.year,
            trackNumber: metadata.trackNumber,
            discNumber: metadata.discNumber,
            comment: metadata.comment,
            composer: metadata.composer
        )
    }

    private var currentMetadata: RemoteAudioMetadata {
        RemoteAudioMetadata(
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

    private func reloadAfterWrite() async {
        do {
            let loaded = try await service.provider().readRemoteMetadata(for: song)
            remote = loaded
            apply(loaded.metadata)
        } catch {
            informationalMessage = "文件已写入，但重新读取远程标签失败：\(Self.message(for: error))"
        }
    }

    private static func hasChanges(before: RemoteAudioMetadata?, after: RemoteAudioMetadata?) -> Bool {
        guard let before, let after else { return false }
        return before.title != after.title ||
        before.artist != after.artist ||
        before.album != after.album ||
        before.albumArtist != after.albumArtist ||
        before.genre != after.genre ||
        before.year != after.year ||
        before.trackNumber != after.trackNumber ||
        before.discNumber != after.discNumber ||
        before.trackTotal != after.trackTotal ||
        before.discTotal != after.discTotal ||
        before.comment != after.comment ||
        before.composer != after.composer
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "标签写回失败，请稍后重试。"
    }
}
