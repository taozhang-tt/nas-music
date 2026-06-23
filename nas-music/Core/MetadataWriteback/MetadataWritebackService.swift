//
//  MetadataWritebackService.swift
//  nas-music
//

import Foundation
import Combine

@MainActor
final class MetadataWritebackService: ObservableObject {
    @Published private(set) var health: MetadataAgentHealth?
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    private let sessionManager: NASSessionManager
    private let configStore: MetadataAgentConfigStore
    private let operationRepository: MetadataWriteOperationRepositoryProtocol

    init(
        sessionManager: NASSessionManager,
        configStore: MetadataAgentConfigStore = MetadataAgentConfigStore(),
        operationRepository: MetadataWriteOperationRepositoryProtocol = MetadataWriteOperationRepository()
    ) {
        self.sessionManager = sessionManager
        self.configStore = configStore
        self.operationRepository = operationRepository
    }

    var currentConfig: MetadataAgentConfig? {
        guard let nasId = sessionManager.config?.id else { return nil }
        return configStore.readConfig(nasId: nasId)
    }

    func saveAgentConfig(baseURLText: String, token: String?, isEnabled: Bool) {
        do {
            guard let nasId = sessionManager.config?.id else { throw MetadataWritebackError.agentNotConfigured }
            guard let baseURL = URL(string: baseURLText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw MetadataWritebackError.agentNotConfigured
            }
            try configStore.saveConfig(MetadataAgentConfig(nasId: nasId, baseURL: baseURL, isEnabled: isEnabled), token: token)
            statusMessage = "Agent 配置已保存"
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func loadHealth() async {
        do {
            health = try await provider().health()
            statusMessage = health?.status == "ok" ? "Agent 已连接" : "Agent 状态异常"
            errorMessage = nil
        } catch {
            health = nil
            errorMessage = Self.message(for: error)
        }
    }

    func provider() throws -> MetadataWritebackProvider {
        guard let nasId = sessionManager.config?.id,
              let config = configStore.readConfig(nasId: nasId),
              config.isEnabled,
              let token = configStore.readToken(nasId: nasId),
              !token.isEmpty else {
            throw MetadataWritebackError.agentNotConfigured
        }
        return NASAgentMetadataWritebackProvider(baseURL: config.baseURL, apiToken: token)
    }

    func recordWrite(
        song: Song,
        oldRevision: String?,
        result: MetadataWriteResult,
        before: RemoteAudioMetadata?
    ) async {
        guard let nasId = sessionManager.config?.id.uuidString,
              let sourceId = song.audioStationId else { return }
        let encoder = JSONEncoder()
        let beforeJSON = before.flatMap { try? String(data: encoder.encode($0), encoding: .utf8) }
        let afterJSON = try? String(data: encoder.encode(result.metadata), encoding: .utf8)
        let status: MetadataWriteStatus = result.indexStatus == "indexed" ? .indexed : .waitingForIndex
        try? await operationRepository.upsert(MetadataWriteOperationRecord(
            id: result.operationId,
            nasId: nasId,
            songId: song.id,
            sourceId: sourceId,
            status: status,
            oldRevision: oldRevision,
            newRevision: result.newRevision,
            beforeMetadataJSON: beforeJSON,
            afterMetadataJSON: afterJSON,
            backupAvailable: result.backupCreated,
            errorMessage: nil,
            createdAt: Date(),
            completedAt: Date()
        ))
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Agent 操作失败，请稍后重试。"
    }
}

