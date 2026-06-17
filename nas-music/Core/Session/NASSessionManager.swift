//
//  NASSessionManager.swift
//  nas-music
//
//  App 级别的 NAS 登录状态：持有当前 NASConnectionConfig（存 UserDefaults）和登录状态，
//  sid/synotoken 永远只读写 Keychain。当前只支持一个「当前连接」，isDefault 字段是为
//  将来支持多个保存的连接预留的。
//

import Foundation
import Combine

enum NASConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(message: String)
}

@MainActor
final class NASSessionManager: ObservableObject {
    @Published private(set) var state: NASConnectionState = .disconnected
    @Published private(set) var config: NASConnectionConfig?

    private let credentialStore: NASCredentialStore
    private let defaults: UserDefaults
    private let configKey = "nas.connection.config"
    private let defaultConfigIDKey = "nas.connection.defaultConfigID"

    init(credentialStore: NASCredentialStore = NASCredentialStore(), defaults: UserDefaults = .standard) {
        self.credentialStore = credentialStore
        self.defaults = defaults
        loadPersistedState()
    }

    var hasStoredCredential: Bool {
        guard let config else { return false }
        return credentialStore.readCredential(configId: config.id) != nil
    }

    func testConnection(host: String, port: Int, useHTTPS: Bool, username: String, password: String) async -> Result<Void, SynologyAPIError> {
        do {
            let client = try SynologyAPIClient(host: host, port: port, useHTTPS: useHTTPS)
            let authService = SynologyAuthService(client: client)
            try await authService.testConnection(username: username, password: password)
            return .success(())
        } catch let error as SynologyAPIError {
            return .failure(error)
        } catch {
            return .failure(.invalidResponse)
        }
    }

    func connect(name: String, host: String, port: Int, useHTTPS: Bool, username: String, password: String) async -> Result<Void, SynologyAPIError> {
        state = .connecting
        do {
            let client = try SynologyAPIClient(host: host, port: port, useHTTPS: useHTTPS)
            let authService = SynologyAuthService(client: client)
            let result = try await authService.login(username: username, password: password)

            let configId = config?.id ?? UUID()
            let newConfig = NASConnectionConfig(
                id: configId,
                name: name,
                host: host,
                port: port,
                useHTTPS: useHTTPS,
                username: username,
                displayName: config?.displayName,
                lastConnectedAt: Date(),
                isDefault: true
            )
            try credentialStore.saveCredential(
                configId: configId,
                username: username,
                sid: result.sid,
                synoToken: result.synoToken,
                deviceId: result.deviceId
            )
            persist(newConfig)
            state = .connected
            return .success(())
        } catch let error as SynologyAPIError {
            state = .failed(message: error.localizedDescription)
            return .failure(error)
        } catch {
            state = .failed(message: SynologyAPIError.invalidResponse.localizedDescription)
            return .failure(.invalidResponse)
        }
    }

    /// 断开连接：尽力调用登出 API，再清掉本地凭证；保留 NASConnectionConfig 方便下次直接重连。
    func disconnect() async {
        guard let config else { return }
        if let credential = credentialStore.readCredential(configId: config.id),
           let client = try? SynologyAPIClient(host: config.host, port: config.port, useHTTPS: config.useHTTPS) {
            await SynologyAuthService(client: client).logout(sid: credential.sid)
        }
        clearCredentials()
    }

    /// 只清掉 Keychain 里的登录凭证，保留已保存的连接配置。
    func clearCredentials() {
        if let config {
            credentialStore.deleteCredential(configId: config.id)
        }
        state = .disconnected
    }

    /// 删除已保存的连接配置和所有凭证，恢复到从未配置过的状态。
    func clearAllNASData() {
        credentialStore.deleteAllCredentials()
        config = nil
        defaults.removeObject(forKey: configKey)
        defaults.removeObject(forKey: defaultConfigIDKey)
        state = .disconnected
    }

    private func loadPersistedState() {
        guard let data = defaults.data(forKey: configKey),
              let savedConfig = try? JSONDecoder().decode(NASConnectionConfig.self, from: data) else {
            state = .disconnected
            return
        }
        config = savedConfig
        state = credentialStore.readCredential(configId: savedConfig.id) != nil ? .connected : .disconnected
    }

    private func persist(_ config: NASConnectionConfig) {
        self.config = config
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: configKey)
        }
        defaults.set(config.id.uuidString, forKey: defaultConfigIDKey)
    }
}
