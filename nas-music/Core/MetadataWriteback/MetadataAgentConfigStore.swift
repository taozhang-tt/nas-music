//
//  MetadataAgentConfigStore.swift
//  nas-music
//

import Foundation

struct MetadataAgentConfig: Codable, Equatable {
    let nasId: UUID
    var baseURL: URL
    var isEnabled: Bool
}

struct MetadataAgentConfigStore {
    private let defaults: UserDefaults
    private let keychain: KeychainService
    private let configPrefix = "metadataAgent.config."
    private let tokenPrefix = "metadataAgent.token."

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainService = KeychainService(service: "zero-tt.top.nas-music.metadata-agent")
    ) {
        self.defaults = defaults
        self.keychain = keychain
    }

    func readConfig(nasId: UUID) -> MetadataAgentConfig? {
        guard let data = defaults.data(forKey: configPrefix + nasId.uuidString) else { return nil }
        return try? JSONDecoder().decode(MetadataAgentConfig.self, from: data)
    }

    func saveConfig(_ config: MetadataAgentConfig, token: String?) throws {
        let data = try JSONEncoder().encode(config)
        defaults.set(data, forKey: configPrefix + config.nasId.uuidString)
        if let token, !token.isEmpty {
            try keychain.save(Data(token.utf8), account: tokenPrefix + config.nasId.uuidString)
        }
    }

    func readToken(nasId: UUID) -> String? {
        guard let data = try? keychain.read(account: tokenPrefix + nasId.uuidString) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(nasId: UUID) {
        defaults.removeObject(forKey: configPrefix + nasId.uuidString)
        try? keychain.delete(account: tokenPrefix + nasId.uuidString)
    }
}

