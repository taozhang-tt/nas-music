//
//  NASSettingsViewModel.swift
//  nas-music
//
//  NAS 设置页的表单状态和操作转发。密码只活在 @Published password 里，
//  从不写回 NASSessionManager 之外的任何持久化层。
//

import Foundation
import Combine

@MainActor
final class NASSettingsViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var host: String = ""
    @Published var port: String = "5001"
    @Published var useHTTPS: Bool = true
    @Published var username: String = ""
    @Published var password: String = ""

    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    @Published var testResultMessage: String?

    @Published private(set) var artworkCacheSizeText: String = "—"
    @Published private(set) var artworkCacheFileCountText: String = "—"
    @Published private(set) var isClearingArtworkCache = false
    @Published var artworkCacheErrorMessage: String?

    private let sessionManager: NASSessionManager
    private let artworkCacheManager: ArtworkCacheManager
    private var cancellable: AnyCancellable?

    init(sessionManager: NASSessionManager, artworkCacheManager: ArtworkCacheManager = .shared) {
        self.sessionManager = sessionManager
        self.artworkCacheManager = artworkCacheManager
        cancellable = sessionManager.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        loadFormFromConfig()
    }

    var state: NASConnectionState { sessionManager.state }
    var hasSavedConfig: Bool { sessionManager.config != nil }
    var hasStoredCredential: Bool { sessionManager.hasStoredCredential }

    var statusTitle: String {
        switch state {
        case .disconnected: return "未连接"
        case .connecting: return "正在连接…"
        case .connected: return "已连接"
        case .failed: return "连接失败"
        }
    }

    var failureDetail: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    var diagnosticsText: String {
        let scheme = useHTTPS ? "https" : "http"
        let portText = port.isEmpty ? "-" : port
        var lines = [
            "Base URL: \(scheme)://\(host.isEmpty ? "-" : host):\(portText)",
            "Endpoint: /webapi/entry.cgi",
            "已保存凭证: \(hasStoredCredential ? "是" : "否")",
        ]
        if let configId = sessionManager.config?.id {
            lines.append("Config ID: \(configId.uuidString)")
        }
        if let lastConnectedAt = sessionManager.config?.lastConnectedAt {
            lines.append("最近连接: \(lastConnectedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        return lines.joined(separator: "\n")
    }

    func loadFormFromConfig() {
        guard let config = sessionManager.config else { return }
        name = config.name
        host = config.host
        port = String(config.port)
        useHTTPS = config.useHTTPS
        username = config.username
    }

    func testConnection() {
        guard let validated = validateForm() else { return }
        runBusyTask {
            let result = await self.sessionManager.testConnection(
                host: validated.host, port: validated.port, useHTTPS: self.useHTTPS,
                username: self.username, password: self.password
            )
            switch result {
            case .success:
                self.testResultMessage = "连接测试成功。"
            case .failure(let error):
                self.errorMessage = self.friendlyMessage(for: error)
            }
        }
    }

    func saveAndConnect() {
        guard let validated = validateForm() else { return }
        let connectionName = name.trimmingCharacters(in: .whitespaces).isEmpty ? validated.host : name
        runBusyTask {
            let result = await self.sessionManager.connect(
                name: connectionName, host: validated.host, port: validated.port,
                useHTTPS: self.useHTTPS, username: self.username, password: self.password
            )
            self.password = ""
            switch result {
            case .success:
                self.loadFormFromConfig()
            case .failure(let error):
                self.errorMessage = self.friendlyMessage(for: error)
            }
        }
    }

    func disconnect() {
        runBusyTask {
            await self.sessionManager.disconnect()
        }
    }

    func deleteConfig() {
        sessionManager.clearAllNASData()
        name = ""
        host = ""
        port = "5001"
        useHTTPS = true
        username = ""
        password = ""
        testResultMessage = nil
        errorMessage = nil
    }

    func clearCredentials() {
        sessionManager.clearCredentials()
        password = ""
    }

    func loadArtworkCacheStats() async {
        let stats = await artworkCacheManager.cacheStats()
        artworkCacheSizeText = Self.formattedByteCount(stats.totalBytes)
        artworkCacheFileCountText = "\(stats.fileCount) 个文件"
    }

    func clearArtworkCache() {
        artworkCacheErrorMessage = nil
        isClearingArtworkCache = true
        Task {
            do {
                try await artworkCacheManager.clearArtworkCache()
                await loadArtworkCacheStats()
            } catch {
                artworkCacheErrorMessage = (error as? LocalizedError)?.errorDescription ?? "清除封面缓存失败，请稍后重试。"
            }
            isClearingArtworkCache = false
        }
    }

    private static func formattedByteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func runBusyTask(_ operation: @escaping () async -> Void) {
        errorMessage = nil
        testResultMessage = nil
        isBusy = true
        Task {
            await operation()
            isBusy = false
        }
    }

    private func validateForm() -> (host: String, port: Int)? {
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        guard !trimmedHost.isEmpty else {
            errorMessage = SynologyAPIError.invalidHost.localizedDescription
            return nil
        }
        guard let portValue = Int(port), (1...65535).contains(portValue) else {
            errorMessage = SynologyAPIError.invalidPort.localizedDescription
            return nil
        }
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else {
            errorMessage = "请输入用户名和密码。"
            return nil
        }
        return (trimmedHost, portValue)
    }

    private func friendlyMessage(for error: SynologyAPIError) -> String {
        let message = error.localizedDescription
        guard error == .networkUnavailable || error == .timeout, Self.isPrivateLANHost(host) else {
            return message
        }
        return message + "\n请确认 NASMusic 已在「设置 -> 隐私与安全性 -> 本地网络」中被允许访问。"
    }

    private static func isPrivateLANHost(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        switch parts[0] {
        case 10: return true
        case 172: return (16...31).contains(parts[1])
        case 192: return parts[1] == 168
        default: return false
        }
    }
}
